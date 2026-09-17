-- ============================================================================
-- 基于原 notebook「card billing」/「card_billing_v2_aug」的修正版
-- 结构、CTE、四分支 UNION 完全沿用，仅改两处
--
-- 【修正 A】多账期 types=1 分支（原 L205-217）
--   原：WHEN max(pt) >= last_day AND Cycle_End > last_day THEN COUNT(1) - 1
--   改：当月1号在网 且 月末最后一天在网 → 满月天数(DAY(LAST_DAY))
--   实测（8月 WA 多账期卡 6,294 张）：平均天数 30.0 → 30.99
--                                    费用 $303,091.07 → $313,125.33 (+$10,034.26)
--
-- 【修正 B】多账期 types=2 预付分支（原 L241-246）
--   原：prepaid_end = date(max(Cycle_End_Time))          -- 收满到自然账期末
--   改：prepaid_end = LEAST(自然账期末, 作废日-1)         -- 换卡旧卡不预付到作废日之后
-- ============================================================================
WITH basic_data AS (
  SELECT
    imsi, product_id, SIM_Product_Data_Capacity,
    partition_time   - INTERVAL 4 HOUR AS partition_time,
    Cycle_Start_Time - INTERVAL 5 HOUR AS Cycle_Start_Time,
    Cycle_End_Time   - INTERVAL 5 HOUR AS Cycle_End_Time,
    ROW_NUMBER() OVER (
      PARTITION BY DATE(partition_time - INTERVAL 4 HOUR), imsi ORDER BY partition_time
    ) AS rm
  FROM (
    SELECT
      s1.imsi,
      IF(DATE(Cycle_End_Time) <= DATE('2026-08-31'), s2.product_id, s1.product_id) AS product_id,
      ICCID, SIM_Product_Threshold, SIM_Product_Data_Capacity,
      IF(DATE(Cycle_End_Time) <= DATE('2026-08-31'),
         DATE_FORMAT(s2.cycle_time, 'yyyy-MM-dd HH:mm:ss'), s1.Cycle_Start_Time) AS Cycle_Start_Time,
      IF(DATE(Cycle_End_Time) <= DATE('2026-08-31'),
         DATE_FORMAT(s2.next_cycle_time, 'yyyy-MM-dd HH:mm:ss'), s1.Cycle_End_Time) AS Cycle_End_Time,
      DispatchStatus, SimStatus, year, month, day, hour, partition_time
    FROM (
      SELECT * FROM simo_prod.tc_cdr.sim_status_for_sftp_bak
      WHERE DATE(partition_time - INTERVAL 4 HOUR) > DATE('2026-07-31')
        AND DATE(partition_time - INTERVAL 4 HOUR) <= DATE('2026-08-31')
    ) s1
    LEFT JOIN (
      SELECT imsi, product_id, cycle_time, next_cycle_time FROM (
        SELECT *, ROW_NUMBER() OVER (
          PARTITION BY imsi, YEAR(cycle_time), MONTH(cycle_time) ORDER BY create_time DESC
        ) rm
        FROM simo_prod.ods.resource_res_vsim_cycle_history
      ) WHERE rm = 1
    ) s2
      ON s1.imsi = s2.imsi
     AND YEAR(s1.Cycle_Start_Time)  = YEAR(s2.cycle_time)
     AND MONTH(s1.Cycle_Start_Time) = MONTH(s2.cycle_time)
  )
  WHERE SimStatus != 'Installed' AND Cycle_Start_Time IS NOT NULL
),

cycle_counts AS (
  SELECT imsi, COUNT(DISTINCT Cycle_Start_Time) AS cycles_nums FROM basic_data GROUP BY imsi
),

first_time_imsi AS (
  SELECT DISTINCT curr.imsi, 1 AS is_first_time
  FROM (SELECT DISTINCT imsi FROM basic_data) curr
  LEFT JOIN (
    SELECT DISTINCT IMSI FROM simo_prod.dm.Card_Billing_Report_Detail_new02
    WHERE Billing_Period < '20260801-20260831'
  ) hist ON curr.imsi = hist.IMSI
  WHERE hist.IMSI IS NULL
),

