# Databricks notebook source
# /// script
# [tool.databricks.environment]
# environment_version = "5"
# ///
# MAGIC %md
# MAGIC # Card Billing V2 — 2026-07 对账分析
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
# MAGIC ## Step 1: 跑原 notebook 逻辑写入 card_billing_v2_jul_test（2026-07）

# COMMAND ----------

# MAGIC %sql
# MAGIC -- COMMAND ----------
# MAGIC -- Markdown: 历史账单处理方案（2026-08 逻辑修正版）
# MAGIC -- 基于原 card billing.html
# MAGIC -- 测试表建在 simo_prod.mysql_cdc_sync 库下
# MAGIC -- 价格全部走平台 s4.package_price，不硬编码
# MAGIC -- 退款排除 Full Cycle Charge
# MAGIC
# MAGIC -- COMMAND ----------
# MAGIC CREATE OR REPLACE TABLE simo_prod.mysql_cdc_sync.card_billing_test01 AS
# MAGIC WITH basic_data AS (
# MAGIC   SELECT
# MAGIC     imsi,
# MAGIC     product_id,
# MAGIC     SIM_Product_Data_Capacity,
# MAGIC     partition_time - INTERVAL 4 HOUR AS partition_time,
# MAGIC     Cycle_Start_Time - INTERVAL 5 HOUR AS Cycle_Start_Time,
# MAGIC     Cycle_End_Time - INTERVAL 5 HOUR AS Cycle_End_Time,
# MAGIC     ROW_NUMBER() OVER (
# MAGIC       PARTITION BY DATE(partition_time - INTERVAL 4 HOUR), imsi
# MAGIC       ORDER BY partition_time
# MAGIC     ) AS rm
# MAGIC   FROM (
# MAGIC     SELECT
# MAGIC       s1.imsi,
# MAGIC       IF(DATE(Cycle_End_Time) <= LAST_DAY(ADD_MONTHS(NOW(), -1)), s2.product_id, s1.product_id) AS product_id,
# MAGIC       ICCID,
# MAGIC       SIM_Product_Threshold,
# MAGIC       SIM_Product_Data_Capacity,
# MAGIC       IF(DATE(Cycle_End_Time) <= LAST_DAY(ADD_MONTHS(NOW(), -1)),
# MAGIC          DATE_FORMAT(s2.cycle_time, 'yyyy-MM-dd HH:mm:ss'),
# MAGIC          s1.Cycle_Start_Time) AS Cycle_Start_Time,
# MAGIC       IF(DATE(Cycle_End_Time) <= LAST_DAY(ADD_MONTHS(NOW(), -1)),
# MAGIC          DATE_FORMAT(s2.next_cycle_time, 'yyyy-MM-dd HH:mm:ss'),
# MAGIC          s1.Cycle_End_Time) AS Cycle_End_Time,
# MAGIC       DispatchStatus,
# MAGIC       SimStatus,
# MAGIC       year,
# MAGIC       month,
# MAGIC       day,
# MAGIC       hour,
# MAGIC       partition_time
# MAGIC     FROM (
# MAGIC       SELECT *
# MAGIC       FROM tc_cdr.sim_status_for_sftp_bak
# MAGIC       WHERE DATE(partition_time - INTERVAL 4 HOUR) > LAST_DAY(ADD_MONTHS(NOW(), -2))
# MAGIC         AND DATE(partition_time - INTERVAL 4 HOUR) <= LAST_DAY(ADD_MONTHS(NOW(), -1))
# MAGIC     ) s1
# MAGIC     LEFT JOIN (
# MAGIC       SELECT imsi, product_id, cycle_time, next_cycle_time
# MAGIC       FROM (
# MAGIC         SELECT
# MAGIC           *,
# MAGIC           ROW_NUMBER() OVER (
# MAGIC             PARTITION BY imsi, YEAR(cycle_time), MONTH(cycle_time)
# MAGIC             ORDER BY create_time DESC
# MAGIC           ) AS rm
# MAGIC         FROM ods.resource_res_vsim_cycle_history
# MAGIC       ) t
# MAGIC       WHERE rm = 1
# MAGIC     ) s2
# MAGIC       ON s1.imsi = s2.imsi
# MAGIC      AND YEAR(s1.Cycle_Start_Time) = YEAR(s2.cycle_time)
# MAGIC      AND MONTH(s1.Cycle_Start_Time) = MONTH(s2.cycle_time)
# MAGIC   ) x
# MAGIC   WHERE SimStatus != 'Installed'
# MAGIC     AND Cycle_Start_Time IS NOT NULL
# MAGIC ),
# MAGIC cycle_counts AS (
# MAGIC   SELECT
# MAGIC     imsi,
# MAGIC     COUNT(DISTINCT Cycle_Start_Time) AS cycles_nums
# MAGIC   FROM basic_data
# MAGIC   GROUP BY imsi
# MAGIC ),
# MAGIC first_time_imsi AS (
# MAGIC   SELECT DISTINCT
# MAGIC     curr.imsi,
# MAGIC     1 AS is_first_time
# MAGIC   FROM (
# MAGIC     SELECT DISTINCT imsi FROM basic_data
# MAGIC   ) curr
# MAGIC   LEFT JOIN (
# MAGIC     SELECT DISTINCT IMSI
# MAGIC     FROM dm.Card_Billing_Report_Detail_new02
# MAGIC     WHERE Billing_Period < CONCAT(
# MAGIC       REPLACE(TRUNC(ADD_MONTHS(CURRENT_DATE(), -1), 'MM'), '-', ''),
# MAGIC       '-',
# MAGIC       REPLACE(LAST_DAY(ADD_MONTHS(CURRENT_DATE(), -1)), '-', '')
# MAGIC     )
# MAGIC   ) hist
# MAGIC     ON curr.imsi = hist.IMSI
# MAGIC   WHERE hist.IMSI IS NULL
# MAGIC ),
# MAGIC imsi_max_date AS (
# MAGIC   SELECT
# MAGIC     imsi,
# MAGIC     Cycle_End_Time,
# MAGIC     MAX(DATE(partition_time)) AS max_partition_date
# MAGIC   FROM basic_data
# MAGIC   GROUP BY imsi, Cycle_End_Time
# MAGIC ),
# MAGIC imsi_activation_date AS (
# MAGIC   SELECT
# MAGIC     IMSI,
# MAGIC     MAX(CREATE_DATE) AS activation_date
# MAGIC   FROM ods.resource_res_vsim_status_log
# MAGIC   WHERE NEXT_STATUS = '激活'
# MAGIC   GROUP BY IMSI
# MAGIC ),
# MAGIC -- 动态计算停用卡日期，不再写死 2026-03
# MAGIC mar_deact_cycles AS (
# MAGIC   SELECT DISTINCT
# MAGIC     DAY(DATE(bd.Cycle_Start_Time)) AS cycle_day
# MAGIC   FROM basic_data bd
# MAGIC   INNER JOIN ods.resource_res_vsim_status_log sl
# MAGIC     ON bd.imsi = sl.IMSI
# MAGIC   WHERE sl.NEXT_STATUS = '停用'
# MAGIC     AND date(sl.CREATE_DATE) >= DATE_FORMAT(ADD_MONTHS(CURRENT_DATE(), -1), 'yyyy-MM-01')
# MAGIC     AND date(sl.CREATE_DATE) <= LAST_DAY(ADD_MONTHS(CURRENT_DATE(), -1))
# MAGIC ),
# MAGIC -- 动态计算替换卡 IMSI，不再写死 2026-03
# MAGIC replacement_imsi AS (
# MAGIC   SELECT DISTINCT
# MAGIC     bd.imsi
# MAGIC   FROM basic_data bd
# MAGIC   INNER JOIN ods.resource_res_vsim_status_log sl
# MAGIC     ON bd.imsi = sl.IMSI
# MAGIC   INNER JOIN mar_deact_cycles mdc
# MAGIC     ON DAY(DATE(bd.Cycle_Start_Time)) = mdc.cycle_day
# MAGIC   WHERE sl.NEXT_STATUS = '激活'
# MAGIC     AND date(sl.CREATE_DATE) >= DATE_FORMAT(ADD_MONTHS(CURRENT_DATE(), -1), 'yyyy-MM-01')
# MAGIC     AND date(sl.CREATE_DATE) <= LAST_DAY(ADD_MONTHS(CURRENT_DATE(), -1))
# MAGIC ),
# MAGIC prev_month_prepaid AS (
# MAGIC   SELECT
# MAGIC     Billing_Period,
# MAGIC     IMSI,
# MAGIC     ICCID,
# MAGIC     Cycle_Start_Time,
# MAGIC     Cycle_End_Time,
# MAGIC     data_usage_gb,
# MAGIC     Plan_Name,
# MAGIC     Data_Capacity_GB,
# MAGIC     Plan_Price,
# MAGIC     start_date,
# MAGIC     end_date,
# MAGIC     SIM_Supplier,
# MAGIC     Billing_Days,
# MAGIC     SIM_Product_ID,
# MAGIC     SIM_Product_Name,
# MAGIC     SIM_Product_Type,
# MAGIC     Data_Threshold_GB,
# MAGIC     Billable_Days,
# MAGIC     Billable_Fee_Time,
# MAGIC     Billable_Fee_Usage,
# MAGIC     Billable_Fee_Final,
# MAGIC     Report_Date,
# MAGIC     year,
# MAGIC     month,
# MAGIC     types
# MAGIC   FROM dm.Card_Billing_Report_Detail_new02
# MAGIC   WHERE Billing_Period = CONCAT(
# MAGIC       REPLACE(TRUNC(ADD_MONTHS(CURRENT_DATE(), -2), 'MM'), '-', ''),
# MAGIC       '-',
# MAGIC       REPLACE(LAST_DAY(ADD_MONTHS(CURRENT_DATE(), -2)), '-', '')
# MAGIC     )
# MAGIC     AND types = 2
# MAGIC     AND SIM_Supplier = 'Wing Alpha'
# MAGIC     AND SIM_Product_Name NOT LIKE '%PI%'
# MAGIC ),
# MAGIC prev_month_billed_imsi AS (
# MAGIC   SELECT DISTINCT IMSI
# MAGIC   FROM dm.Card_Billing_Report_Detail_new02
# MAGIC   WHERE Billing_Period = CONCAT(
# MAGIC       REPLACE(TRUNC(ADD_MONTHS(CURRENT_DATE(), -2), 'MM'), '-', ''),
# MAGIC       '-',
# MAGIC       REPLACE(LAST_DAY(ADD_MONTHS(CURRENT_DATE(), -2)), '-', '')
# MAGIC     )
# MAGIC     AND billing_state IN (2, 3)
# MAGIC ),
# MAGIC -- 退款：排除当月已产生 Full Cycle Charge 的 IMSI
# MAGIC -- wa_invoice_detail 与测试表同库
# MAGIC refund_data AS (
# MAGIC   SELECT
# MAGIC     p.Billing_Period,
# MAGIC     p.IMSI,
# MAGIC     p.ICCID,
# MAGIC     p.Cycle_Start_Time,
# MAGIC     p.Cycle_End_Time,
# MAGIC     p.data_usage_gb,
# MAGIC     p.Plan_Name,
# MAGIC     p.Data_Capacity_GB,
# MAGIC     p.Plan_Price,
# MAGIC     p.start_date,
# MAGIC     p.end_date,
# MAGIC     p.SIM_Supplier,
# MAGIC     p.Billing_Days,
# MAGIC     p.SIM_Product_ID,
# MAGIC     p.SIM_Product_Name,
# MAGIC     p.SIM_Product_Type,
# MAGIC     p.Data_Threshold_GB,
# MAGIC     COALESCE(b.actual_days, 0) AS actual_active_days,
# MAGIC     p.Billable_Days AS original_prepaid_days,
# MAGIC     ROUND(
# MAGIC       p.Billable_Fee_Time * (p.Billable_Days - COALESCE(b.actual_days, 0)) / p.Billable_Days,
# MAGIC       4
# MAGIC     ) AS refund_fee_time,
# MAGIC     ROUND(
# MAGIC       p.Billable_Fee_Usage * (p.Billable_Days - COALESCE(b.actual_days, 0)) / p.Billable_Days,
# MAGIC       2
# MAGIC     ) AS refund_fee_usage,
# MAGIC     ROUND(
# MAGIC       p.Billable_Fee_Final * (p.Billable_Days - COALESCE(b.actual_days, 0)) / p.Billable_Days,
# MAGIC       4
# MAGIC     ) AS refund_fee_final,
# MAGIC     p.Report_Date,
# MAGIC     p.year,
# MAGIC     p.month,
# MAGIC     p.types
# MAGIC   FROM prev_month_prepaid p
# MAGIC   LEFT JOIN (
# MAGIC     SELECT
# MAGIC       bd.imsi,
# MAGIC       pp.start_date AS pp_start,
# MAGIC       pp.end_date AS pp_end,
# MAGIC       COUNT(DISTINCT DATE(bd.partition_time)) AS actual_days
# MAGIC     FROM basic_data bd
# MAGIC     INNER JOIN prev_month_prepaid pp
# MAGIC       ON bd.imsi = pp.IMSI
# MAGIC     WHERE DATE(bd.partition_time) >= pp.start_date
# MAGIC       AND DATE(bd.partition_time) <= pp.end_date
# MAGIC       AND bd.rm = 1
# MAGIC     GROUP BY bd.imsi, pp.start_date, pp.end_date
# MAGIC   ) b
# MAGIC     ON p.IMSI = b.imsi
# MAGIC    AND p.start_date = b.pp_start
# MAGIC    AND p.end_date = b.pp_end
# MAGIC   WHERE COALESCE(b.actual_days, 0) < p.Billable_Days
# MAGIC     AND p.IMSI NOT IN (
# MAGIC       SELECT DISTINCT imsi
# MAGIC       FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
# MAGIC       WHERE LEFT(final_start_date, 7) = DATE_FORMAT(ADD_MONTHS(CURRENT_DATE(), -1), 'yyyy-MM')
# MAGIC         AND final_charge IS NOT NULL
# MAGIC         AND final_charge != '-'
# MAGIC         AND charge_type = 'Full Cycle Charge'
# MAGIC     )
# MAGIC ),
# MAGIC card_details AS (
# MAGIC   -- 单周期卡
# MAGIC   SELECT
# MAGIC     imsi,
# MAGIC     product_id,
# MAGIC     SIM_Product_Data_Capacity,
# MAGIC     Cycle_Start_Time,
# MAGIC     Cycle_End_Time,
# MAGIC     date_diff(final_end_date, start_date) + 1 AS billing_days,
# MAGIC     start_date,
# MAGIC     final_end_date AS end_date,
# MAGIC     cycle_days,
# MAGIC     types
# MAGIC   FROM (
# MAGIC     SELECT
# MAGIC       imsi,
# MAGIC       product_id,
# MAGIC       SIM_Product_Data_Capacity,
# MAGIC       Cycle_Start_Time,
# MAGIC       Cycle_End_Time,
# MAGIC       start_date,
# MAGIC       max_date,
# MAGIC       end_date,
# MAGIC       types,
# MAGIC       cycle_days,
# MAGIC       CASE
# MAGIC         WHEN max_date < last_day(ADD_MONTHS(NOW(), -1)) AND max_date < end_date THEN max_date
# MAGIC         ELSE end_date
# MAGIC       END AS final_end_date
# MAGIC     FROM (
# MAGIC       SELECT
# MAGIC         imsi,
# MAGIC         product_id,
# MAGIC         TRY_CAST(SIM_Product_Data_Capacity AS DOUBLE) / 1024 AS SIM_Product_Data_Capacity,
# MAGIC         Cycle_Start_Time,
# MAGIC         Cycle_End_Time,
# MAGIC         COUNT(1) AS billing_days,
# MAGIC         MIN(DATE(partition_time)) AS start_date,
# MAGIC         MAX(DATE(partition_time)) AS max_date,
# MAGIC         DATE(Cycle_End_Time) AS end_date,
# MAGIC         1 AS types,
# MAGIC         DATEDIFF(DATE(Cycle_End_Time + INTERVAL 1 MINUTE), DATE(Cycle_Start_Time)) AS cycle_days
# MAGIC       FROM (
# MAGIC         SELECT b.*, c.cycles_nums
# MAGIC         FROM basic_data b
# MAGIC         LEFT JOIN cycle_counts c
# MAGIC           ON b.imsi = c.imsi
# MAGIC         WHERE c.cycles_nums = 1
# MAGIC           AND b.rm = 1
# MAGIC       ) x
# MAGIC       GROUP BY ALL
# MAGIC     ) t
# MAGIC   ) t1
# MAGIC
# MAGIC   UNION ALL
# MAGIC
# MAGIC   -- 多周期卡：跨月部分
# MAGIC   SELECT
# MAGIC     imsi,
# MAGIC     product_id,
# MAGIC     SIM_Product_Data_Capacity,
# MAGIC     Cycle_Start_Time,
# MAGIC     Cycle_End_Time,
# MAGIC     date_diff(end_date, max_date) AS billing_days,
# MAGIC     max_date AS start_date,
# MAGIC     end_date,
# MAGIC     cycle_days,
# MAGIC     types
# MAGIC   FROM (
# MAGIC     SELECT
# MAGIC       imsi,
# MAGIC       product_id,
# MAGIC       SIM_Product_Data_Capacity,
# MAGIC       Cycle_Start_Time,
# MAGIC       Cycle_End_Time,
# MAGIC       start_date,
# MAGIC       max_date,
# MAGIC       IF(max_date < last_day(ADD_MONTHS(NOW(), -1)) AND max_date < end_date, max_date, end_date) AS end_date,
# MAGIC       types,
# MAGIC       cycle_days
# MAGIC     FROM (
# MAGIC       SELECT
# MAGIC         imsi,
# MAGIC         product_id,
# MAGIC         TRY_CAST(SIM_Product_Data_Capacity AS DOUBLE) / 1024 AS SIM_Product_Data_Capacity,
# MAGIC         Cycle_Start_Time,
# MAGIC         Cycle_End_Time,
# MAGIC         COUNT(1) AS billing_days,
# MAGIC         MIN(DATE(partition_time)) AS start_date,
# MAGIC         MAX(DATE(partition_time)) AS max_date,
# MAGIC         DATE(Cycle_End_Time) AS end_date,
# MAGIC         2 AS types,
# MAGIC         DATEDIFF(DATE(Cycle_End_Time + INTERVAL 1 MINUTE), DATE(Cycle_Start_Time)) AS cycle_days
# MAGIC       FROM (
# MAGIC         SELECT b.*, c.cycles_nums
# MAGIC         FROM basic_data b
# MAGIC         LEFT JOIN cycle_counts c
# MAGIC           ON b.imsi = c.imsi
# MAGIC         WHERE c.cycles_nums > 1
# MAGIC           AND b.rm = 1
# MAGIC       ) x
# MAGIC       GROUP BY ALL
# MAGIC     ) t
# MAGIC   ) t2
# MAGIC   WHERE end_date > max_date
# MAGIC
# MAGIC   UNION ALL
# MAGIC
# MAGIC   -- 预付费卡
# MAGIC   SELECT
# MAGIC     imsi,
# MAGIC     product_id,
# MAGIC     SIM_Product_Data_Capacity,
# MAGIC     Cycle_Start_Time,
# MAGIC     Cycle_End_Time,
# MAGIC     date_diff(prepaid_end, max_date) + 1 AS billing_days,
# MAGIC     max_date AS start_date,
# MAGIC     prepaid_end AS end_date,
# MAGIC     cycle_days,
# MAGIC     2 AS types
# MAGIC   FROM (
# MAGIC     SELECT
# MAGIC       b.imsi,
# MAGIC       MAX_BY(b.product_id, b.Cycle_End_Time) AS product_id,
# MAGIC       TRY_CAST(MAX_BY(b.SIM_Product_Data_Capacity, b.Cycle_End_Time) AS DOUBLE) / 1024 AS SIM_Product_Data_Capacity,
# MAGIC       MAX_BY(b.Cycle_Start_Time, b.Cycle_End_Time) AS Cycle_Start_Time,
# MAGIC       MAX(b.Cycle_End_Time) AS Cycle_End_Time,
# MAGIC       MAX(DATE(b.partition_time)) AS max_date,
# MAGIC       IF(
# MAGIC         MAX(DATE(b.partition_time)) < last_day(ADD_MONTHS(NOW(), -1))
# MAGIC         AND MAX(DATE(b.partition_time)) < DATE(MAX(b.Cycle_End_Time)),
# MAGIC         MAX(DATE(b.partition_time)),
# MAGIC         DATE(MAX(b.Cycle_End_Time))
# MAGIC       ) AS prepaid_end,
# MAGIC       DATEDIFF(
# MAGIC         DATE(MAX(b.Cycle_End_Time) + INTERVAL 1 MINUTE),
# MAGIC         DATE(MAX_BY(b.Cycle_Start_Time, b.Cycle_End_Time))
# MAGIC       ) AS cycle_days
# MAGIC     FROM basic_data b
# MAGIC     JOIN cycle_counts c
# MAGIC       ON b.imsi = c.imsi
# MAGIC     WHERE c.cycles_nums > 1
# MAGIC       AND b.rm = 1
# MAGIC     GROUP BY b.imsi
# MAGIC   ) t3
# MAGIC   WHERE prepaid_end > max_date
# MAGIC ),
# MAGIC billing_data AS (
# MAGIC   SELECT
# MAGIC     Billing_Period,
# MAGIC     IMSI,
# MAGIC     Cycle_Start_Time,
# MAGIC     Cycle_End_Time,
# MAGIC     ICCID,
# MAGIC     SIM_Supplier,
# MAGIC     SIM_Product_ID,
# MAGIC     SIM_Product_Name,
# MAGIC     SIM_Product_Type,
# MAGIC     Data_Capacity_GB,
# MAGIC     Data_Threshold_GB,
# MAGIC     Plan_Price,
# MAGIC     Billing_Days,
# MAGIC     CASE
# MAGIC       WHEN is_first_time = 1 AND activation_date IS NOT NULL AND DATE(activation_date) > end_date THEN 0
# MAGIC       WHEN is_first_time = 1 AND start_date > DATE(Cycle_Start_Time) AND types = 2 THEN 0
# MAGIC       WHEN is_first_time = 1 AND start_date > DATE(Cycle_Start_Time)
# MAGIC         THEN date_diff(LAST_DAY(ADD_MONTHS(NOW(), -1)), start_date) + 1
# MAGIC       WHEN is_first_time = 1 AND max_partition_date >= DATE(Cycle_End_Time)
# MAGIC         THEN DAY(LAST_DAY(ADD_MONTHS(NOW(), -1)))
# MAGIC       WHEN COALESCE(had_prev_month_bill, 0) = 0
# MAGIC         AND types = 1
# MAGIC         AND date(Cycle_Start_Time) >= DATE_FORMAT(ADD_MONTHS(NOW(), -1), 'yyyy-MM-01')
# MAGIC         THEN date_diff(
# MAGIC           LAST_DAY(ADD_MONTHS(NOW(), -1)),
# MAGIC           COALESCE(DATE(activation_date), start_date)
# MAGIC         )
# MAGIC       ELSE Billable_Days
# MAGIC     END AS Billable_Days,
# MAGIC     data_usage_gb,
# MAGIC     ROUND(
# MAGIC       CASE
# MAGIC         WHEN is_first_time = 1 AND activation_date IS NOT NULL AND DATE(activation_date) > end_date THEN 0
# MAGIC         WHEN is_first_time = 1 AND start_date > DATE(Cycle_Start_Time) AND types = 2 THEN 0
# MAGIC         WHEN is_first_time = 1 AND start_date > DATE(Cycle_Start_Time)
# MAGIC           THEN (date_diff(LAST_DAY(ADD_MONTHS(NOW(), -1)), start_date) + 1) / billing_days * Plan_Price
# MAGIC         WHEN is_first_time = 1 AND max_partition_date >= DATE(Cycle_End_Time)
# MAGIC           THEN DAY(LAST_DAY(ADD_MONTHS(NOW(), -1))) / billing_days * Plan_Price
# MAGIC         WHEN COALESCE(had_prev_month_bill, 0) = 0
# MAGIC           AND types = 1
# MAGIC           AND date(Cycle_Start_Time) >= DATE_FORMAT(ADD_MONTHS(NOW(), -1), 'yyyy-MM-01')
# MAGIC           THEN date_diff(
# MAGIC             LAST_DAY(ADD_MONTHS(NOW(), -1)),
# MAGIC             COALESCE(DATE(activation_date), start_date)
# MAGIC           ) / billing_days * Plan_Price
# MAGIC         ELSE Billable_Days / billing_days * Plan_Price
# MAGIC       END,
# MAGIC       4
# MAGIC     ) AS Billable_Fee_Time,
# MAGIC     CASE
# MAGIC       WHEN is_first_time = 1 AND activation_date IS NOT NULL AND DATE(activation_date) > end_date THEN 0
# MAGIC       WHEN is_first_time = 1 AND start_date > DATE(Cycle_Start_Time) AND types = 2 THEN 0
# MAGIC       WHEN is_first_time = 1 AND start_date > DATE(Cycle_Start_Time) AND is_replacement = 0 THEN 0
# MAGIC       ELSE ROUND(data_usage_gb / Data_Capacity_GB * Plan_Price, 2)
# MAGIC     END AS Billable_Fee_Usage,
# MAGIC     Report_Date,
# MAGIC     year,
# MAGIC     month,
# MAGIC     types,
# MAGIC     start_date,
# MAGIC     end_date,
# MAGIC     is_first_time,
# MAGIC     max_partition_date,
# MAGIC     had_prev_month_bill
# MAGIC   FROM (
# MAGIC     SELECT
# MAGIC       CONCAT(
# MAGIC         REPLACE(TRUNC(ADD_MONTHS(CURRENT_DATE(), -1), 'MM'), '-', ''),
# MAGIC         '-',
# MAGIC         REPLACE(LAST_DAY(ADD_MONTHS(CURRENT_DATE(), -1)), '-', '')
# MAGIC       ) AS Billing_Period,
# MAGIC       s1.imsi AS IMSI,
# MAGIC       s1.Cycle_Start_Time,
# MAGIC       s1.Cycle_End_Time,
# MAGIC       s2.iccid_show AS ICCID,
# MAGIC       s5.CARRIER_NAME AS SIM_Supplier,
# MAGIC       s1.product_id AS SIM_Product_ID,
# MAGIC       s4.product_name AS SIM_Product_Name,
# MAGIC       CASE WHEN s4.is_local = 1 THEN 'Local' ELSE 'Roaming' END AS SIM_Product_Type,
# MAGIC       s1.SIM_Product_Data_Capacity AS Data_Capacity_GB,
# MAGIC       0 AS Data_Threshold_GB,
# MAGIC       -- 价格全部走平台，不硬编码
# MAGIC       s4.package_price AS Plan_Price,
# MAGIC       s1.cycle_days AS Billing_Days,
# MAGIC       s1.billing_days AS Billable_Days,
# MAGIC       0.0 AS data_usage_gb,
# MAGIC       CURRENT_DATE() AS Report_Date,
# MAGIC       YEAR(ADD_MONTHS(CURRENT_DATE(), -1)) AS year,
# MAGIC       MONTH(ADD_MONTHS(CURRENT_DATE(), -1)) AS month,
# MAGIC       s1.types,
# MAGIC       s1.cycle_days,
# MAGIC       s1.start_date,
# MAGIC       s1.end_date,
# MAGIC       COALESCE(ft.is_first_time, 0) AS is_first_time,
# MAGIC       imd.max_partition_date,
# MAGIC       iad.activation_date,
# MAGIC       CASE WHEN pmb.IMSI IS NOT NULL THEN 1 ELSE 0 END AS had_prev_month_bill,
# MAGIC       CASE WHEN ri.imsi IS NOT NULL THEN 1 ELSE 0 END AS is_replacement
# MAGIC     FROM card_details s1
# MAGIC     LEFT JOIN first_time_imsi ft
# MAGIC       ON s1.imsi = ft.imsi
# MAGIC     LEFT JOIN imsi_max_date imd
# MAGIC       ON s1.imsi = imd.imsi
# MAGIC      AND s1.Cycle_End_Time = imd.Cycle_End_Time
# MAGIC     LEFT JOIN imsi_activation_date iad
# MAGIC       ON s1.imsi = iad.IMSI
# MAGIC     LEFT JOIN prev_month_billed_imsi pmb
# MAGIC       ON s1.imsi = pmb.IMSI
# MAGIC     LEFT JOIN replacement_imsi ri
# MAGIC       ON s1.imsi = ri.imsi
# MAGIC     LEFT JOIN ods.resource_res_vsim_billing s2
# MAGIC       ON s1.imsi = s2.imsi
# MAGIC     LEFT JOIN ods.resource_res_vsim_product s4
# MAGIC       ON s1.product_id = s4.product_id
# MAGIC     LEFT JOIN ods.resource_res_carrier s5
# MAGIC       ON s4.supplier_id = s5.id
# MAGIC     WHERE s5.CARRIER_NAME = 'Wing Alpha'
# MAGIC       AND s4.product_name NOT LIKE '%PI%'
# MAGIC   ) x
# MAGIC )
# MAGIC SELECT
# MAGIC   Billing_Period,
# MAGIC   IMSI,
# MAGIC   ICCID,
# MAGIC   Cycle_Start_Time,
# MAGIC   Cycle_End_Time,
# MAGIC   data_usage_gb,
# MAGIC   SIM_Product_Name AS Plan_Name,
# MAGIC   Data_Capacity_GB,
# MAGIC   Plan_Price,
# MAGIC   start_date,
# MAGIC   end_date,
# MAGIC   SIM_Supplier,
# MAGIC   Billing_Days,
# MAGIC   SIM_Product_ID,
# MAGIC   SIM_Product_Name,
# MAGIC   SIM_Product_Type,
# MAGIC   Data_Threshold_GB,
# MAGIC   Billable_Days,
# MAGIC   IF(Billable_Fee_Time > Plan_Price, Plan_Price, Billable_Fee_Time) AS Billable_Fee_Time,
# MAGIC   IF(Billable_Fee_Usage > Plan_Price, Plan_Price, Billable_Fee_Usage) AS Billable_Fee_Usage,
# MAGIC   IF(
# MAGIC     IF(Billable_Fee_Usage > Billable_Fee_Time, Billable_Fee_Usage, Billable_Fee_Time) > Plan_Price,
# MAGIC     Plan_Price,
# MAGIC     IF(Billable_Fee_Usage > Billable_Fee_Time, Billable_Fee_Usage, Billable_Fee_Time)
# MAGIC   ) AS Billable_Fee_Final,
# MAGIC   Report_Date,
# MAGIC   year,
# MAGIC   month,
# MAGIC   types,
# MAGIC   CASE
# MAGIC     WHEN DATE(Cycle_Start_Time) >= DATE_FORMAT(ADD_MONTHS(NOW(), -2), 'yyyy-MM-01')
# MAGIC       AND DATE(Cycle_Start_Time) < DATE_FORMAT(ADD_MONTHS(NOW(), -1), 'yyyy-MM-01')
# MAGIC       AND DATE(Cycle_End_Time) >= DATE_FORMAT(ADD_MONTHS(NOW(), -1), 'yyyy-MM-01')
# MAGIC     THEN 1
# MAGIC     ELSE 2
# MAGIC   END AS billing_state
# MAGIC FROM billing_data
# MAGIC WHERE NOT (
# MAGIC   types = 1
# MAGIC   AND COALESCE(had_prev_month_bill, 0) = 0
# MAGIC   AND DATE(Cycle_Start_Time) >= DATE_FORMAT(ADD_MONTHS(NOW(), -1), 'yyyy-MM-01')
# MAGIC   AND DATE(Cycle_Start_Time) < DATE_FORMAT(ADD_MONTHS(NOW(), 0), 'yyyy-MM-01')
# MAGIC   AND DATE(Cycle_End_Time) >= DATE_FORMAT(ADD_MONTHS(NOW(), 0), 'yyyy-MM-01')
# MAGIC )
# MAGIC
# MAGIC UNION ALL
# MAGIC
# MAGIC SELECT
# MAGIC   Billing_Period,
# MAGIC   IMSI,
# MAGIC   ICCID,
# MAGIC   Cycle_Start_Time,
# MAGIC   Cycle_End_Time,
# MAGIC   data_usage_gb,
# MAGIC   Plan_Name,
# MAGIC   Data_Capacity_GB,
# MAGIC   Plan_Price,
# MAGIC   start_date,
# MAGIC   end_date,
# MAGIC   SIM_Supplier,
# MAGIC   Billing_Days,
# MAGIC   SIM_Product_ID,
# MAGIC   SIM_Product_Name,
# MAGIC   SIM_Product_Type,
# MAGIC   Data_Threshold_GB,
# MAGIC   actual_active_days AS Billable_Days,
# MAGIC   -refund_fee_time AS Billable_Fee_Time,
# MAGIC   -refund_fee_usage AS Billable_Fee_Usage,
# MAGIC   -refund_fee_final AS Billable_Fee_Final,
# MAGIC   CURRENT_DATE() AS Report_Date,
# MAGIC   year,
# MAGIC   month,
# MAGIC   types,
# MAGIC   3 AS billing_state
# MAGIC FROM refund_data;
# MAGIC

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 2: 总金额

