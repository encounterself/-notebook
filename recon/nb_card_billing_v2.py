# Databricks notebook source
# MAGIC %md
# MAGIC # Card Billing V2 — 对齐 Wing Alpha Excel 计费逻辑
# MAGIC
# MAGIC ## 核心公式
# MAGIC ```
# MAGIC final_charge = final_days / DAY(LAST_DAY(cycle_start)) × package_price
# MAGIC ```
# MAGIC
# MAGIC ## 7 条已验证规则
# MAGIC 1. **SimStatus 过滤**: `= 'Ready'`（不是 `!= 'Installed'`）
# MAGIC 2. **时区**: `partition_time` 不减时区，用原始 UTC 日期
# MAGIC 3. **分母**: `DAY(LAST_DAY(cycle_start))` 自然月天数
# MAGIC 4. **计费天数**: 日历天数（DATEDIFF + 1），不扣中间挂起
# MAGIC 5. **Full Cycle**: 上月有 Ready → Full Cycle = Plan_Price
# MAGIC 6. **双账期**: 同一 IMSI 同月可有多条记录（不按 IMSI 去重）
# MAGIC 7. **New Activation**: 截止到 cycle_end，不截月末
# MAGIC
# MAGIC ## 价格说明
# MAGIC 使用平台 `package_price`，不硬编码覆盖。以下 4 个产品与 Excel 价格不一致（已知差异）：
# MAGIC - 600111087 (AT&T 300GB Plan ATM RT): 平台 $43, Excel $62
# MAGIC - 600111150 (AT&T 150GB Plan SP RA): 平台 $62, Excel $43
# MAGIC - 60011921 (ATT Unlimited Plan DI MZ): 平台 $62, Excel $43
# MAGIC - 600111214: 平台 $62, Excel $43
# MAGIC
# MAGIC ## 数据源
# MAGIC - 平台: `tc_cdr.sim_status_for_sftp_bak`, `ods.resource_res_vsim_*`
# MAGIC - Excel: `mysql_cdc_sync.wa_invoice_detail`, `mysql_cdc_sync.wa_invoice_prorated`

# COMMAND ----------

# MAGIC %md
# MAGIC ## Cell 1: 创建目标表

# COMMAND ----------

# MAGIC %sql
# MAGIC CREATE TABLE IF NOT EXISTS simo_prod.mysql_cdc_sync.card_billing_v2_detail (
# MAGIC   Billing_Period STRING,
# MAGIC   IMSI STRING,
# MAGIC   ICCID STRING,
# MAGIC   Cycle_Start_Time STRING,
# MAGIC   Cycle_End_Time STRING,
# MAGIC   SIM_Supplier STRING,
# MAGIC   SIM_Product_ID STRING,
# MAGIC   SIM_Product_Name STRING,
# MAGIC   SIM_Product_Type STRING,
# MAGIC   Data_Capacity_GB DOUBLE,
# MAGIC   Plan_Price DOUBLE,
# MAGIC   Natural_Month_Days INT,
# MAGIC   Charge_Type STRING,
# MAGIC   Final_Start_Date DATE,
# MAGIC   Final_End_Date DATE,
# MAGIC   Final_Days INT,
# MAGIC   Final_Charge DOUBLE,
# MAGIC   Report_Date DATE,
# MAGIC   year INT,
# MAGIC   month INT
# MAGIC );

# COMMAND ----------

# MAGIC %sql
# MAGIC CREATE TABLE IF NOT EXISTS simo_prod.mysql_cdc_sync.card_billing_v2_prorated (
# MAGIC   Billing_Period STRING,
# MAGIC   IMSI STRING,
# MAGIC   ICCID STRING,
# MAGIC   Product_Name STRING,
# MAGIC   Cycle_Start_Time STRING,
# MAGIC   Cycle_End_Time STRING,
# MAGIC   New_Activation_Date DATE,
# MAGIC   Final_Start_Date DATE,
# MAGIC   Final_End_Date DATE,
# MAGIC   Active_Days INT,
# MAGIC   Monthly_Rate DOUBLE,
# MAGIC   Original_Charge DOUBLE,
# MAGIC   Usage_Days INT,
# MAGIC   Final_Charge_For_Usage_Days DOUBLE,
# MAGIC   Pending_Charge DOUBLE,
# MAGIC   Report_Date DATE,
# MAGIC   year INT,
# MAGIC   month INT
# MAGIC );