imsi_max_date AS (
  SELECT imsi, Cycle_End_Time, MAX(DATE(partition_time)) AS max_partition_date
  FROM basic_data GROUP BY imsi, Cycle_End_Time
),

imsi_activation_date AS (
  SELECT IMSI, MAX(CREATE_DATE) AS activation_date
  FROM simo_prod.ods.resource_res_vsim_status_log
  WHERE NEXT_STATUS = '\u6fc0\u6d3b' GROUP BY IMSI
),

-- 【修正 B 新增】作废日
deact_date AS (
  SELECT IMSI AS imsi, MIN(DATE(CREATE_DATE)) AS deact_date
  FROM simo_prod.ods.resource_res_vsim_status_log
  WHERE NEXT_STATUS = '\u4f5c\u5e9f'
    AND DATE(CREATE_DATE) >= '2026-08-01' AND DATE(CREATE_DATE) < '2026-10-01'
  GROUP BY IMSI
),

prev_month_billed_imsi AS (
  SELECT DISTINCT IMSI FROM simo_prod.dm.Card_Billing_Report_Detail_new02
  WHERE Billing_Period = '20260701-20260731' AND billing_state IN (2, 3)
),

card_details AS (
  -- ── 分支 1：单账期 types=1（沿用原逻辑）────────────────────────────────
  SELECT imsi, product_id, SIM_Product_Data_Capacity, Cycle_Start_Time, Cycle_End_Time,
         DATE_DIFF(final_end_date, start_date) + 1 AS billing_days,
         start_date, final_end_date AS end_date, cycle_days, types
  FROM (
    SELECT imsi, product_id, SIM_Product_Data_Capacity, Cycle_Start_Time, Cycle_End_Time,
           start_date, max_date, end_date, types, cycle_days,
           CASE WHEN max_date < LAST_DAY(DATE('2026-08-01')) AND max_date < end_date
                THEN max_date ELSE end_date END AS final_end_date
    FROM (
      SELECT imsi, product_id,
             TRY_CAST(SIM_Product_Data_Capacity AS DOUBLE)/1024 AS SIM_Product_Data_Capacity,
             Cycle_Start_Time, Cycle_End_Time,
             COUNT(1) AS billing_days,
             MIN(DATE(partition_time)) AS start_date,
             MAX(DATE(partition_time)) AS max_date,
             DATE(Cycle_End_Time) AS end_date, 1 AS types,
             DATE_DIFF(DATE(Cycle_End_Time + INTERVAL 1 MINUTES), DATE(Cycle_Start_Time)) AS cycle_days
      FROM (SELECT b.*, c.cycles_nums FROM basic_data b
            LEFT JOIN cycle_counts c ON b.imsi = c.imsi
            WHERE c.cycles_nums = 1 AND b.rm = 1)
      GROUP BY ALL
    ) t
  )
  UNION ALL
  -- ── 分支 2：单账期 types=2 跨月预付（沿用原逻辑）──────────────────────
  SELECT imsi, product_id, SIM_Product_Data_Capacity, Cycle_Start_Time, Cycle_End_Time,
         DATE_DIFF(end_date, max_date) AS billing_days,
         max_date AS start_date, end_date, cycle_days, types
  FROM (
    SELECT imsi, product_id, SIM_Product_Data_Capacity, Cycle_Start_Time, Cycle_End_Time,
           start_date, max_date,
           IF(max_date < LAST_DAY(DATE('2026-08-01')) AND max_date < end_date, max_date, end_date) AS end_date,
           types, cycle_days
    FROM (
      SELECT imsi, product_id,
             TRY_CAST(SIM_Product_Data_Capacity AS DOUBLE)/1024 AS SIM_Product_Data_Capacity,
             Cycle_Start_Time, Cycle_End_Time,
             COUNT(1) AS billing_days,
             MIN(DATE(partition_time)) AS start_date,
             MAX(DATE(partition_time)) AS max_date,
             DATE(Cycle_End_Time) AS end_date, 2 AS types,
             DATE_DIFF(DATE(Cycle_End_Time + INTERVAL 1 MINUTES), DATE(Cycle_Start_Time)) AS cycle_days
      FROM (SELECT b.*, c.cycles_nums FROM basic_data b
            LEFT JOIN cycle_counts c ON b.imsi = c.imsi
            WHERE c.cycles_nums = 1 AND b.rm = 1)
      GROUP BY ALL
    ) t
  )
  WHERE end_date > max_date
  UNION ALL
  -- ── 分支 3：多账期 types=1  ★修正 A★ ──────────────────────────────────
  SELECT imsi, product_id, SIM_Product_Data_Capacity, Cycle_Start_Time, Cycle_End_Time,
         billing_days, start_date, end_date, cycle_days, 1 AS types
  FROM (
    SELECT imsi, product_id,
           TRY_CAST(SIM_Product_Data_Capacity AS DOUBLE)/1024 AS SIM_Product_Data_Capacity,
           Cycle_Start_Time, Cycle_End_Time,
           -- ★修正 A：整月都在网 → 满月天数
           CASE WHEN MIN(DATE(partition_time)) = DATE('2026-08-01')
                 AND MAX(DATE(partition_time)) = DATE('2026-08-31')
                THEN DAY(LAST_DAY(DATE('2026-08-01')))
                ELSE COUNT(DISTINCT DATE(partition_time)) END AS billing_days,
           MIN(DATE(partition_time)) AS start_date,
           MAX(DATE(partition_time)) AS end_date,
           DATE_DIFF(DATE(Cycle_End_Time + INTERVAL 1 MINUTES), DATE(Cycle_Start_Time)) AS cycle_days
    FROM (SELECT b.*, c.cycles_nums FROM basic_data b
          LEFT JOIN cycle_counts c ON b.imsi = c.imsi
          WHERE c.cycles_nums > 1 AND b.rm = 1)
    GROUP BY ALL
  ) t
  UNION ALL
  -- ── 分支 4：多账期 types=2 预付  ★修正 B★ ─────────────────────────────
  SELECT imsi, product_id, SIM_Product_Data_Capacity, Cycle_Start_Time, Cycle_End_Time,
         DATE_DIFF(prepaid_end, max_date) + 1 AS billing_days,
         max_date AS start_date, prepaid_end AS end_date, cycle_days, 2 AS types
  FROM (
    SELECT b.imsi,
           MAX_BY(b.product_id, b.Cycle_End_Time) AS product_id,
           TRY_CAST(MAX_BY(b.SIM_Product_Data_Capacity, b.Cycle_End_Time) AS DOUBLE)/1024 AS SIM_Product_Data_Capacity,
           MAX_BY(b.Cycle_Start_Time, b.Cycle_End_Time) AS Cycle_Start_Time,
           MAX(b.Cycle_End_Time) AS Cycle_End_Time,
           MAX(DATE(b.partition_time)) AS max_date,
           -- ★修正 B：预付上限 = LEAST(自然账期末, 作废日-1)
           LEAST(
             DATE(MAX(b.Cycle_End_Time)),
             COALESCE(DATE_SUB(dd.deact_date, 1), DATE(MAX(b.Cycle_End_Time)))
           ) AS prepaid_end,
           DATE_DIFF(DATE(MAX(b.Cycle_End_Time) + INTERVAL 1 MINUTES),
                     DATE(MAX_BY(b.Cycle_Start_Time, b.Cycle_End_Time))) AS cycle_days
    FROM basic_data b
    JOIN cycle_counts c ON b.imsi = c.imsi
    LEFT JOIN deact_date dd ON b.imsi = dd.imsi
    WHERE c.cycles_nums > 1 AND b.rm = 1
    GROUP BY b.imsi, dd.deact_date
  ) t
  WHERE prepaid_end > max_date
),