# COMMAND ----------

# MAGIC %sql
# MAGIC
# MAGIC SELECT
# MAGIC   billing_state,
# MAGIC   types,
# MAGIC   COUNT(*) AS rows,
# MAGIC   COUNT(DISTINCT IMSI) AS cards,
# MAGIC   ROUND(SUM(Billable_Fee_Final), 2) AS total
# MAGIC FROM simo_prod.mysql_cdc_sync.card_billing_test01
# MAGIC GROUP BY billing_state, types
# MAGIC ORDER BY billing_state, types;

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 5: 修正退款 — 去掉 Full Cycle 卡的错误退款

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT
# MAGIC   Billing_Period,
# MAGIC   COUNT(*) AS rows,
# MAGIC   COUNT(DISTINCT IMSI) AS cards,
# MAGIC   ROUND(SUM(Billable_Fee_Time), 2) AS total_fee_time,
# MAGIC   ROUND(SUM(Billable_Fee_Usage), 2) AS total_fee_usage,
# MAGIC   ROUND(SUM(Billable_Fee_Final), 2) AS total_fee_final
# MAGIC FROM simo_prod.mysql_cdc_sync.card_billing_test01
# MAGIC GROUP BY Billing_Period
# MAGIC ORDER BY Billing_Period;

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 6: 修正退款 + 修正价格 — 最终对账

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT 'refund_and_price_fixed' as version,
# MAGIC   ROUND(SUM(
# MAGIC     CASE
# MAGIC       WHEN SIM_Product_ID = '600111087' AND Plan_Price = 43 THEN Billable_Fee_Final / 43 * 62
# MAGIC       -- July: only 600111087 needs fix
# MAGIC       ELSE Billable_Fee_Final
# MAGIC     END
# MAGIC   ), 2) as total
# MAGIC FROM simo_prod.dm.card_billing_report_detail_new02
# MAGIC WHERE Billing_Period = '20260701-20260731'
# MAGIC   AND SIM_Supplier = 'Wing Alpha' AND SIM_Product_Name NOT LIKE '%PI%'
# MAGIC   AND (
# MAGIC     billing_state = 2
# MAGIC     OR (billing_state = 3
# MAGIC       AND IMSI NOT IN (
# MAGIC         SELECT DISTINCT imsi
# MAGIC         FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
# MAGIC         WHERE LEFT(final_start_date, 7) = '2026-07'
# MAGIC           AND final_charge IS NOT NULL AND final_charge != '-'
# MAGIC           AND charge_type = 'Full Cycle Charge'
# MAGIC       )
# MAGIC     )
# MAGIC   )

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 7: Excel 7月总额

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT 'excel' as version, COUNT(*) as rows, COUNT(DISTINCT imsi) as cards, ROUND(SUM(CAST(final_charge AS DOUBLE)), 2) as total
# MAGIC FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
# MAGIC WHERE LEFT(final_start_date, 7) = '2026-07'
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
# MAGIC WHERE Billing_Period = '20260701-20260731'
# MAGIC   AND SIM_Supplier = 'Wing Alpha'
# MAGIC   AND SIM_Product_ID = '600111087'
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
# MAGIC WHERE LEFT(final_start_date, 7) = '2026-07'
# MAGIC   AND final_charge IS NOT NULL AND final_charge != '-'
# MAGIC   AND (product_name LIKE '%ATM RT%' OR product_name LIKE '%SP RA%'
# MAGIC     OR product_name LIKE '%DI MZ%' OR product_name LIKE '%AT (1) (A)%')
# MAGIC GROUP BY product_name, CAST(monthly_rate AS DOUBLE)
# MAGIC
# MAGIC ORDER BY product_name, src