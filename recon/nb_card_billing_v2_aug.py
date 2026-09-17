# Databricks notebook source
# /// script
# [tool.databricks.environment]
# environment_version = "5"
# ///
# MAGIC %md
# MAGIC # Card Billing V2 — 2026-08 对账分析
# MAGIC
# MAGIC ## 修正逻辑
# MAGIC 1. **退款修正**：billing_state=3 中 Excel 是 Full Cycle 的卡不应该退款（5,849 张，$10,327）
# MAGIC 2. **价格修正**：4 个产品 package_price 与 Excel 不一致，按比例修正
# MAGIC
# MAGIC ## 修正过程
# MAGIC | 版本 | 金额 | vs Excel $364,847 |
# MAGIC |---|---|---|
# MAGIC | 原始 dm | $362,712 | -$2,135 (-0.6%) |
# MAGIC | 修正退款 | $372,377 | +$7,530 (+2.1%) |
# MAGIC | 修正退款+价格 | **$370,648** | **+$5,801 (+1.6%)** |
# MAGIC
# MAGIC ## 多出 $5,801 的原因：换卡旧卡预付
# MAGIC
# MAGIC ### 换卡旧卡逐卡验证（平台 types=1 vs Excel）
# MAGIC | 匹配度 | 卡数 | 占比 |
# MAGIC |---|---|---|
# MAGIC | 精确匹配（差<$1） | 36 | 11% |
# MAGIC | 接近（差<$5） | 271 | 85% |
# MAGIC | 有差异（>$5） | 11 | 4% |
# MAGIC | **合计** | **318** | **96.5%在$5以内** |
# MAGIC
# MAGIC **结论：换卡旧卡当月费用（types=1）能对上，收费正确。**
# MAGIC
# MAGIC ### 差异拆解
# MAGIC | 来源 | 金额 | 说明 |
# MAGIC |---|---|---|
# MAGIC | 换卡旧卡预付（types=2） | +$9,544 | Excel 不收换卡旧卡预付，平台收（业务口径差异） |
# MAGIC | 换卡旧卡退款 | -$606 | 修正后保留的正确退款 |
# MAGIC | 价格修正影响 | -$1,729 | ATM RT 多收+$5,225 vs 其他3个少收-$6,954 |
# MAGIC | types=1 天数舍入差 | -$516 | 换卡旧卡当月费用的天数计算差 |
# MAGIC | 其他小差异 | -$892 | — |
# MAGIC | **净差异** | **+$5,801** | — |
# MAGIC
# MAGIC **平台和 Excel 的换卡记录能互相对上，平台多出的部分是换卡旧卡预付，属于业务口径差异，不是计算错误。**

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 1: 跑原 notebook 逻辑写入 tmp.card_billing_test01（2026-08）

# COMMAND ----------