billing_data AS (
  SELECT
    Billing_Period, IMSI, Cycle_Start_Time, Cycle_End_Time, ICCID, SIM_Supplier,
    SIM_Product_ID, SIM_Product_Name, SIM_Product_Type, Data_Capacity_GB,
    Data_Threshold_GB, Plan_Price, Billing_Days,
    CASE
      WHEN is_first_time = 1 AND activation_date IS NOT NULL AND DATE(activation_date) > end_date THEN 0
      WHEN is_first_time = 1 AND start_date > DATE(Cycle_Start_Time) AND types = 2 THEN 0
      WHEN is_first_time = 1 AND start_date > DATE(Cycle_Start_Time)
        THEN DATE_DIFF(LAST_DAY(DATE('2026-08-01')), start_date) + 1
      WHEN is_first_time = 1 AND max_partition_date >= DATE(Cycle_End_Time)
        THEN DAY(LAST_DAY(DATE('2026-08-01')))
      WHEN COALESCE(had_prev_month_bill, 0) = 0 AND types = 1
           AND DATE(Cycle_Start_Time) >= DATE('2026-08-01')
        THEN DATE_DIFF(LAST_DAY(DATE('2026-08-01')), COALESCE(DATE(activation_date), start_date))
      ELSE Billable_Days
    END AS Billable_Days,
    ROUND(
      CASE
        WHEN is_first_time = 1 AND activation_date IS NOT NULL AND DATE(activation_date) > end_date THEN 0
        WHEN is_first_time = 1 AND start_date > DATE(Cycle_Start_Time) AND types = 2 THEN 0
        WHEN is_first_time = 1 AND start_date > DATE(Cycle_Start_Time)
          THEN (DATE_DIFF(LAST_DAY(DATE('2026-08-01')), start_date) + 1) / billing_days * Plan_Price
        WHEN is_first_time = 1 AND max_partition_date >= DATE(Cycle_End_Time)
          THEN DAY(LAST_DAY(DATE('2026-08-01'))) / billing_days * Plan_Price
        WHEN COALESCE(had_prev_month_bill, 0) = 0 AND types = 1
             AND DATE(Cycle_Start_Time) >= DATE('2026-08-01')
          THEN DATE_DIFF(LAST_DAY(DATE('2026-08-01')), COALESCE(DATE(activation_date), start_date)) / billing_days * Plan_Price
        ELSE Billable_Days / billing_days * Plan_Price
      END, 4) AS Billable_Fee_Time,
    Report_Date, year, month, types
  FROM (
    SELECT
      '20260801-20260831' AS Billing_Period,
      s1.imsi AS IMSI, s1.Cycle_Start_Time, s1.Cycle_End_Time,
      s2.iccid_show AS ICCID, s5.CARRIER_NAME AS SIM_Supplier,
      s1.product_id AS SIM_Product_ID, s4.product_name AS SIM_Product_Name,
      CASE WHEN s4.is_local = 1 THEN 'Local' ELSE 'Roaming' END AS SIM_Product_Type,
      s1.SIM_Product_Data_Capacity AS Data_Capacity_GB,
      0 AS Data_Threshold_GB,
      s4.package_price AS Plan_Price,
      s1.cycle_days AS Billing_Days,
      s1.billing_days AS Billable_Days,
      s1.start_date, s1.end_date,
      CURRENT_DATE() AS Report_Date,
      2026 AS year, 8 AS month, s1.types,
      COALESCE(ft.is_first_time, 0) AS is_first_time,
      imd.max_partition_date, iad.activation_date,
      CASE WHEN pmb.IMSI IS NOT NULL THEN 1 ELSE 0 END AS had_prev_month_bill
    FROM card_details s1
    LEFT JOIN first_time_imsi ft ON s1.imsi = ft.imsi
    LEFT JOIN imsi_max_date imd ON s1.imsi = imd.imsi AND s1.Cycle_End_Time = imd.Cycle_End_Time
    LEFT JOIN imsi_activation_date iad ON s1.imsi = iad.IMSI
    LEFT JOIN prev_month_billed_imsi pmb ON s1.imsi = pmb.IMSI
    LEFT JOIN simo_prod.ods.resource_res_vsim_billing s2 ON s1.imsi = s2.imsi
    LEFT JOIN simo_prod.ods.resource_res_vsim_product s4 ON s1.product_id = s4.product_id
    LEFT JOIN simo_prod.ods.resource_res_carrier s5 ON s4.supplier_id = s5.id
    WHERE s5.CARRIER_NAME = 'Wing Alpha' AND s4.product_name NOT LIKE '%PI%'
  )
)

SELECT types, COUNT(1) AS rows_cnt, ROUND(SUM(Billable_Fee_Time),2) AS total
FROM billing_data
GROUP BY types
UNION ALL
SELECT 99, COUNT(1), ROUND(SUM(Billable_Fee_Time),2) FROM billing_data
ORDER BY types
