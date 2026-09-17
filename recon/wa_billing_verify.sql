-- ============================================================================
-- 验证脚本 · 方案 A（推荐基线，整体差异最小）
-- 规则：① 整月都在网 → 满月天数
--       ② 月中停用（status_log NEXT_STATUS='作废'）→ 当月1号算到停用日
--       ③ 其余 → 当月实际在网天数
-- 结果：114,468 行，Excel $6,107,097.95 vs 平台 $6,094,937.01（-0.20%）
--
-- 方案 B（换卡新账期规则）见文件末尾注释：天数命中率更高(90.2%)，
--       但整体差异 -0.52%，原因是该规则对"未离网卡"误伤，需先分类再启用。
-- ============================================================================
WITH xl AS (
  SELECT DATE_FORMAT(TO_DATE(final_start_date),'yyyy-MM') AS bill_month, TO_DATE(final_start_date) AS bm_first,
         imsi, charge_type, CAST(final_days AS DOUBLE) AS xl_days, CAST(monthly_rate AS DOUBLE) AS xl_rate,
         CAST(final_charge AS DOUBLE) AS xl_charge
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE TO_DATE(final_start_date) >= '2025-10-01'
),
snap AS (
  SELECT imsi, year, month, DATE(partition_time) AS snap_date, MAX(product_id) AS product_id
  FROM simo_prod.tc_cdr.sim_status_for_sftp_bak
  WHERE (year = 2025 AND month BETWEEN 10 AND 12) OR (year = 2026 AND month BETWEEN 1 AND 9)
  GROUP BY imsi, year, month, DATE(partition_time)
),
presence AS (
  SELECT imsi, CONCAT(year,'-',LPAD(month,2,'0')) AS ym, COUNT(1) AS presence_days,
         MIN(snap_date) AS first_seen, MAX(snap_date) AS last_seen, MAX(product_id) AS product_id
  FROM snap GROUP BY imsi, year, month
),
stop AS (
  SELECT IMSI AS imsi, MIN(TO_DATE(CREATE_DATE)) AS stop_date
  FROM simo_prod.ods.resource_res_vsim_status_log
  WHERE NEXT_STATUS = '\u4f5c\u5e9f' AND CREATE_DATE >= '2025-09-15'
  GROUP BY IMSI
),
prod AS (
  SELECT product_id, CAST(package_price AS DOUBLE) AS price
  FROM simo_prod.ods.resource_res_vsim_product WHERE supplier_id = 2275
),
j AS (
  SELECT x.*, m.presence_days, m.first_seen, m.last_seen, p.price AS plat_price,
         DAY(LAST_DAY(x.bm_first)) AS dim,
         CASE WHEN s.stop_date BETWEEN x.bm_first AND LAST_DAY(x.bm_first) THEN s.stop_date END AS stop_in_month,
         CASE WHEN m.first_seen = x.bm_first AND m.last_seen = LAST_DAY(x.bm_first) THEN DAY(LAST_DAY(x.bm_first))
              WHEN m.presence_days IS NULL THEN 0 ELSE m.presence_days END AS days_presence
  FROM xl x
  LEFT JOIN presence m ON m.imsi = x.imsi AND m.ym = x.bill_month
  LEFT JOIN stop s ON s.imsi = x.imsi
  LEFT JOIN prod p ON p.product_id = m.product_id
),
f AS (
  SELECT *,
    LEAST(CASE WHEN stop_in_month IS NOT NULL AND stop_in_month < LAST_DAY(bm_first)
               THEN DATEDIFF(stop_in_month, bm_first) + 1 ELSE days_presence END, dim) AS plat_days
  FROM j
)
SELECT bill_month,
  COUNT(1) AS xl_rows,
  SUM(CASE WHEN plat_days = CAST(xl_days AS INT) THEN 1 ELSE 0 END) AS days_exact,
  SUM(CASE WHEN plat_price IS NOT NULL AND ABS(plat_price - xl_rate) < 0.01 THEN 1 ELSE 0 END) AS price_eq,
  ROUND(SUM(xl_charge),2) AS excel_total,
  ROUND(SUM(COALESCE(ROUND(plat_price/dim*plat_days,4), ROUND(xl_rate/dim*plat_days,4))),2) AS plat_total,
  ROUND(SUM(COALESCE(ROUND(plat_price/dim*plat_days,4), ROUND(xl_rate/dim*plat_days,4))) - SUM(xl_charge),2) AS diff
FROM f GROUP BY bill_month ORDER BY bill_month

-- ============================================================================
-- 方案 B 附加分支（在 2026-08 上验证为精确，可单独按 charge_type 启用）：
--   换卡旧卡：new_cs = 当月快照中 Cycle_Start_Time >= 当月2号 的最小值
--            计费天数 = offstock_date - new_cs + 1
--   验证：2026-08 的 Partial Charge - Card Replaced Mid Cycle 318 张中
--         297 张天数完全命中，金额 $8,452.00 vs Excel $8,578.61（差 $126.61）
--   启用方式：在 f 的 CONCAT 前插入
--     CASE WHEN repl_days IS NOT NULL AND repl_days <= 30 THEN repl_days END,
-- ============================================================================