# COMMAND ----------

# MAGIC %sql
# MAGIC -- 清空表（重新计算时取消注释）
# MAGIC -- TRUNCATE TABLE simo_prod.mysql_cdc_sync.card_billing_v2_detail;
# MAGIC -- TRUNCATE TABLE simo_prod.mysql_cdc_sync.card_billing_v2_prorated;
# MAGIC SELECT 'Tables ready' AS status

# COMMAND ----------

# MAGIC %md
# MAGIC ## Cell 2: 逐月循环处理 Detail 费用
# MAGIC
# MAGIC 核心改动（相对原 notebook）：
# MAGIC - `SimStatus = 'Ready'` 替代 `!= 'Installed'`
# MAGIC - `DATE(partition_time)` 不减时区
# MAGIC - 不按 IMSI 去重，按 (IMSI, Cycle_Start, Cycle_End) 分组
# MAGIC - 分母 = DAY(LAST_DAY(cycle_start))
# MAGIC - 日历天数 = DATEDIFF(end, start) + 1
# MAGIC - 从 status_log 查激活/作废日期

# COMMAND ----------

from datetime import date, timedelta
from dateutil.relativedelta import relativedelta

start_month = date(2025, 9, 1)
end_month = date(2026, 8, 1)

current = start_month
while current <= end_month:
    billing_month_str = current.strftime('%Y-%m-%d')
    last_day = (current + relativedelta(months=1) - timedelta(days=1)).strftime('%Y-%m-%d')
    prev_month_end = (current - timedelta(days=1)).strftime('%Y-%m-%d')
    prev_prev_month_end = (current - relativedelta(months=1) - timedelta(days=1)).strftime('%Y-%m-%d')

    billing_period = current.strftime('%Y%m%d') + '-' + (current + relativedelta(months=1) - timedelta(days=1)).strftime('%Y%m%d')

    # Pace 卡过滤：2026-04 之前不过滤
    pace_filter = "AND SIM_Product_Name NOT LIKE '%PI%'" if current >= date(2026, 4, 1) else ""

    sql = f"""
    INSERT INTO simo_prod.mysql_cdc_sync.card_billing_v2_detail
    WITH basic_data AS (
      SELECT
        imsi, product_id, SIM_Product_Data_Capacity,
        DATE(partition_time) AS partition_date,
        Cycle_Start_Time - INTERVAL 5 HOUR AS Cycle_Start_Time,
        Cycle_End_Time - INTERVAL 5 HOUR AS Cycle_End_Time,
        ROW_NUMBER() OVER(
          PARTITION BY DATE(partition_time), imsi
          ORDER BY partition_time
        ) AS rm
      FROM (
        SELECT
          s1.imsi,
          IF(DATE(Cycle_End_Time) <= DATE('{last_day}'), s2.product_id, s1.product_id) AS product_id,
          ICCID, SIM_Product_Threshold, SIM_Product_Data_Capacity,
          IF(DATE(Cycle_End_Time) <= DATE('{last_day}'),
             DATE_FORMAT(s2.cycle_time, 'yyyy-MM-dd HH:mm:ss'), s1.Cycle_Start_Time) AS Cycle_Start_Time,
          IF(DATE(Cycle_End_Time) <= DATE('{last_day}'),
             DATE_FORMAT(s2.next_cycle_time, 'yyyy-MM-dd HH:mm:ss'), s1.Cycle_End_Time) AS Cycle_End_Time,
          DispatchStatus, SimStatus, year, month, day, hour, partition_time
        FROM (
          SELECT * FROM simo_prod.tc_cdr.sim_status_for_sftp_bak
          WHERE DATE(partition_time) > DATE('{prev_month_end}')
            AND DATE(partition_time) <= DATE('{last_day}')
        ) s1
        LEFT JOIN (
          SELECT imsi, product_id, cycle_time, next_cycle_time FROM (
            SELECT *, ROW_NUMBER() OVER(
              PARTITION BY imsi, YEAR(cycle_time), MONTH(cycle_time)
              ORDER BY create_time DESC
            ) rm
            FROM simo_prod.ods.resource_res_vsim_cycle_history
          ) WHERE rm = 1
        ) s2
        ON s1.imsi = s2.imsi
        AND YEAR(s1.Cycle_Start_Time) = YEAR(s2.cycle_time)
        AND MONTH(s1.Cycle_Start_Time) = MONTH(s2.cycle_time)
      )
      WHERE SimStatus = 'Ready'
        AND Cycle_Start_Time IS NOT NULL
    ),

    -- 按账期分组，不去重（同一 IMSI 可有多个账期）
    card_cycles AS (
      SELECT
        imsi, product_id,
        TRY_CAST(SIM_Product_Data_Capacity AS DOUBLE)/1024 AS Data_Capacity_GB,
        Cycle_Start_Time, Cycle_End_Time,
        DATE(Cycle_Start_Time) AS cycle_start_date,
        DATE(Cycle_End_Time) AS cycle_end_date,
        MIN(partition_date) AS first_ready_date,
        MAX(partition_date) AS last_ready_date,
        COUNT(DISTINCT partition_date) AS active_days,
        DAY(LAST_DAY(DATE(Cycle_Start_Time))) AS natural_month_days
      FROM basic_data
      WHERE rm = 1
      GROUP BY imsi, product_id, SIM_Product_Data_Capacity, Cycle_Start_Time, Cycle_End_Time
    ),

    -- 从 status_log 获取激活日期
    activation_dates AS (
      SELECT IMSI, MIN(DATE(CREATE_DATE)) AS activation_date
      FROM simo_prod.ods.resource_res_vsim_status_log
      WHERE NEXT_STATUS = '激活'
      GROUP BY IMSI
    ),

    -- 从 status_log 获取作废日期
    deactivation_dates AS (
      SELECT IMSI, MAX(DATE(CREATE_DATE)) AS deactivation_date
      FROM simo_prod.ods.resource_res_vsim_status_log
      WHERE NEXT_STATUS = '作废'
      GROUP BY IMSI
    ),

    -- 上月是否有 Ready 记录
    prev_month_ready AS (
      SELECT DISTINCT imsi
      FROM simo_prod.tc_cdr.sim_status_for_sftp_bak
      WHERE DATE(partition_time) > DATE('{prev_prev_month_end}')
        AND DATE(partition_time) <= DATE('{prev_month_end}')
        AND SimStatus = 'Ready'
    ),

    -- 分类 charge_type
    classified AS (
      SELECT
        cc.*,
        ad.activation_date,
        dd.deactivation_date,
        CASE WHEN pmr.imsi IS NOT NULL THEN 1 ELSE 0 END AS had_prev_ready,
        CASE
          -- 1. 作废日在账期开始前 → 不收费
          WHEN dd.deactivation_date IS NOT NULL
            AND dd.deactivation_date < cc.cycle_start_date
          THEN 'Offstocked before cycle start'

          -- 2. 新激活：激活日在账期中间 → 按比例
          WHEN ad.activation_date IS NOT NULL
            AND ad.activation_date > cc.cycle_start_date
            AND ad.activation_date >= DATE('{billing_month_str}')
            AND ad.activation_date <= DATE('{last_day}')
          THEN 'New Activation: Prorated-in Charge'

          -- 3. 作废日在账期中间 → 旧卡换卡/退卡
          WHEN dd.deactivation_date IS NOT NULL
            AND dd.deactivation_date >= cc.cycle_start_date
            AND dd.deactivation_date < cc.cycle_end_date
            AND dd.deactivation_date >= DATE('{billing_month_str}')
            AND dd.deactivation_date <= DATE('{last_day}')
          THEN 'Partial Charge - Card Replaced Mid Cycle'

          -- 4. 上月有 Ready 且本周期完整 → Full Cycle
          WHEN pmr.imsi IS NOT NULL
            AND cc.cycle_start_date >= DATE('{billing_month_str}')
            AND cc.last_ready_date >= DATE('{last_day}')
          THEN 'Full Cycle Charge'

          -- 5. 账期跨月的尾部（账期从上月开始，本月仍活跃）
          WHEN cc.cycle_start_date < DATE('{billing_month_str}')
            AND cc.last_ready_date >= DATE('{billing_month_str}')
          THEN 'Partial Charge'

          -- 6. 上月有 Ready，账期在本月
          WHEN pmr.imsi IS NOT NULL
            AND cc.cycle_start_date >= DATE('{billing_month_str}')
          THEN 'Full Cycle Charge'

          -- 7. 本月新出现但无激活记录（可能迁移卡）
          WHEN cc.first_ready_date > cc.cycle_start_date
          THEN 'New Activation: Prorated-in Charge'

          ELSE 'Full Cycle Charge'
        END AS charge_type
      FROM card_cycles cc
      LEFT JOIN activation_dates ad ON cc.imsi = ad.IMSI
      LEFT JOIN deactivation_dates dd ON cc.imsi = dd.IMSI
      LEFT JOIN prev_month_ready pmr ON cc.imsi = pmr.imsi
    ),

    -- 关联维度表，计算费用
    billing_result AS (
      SELECT
        '{billing_period}' AS Billing_Period,
        c.imsi AS IMSI,
        s2.iccid_show AS ICCID,
        c.Cycle_Start_Time,
        c.Cycle_End_Time,
        s5.CARRIER_NAME AS SIM_Supplier,
        c.product_id AS SIM_Product_ID,
        s4.product_name AS SIM_Product_Name,
        CASE WHEN s4.is_local = 1 THEN 'Local' ELSE 'Roaming' END AS SIM_Product_Type,
        c.Data_Capacity_GB,
        s4.package_price AS Plan_Price,
        c.natural_month_days AS Natural_Month_Days,
        c.charge_type AS Charge_Type,
        -- Final_Start_Date
        CASE c.charge_type
          WHEN 'New Activation: Prorated-in Charge' THEN COALESCE(c.activation_date, c.first_ready_date)
          WHEN 'Partial Charge' THEN DATE('{billing_month_str}')
          ELSE c.cycle_start_date
        END AS Final_Start_Date,
        -- Final_End_Date
        CASE c.charge_type
          WHEN 'Offstocked before cycle start' THEN c.cycle_start_date
          WHEN 'Partial Charge - Card Replaced Mid Cycle' THEN c.deactivation_date
          WHEN 'Partial Charge' THEN LEAST(c.cycle_end_date, DATE('{last_day}'))
          ELSE c.cycle_end_date
        END AS Final_End_Date
      FROM classified c
      LEFT JOIN simo_prod.ods.resource_res_vsim_billing s2 ON c.imsi = s2.imsi
      LEFT JOIN simo_prod.ods.resource_res_vsim_product s4 ON c.product_id = s4.product_id
      LEFT JOIN simo_prod.ods.resource_res_carrier s5 ON s4.supplier_id = s5.id
      WHERE s5.CARRIER_NAME = 'Wing Alpha'
        {pace_filter}
    )

    SELECT
      Billing_Period, IMSI, ICCID, Cycle_Start_Time, Cycle_End_Time,
      SIM_Supplier, SIM_Product_ID, SIM_Product_Name, SIM_Product_Type,
      Data_Capacity_GB, Plan_Price, Natural_Month_Days, Charge_Type,
      Final_Start_Date, Final_End_Date,
      -- Final_Days
      CASE
        WHEN Charge_Type = 'Offstocked before cycle start' THEN 0
        ELSE DATEDIFF(Final_End_Date, Final_Start_Date) + 1
      END AS Final_Days,
      -- Final_Charge
      CASE
        WHEN Charge_Type = 'Offstocked before cycle start' THEN 0.0
        WHEN Charge_Type = 'Full Cycle Charge' THEN Plan_Price
        ELSE ROUND(
          (DATEDIFF(Final_End_Date, Final_Start_Date) + 1) * 1.0 / Natural_Month_Days * Plan_Price, 4)
      END AS Final_Charge,
      CURRENT_DATE() AS Report_Date,
      YEAR(DATE('{billing_month_str}')) AS year,
      MONTH(DATE('{billing_month_str}')) AS month
    FROM billing_result
    """

    spark.sql(sql)
    print(f"Processed {billing_period}")
    current += relativedelta(months=1)

