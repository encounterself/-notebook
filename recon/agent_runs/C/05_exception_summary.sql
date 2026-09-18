WITH cfg AS (
  SELECT '2026-03' AS billing_month, '01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx' AS source_file, DATE '2026-03-01' AS d1, LAST_DAY(DATE '2026-03-01') AS d2
  UNION ALL SELECT '2026-04', '01-SIMO Data Purchase Invoice Details - APR 2026.xlsx', DATE '2026-04-01', LAST_DAY(DATE '2026-04-01')
  UNION ALL SELECT '2026-05', '01-SIMO Data Purchase Invoice Details - MAY 2026.xlsx', DATE '2026-05-01', LAST_DAY(DATE '2026-05-01')
),
wa_raw AS (
  SELECT
    c.billing_month,
    c.d1,
    c.d2,
    CAST(x.imsi AS STRING) AS imsi,
    CAST(x.charge_type AS STRING) AS charge_type,
    TRY_CAST(x.final_start_date AS DATE) AS final_start_d,
    TRY_CAST(x.final_end_date AS DATE) AS final_end_d,
    TRY_CAST(x.new_activation_date AS DATE) AS activation_d,
    TRY_CAST(x.offstock_date AS DATE) AS offstock_d,
    TRY_CAST(x.final_days AS DOUBLE) AS final_days_raw,
    TRY_CAST(x.active_days AS DOUBLE) AS active_days_raw,
    TRY_CAST(x.monthly_rate AS DOUBLE) AS wa_price_raw,
    TRY_CAST(x.final_charge AS DOUBLE) AS wa_amount_raw,
    CAST(x.source_file AS STRING) AS source_file,
    CAST(x.sheet_name AS STRING) AS sheet_name
  FROM cfg c
  JOIN simo_prod.mysql_cdc_sync.wa_invoice_detail x ON x.source_file = c.source_file
),
wa_card AS (
  SELECT
    billing_month,
    d1,
    d2,
    imsi,
    charge_type,
    COUNT(*) AS wa_row_count,
    CASE WHEN COUNT(DISTINCT final_start_d) = 1 THEN MIN(final_start_d) END AS final_start_d,
    CASE WHEN COUNT(DISTINCT final_end_d) = 1 THEN MIN(final_end_d) END AS final_end_d,
    CASE WHEN COUNT(DISTINCT activation_d) = 1 THEN MIN(activation_d) END AS activation_d,
    CASE WHEN COUNT(DISTINCT offstock_d) = 1 THEN MIN(offstock_d) END AS offstock_d,
    CASE WHEN COUNT(DISTINCT final_days_raw) = 1 THEN MIN(final_days_raw) END AS wa_final_days,
    CASE WHEN COUNT(DISTINCT active_days_raw) = 1 THEN MIN(active_days_raw) END AS wa_active_days,
    CASE WHEN COUNT(DISTINCT wa_price_raw) = 1 THEN MIN(wa_price_raw) END AS wa_price,
    CASE WHEN COUNT(DISTINCT wa_amount_raw) = 1 THEN MIN(wa_amount_raw) ELSE ROUND(SUM(wa_amount_raw), 6) END AS wa_amount,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(final_days_raw AS STRING)))) AS wa_final_days_values,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(wa_price_raw AS STRING)))) AS wa_price_values,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(source_file AS STRING)))) AS wa_source_files,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(sheet_name AS STRING)))) AS wa_sheet_names
  FROM wa_raw
  GROUP BY billing_month, d1, d2, imsi, charge_type
),
wa_keys AS (
  SELECT DISTINCT billing_month, d1, d2, imsi FROM wa_card
),
platform_cycle AS (
  SELECT
    k.billing_month,
    k.imsi,
    w.wa_price AS wa_price_key,
    COUNT(h.imsi) AS cycle_row_count,
    COUNT(DISTINCT TO_DATE(h.next_cycle_time)) AS next_cycle_date_count,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(TO_DATE(h.next_cycle_time) AS STRING)))) AS next_cycle_dates,
    MIN(TO_DATE(h.next_cycle_time)) AS cycle_next_first_utc,
    MIN(TO_DATE(h.next_cycle_time - INTERVAL 5 HOURS)) AS cycle_next_first_minus5,
    COUNT(DISTINCT p.package_price) AS platform_package_price_count,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(ROUND(p.package_price, 6) AS STRING)))) AS platform_package_prices,
    MAX(CASE WHEN p.package_price IS NOT NULL AND ROUND(p.package_price, 6) = ROUND(w.wa_price, 6) THEN 1 ELSE 0 END) AS package_price_exact_match,
    COUNT(DISTINCT p.product_name) AS platform_product_name_count,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(p.product_name AS STRING)))) AS platform_product_names
  FROM wa_keys k
  LEFT JOIN wa_card w
    ON w.billing_month = k.billing_month AND w.imsi = k.imsi
  LEFT JOIN simo_prod.ods.resource_res_vsim_cycle_history h
    ON CAST(h.imsi AS STRING) = k.imsi
   AND h.cycle_time >= CAST(k.d1 AS TIMESTAMP) - INTERVAL 45 DAYS
   AND h.cycle_time < CAST(k.d2 AS TIMESTAMP) + INTERVAL 46 DAYS
  LEFT JOIN simo_prod.ods.resource_res_vsim_product p
    ON CAST(p.product_id AS STRING) = CAST(h.product_id AS STRING)
  GROUP BY k.billing_month, k.imsi, w.wa_price
),
platform_status AS (
  SELECT
    k.billing_month,
    k.imsi,
    COUNT(l.IMSI) AS status_log_row_count,
    MIN(CASE WHEN l.NEXT_STATUS = '激活' THEN l.CREATE_DATE END) AS activation_first_utc,
    MIN(CASE WHEN l.NEXT_STATUS = '激活' THEN TO_DATE(l.CREATE_DATE - INTERVAL 5 HOURS) END) AS activation_first_minus5,
    MIN(CASE WHEN l.NEXT_STATUS = '作废' THEN l.CREATE_DATE END) AS void_first_utc,
    MIN(CASE WHEN l.NEXT_STATUS = '作废' THEN TO_DATE(l.CREATE_DATE - INTERVAL 5 HOURS) END) AS void_first_minus5
  FROM wa_keys k
  LEFT JOIN simo_prod.ods.resource_res_vsim_status_log l
    ON CAST(l.IMSI AS STRING) = k.imsi
   AND l.CREATE_DATE >= CAST(k.d1 AS TIMESTAMP) - INTERVAL 2 DAYS
   AND l.CREATE_DATE < CAST(k.d2 AS TIMESTAMP) + INTERVAL 46 DAYS
  GROUP BY k.billing_month, k.imsi
),
scored AS (
  SELECT
    w.*,
    DAY(w.d2) AS month_days,
    CASE
      WHEN w.charge_type = 'Full Cycle Charge' THEN CAST(DAY(w.d2) AS DOUBLE)
      WHEN w.final_start_d IS NOT NULL AND w.final_end_d IS NOT NULL THEN CAST(DATEDIFF(w.final_end_d, w.final_start_d) + 1 AS DOUBLE)
      ELSE NULL
    END AS candidate_days,
    CASE
      WHEN w.charge_type = 'Full Cycle Charge' THEN 'WA_FULL_MONTH_DAYS'
      WHEN w.final_start_d IS NOT NULL AND w.final_end_d IS NOT NULL THEN 'WA_FINAL_DATE_SPAN'
      ELSE 'UNRESOLVED_NO_DATES'
    END AS candidate_rule,
    pc.cycle_row_count,
    pc.next_cycle_date_count,
    pc.next_cycle_dates,
    pc.cycle_next_first_utc,
    pc.cycle_next_first_minus5,
    pc.platform_package_price_count,
    pc.platform_package_prices,
    pc.package_price_exact_match,
    pc.platform_product_name_count,
    pc.platform_product_names,
    ps.status_log_row_count,
    ps.activation_first_utc,
    ps.activation_first_minus5,
    ps.void_first_utc,
    ps.void_first_minus5
  FROM wa_card w
  LEFT JOIN platform_cycle pc
    ON pc.billing_month = w.billing_month AND pc.imsi = w.imsi
   AND ((pc.wa_price_key = w.wa_price) OR (pc.wa_price_key IS NULL AND w.wa_price IS NULL))
  LEFT JOIN platform_status ps
    ON ps.billing_month = w.billing_month AND ps.imsi = w.imsi
),
calculated AS (
  SELECT
    *,
    CASE
      WHEN charge_type IN ('Full Cycle Charge', 'Full Cycle Charge - Backbilled for FEB Invoice') AND wa_price IS NOT NULL THEN ROUND(wa_price, 6)
      WHEN candidate_days IS NOT NULL AND wa_price IS NOT NULL AND charge_type NOT LIKE 'Credit%' THEN ROUND(wa_price * candidate_days / month_days, 6)
      ELSE NULL
    END AS calculated_amount,
    CASE
      WHEN candidate_days IS NOT NULL AND cycle_next_first_utc IS NOT NULL THEN DATEDIFF(d2, cycle_next_first_utc) + 1
      ELSE NULL
    END AS platform_cycle_to_month_end_days,
    CASE
      WHEN candidate_days IS NOT NULL AND activation_first_utc IS NOT NULL THEN DATEDIFF(d2, TO_DATE(activation_first_utc)) + 1
      ELSE NULL
    END AS platform_activation_to_month_end_days,
    CASE
      WHEN candidate_days IS NOT NULL AND void_first_utc IS NOT NULL AND final_start_d IS NOT NULL THEN DATEDIFF(DATE_SUB(TO_DATE(void_first_utc), 1), final_start_d) + 1
      ELSE NULL
    END AS platform_final_start_to_void_minus1_days
  FROM scored
)
SELECT
  billing_month,
  charge_type,
  CASE
    WHEN wa_final_days IS NULL OR candidate_days IS NULL THEN 'MISSING_DATA'
    WHEN wa_final_days <> candidate_days THEN 'DAY_MISMATCH'
    WHEN platform_package_price_count IS NULL OR platform_package_price_count = 0 THEN 'MISSING_PLATFORM_PRICE'
    WHEN package_price_exact_match <> 1 THEN 'MISSING_MAPPING'
    WHEN calculated_amount IS NOT NULL AND ABS(wa_amount - calculated_amount) > 0.01 THEN 'AMOUNT_MISMATCH'
    ELSE 'NO_EXCEPTION'
  END AS exception_reason,
  COUNT(*) AS card_count,
  ROUND(SUM(wa_amount), 6) AS wa_amount_sum,
  ROUND(SUM(CASE WHEN calculated_amount IS NOT NULL THEN wa_amount - calculated_amount ELSE 0 END), 6) AS amount_diff_sum
FROM calculated
WHERE wa_final_days IS NULL
   OR candidate_days IS NULL
   OR wa_final_days <> candidate_days
   OR platform_package_price_count IS NULL
   OR platform_package_price_count = 0
   OR package_price_exact_match <> 1
   OR (calculated_amount IS NOT NULL AND ABS(wa_amount - calculated_amount) > 0.01)
GROUP BY billing_month, charge_type,
  CASE
    WHEN wa_final_days IS NULL OR candidate_days IS NULL THEN 'MISSING_DATA'
    WHEN wa_final_days <> candidate_days THEN 'DAY_MISMATCH'
    WHEN platform_package_price_count IS NULL OR platform_package_price_count = 0 THEN 'MISSING_PLATFORM_PRICE'
    WHEN package_price_exact_match <> 1 THEN 'MISSING_MAPPING'
    WHEN calculated_amount IS NOT NULL AND ABS(wa_amount - calculated_amount) > 0.01 THEN 'AMOUNT_MISMATCH'
    ELSE 'NO_EXCEPTION'
  END
ORDER BY billing_month, charge_type, exception_reason