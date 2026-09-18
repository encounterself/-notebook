WITH cfg AS (
  SELECT '2026-03' AS billing_month, '01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx' AS source_file, DATE '2026-03-01' AS d1, LAST_DAY(DATE '2026-03-01') AS d2
  UNION ALL SELECT '2026-04', '01-SIMO Data Purchase Invoice Details - APR 2026.xlsx', DATE '2026-04-01', LAST_DAY(DATE '2026-04-01')
  UNION ALL SELECT '2026-05', '01-SIMO Data Purchase Invoice Details - MAY 2026.xlsx', DATE '2026-05-01', LAST_DAY(DATE '2026-05-01')
),
wa_raw AS (
  SELECT c.billing_month, c.d1, c.d2, CAST(x.imsi AS STRING) AS imsi,
    CAST(x.charge_type AS STRING) AS charge_type,
    TRY_CAST(x.final_start_date AS DATE) AS final_start_d,
    TRY_CAST(x.final_end_date AS DATE) AS final_end_d,
    TRY_CAST(x.final_days AS DOUBLE) AS final_days_raw,
    TRY_CAST(x.monthly_rate AS DOUBLE) AS wa_price_raw,
    TRY_CAST(x.final_charge AS DOUBLE) AS wa_amount_raw,
    CAST(x.source_file AS STRING) AS source_file,
    CAST(x.sheet_name AS STRING) AS sheet_name
  FROM cfg c JOIN simo_prod.mysql_cdc_sync.wa_invoice_detail x ON x.source_file = c.source_file
),
wa_card AS (
  SELECT billing_month, d1, d2, imsi, charge_type,
    CASE WHEN COUNT(DISTINCT final_start_d) = 1 THEN MIN(final_start_d) END AS final_start_d,
    CASE WHEN COUNT(DISTINCT final_end_d) = 1 THEN MIN(final_end_d) END AS final_end_d,
    CASE WHEN COUNT(DISTINCT final_days_raw) = 1 THEN MIN(final_days_raw) END AS wa_final_days,
    CASE WHEN COUNT(DISTINCT wa_price_raw) = 1 THEN MIN(wa_price_raw) END AS wa_price,
    CASE WHEN COUNT(DISTINCT wa_amount_raw) = 1 THEN MIN(wa_amount_raw) ELSE ROUND(SUM(wa_amount_raw), 6) END AS raw_wa_amount,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(final_days_raw AS STRING)))) AS wa_final_days_values,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(wa_price_raw AS STRING)))) AS wa_price_values,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(source_file))) AS source_files,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(sheet_name))) AS sheet_names
  FROM wa_raw GROUP BY billing_month, d1, d2, imsi, charge_type
),
platform_price AS (
  SELECT w.billing_month, w.imsi, w.wa_price,
    COUNT(DISTINCT p.package_price) AS platform_package_price_count,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(ROUND(p.package_price, 6) AS STRING)))) AS platform_package_prices,
    CASE WHEN COUNT(DISTINCT p.package_price) = 1 THEN MIN(p.package_price) END AS platform_evidenced_price,
    CASE WHEN COUNT(DISTINCT p.package_price) = 1 AND SUM(CASE WHEN ROUND(p.package_price, 6) = ROUND(w.wa_price, 6) THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END AS package_price_exact_match,
    COUNT(DISTINCT p.product_name) AS platform_product_name_count,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(p.product_name AS STRING)))) AS platform_product_names
  FROM (SELECT DISTINCT billing_month, imsi, wa_price, d1, d2 FROM wa_card) w
  LEFT JOIN simo_prod.ods.resource_res_vsim_cycle_history h
    ON CAST(h.imsi AS STRING) = w.imsi
   AND h.cycle_time >= CAST(w.d1 AS TIMESTAMP) - INTERVAL 45 DAYS
   AND h.cycle_time < CAST(w.d2 AS TIMESTAMP) + INTERVAL 46 DAYS
  LEFT JOIN simo_prod.ods.resource_res_vsim_product p ON CAST(p.product_id AS STRING) = CAST(h.product_id AS STRING)
  GROUP BY w.billing_month, w.imsi, w.wa_price
),
evaluated AS (
  SELECT w.*, p.platform_package_price_count, p.platform_package_prices, p.platform_evidenced_price,
    p.package_price_exact_match, p.platform_product_name_count, p.platform_product_names,
    CASE WHEN w.charge_type = 'Full Cycle Charge' THEN CAST(DAY(w.d2) AS DOUBLE)
         WHEN w.final_start_d IS NOT NULL AND w.final_end_d IS NOT NULL THEN CAST(DATEDIFF(w.final_end_d, w.final_start_d) + 1 AS DOUBLE)
         ELSE NULL END AS candidate_days,
    CASE WHEN w.charge_type = 'Full Cycle Charge' THEN 'WA_FULL_MONTH_DAYS'
         WHEN w.final_start_d IS NOT NULL AND w.final_end_d IS NOT NULL THEN 'WA_FINAL_DATE_SPAN'
         ELSE 'UNRESOLVED_NO_DATES' END AS candidate_rule,
    DAY(w.d2) AS month_days
  FROM wa_card w LEFT JOIN platform_price p ON p.billing_month = w.billing_month AND p.imsi = w.imsi AND ((p.wa_price = w.wa_price) OR (p.wa_price IS NULL AND w.wa_price IS NULL))
),
detail_candidate AS (
  SELECT billing_month, imsi, charge_type, 'WA_DETAIL' AS source_layer, final_start_d, final_end_d, wa_final_days,
    wa_final_days_values, wa_price, wa_price_values, raw_wa_amount, platform_package_price_count, platform_package_prices,
    platform_evidenced_price, package_price_exact_match, platform_product_name_count, platform_product_names,
    candidate_rule, candidate_days,
    CASE WHEN charge_type LIKE 'Credit%' THEN raw_wa_amount
         WHEN platform_package_price_count = 1 AND package_price_exact_match = 1 AND wa_price IS NOT NULL AND candidate_days IS NOT NULL
           THEN CASE WHEN charge_type IN ('Full Cycle Charge', 'Full Cycle Charge - Backbilled for FEB Invoice') THEN ROUND(wa_price, 6) ELSE ROUND(wa_price * candidate_days / month_days, 6) END
         ELSE NULL END AS candidate_amount,
    CASE WHEN charge_type LIKE 'Credit%' THEN 'CREDIT_SIGN_PRESERVED'
         WHEN candidate_days IS NULL THEN 'MISSING_DATA'
         WHEN platform_package_price_count IS NULL OR platform_package_price_count = 0 THEN 'MISSING_MAPPING'
         WHEN platform_package_price_count > 1 THEN 'UNRESOLVED_MULTIPLE_PLATFORM_PRICES'
         WHEN package_price_exact_match <> 1 THEN 'MISSING_MAPPING'
         WHEN charge_type = 'Full Cycle Charge' THEN 'CANDIDATE_FULL_MONTH_PRICE_SUPPORTED'
         WHEN charge_type = 'Full Cycle Charge - Backbilled for FEB Invoice' THEN 'CANDIDATE_BACKBILLED_MONTHLY_PRICE_SUPPORTED'
         ELSE 'CANDIDATE_WA_DATE_SPAN_ONLY' END AS candidate_status,
    source_files, sheet_names
  FROM evaluated
),
pending_raw AS (
  SELECT c.billing_month, CAST(x.imsi AS STRING) AS imsi,
    COUNT(*) AS pending_row_count,
    CASE WHEN COUNT(DISTINCT TRY_CAST(x.final_start_date AS DATE)) = 1 THEN MIN(TRY_CAST(x.final_start_date AS DATE)) END AS final_start_d,
    CASE WHEN COUNT(DISTINCT TRY_CAST(x.final_end_date AS DATE)) = 1 THEN MIN(TRY_CAST(x.final_end_date AS DATE)) END AS final_end_d,
    CASE WHEN COUNT(DISTINCT TRY_CAST(x.monthly_rate AS DOUBLE)) = 1 THEN MIN(TRY_CAST(x.monthly_rate AS DOUBLE)) END AS wa_price,
    ROUND(SUM(TRY_CAST(x.final_charge_for_usage_days AS DOUBLE)), 6) AS raw_wa_amount,
    ROUND(SUM(TRY_CAST(x.pending_charge AS DOUBLE)), 6) AS raw_pending_charge,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(x.monthly_rate AS STRING)))) AS wa_price_values,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(x.sheet_name AS STRING)))) AS sheet_names,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(x.source_file AS STRING)))) AS source_files
  FROM cfg c JOIN simo_prod.mysql_cdc_sync.wa_invoice_prorated x ON x.source_file = c.source_file
  GROUP BY c.billing_month, CAST(x.imsi AS STRING)
),
pending_candidate AS (
  SELECT billing_month, imsi, 'Pending Prorated-In' AS charge_type, 'WA_PENDING_PRORATED' AS source_layer,
    final_start_d, final_end_d, CAST(NULL AS DOUBLE) AS wa_final_days, CAST(NULL AS STRING) AS wa_final_days_values,
    wa_price, wa_price_values, raw_wa_amount, CAST(NULL AS BIGINT) AS platform_package_price_count,
    CAST(NULL AS STRING) AS platform_package_prices, CAST(NULL AS DOUBLE) AS platform_evidenced_price,
    CAST(NULL AS BIGINT) AS package_price_exact_match, CAST(NULL AS BIGINT) AS platform_product_name_count,
    CAST(NULL AS STRING) AS platform_product_names, 'PENDING_NO_FINAL_DAYS' AS candidate_rule,
    CAST(NULL AS DOUBLE) AS candidate_days, CAST(NULL AS DOUBLE) AS candidate_amount,
    'MISSING_DATA' AS candidate_status, source_files, sheet_names
  FROM pending_raw
)
SELECT billing_month, imsi, charge_type, source_layer, final_start_d, final_end_d, wa_final_days,
  wa_final_days_values, wa_price, wa_price_values, raw_wa_amount, platform_package_price_count,
  platform_package_prices, platform_evidenced_price, package_price_exact_match, platform_product_name_count,
  platform_product_names, candidate_rule, candidate_days, candidate_amount, candidate_status, source_files, sheet_names
FROM detail_candidate
UNION ALL
SELECT billing_month, imsi, charge_type, source_layer, final_start_d, final_end_d, wa_final_days,
  wa_final_days_values, wa_price, wa_price_values, raw_wa_amount, platform_package_price_count,
  platform_package_prices, platform_evidenced_price, package_price_exact_match, platform_product_name_count,
  platform_product_names, candidate_rule, candidate_days, candidate_amount, candidate_status, source_files, sheet_names
FROM pending_candidate
ORDER BY billing_month, source_layer, charge_type, imsi