print("Done!")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Cell 3: 验证 — 月度对账（平台 vs Excel）

# COMMAND ----------

# MAGIC %sql
# MAGIC WITH platform AS (
# MAGIC   SELECT
# MAGIC     CONCAT(year, '-', LPAD(month, 2, '0')) AS charge_month,
# MAGIC     COUNT(DISTINCT IMSI) AS platform_cards,
# MAGIC     COUNT(*) AS platform_rows,
# MAGIC     ROUND(SUM(Final_Charge), 2) AS platform_total
# MAGIC   FROM simo_prod.mysql_cdc_sync.card_billing_v2_detail
# MAGIC   GROUP BY year, month
# MAGIC ),
# MAGIC excel AS (
# MAGIC   SELECT
# MAGIC     LEFT(final_start_date, 7) AS charge_month,
# MAGIC     COUNT(DISTINCT imsi) AS excel_cards,
# MAGIC     COUNT(*) AS excel_rows,
# MAGIC     ROUND(SUM(CAST(final_charge AS DOUBLE)), 2) AS excel_total
# MAGIC   FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
# MAGIC   WHERE final_charge IS NOT NULL AND final_charge != '-' AND final_charge != ''
# MAGIC     AND final_start_date LIKE '20%'
# MAGIC   GROUP BY LEFT(final_start_date, 7)
# MAGIC )
# MAGIC SELECT
# MAGIC   COALESCE(p.charge_month, e.charge_month) AS month,
# MAGIC   e.excel_cards, e.excel_rows, e.excel_total,
# MAGIC   p.platform_cards, p.platform_rows, p.platform_total,
# MAGIC   ROUND(COALESCE(p.platform_total, 0) - COALESCE(e.excel_total, 0), 2) AS diff,
# MAGIC   CASE WHEN COALESCE(e.excel_total, 0) > 0
# MAGIC     THEN ROUND((COALESCE(p.platform_total, 0) - e.excel_total) * 100.0 / e.excel_total, 2)
# MAGIC   END AS diff_pct
# MAGIC FROM platform p
# MAGIC FULL OUTER JOIN excel e ON p.charge_month = e.charge_month
# MAGIC ORDER BY month

