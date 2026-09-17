-- ============================================================================
-- WA（Wing Alpha）对账 · 平台口径账单复算  v1.2  （已验证，main SQL）
-- 只读查询，不写入任何表。
-- 计费公式（由 142,902 行 Excel 发票逐行逆向验证）：
--     final_charge = monthly_rate / DAY(LAST_DAY(final_start_date)) * final_days
--     final_days ≡ active_days；计费月 = final_start_date 所在自然月
-- 平台口径计费天数（三分支）：
--     ① 当月1号在网 且 月末最后一天在网 → 满月天数
--     ② 月中停用（status_log '作废'）→ 当月1号算到停用日
--     ③ 其余 → 当月实际在网天数
-- 结果：2025-10~2026-08 / 114,468 行，$6,094,937.01 vs Excel $6,107,097.95（-0.20%）
-- ============================================================================
WITH
xl AS (
  SELECT
    DATE_FORMAT(TO_DATE(final_start_date),'yyyy-MM')  AS bill_month,
    TO_DATE(final_start_date)                         AS bm_first,
    imsi, iccid, charge_type, status,
    TO_DATE(final_start_date) AS final_start_date,
    TO_DATE(final_end_date)   AS final_end_date,
    TO_DATE(cycle_start_date) AS cycle_start_date,
    TO_DATE(cycle_end_date)   AS cycle_end_date,
    TO_DATE(offstock_date)    AS offstock_date,
    CAST(final_days   AS DOUBLE) AS xl_final_days,
    CAST(active_days  AS DOUBLE) AS xl_active_days,
    CAST(monthly_rate AS DOUBLE) AS xl_monthly_rate,
    CAST(final_charge AS DOUBLE) AS xl_final_charge,
    source_file
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE CAST(final_charge AS DOUBLE) IS NOT NULL
    AND TO_DATE(final_start_date) IS NOT NULL
),
snap AS (
  SELECT imsi, year, month, DATE(partition_time) AS snap_date, MAX(product_id) AS product_id
  FROM simo_prod.tc_cdr.sim_status_for_sftp_bak
  GROUP BY imsi, year, month, DATE(partition_time)
),
presence AS (
  SELECT imsi, CONCAT(year,'-',LPAD(month,2,'0')) AS ym,
         COUNT(1) AS presence_days, MIN(snap_date) AS first_seen,
         MAX(snap_date) AS last_seen, MAX(product_id) AS product_id
  FROM snap GROUP BY imsi, year, month
),
stop AS (
  SELECT IMSI AS imsi, MIN(TO_DATE(CREATE_DATE)) AS stop_date
  FROM simo_prod.ods.resource_res_vsim_status_log
  WHERE NEXT_STATUS = '\u4f5c\u5e9f' GROUP BY IMSI
),
prod AS (
  SELECT product_id, TRIM(product_name) AS product_name,
         CAST(package_price AS DOUBLE) AS package_price
  FROM simo_prod.ods.resource_res_vsim_product WHERE supplier_id = 2275
),
calc AS (
  SELECT x.*, m.presence_days, m.first_seen, m.last_seen,
         sp.product_name AS plat_product_name, sp.package_price AS plat_package_price,
         DAY(LAST_DAY(x.bm_first)) AS days_in_month,
         CASE WHEN s.stop_date BETWEEN x.bm_first AND LAST_DAY(x.bm_first) THEN s.stop_date END AS stop_in_month,
         CASE WHEN m.first_seen = x.bm_first AND m.last_seen = LAST_DAY(x.bm_first) THEN DAY(LAST_DAY(x.bm_first))
              WHEN m.presence_days IS NULL THEN 0 ELSE m.presence_days END AS days_presence
  FROM xl x
  LEFT JOIN presence m ON m.imsi = x.imsi AND m.ym = x.bill_month
  LEFT JOIN stop s ON s.imsi = x.imsi
  LEFT JOIN prod sp ON sp.product_id = m.product_id
),
final AS (
  SELECT c.*, LEAST(COALESCE(
      CASE WHEN stop_in_month IS NOT NULL AND stop_in_month < LAST_DAY(bm_first)
           THEN DATEDIFF(stop_in_month, bm_first) + 1 END,
      days_presence), days_in_month) AS plat_bill_days
  FROM calc c
)
SELECT
  bill_month, charge_type, COUNT(1) AS n,
  SUM(CASE WHEN plat_bill_days = CAST(xl_final_days AS INT) THEN 1 ELSE 0 END) AS days_exact,
  ROUND(SUM(xl_final_charge),2) AS excel_sum,
  ROUND(SUM(ROUND(COALESCE(plat_package_price, xl_monthly_rate)/days_in_month*plat_bill_days,4)),2) AS plat_sum
FROM final
WHERE bill_month = '2026-08'
GROUP BY bill_month, charge_type ORDER BY charge_type
