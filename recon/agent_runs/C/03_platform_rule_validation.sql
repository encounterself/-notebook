WITH cfg AS (
  SELECT '2026-03' AS billing_month, '01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx' AS source_file, DATE '2026-03-01' AS d1, LAST_DAY(DATE '2026-03-01') AS d2
  UNION ALL SELECT '2026-04', '01-SIMO Data Purchase Invoice Details - APR 2026.xlsx', DATE '2026-04-01', LAST_DAY(DATE '2026-04-01')
  UNION ALL SELECT '2026-05', '01-SIMO Data Purchase Invoice Details - MAY 2026.xlsx', DATE '2026-05-01', LAST_DAY(DATE '2026-05-01')
),
wa_raw AS (
  SELECT
    c.billing_month,
    CAST(x.imsi AS STRING) AS imsi,
    CAST(x.charge_type AS STRING) AS charge_type,
    TRY_CAST(x.final_start_date AS DATE) AS final_start_d,
    TRY_CAST(x.final_end_date AS DATE) AS final_end_d,
    TRY_CAST(x.new_activation_date AS DATE) AS activation_d,
    TRY_CAST(x.offstock_date AS DATE) AS offstock_d,
    TRY_CAST(x.final_days AS DOUBLE) AS final_days_raw,
    TRY_CAST(x.active_days AS DOUBLE) AS active_days_raw,
    TRY_CAST(x.usage_days AS DOUBLE) AS usage_days_raw,
    TRY_CAST(x.usage_days_alt AS DOUBLE) AS usage_days_alt_raw,
    TRY_CAST(x.monthly_rate AS DOUBLE) AS wa_price_raw,
    TRY_CAST(x.final_charge AS DOUBLE) AS wa_amount_raw
  FROM cfg c
  JOIN simo_prod.mysql_cdc_sync.wa_invoice_detail x
    ON x.source_file = c.source_file
),
wa_card AS (
  SELECT
    billing_month,
    imsi,
    charge_type,
    COUNT(*) AS wa_row_count,
    COUNT(DISTINCT final_start_d) AS final_start_count,
    COUNT(DISTINCT final_end_d) AS final_end_count,
    COUNT(DISTINCT final_days_raw) AS final_days_count,
    COUNT(DISTINCT active_days_raw) AS active_days_count,
    COUNT(DISTINCT usage_days_raw) AS usage_days_count,
    COUNT(DISTINCT usage_days_alt_raw) AS usage_days_alt_count,
    COUNT(DISTINCT wa_price_raw) AS wa_price_count,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(COALESCE(CAST(final_start_d AS STRING), '<NULL>')))) AS final_start_values,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(COALESCE(CAST(final_end_d AS STRING), '<NULL>')))) AS final_end_values,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(COALESCE(CAST(final_days_raw AS STRING), '<NULL>')))) AS final_days_values,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(COALESCE(CAST(wa_price_raw AS STRING), '<NULL>')))) AS wa_price_values,
    CASE WHEN COUNT(DISTINCT final_start_d) = 1 THEN MIN(final_start_d) END AS final_start_d,
    CASE WHEN COUNT(DISTINCT final_end_d) = 1 THEN MIN(final_end_d) END AS final_end_d,
    CASE WHEN COUNT(DISTINCT activation_d) = 1 THEN MIN(activation_d) END AS activation_d,
    CASE WHEN COUNT(DISTINCT offstock_d) = 1 THEN MIN(offstock_d) END AS offstock_d,
    CASE WHEN COUNT(DISTINCT final_days_raw) = 1 THEN MIN(final_days_raw) END AS wa_final_days,
    CASE WHEN COUNT(DISTINCT active_days_raw) = 1 THEN MIN(active_days_raw) END AS wa_active_days,
    CASE WHEN COUNT(DISTINCT usage_days_raw) = 1 THEN MIN(usage_days_raw) END AS wa_usage_days,
    CASE WHEN COUNT(DISTINCT usage_days_alt_raw) = 1 THEN MIN(usage_days_alt_raw) END AS wa_usage_days_alt,
    CASE WHEN COUNT(DISTINCT wa_price_raw) = 1 THEN MIN(wa_price_raw) END AS wa_price,
    ROUND(SUM(wa_amount_raw), 6) AS wa_amount
  FROM wa_raw
  GROUP BY billing_month, imsi, charge_type
),
platform_card AS (
  SELECT
    w.billing_month,
    w.imsi,
    COUNT(DISTINCT h.imsi) AS cycle_imsi_evidence,
    COUNT(h.imsi) AS cycle_row_count,
    COUNT(DISTINCT CAST(h.product_id AS STRING)) AS product_id_count,
    COUNT(DISTINCT TO_DATE(h.next_cycle_time)) AS next_cycle_utc_date_count,
    COUNT(DISTINCT TO_DATE(h.next_cycle_time - INTERVAL 5 HOURS)) AS next_cycle_minus5_date_count,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(COALESCE(CAST(TO_DATE(h.next_cycle_time) AS STRING), '<NULL>')))) AS next_cycle_utc_dates,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(COALESCE(CAST(TO_DATE(h.next_cycle_time - INTERVAL 5 HOURS) AS STRING), '<NULL>')))) AS next_cycle_minus5_dates,
    MIN(TO_DATE(h.next_cycle_time)) AS cycle_next_utc_first,
    MIN(TO_DATE(h.next_cycle_time - INTERVAL 5 HOURS)) AS cycle_next_minus5_first,
    COUNT(DISTINCT p.package_price) AS product_package_price_count,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(COALESCE(CAST(ROUND(p.package_price, 6) AS STRING), '<NULL>')))) AS product_package_prices,
    COUNT(DISTINCT p.monthly_rent) AS product_monthly_rent_count,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(COALESCE(CAST(ROUND(p.monthly_rent, 6) AS STRING), '<NULL>')))) AS product_monthly_rents,
    MAX(CASE WHEN p.package_price IS NOT NULL AND w.wa_price IS NOT NULL AND ROUND(p.package_price, 6) = ROUND(w.wa_price, 6) THEN 1 ELSE 0 END) AS package_price_exact_match,
    MAX(CASE WHEN p.monthly_rent IS NOT NULL AND w.wa_price IS NOT NULL AND ROUND(p.monthly_rent, 6) = ROUND(w.wa_price, 6) THEN 1 ELSE 0 END) AS monthly_rent_exact_match
  FROM wa_card w
  LEFT JOIN cfg c ON c.billing_month = w.billing_month
  LEFT JOIN simo_prod.ods.resource_res_vsim_cycle_history h
    ON CAST(h.imsi AS STRING) = w.imsi
   AND h.cycle_time >= CAST(c.d1 AS TIMESTAMP) - INTERVAL 45 DAYS
   AND h.cycle_time < CAST(c.d2 AS TIMESTAMP) + INTERVAL 46 DAYS
  LEFT JOIN simo_prod.ods.resource_res_vsim_product p
    ON CAST(p.product_id AS STRING) = CAST(h.product_id AS STRING)
  GROUP BY w.billing_month, w.imsi
),
status_card AS (
  SELECT
    w.billing_month,
    w.imsi,
    COUNT(l.IMSI) AS status_row_count,
    COUNT(DISTINCT CAST(l.NEXT_STATUS AS STRING)) AS status_next_count,
    MIN(CASE WHEN l.NEXT_STATUS = '激活' THEN l.CREATE_DATE END) AS activation_first_utc,
    MIN(CASE WHEN l.NEXT_STATUS = '激活' THEN TO_DATE(l.CREATE_DATE - INTERVAL 5 HOURS) END) AS activation_first_minus5,
    COUNT(CASE WHEN l.NEXT_STATUS = '激活' THEN 1 END) AS activation_row_count,
    MIN(CASE WHEN l.NEXT_STATUS = '作废' THEN l.CREATE_DATE END) AS void_first_utc,
    MIN(CASE WHEN l.NEXT_STATUS = '作废' THEN TO_DATE(l.CREATE_DATE - INTERVAL 5 HOURS) END) AS void_first_minus5,
    COUNT(CASE WHEN l.NEXT_STATUS = '作废' THEN 1 END) AS void_row_count
  FROM wa_card w
  LEFT JOIN cfg c ON c.billing_month = w.billing_month
  LEFT JOIN simo_prod.ods.resource_res_vsim_status_log l
    ON CAST(l.IMSI AS STRING) = w.imsi
   AND l.CREATE_DATE >= CAST(c.d1 AS TIMESTAMP) - INTERVAL 2 DAYS
   AND l.CREATE_DATE < CAST(c.d2 AS TIMESTAMP) + INTERVAL 46 DAYS
  GROUP BY w.billing_month, w.imsi
),
card_evidence AS (
  SELECT
    w.*,
    pc.cycle_imsi_evidence,
    pc.cycle_row_count,
    pc.product_id_count,
    pc.next_cycle_utc_date_count,
    pc.next_cycle_minus5_date_count,
    pc.next_cycle_utc_dates,
    pc.next_cycle_minus5_dates,
    pc.cycle_next_utc_first,
    pc.cycle_next_minus5_first,
    pc.product_package_price_count,
    pc.product_package_prices,
    pc.product_monthly_rent_count,
    pc.product_monthly_rents,
    pc.package_price_exact_match,
    pc.monthly_rent_exact_match,
    sc.status_row_count,
    sc.status_next_count,
    sc.activation_first_utc,
    sc.activation_first_minus5,
    sc.activation_row_count,
    sc.void_first_utc,
    sc.void_first_minus5,
    sc.void_row_count
  FROM wa_card w
  LEFT JOIN platform_card pc
    ON pc.billing_month = w.billing_month AND pc.imsi = w.imsi
  LEFT JOIN status_card sc
    ON sc.billing_month = w.billing_month AND sc.imsi = w.imsi
),
candidate_rows AS (
  SELECT billing_month, imsi, charge_type, wa_final_days, wa_price, wa_amount, package_price_exact_match, monthly_rent_exact_match, cycle_row_count, status_row_count, 'WA_FINAL_DATE_SPAN' AS candidate_rule, DATEDIFF(final_end_d, final_start_d) + 1 AS candidate_days FROM card_evidence
  UNION ALL SELECT billing_month, imsi, charge_type, wa_final_days, wa_price, wa_amount, package_price_exact_match, monthly_rent_exact_match, cycle_row_count, status_row_count, 'WA_ACTIVE_DAYS', wa_active_days FROM card_evidence
  UNION ALL SELECT billing_month, imsi, charge_type, wa_final_days, wa_price, wa_amount, package_price_exact_match, monthly_rent_exact_match, cycle_row_count, status_row_count, 'WA_USAGE_DAYS', wa_usage_days FROM card_evidence
  UNION ALL SELECT billing_month, imsi, charge_type, wa_final_days, wa_price, wa_amount, package_price_exact_match, monthly_rent_exact_match, cycle_row_count, status_row_count, 'WA_USAGE_DAYS_ALT', wa_usage_days_alt FROM card_evidence
  UNION ALL SELECT billing_month, imsi, charge_type, wa_final_days, wa_price, wa_amount, package_price_exact_match, monthly_rent_exact_match, cycle_row_count, status_row_count, 'WA_FULL_MONTH_DAYS', DAY(LAST_DAY(TO_DATE(CONCAT(billing_month, '-01')))) FROM card_evidence
  UNION ALL SELECT billing_month, imsi, charge_type, wa_final_days, wa_price, wa_amount, package_price_exact_match, monthly_rent_exact_match, cycle_row_count, status_row_count, 'WA_ACTIVATION_TO_MONTH_END', DATEDIFF(LAST_DAY(TO_DATE(CONCAT(billing_month, '-01'))), activation_d) + 1 FROM card_evidence
  UNION ALL SELECT billing_month, imsi, charge_type, wa_final_days, wa_price, wa_amount, package_price_exact_match, monthly_rent_exact_match, cycle_row_count, status_row_count, 'WA_FINAL_START_TO_MONTH_END', DATEDIFF(LAST_DAY(TO_DATE(CONCAT(billing_month, '-01'))), final_start_d) + 1 FROM card_evidence
  UNION ALL SELECT billing_month, imsi, charge_type, wa_final_days, wa_price, wa_amount, package_price_exact_match, monthly_rent_exact_match, cycle_row_count, status_row_count, 'WA_FINAL_START_TO_OFFSTOCK', DATEDIFF(offstock_d, final_start_d) + 1 FROM card_evidence
  UNION ALL SELECT billing_month, imsi, charge_type, wa_final_days, wa_price, wa_amount, package_price_exact_match, monthly_rent_exact_match, cycle_row_count, status_row_count, 'PLATFORM_ACTIVATION_UTC_TO_MONTH_END', DATEDIFF(LAST_DAY(TO_DATE(CONCAT(billing_month, '-01'))), TO_DATE(activation_first_utc)) + 1 FROM card_evidence
  UNION ALL SELECT billing_month, imsi, charge_type, wa_final_days, wa_price, wa_amount, package_price_exact_match, monthly_rent_exact_match, cycle_row_count, status_row_count, 'PLATFORM_ACTIVATION_MINUS5_TO_MONTH_END', DATEDIFF(LAST_DAY(TO_DATE(CONCAT(billing_month, '-01'))), activation_first_minus5) + 1 FROM card_evidence
  UNION ALL SELECT billing_month, imsi, charge_type, wa_final_days, wa_price, wa_amount, package_price_exact_match, monthly_rent_exact_match, cycle_row_count, status_row_count, 'PLATFORM_ACTIVATION_UTC_TO_VOID_MINUS1', DATEDIFF(DATE_SUB(TO_DATE(void_first_utc), 1), TO_DATE(activation_first_utc)) + 1 FROM card_evidence
  UNION ALL SELECT billing_month, imsi, charge_type, wa_final_days, wa_price, wa_amount, package_price_exact_match, monthly_rent_exact_match, cycle_row_count, status_row_count, 'PLATFORM_ACTIVATION_MINUS5_TO_VOID_MINUS1', DATEDIFF(DATE_SUB(void_first_minus5, 1), activation_first_minus5) + 1 FROM card_evidence
  UNION ALL SELECT billing_month, imsi, charge_type, wa_final_days, wa_price, wa_amount, package_price_exact_match, monthly_rent_exact_match, cycle_row_count, status_row_count, 'PLATFORM_CYCLE_UTC_TO_MONTH_END', DATEDIFF(LAST_DAY(TO_DATE(CONCAT(billing_month, '-01'))), cycle_next_utc_first) + 1 FROM card_evidence
  UNION ALL SELECT billing_month, imsi, charge_type, wa_final_days, wa_price, wa_amount, package_price_exact_match, monthly_rent_exact_match, cycle_row_count, status_row_count, 'PLATFORM_CYCLE_MINUS5_TO_MONTH_END', DATEDIFF(LAST_DAY(TO_DATE(CONCAT(billing_month, '-01'))), cycle_next_minus5_first) + 1 FROM card_evidence
  UNION ALL SELECT billing_month, imsi, charge_type, wa_final_days, wa_price, wa_amount, package_price_exact_match, monthly_rent_exact_match, cycle_row_count, status_row_count, 'PLATFORM_CYCLE_UTC_TO_VOID_MINUS1', DATEDIFF(DATE_SUB(TO_DATE(void_first_utc), 1), cycle_next_utc_first) + 1 FROM card_evidence
  UNION ALL SELECT billing_month, imsi, charge_type, wa_final_days, wa_price, wa_amount, package_price_exact_match, monthly_rent_exact_match, cycle_row_count, status_row_count, 'PLATFORM_CYCLE_MINUS5_TO_VOID_MINUS1', DATEDIFF(DATE_SUB(void_first_minus5, 1), cycle_next_minus5_first) + 1 FROM card_evidence
  UNION ALL SELECT billing_month, imsi, charge_type, wa_final_days, wa_price, wa_amount, package_price_exact_match, monthly_rent_exact_match, cycle_row_count, status_row_count, 'PLATFORM_FINAL_START_TO_VOID_MINUS1', DATEDIFF(DATE_SUB(TO_DATE(void_first_utc), 1), final_start_d) + 1 FROM card_evidence
  UNION ALL SELECT billing_month, imsi, charge_type, wa_final_days, wa_price, wa_amount, package_price_exact_match, monthly_rent_exact_match, cycle_row_count, status_row_count, 'PLATFORM_MONTH_START_TO_VOID_MINUS1', DATEDIFF(DATE_SUB(TO_DATE(void_first_utc), 1), TO_DATE(CONCAT(billing_month, '-01'))) + 1 FROM card_evidence
)
SELECT
  billing_month,
  charge_type,
  candidate_rule,
  COUNT(DISTINCT imsi) AS card_count,
  COUNT(DISTINCT CASE WHEN candidate_days IS NOT NULL THEN imsi END) AS evaluable_cards,
  COUNT(DISTINCT CASE WHEN candidate_days IS NOT NULL AND wa_final_days IS NOT NULL AND wa_final_days = candidate_days THEN imsi END) AS exact_day_match_cards,
  ROUND(
    COUNT(DISTINCT CASE WHEN candidate_days IS NOT NULL AND wa_final_days IS NOT NULL AND wa_final_days = candidate_days THEN imsi END)
    / NULLIF(COUNT(DISTINCT CASE WHEN candidate_days IS NOT NULL AND wa_final_days IS NOT NULL THEN imsi END), 0),
    6
  ) AS exact_day_match_rate,
  COUNT(DISTINCT CASE WHEN candidate_days IS NOT NULL AND wa_final_days IS NOT NULL AND ABS(wa_final_days - candidate_days) = 0 THEN imsi END) AS day_error_0_cards,
  COUNT(DISTINCT CASE WHEN candidate_days IS NOT NULL AND wa_final_days IS NOT NULL AND ABS(wa_final_days - candidate_days) = 1 THEN imsi END) AS day_error_1_cards,
  COUNT(DISTINCT CASE WHEN candidate_days IS NOT NULL AND wa_final_days IS NOT NULL AND ABS(wa_final_days - candidate_days) >= 2 THEN imsi END) AS day_error_ge2_cards,
  COUNT(DISTINCT CASE WHEN package_price_exact_match = 1 THEN imsi END) AS package_price_match_cards,
  COUNT(DISTINCT CASE WHEN monthly_rent_exact_match = 1 THEN imsi END) AS monthly_rent_match_cards,
  COUNT(DISTINCT CASE WHEN cycle_row_count IS NOT NULL AND cycle_row_count > 0 THEN imsi END) AS cycle_evidence_cards,
  COUNT(DISTINCT CASE WHEN status_row_count IS NOT NULL AND status_row_count > 0 THEN imsi END) AS status_evidence_cards,
  ROUND(SUM(CASE WHEN candidate_rule = 'WA_FINAL_DATE_SPAN' THEN wa_amount ELSE 0 END), 6) AS wa_amount_sum_for_group
FROM candidate_rows
GROUP BY billing_month, charge_type, candidate_rule
ORDER BY billing_month, charge_type, candidate_rule;