# COMMAND ----------

# MAGIC %md
# MAGIC ## Cell 4: 验证 — Charge Type 拆分对比

# COMMAND ----------

# MAGIC %sql
# MAGIC WITH platform AS (
# MAGIC   SELECT
# MAGIC     CONCAT(year, '-', LPAD(month, 2, '0')) AS charge_month,
# MAGIC     Charge_Type,
# MAGIC     COUNT(*) AS cnt,
# MAGIC     ROUND(SUM(Final_Charge), 2) AS total
# MAGIC   FROM simo_prod.mysql_cdc_sync.card_billing_v2_detail
# MAGIC   GROUP BY year, month, Charge_Type
# MAGIC ),
# MAGIC excel AS (
# MAGIC   SELECT
# MAGIC     LEFT(final_start_date, 7) AS charge_month,
# MAGIC     charge_type,
# MAGIC     COUNT(*) AS cnt,
# MAGIC     ROUND(SUM(CAST(final_charge AS DOUBLE)), 2) AS total
# MAGIC   FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
# MAGIC   WHERE final_charge IS NOT NULL AND final_charge != '-'
# MAGIC     AND final_start_date LIKE '20%'
# MAGIC   GROUP BY LEFT(final_start_date, 7), charge_type
# MAGIC )
# MAGIC SELECT
# MAGIC   COALESCE(p.charge_month, e.charge_month) AS month,
# MAGIC   COALESCE(p.Charge_Type, e.charge_type) AS charge_type,
# MAGIC   p.cnt AS platform_cnt, p.total AS platform_total,
# MAGIC   e.cnt AS excel_cnt, e.total AS excel_total,
# MAGIC   ROUND(COALESCE(p.total, 0) - COALESCE(e.total, 0), 2) AS diff
# MAGIC FROM platform p
# MAGIC FULL OUTER JOIN excel e
# MAGIC   ON p.charge_month = e.charge_month AND p.Charge_Type = e.charge_type
# MAGIC ORDER BY month, ABS(COALESCE(p.total, 0) - COALESCE(e.total, 0)) DESC