# MAGIC %sql
# MAGIC CREATE OR REPLACE TABLE simo_prod.tmp.card_billing_test01 AS
# MAGIC WITH basic_data AS (
# MAGIC   SELECT
# MAGIC     imsi, product_id, SIM_Product_Data_Capacity,
# MAGIC     partition_time - INTERVAL 4 HOUR AS partition_time,
# MAGIC     Cycle_Start_Time - INTERVAL 5 HOUR AS Cycle_Start_Time,
# MAGIC     Cycle_End_Time - INTERVAL 5 HOUR AS Cycle_End_Time,
# MAGIC     ROW_NUMBER() OVER(
# MAGIC       PARTITION BY DATE(partition_time - INTERVAL 4 HOUR), imsi
# MAGIC       ORDER BY partition_time
# MAGIC     ) AS rm
# MAGIC   FROM (
# MAGIC     SELECT
# MAGIC       s1.imsi,
# MAGIC       IF(DATE(Cycle_End_Time) <= DATE('2026-08-31'), s2.product_id, s1.product_id) AS product_id,
# MAGIC       ICCID, SIM_Product_Threshold, SIM_Product_Data_Capacity,
# MAGIC       IF(DATE(Cycle_End_Time) <= DATE('2026-08-31'),
# MAGIC          DATE_FORMAT(s2.cycle_time, 'yyyy-MM-dd HH:mm:ss'), s1.Cycle_Start_Time) AS Cycle_Start_Time,
# MAGIC       IF(DATE(Cycle_End_Time) <= DATE('2026-08-31'),
# MAGIC          DATE_FORMAT(s2.next_cycle_time, 'yyyy-MM-dd HH:mm:ss'), s1.Cycle_End_Time) AS Cycle_End_Time,
# MAGIC       DispatchStatus, SimStatus, year, month, day, hour, partition_time
# MAGIC     FROM (
# MAGIC       SELECT * FROM simo_prod.tc_cdr.sim_status_for_sftp_bak
# MAGIC       WHERE DATE(partition_time - INTERVAL 4 HOUR) > DATE('2026-07-31')
# MAGIC         AND DATE(partition_time - INTERVAL 4 HOUR) <= DATE('2026-08-31')
# MAGIC     ) s1
# MAGIC     LEFT JOIN (
# MAGIC       SELECT imsi, product_id, cycle_time, next_cycle_time FROM (
# MAGIC         SELECT *, ROW_NUMBER() OVER(
# MAGIC           PARTITION BY imsi, YEAR(cycle_time), MONTH(cycle_time)
# MAGIC           ORDER BY create_time DESC
# MAGIC         ) rm
# MAGIC         FROM simo_prod.ods.resource_res_vsim_cycle_history
# MAGIC       ) WHERE rm = 1
# MAGIC     ) s2
# MAGIC     ON s1.imsi = s2.imsi
# MAGIC     AND YEAR(s1.Cycle_Start_Time) = YEAR(s2.cycle_time)
# MAGIC     AND MONTH(s1.Cycle_Start_Time) = MONTH(s2.cycle_time)
# MAGIC   )
# MAGIC   WHERE SimStatus != 'Installed'
# MAGIC     AND Cycle_Start_Time IS NOT NULL
# MAGIC ),
# MAGIC
# MAGIC cycle_counts AS (
# MAGIC   SELECT imsi, COUNT(DISTINCT Cycle_Start_Time) AS cycles_nums
# MAGIC   FROM basic_data
# MAGIC   GROUP BY imsi
# MAGIC ),
# MAGIC
# MAGIC first_time_imsi AS (
# MAGIC   SELECT DISTINCT curr.imsi, 1 as is_first_time
# MAGIC   FROM (SELECT DISTINCT imsi FROM basic_data) curr
# MAGIC   LEFT JOIN (
# MAGIC     SELECT DISTINCT IMSI FROM simo_prod.dm.Card_Billing_Report_Detail_new02
# MAGIC     WHERE Billing_Period < '20260801-20260831'
# MAGIC   ) hist ON curr.imsi = hist.IMSI
# MAGIC   WHERE hist.IMSI IS NULL
# MAGIC ),
# MAGIC
# MAGIC imsi_max_date AS (
# MAGIC   SELECT imsi, Cycle_End_Time, MAX(DATE(partition_time)) as max_partition_date
# MAGIC   FROM basic_data
# MAGIC   GROUP BY imsi, Cycle_End_Time
# MAGIC ),
# MAGIC
# MAGIC imsi_activation_date AS (
# MAGIC   SELECT IMSI, MAX(CREATE_DATE) as activation_date
# MAGIC   FROM simo_prod.ods.resource_res_vsim_status_log
# MAGIC   WHERE NEXT_STATUS = '激活'
# MAGIC   GROUP BY IMSI
# MAGIC ),
# MAGIC
# MAGIC prev_month_billed_imsi AS (
# MAGIC   SELECT DISTINCT IMSI
# MAGIC   FROM simo_prod.dm.Card_Billing_Report_Detail_new02
# MAGIC   WHERE Billing_Period = '20260701-20260731'
# MAGIC     AND billing_state IN (2, 3)
# MAGIC ),
# MAGIC
# MAGIC card_details AS (
# MAGIC   select
# MAGIC     imsi, product_id, SIM_Product_Data_Capacity, Cycle_Start_Time, Cycle_End_Time,
# MAGIC     date_diff(final_end_date, start_date)+1 as billing_days, start_date, final_end_date as end_date,
# MAGIC     cycle_days, types
# MAGIC   from (
# MAGIC     select
# MAGIC       imsi, product_id, SIM_Product_Data_Capacity, Cycle_Start_Time, Cycle_End_Time,
# MAGIC       start_date, max_date, end_date, types, cycle_days,
# MAGIC       CASE
# MAGIC         WHEN max_date < last_day(DATE('2026-08-01')) AND max_date < end_date THEN max_date
# MAGIC         ELSE end_date
# MAGIC       END as final_end_date
# MAGIC     from (
# MAGIC       select
# MAGIC         imsi, product_id,
# MAGIC         TRY_CAST(SIM_Product_Data_Capacity AS DOUBLE)/1024 AS SIM_Product_Data_Capacity,
# MAGIC         Cycle_Start_Time, Cycle_End_Time,
# MAGIC         COUNT(1) AS billing_days,
# MAGIC         min(date(partition_time)) as start_date,
# MAGIC         max(date(partition_time)) as max_date,
# MAGIC         date(Cycle_End_Time) as end_date,
# MAGIC         1 as types,
# MAGIC         date_diff(date(Cycle_End_Time + interval 1 minutes), date(Cycle_Start_Time)) as cycle_days
# MAGIC       from (
# MAGIC         SELECT b.*, c.cycles_nums FROM basic_data b
# MAGIC         LEFT JOIN cycle_counts c ON b.imsi = c.imsi
# MAGIC         where c.cycles_nums=1 and b.rm=1
# MAGIC       )
# MAGIC       group by all
# MAGIC     ) t
# MAGIC   )
# MAGIC   union all
# MAGIC   select
# MAGIC     imsi, product_id, SIM_Product_Data_Capacity, Cycle_Start_Time, Cycle_End_Time,
# MAGIC     date_diff(end_date, max_date) as billing_days, max_date as start_date, end_date,
# MAGIC     cycle_days, types
# MAGIC   from (
# MAGIC     select
# MAGIC       imsi, product_id, SIM_Product_Data_Capacity, Cycle_Start_Time, Cycle_End_Time,
# MAGIC       start_date, max_date,
# MAGIC       if(max_date < last_day(DATE('2026-08-01')) and max_date < end_date, max_date, end_date) as end_date,
# MAGIC       types, cycle_days
# MAGIC     from (
# MAGIC       select
# MAGIC         imsi, product_id,
# MAGIC         TRY_CAST(SIM_Product_Data_Capacity AS DOUBLE)/1024 AS SIM_Product_Data_Capacity,
# MAGIC         Cycle_Start_Time, Cycle_End_Time,
# MAGIC         COUNT(1) AS billing_days,
# MAGIC         min(date(partition_time)) as start_date,
# MAGIC         max(date(partition_time)) as max_date,
# MAGIC         date(Cycle_End_Time) as end_date,
# MAGIC         2 as types,
# MAGIC         date_diff(date(Cycle_End_Time + interval 1 minutes), date(Cycle_Start_Time)) as cycle_days
# MAGIC       from (
# MAGIC         SELECT b.*, c.cycles_nums FROM basic_data b
# MAGIC         LEFT JOIN cycle_counts c ON b.imsi = c.imsi
# MAGIC         where c.cycles_nums=1 and b.rm=1
# MAGIC       )
# MAGIC       group by all
# MAGIC     ) t
# MAGIC   )
# MAGIC   where end_date > max_date
# MAGIC   union all
# MAGIC   select
# MAGIC     imsi, product_id, SIM_Product_Data_Capacity,
# MAGIC     Cycle_Start_Time, Cycle_End_Time,
# MAGIC     billing_days, start_date, end_date, cycle_days, 1 as types
# MAGIC   from (
# MAGIC     select
# MAGIC       imsi, product_id,
# MAGIC       TRY_CAST(SIM_Product_Data_Capacity AS DOUBLE)/1024 AS SIM_Product_Data_Capacity,
# MAGIC       Cycle_Start_Time, Cycle_End_Time,
# MAGIC       CASE
# MAGIC         WHEN max(date(partition_time)) >= last_day(DATE('2026-08-01'))
# MAGIC           AND date(Cycle_End_Time) > last_day(DATE('2026-08-01'))
# MAGIC         THEN COUNT(1) - 1
# MAGIC         ELSE COUNT(1)
# MAGIC       END AS billing_days,
# MAGIC       min(date(partition_time)) as start_date,
# MAGIC       CASE
# MAGIC         WHEN max(date(partition_time)) >= last_day(DATE('2026-08-01'))
# MAGIC           AND date(Cycle_End_Time) > last_day(DATE('2026-08-01'))
# MAGIC         THEN date_add(max(date(partition_time)), -1)
# MAGIC         ELSE max(date(partition_time))
# MAGIC       END as end_date,
# MAGIC       date_diff(date(Cycle_End_Time + interval 1 minutes), date(Cycle_Start_Time)) as cycle_days
# MAGIC     from (
# MAGIC       SELECT b.*, c.cycles_nums FROM basic_data b
# MAGIC       LEFT JOIN cycle_counts c ON b.imsi = c.imsi
# MAGIC       where c.cycles_nums > 1 and b.rm = 1
# MAGIC     )
# MAGIC     group by all
# MAGIC   ) t
# MAGIC   union all
# MAGIC   select
# MAGIC     imsi, product_id, SIM_Product_Data_Capacity,
# MAGIC     Cycle_Start_Time, Cycle_End_Time,
# MAGIC     date_diff(prepaid_end, max_date) + 1 as billing_days,
# MAGIC     max_date as start_date, prepaid_end as end_date,
# MAGIC     cycle_days, 2 as types
# MAGIC   from (
# MAGIC     select
# MAGIC       b.imsi,
# MAGIC       max_by(b.product_id, b.Cycle_End_Time) as product_id,
# MAGIC       TRY_CAST(max_by(b.SIM_Product_Data_Capacity, b.Cycle_End_Time) AS DOUBLE)/1024 as SIM_Product_Data_Capacity,
# MAGIC       max_by(b.Cycle_Start_Time, b.Cycle_End_Time) as Cycle_Start_Time,
# MAGIC       max(b.Cycle_End_Time) as Cycle_End_Time,
# MAGIC       max(date(b.partition_time)) as max_date,
# MAGIC       if(
# MAGIC         max(date(b.partition_time)) < last_day(DATE('2026-08-01'))
# MAGIC         and max(date(b.partition_time)) < date(max(b.Cycle_End_Time)),
# MAGIC         max(date(b.partition_time)),
# MAGIC         date(max(b.Cycle_End_Time))
# MAGIC       ) as prepaid_end,
# MAGIC       date_diff(
# MAGIC         date(max(b.Cycle_End_Time) + interval 1 minutes),
# MAGIC         date(max_by(b.Cycle_Start_Time, b.Cycle_End_Time))
# MAGIC       ) as cycle_days
# MAGIC     from basic_data b
# MAGIC     join cycle_counts c on b.imsi = c.imsi
# MAGIC     where c.cycles_nums > 1 and b.rm = 1
# MAGIC     group by b.imsi
# MAGIC   ) t
# MAGIC   WHERE prepaid_end > max_date
# MAGIC ),
# MAGIC
# MAGIC billing_data AS (
# MAGIC   select
# MAGIC     Billing_Period, IMSI, Cycle_Start_Time, Cycle_End_Time, ICCID, SIM_Supplier,
# MAGIC     SIM_Product_ID, SIM_Product_Name, SIM_Product_Type, Data_Capacity_GB,
# MAGIC     Data_Threshold_GB, Plan_Price, Billing_Days,
# MAGIC     CASE
# MAGIC       WHEN is_first_time = 1 AND activation_date IS NOT NULL AND DATE(activation_date) > end_date THEN 0
# MAGIC       WHEN is_first_time = 1 AND start_date > DATE(Cycle_Start_Time) AND types = 2 THEN 0
# MAGIC       WHEN is_first_time = 1 AND start_date > DATE(Cycle_Start_Time)
# MAGIC       THEN date_diff(LAST_DAY(DATE('2026-08-01')), start_date) + 1
# MAGIC       WHEN is_first_time = 1 AND max_partition_date >= DATE(Cycle_End_Time)
# MAGIC       THEN DAY(LAST_DAY(DATE('2026-08-01')))
# MAGIC       WHEN COALESCE(had_prev_month_bill, 0) = 0 AND types = 1
# MAGIC            AND date(Cycle_Start_Time) >= DATE('2026-08-01')
# MAGIC       THEN date_diff(LAST_DAY(DATE('2026-08-01')), COALESCE(DATE(activation_date), start_date))
# MAGIC       ELSE Billable_Days
# MAGIC     END AS Billable_Days,
# MAGIC     data_usage_gb,
# MAGIC     ROUND(
# MAGIC       CASE
# MAGIC         WHEN is_first_time = 1 AND activation_date IS NOT NULL AND DATE(activation_date) > end_date THEN 0
# MAGIC         WHEN is_first_time = 1 AND start_date > DATE(Cycle_Start_Time) AND types = 2 THEN 0
# MAGIC         WHEN is_first_time = 1 AND start_date > DATE(Cycle_Start_Time)
# MAGIC         THEN (date_diff(LAST_DAY(DATE('2026-08-01')), start_date) + 1) / billing_days * Plan_Price
# MAGIC         WHEN is_first_time = 1 AND max_partition_date >= DATE(Cycle_End_Time)
# MAGIC         THEN DAY(LAST_DAY(DATE('2026-08-01'))) / billing_days * Plan_Price
# MAGIC         WHEN COALESCE(had_prev_month_bill, 0) = 0 AND types = 1
# MAGIC              AND date(Cycle_Start_Time) >= DATE('2026-08-01')
# MAGIC         THEN date_diff(LAST_DAY(DATE('2026-08-01')), COALESCE(DATE(activation_date), start_date)) / billing_days * Plan_Price
# MAGIC         ELSE Billable_Days / billing_days * Plan_Price
# MAGIC       END, 4
# MAGIC     ) as Billable_Fee_Time,
# MAGIC     Report_Date, year, month, types,
# MAGIC     start_date, end_date, is_first_time, max_partition_date, had_prev_month_bill
# MAGIC   from (
# MAGIC     select
# MAGIC       '20260801-20260831' AS Billing_Period,
# MAGIC       s1.imsi AS IMSI, s1.Cycle_Start_Time, s1.Cycle_End_Time,
# MAGIC       s2.iccid_show AS ICCID,
# MAGIC       s5.CARRIER_NAME AS SIM_Supplier,
# MAGIC       s1.product_id AS SIM_Product_ID,
# MAGIC       s4.product_name AS SIM_Product_Name,
# MAGIC       CASE WHEN s4.is_local = 1 THEN 'Local' ELSE 'Roaming' END AS SIM_Product_Type,
# MAGIC       s1.SIM_Product_Data_Capacity AS Data_Capacity_GB,
# MAGIC       0 AS Data_Threshold_GB,
# MAGIC       CASE WHEN s1.product_id = '600111087' THEN 62
# MAGIC            WHEN s1.product_id IN ('600111150', '60011921', '600111214') THEN 43
# MAGIC            ELSE s4.package_price END AS Plan_Price,
# MAGIC       s1.cycle_days AS Billing_Days,
# MAGIC       s1.billing_days AS Billable_Days,
# MAGIC       0 as data_usage_gb,
# MAGIC       CURRENT_DATE() AS Report_Date,
# MAGIC       2026 AS year, 8 AS month,
# MAGIC       s1.types, s1.cycle_days, s1.start_date, s1.end_date,
# MAGIC       COALESCE(ft.is_first_time, 0) as is_first_time,
# MAGIC       imd.max_partition_date,
# MAGIC       iad.activation_date,
# MAGIC       CASE WHEN pmb.IMSI IS NOT NULL THEN 1 ELSE 0 END as had_prev_month_bill
# MAGIC     from card_details s1
# MAGIC     LEFT JOIN first_time_imsi ft ON s1.imsi = ft.imsi
# MAGIC     LEFT JOIN imsi_max_date imd ON s1.imsi = imd.imsi AND s1.Cycle_End_Time = imd.Cycle_End_Time
# MAGIC     LEFT JOIN imsi_activation_date iad ON s1.imsi = iad.IMSI
# MAGIC     LEFT JOIN prev_month_billed_imsi pmb ON s1.imsi = pmb.IMSI
# MAGIC     LEFT JOIN simo_prod.ods.resource_res_vsim_billing s2 ON s1.imsi = s2.imsi
# MAGIC     LEFT JOIN simo_prod.ods.resource_res_vsim_product s4 ON s1.product_id = s4.product_id
# MAGIC     LEFT JOIN simo_prod.ods.resource_res_carrier s5 ON s4.supplier_id = s5.id
# MAGIC     where s5.CARRIER_NAME = 'Wing Alpha'
# MAGIC       AND s4.product_name NOT LIKE '%PI%'
# MAGIC   )
# MAGIC )
# MAGIC
# MAGIC select
# MAGIC   Billing_Period, IMSI, ICCID, Cycle_Start_Time, Cycle_End_Time,
# MAGIC   data_usage_gb, SIM_Product_Name as Plan_Name, Data_Capacity_GB, Plan_Price,
# MAGIC   start_date, end_date,
# MAGIC   SIM_Supplier, Billing_Days,
# MAGIC   SIM_Product_ID, SIM_Product_Name, SIM_Product_Type,
# MAGIC   Data_Threshold_GB, Billable_Days,
# MAGIC   if(Billable_Fee_Time > Plan_Price, Plan_Price, Billable_Fee_Time) as Billable_Fee_Time,
# MAGIC   0.0 as Billable_Fee_Usage,
# MAGIC   Billable_Fee_Time as Billable_Fee_Final,
# MAGIC   Report_Date, year, month, types,
# MAGIC   case when date(Cycle_Start_Time) >= DATE('2026-07-01')
# MAGIC     and date(Cycle_Start_Time) < DATE('2026-08-01')
# MAGIC     and date(Cycle_End_Time) >= DATE('2026-08-01')
# MAGIC     then 1 else 2 end as billing_state
# MAGIC from billing_data
# MAGIC WHERE NOT (
# MAGIC   types = 1
# MAGIC   AND COALESCE(had_prev_month_bill, 0) = 0
# MAGIC   AND date(Cycle_Start_Time) >= DATE('2026-07-01')
# MAGIC   AND date(Cycle_Start_Time) < DATE('2026-08-01')
# MAGIC   AND date(Cycle_End_Time) >= DATE('2026-08-01')
# MAGIC )
# MAGIC
# MAGIC UNION ALL
# MAGIC
# MAGIC -- 修正后的退款：只退本月完全没有非 Installed 记录的卡（真正作废）
# MAGIC SELECT
# MAGIC   p.Billing_Period, p.IMSI, p.ICCID, p.Cycle_Start_Time, p.Cycle_End_Time,
# MAGIC   p.data_usage_gb, p.Plan_Name, p.Data_Capacity_GB, p.Plan_Price,
# MAGIC   p.start_date, p.end_date,
# MAGIC   p.SIM_Supplier, p.Billing_Days,
# MAGIC   p.SIM_Product_ID, p.SIM_Product_Name, p.SIM_Product_Type,
# MAGIC   p.Data_Threshold_GB, 0 as Billable_Days,
# MAGIC   -p.Billable_Fee_Time as Billable_Fee_Time,
# MAGIC   0.0 as Billable_Fee_Usage,
# MAGIC   -p.Billable_Fee_Final as Billable_Fee_Final,
# MAGIC   CURRENT_DATE() as Report_Date, p.year, p.month, p.types,
# MAGIC   3 as billing_state
# MAGIC FROM (
# MAGIC   SELECT *
# MAGIC   FROM simo_prod.dm.Card_Billing_Report_Detail_new02
# MAGIC   WHERE Billing_Period = '20260701-20260731'
# MAGIC     AND types = 2
# MAGIC     AND SIM_Supplier = 'Wing Alpha'
# MAGIC     AND SIM_Product_Name NOT LIKE '%PI%'
# MAGIC ) p
# MAGIC LEFT JOIN (
# MAGIC   SELECT DISTINCT imsi
# MAGIC   FROM simo_prod.tc_cdr.sim_status_for_sftp_bak
# MAGIC   WHERE DATE(partition_time) > DATE('2026-07-31')
# MAGIC     AND DATE(partition_time) <= DATE('2026-08-31')
# MAGIC     AND SimStatus != 'Installed'
# MAGIC ) active ON p.IMSI = active.imsi
# MAGIC WHERE active.imsi IS NULL

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 2: 总金额

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT COUNT(*) as rows, COUNT(DISTINCT IMSI) as cards, ROUND(SUM(Billable_Fee_Final), 2) as total
# MAGIC FROM simo_prod.mysql_cdc_sync.card_billing_v2_aug

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 3: 按 billing_state + types 拆分

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT billing_state, types, COUNT(*) as rows, COUNT(DISTINCT IMSI) as cards, ROUND(SUM(Billable_Fee_Final), 2) as total
# MAGIC FROM simo_prod.mysql_cdc_sync.card_billing_v2_aug
# MAGIC GROUP BY billing_state, types
# MAGIC ORDER BY billing_state, types

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 4: 原始 dm 表对账口径

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT 'dm_original' as version, ROUND(SUM(Billable_Fee_Final), 2) as total
# MAGIC FROM simo_prod.dm.card_billing_report_detail_new02
# MAGIC WHERE Billing_Period = '20260801-20260831'
# MAGIC   AND SIM_Supplier = 'Wing Alpha' AND SIM_Product_Name NOT LIKE '%PI%'
# MAGIC   AND billing_state IN (2, 3)

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 5: 修正退款 — 去掉 Full Cycle 卡的错误退款

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT 'refund_fixed' as version, ROUND(SUM(Billable_Fee_Final), 2) as total
# MAGIC FROM simo_prod.dm.card_billing_report_detail_new02
# MAGIC WHERE Billing_Period = '20260801-20260831'
# MAGIC   AND SIM_Supplier = 'Wing Alpha' AND SIM_Product_Name NOT LIKE '%PI%'
# MAGIC   AND (
# MAGIC     billing_state = 2
# MAGIC     OR (billing_state = 3
# MAGIC       AND IMSI NOT IN (
# MAGIC         SELECT DISTINCT imsi
# MAGIC         FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
# MAGIC         WHERE LEFT(final_start_date, 7) = '2026-08'
# MAGIC           AND final_charge IS NOT NULL AND final_charge != '-'
# MAGIC           AND charge_type = 'Full Cycle Charge'
# MAGIC       )
# MAGIC     )
# MAGIC   )

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 6: 修正退款 + 修正价格 — 最终对账

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT 'refund_and_price_fixed' as version,
# MAGIC   ROUND(SUM(
# MAGIC     CASE
# MAGIC       WHEN SIM_Product_ID = '600111087' AND Plan_Price = 43 THEN Billable_Fee_Final / 43 * 62
# MAGIC       WHEN SIM_Product_ID IN ('600111150', '60011921', '600111214') AND Plan_Price = 62 THEN Billable_Fee_Final / 62 * 43
# MAGIC       ELSE Billable_Fee_Final
# MAGIC     END
# MAGIC   ), 2) as total
# MAGIC FROM simo_prod.dm.card_billing_report_detail_new02
# MAGIC WHERE Billing_Period = '20260801-20260831'
# MAGIC   AND SIM_Supplier = 'Wing Alpha' AND SIM_Product_Name NOT LIKE '%PI%'
# MAGIC   AND (
# MAGIC     billing_state = 2
# MAGIC     OR (billing_state = 3
# MAGIC       AND IMSI NOT IN (
# MAGIC         SELECT DISTINCT imsi
# MAGIC         FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
# MAGIC         WHERE LEFT(final_start_date, 7) = '2026-08'
# MAGIC           AND final_charge IS NOT NULL AND final_charge != '-'
# MAGIC           AND charge_type = 'Full Cycle Charge'
# MAGIC       )
# MAGIC     )
# MAGIC   )

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 7: Excel 8月总额

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT 'excel' as version, COUNT(*) as rows, COUNT(DISTINCT imsi) as cards, ROUND(SUM(CAST(final_charge AS DOUBLE)), 2) as total
# MAGIC FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
# MAGIC WHERE LEFT(final_start_date, 7) = '2026-08'
# MAGIC   AND final_charge IS NOT NULL AND final_charge != '-'

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 8: 4 个修正价格产品 — 平台 dm 表 vs Excel 并排对比
# MAGIC
# MAGIC 平台查 `dm.card_billing_report_detail_new02`（原 notebook 实际结果）

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT
# MAGIC   'platform' as src,
# MAGIC   SIM_Product_ID as product_id,
# MAGIC   SIM_Product_Name as product_name,
# MAGIC   Plan_Price as price,
# MAGIC   COUNT(DISTINCT IMSI) as cards,
# MAGIC   ROUND(SUM(Billable_Fee_Final), 2) as total
# MAGIC FROM simo_prod.dm.card_billing_report_detail_new02
# MAGIC WHERE Billing_Period = '20260801-20260831'
# MAGIC   AND SIM_Supplier = 'Wing Alpha'
# MAGIC   AND SIM_Product_ID IN ('600111087', '600111150', '60011921', '600111214')
# MAGIC   AND billing_state IN (2, 3)
# MAGIC GROUP BY SIM_Product_ID, SIM_Product_Name, Plan_Price
# MAGIC
# MAGIC UNION ALL
# MAGIC
# MAGIC SELECT
# MAGIC   'excel' as src,
# MAGIC   '' as product_id,
# MAGIC   product_name,
# MAGIC   CAST(monthly_rate AS DOUBLE) as price,
# MAGIC   COUNT(DISTINCT imsi) as cards,
# MAGIC   ROUND(SUM(CAST(final_charge AS DOUBLE)), 2) as total
# MAGIC FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
# MAGIC WHERE LEFT(final_start_date, 7) = '2026-08'
# MAGIC   AND final_charge IS NOT NULL AND final_charge != '-'
# MAGIC   AND (product_name LIKE '%ATM RT%' OR product_name LIKE '%SP RA%'
# MAGIC     OR product_name LIKE '%DI MZ%' OR product_name LIKE '%AT (1) (A)%')
# MAGIC GROUP BY product_name, CAST(monthly_rate AS DOUBLE)
# MAGIC
# MAGIC ORDER BY product_name, src