# COMMAND ----------

# MAGIC %md
# MAGIC ## Cell 5: 验证 — 逐卡对比（指定月份，修改 year/month 参数）

# COMMAND ----------

-- 修改下面的 year 和 month 来查看特定月份
DECLARE OR REPLACE VARIABLE check_year INT DEFAULT 2026;
DECLARE OR REPLACE VARIABLE check_month INT DEFAULT 6;

WITH platform AS (
  SELECT IMSI, Charge_Type, Final_Start_Date, Final_End_Date, Final_Days,
         Plan_Price, Final_Charge
  FROM simo_prod.mysql_cdc_sync.card_billing_v2_detail
  WHERE year = check_year AND month = check_month
),
excel AS (
  SELECT imsi, charge_type, final_start_date, final_end_date,
         CAST(final_days AS INT) AS final_days,
         CAST(monthly_rate AS DOUBLE) AS monthly_rate,
         CAST(final_charge AS DOUBLE) AS final_charge
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE final_charge IS NOT NULL AND final_charge != '-'
    AND final_start_date LIKE '20%'
    AND YEAR(DATE(final_start_date)) = check_year
    AND MONTH(DATE(final_start_date)) = check_month
)
SELECT
  COALESCE(p.IMSI, e.imsi) AS imsi,
  p.Charge_Type AS platform_type,
  e.charge_type AS excel_type,
  p.Final_Days AS platform_days,
  e.final_days AS excel_days,
  p.Plan_Price AS platform_rate,
  e.monthly_rate AS excel_rate,
  p.Final_Charge AS platform_charge,
  e.final_charge AS excel_charge,
  ROUND(COALESCE(p.Final_Charge, 0) - COALESCE(e.final_charge, 0), 2) AS charge_diff
FROM platform p
FULL OUTER JOIN excel e ON p.IMSI = e.imsi
WHERE ABS(COALESCE(p.Final_Charge, 0) - COALESCE(e.final_charge, 0)) > 0.01
   OR p.IMSI IS NULL
   OR e.imsi IS NULL
ORDER BY ABS(COALESCE(p.Final_Charge, 0) - COALESCE(e.final_charge, 0)) DESC
LIMIT 100

# COMMAND ----------

# MAGIC %md
# MAGIC ## Cell 6: 验证 — 价格差异产品分析

# COMMAND ----------

# MAGIC %sql
# MAGIC -- 查看 4 个价格不一致产品的差异
# MAGIC WITH price_diff_products AS (
# MAGIC   SELECT '600111087' AS product_id, 43 AS platform_price, 62 AS excel_price
# MAGIC   UNION ALL SELECT '600111150', 62, 43
# MAGIC   UNION ALL SELECT '60011921', 62, 43
# MAGIC   UNION ALL SELECT '600111214', 62, 43
# MAGIC )
# MAGIC SELECT
# MAGIC   CONCAT(d.year, '-', LPAD(d.month, 2, '0')) AS month,
# MAGIC   d.SIM_Product_ID,
# MAGIC   d.SIM_Product_Name,
# MAGIC   p.platform_price,
# MAGIC   p.excel_price,
# MAGIC   COUNT(*) AS card_count,
# MAGIC   ROUND(SUM(d.Final_Charge), 2) AS platform_total,
# MAGIC   ROUND(SUM(d.Final_Charge) / p.platform_price * p.excel_price, 2) AS if_excel_price,
# MAGIC   ROUND(SUM(d.Final_Charge) / p.platform_price * p.excel_price - SUM(d.Final_Charge), 2) AS price_impact
# MAGIC FROM simo_prod.mysql_cdc_sync.card_billing_v2_detail d
# MAGIC JOIN price_diff_products p ON d.SIM_Product_ID = p.product_id
# MAGIC GROUP BY d.year, d.month, d.SIM_Product_ID, d.SIM_Product_Name, p.platform_price, p.excel_price
# MAGIC ORDER BY month, d.SIM_Product_ID
# MAGIC SELECT 'Price diff analysis (uncomment above)' AS note

# COMMAND ----------

# MAGIC %md
# MAGIC ## Cell 7: Prorated Pending Charges（可选，需要用量数据）
# MAGIC
# MAGIC 从上月 New Activation 卡中，查 usage_days > active_days 的补收差额。
# MAGIC 需要 `tc_cdr.tc_udr_usage_data_records_details` 表。

# COMMAND ----------

from datetime import date, timedelta
from dateutil.relativedelta import relativedelta

start_month = date(2025, 10, 1)  # 从第2个月开始（需要有上月数据）
end_month = date(2026, 8, 1)

current = start_month
while current <= end_month:
    billing_month_str = current.strftime('%Y-%m-%d')
    prev_month_str = (current - relativedelta(months=1)).strftime('%Y-%m-%d')
    prev_year = (current - relativedelta(months=1)).year
    prev_mo = (current - relativedelta(months=1)).month

    billing_period = current.strftime('%Y%m%d') + '-' + (current + relativedelta(months=1) - timedelta(days=1)).strftime('%Y%m%d')

    prorated_sql = f"""
    INSERT INTO simo_prod.mysql_cdc_sync.card_billing_v2_prorated
    WITH prev_new_activations AS (
      SELECT *
      FROM simo_prod.mysql_cdc_sync.card_billing_v2_detail
      WHERE year = {prev_year}
        AND month = {prev_mo}
        AND Charge_Type = 'New Activation: Prorated-in Charge'
    ),
    usage_days_calc AS (
      SELECT
        pna.IMSI,
        COUNT(DISTINCT DATE(u.partitiontime - INTERVAL 5 HOUR)) AS usage_days
      FROM prev_new_activations pna
      LEFT JOIN simo_prod.tc_cdr.tc_udr_usage_data_records_details u
        ON pna.IMSI = u.imsi
        AND DATE(u.partitiontime - INTERVAL 5 HOUR) >= DATE(pna.Cycle_Start_Time)
        AND DATE(u.partitiontime - INTERVAL 5 HOUR) <= DATE(pna.Cycle_End_Time)
      GROUP BY pna.IMSI
    )
    SELECT
      '{billing_period}' AS Billing_Period,
      pna.IMSI,
      pna.ICCID,
      pna.SIM_Product_Name AS Product_Name,
      pna.Cycle_Start_Time,
      pna.Cycle_End_Time,
      pna.Final_Start_Date AS New_Activation_Date,
      pna.Final_Start_Date,
      pna.Final_End_Date,
      pna.Final_Days AS Active_Days,
      pna.Plan_Price AS Monthly_Rate,
      pna.Final_Charge AS Original_Charge,
      COALESCE(udc.usage_days, 0) AS Usage_Days,
      ROUND(COALESCE(udc.usage_days, 0) * 1.0 / pna.Natural_Month_Days * pna.Plan_Price, 4) AS Final_Charge_For_Usage_Days,
      ROUND((COALESCE(udc.usage_days, 0) - pna.Final_Days) * 1.0 / pna.Natural_Month_Days * pna.Plan_Price, 4) AS Pending_Charge,
      CURRENT_DATE() AS Report_Date,
      YEAR(DATE('{billing_month_str}')) AS year,
      MONTH(DATE('{billing_month_str}')) AS month
    FROM prev_new_activations pna
    JOIN usage_days_calc udc ON pna.IMSI = udc.IMSI
    WHERE COALESCE(udc.usage_days, 0) > pna.Final_Days
    """

    spark.sql(prorated_sql)
    print(f"Prorated processed {billing_period}")
    current += relativedelta(months=1)

print("Prorated done!")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Cell 8: 最终对账 — Detail + Prorated 合计 vs Excel

# COMMAND ----------

# MAGIC %sql
# MAGIC WITH platform_detail AS (
# MAGIC   SELECT
# MAGIC     CONCAT(year, '-', LPAD(month, 2, '0')) AS charge_month,
# MAGIC     ROUND(SUM(Final_Charge), 2) AS detail_amount
# MAGIC   FROM simo_prod.mysql_cdc_sync.card_billing_v2_detail
# MAGIC   GROUP BY year, month
# MAGIC ),
# MAGIC platform_prorated AS (
# MAGIC   SELECT
# MAGIC     CONCAT(year, '-', LPAD(month, 2, '0')) AS charge_month,
# MAGIC     ROUND(SUM(Pending_Charge), 2) AS prorated_amount
# MAGIC   FROM simo_prod.mysql_cdc_sync.card_billing_v2_prorated
# MAGIC   GROUP BY year, month
# MAGIC ),
# MAGIC excel_detail AS (
# MAGIC   SELECT
# MAGIC     LEFT(final_start_date, 7) AS charge_month,
# MAGIC     ROUND(SUM(CAST(final_charge AS DOUBLE)), 2) AS detail_amount
# MAGIC   FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
# MAGIC   WHERE final_charge IS NOT NULL AND final_charge != '-'
# MAGIC     AND final_start_date LIKE '20%'
# MAGIC   GROUP BY LEFT(final_start_date, 7)
# MAGIC ),
# MAGIC excel_prorated AS (
# MAGIC   SELECT
# MAGIC     LEFT(final_start_date, 7) AS charge_month,
# MAGIC     ROUND(SUM(CAST(pending_charge AS DOUBLE)), 2) AS prorated_amount
# MAGIC   FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
# MAGIC   WHERE pending_charge IS NOT NULL AND pending_charge != '-'
# MAGIC     AND final_start_date LIKE '20%'
# MAGIC   GROUP BY LEFT(final_start_date, 7)
# MAGIC )
# MAGIC SELECT
# MAGIC   COALESCE(pd.charge_month, ed.charge_month) AS month,
# MAGIC   ed.detail_amount AS excel_detail,
# MAGIC   ep.prorated_amount AS excel_prorated,
# MAGIC   ROUND(COALESCE(ed.detail_amount,0) + COALESCE(ep.prorated_amount,0), 2) AS excel_total,
# MAGIC   pd.detail_amount AS platform_detail,
# MAGIC   pp.prorated_amount AS platform_prorated,
# MAGIC   ROUND(COALESCE(pd.detail_amount,0) + COALESCE(pp.prorated_amount,0), 2) AS platform_total,
# MAGIC   ROUND(
# MAGIC     COALESCE(pd.detail_amount,0) + COALESCE(pp.prorated_amount,0) -
# MAGIC     COALESCE(ed.detail_amount,0) - COALESCE(ep.prorated_amount,0), 2
# MAGIC   ) AS diff,
# MAGIC   ROUND(
# MAGIC     (COALESCE(pd.detail_amount,0) + COALESCE(pp.prorated_amount,0) -
# MAGIC      COALESCE(ed.detail_amount,0) - COALESCE(ep.prorated_amount,0)) * 100.0 /
# MAGIC     NULLIF(COALESCE(ed.detail_amount,0) + COALESCE(ep.prorated_amount,0), 0), 2
# MAGIC   ) AS diff_pct
# MAGIC FROM platform_detail pd
# MAGIC FULL OUTER JOIN excel_detail ed ON pd.charge_month = ed.charge_month
# MAGIC LEFT JOIN platform_prorated pp ON pd.charge_month = pp.charge_month
# MAGIC LEFT JOIN excel_prorated ep ON COALESCE(pd.charge_month, ed.charge_month) = ep.charge_month
# MAGIC ORDER BY month