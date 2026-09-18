WITH cfg AS (
  SELECT '2026-03' AS billing_month, DATE '2026-03-01' AS d1, LAST_DAY(DATE '2026-03-01') AS d2
  UNION ALL SELECT '2026-04', DATE '2026-04-01', LAST_DAY(DATE '2026-04-01')
  UNION ALL SELECT '2026-05', DATE '2026-05-01', LAST_DAY(DATE '2026-05-01')
), product_dim AS (
  SELECT CAST(product_id AS STRING) AS product_id,
    CAST(product_name AS STRING) AS platform_product_name,
    CAST(product_category AS STRING) AS product_category,
    CAST(owner AS STRING) AS platform_owner,
    package_price AS dim_package_price,
    monthly_rent AS dim_monthly_rent,
    billing_cycle,
    billing_type,
    create_time,
    modify_time,
    CAST(supplier_id AS BIGINT) AS supplier_id
  FROM simo_prod.ods.resource_res_vsim_product
  WHERE CAST(supplier_id AS BIGINT) = 2275
),
wa_raw AS (
  SELECT c.billing_month, c.d1, c.d2, CAST(x.imsi AS STRING) AS imsi,
    CAST(x.charge_type AS STRING) AS charge_type,
    TRY_CAST(x.final_start_date AS DATE) AS final_start_d,
    TRY_CAST(x.final_end_date AS DATE) AS final_end_d,
    TRY_CAST(x.final_days AS DOUBLE) AS excel_final_days_raw,
    TRY_CAST(x.monthly_rate AS DOUBLE) AS excel_monthly_rate_raw,
    TRY_CAST(x.final_charge AS DOUBLE) AS excel_final_charge_raw,
    CAST(x.product_name AS STRING) AS excel_product_name,
    DAY(c.d2) AS month_days
  FROM cfg c JOIN simo_prod.mysql_cdc_sync.wa_invoice_detail x ON x.source_file = CASE c.billing_month
    WHEN '2026-03' THEN '01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx'
    WHEN '2026-04' THEN '01-SIMO Data Purchase Invoice Details - APR 2026.xlsx'
    WHEN '2026-05' THEN '01-SIMO Data Purchase Invoice Details - MAY 2026.xlsx' END
),
wa_card AS (
  SELECT billing_month, d1, d2, imsi, charge_type,
    CASE WHEN COUNT(DISTINCT final_start_d) = 1 THEN MIN(final_start_d) END AS excel_final_start_date,
    CASE WHEN COUNT(DISTINCT final_end_d) = 1 THEN MIN(final_end_d) END AS excel_final_end_date,
    CASE WHEN COUNT(DISTINCT excel_final_days_raw) = 1 THEN MIN(excel_final_days_raw) END AS excel_final_days,
    CASE WHEN COUNT(DISTINCT excel_monthly_rate_raw) = 1 THEN MIN(excel_monthly_rate_raw) END AS excel_monthly_rate,
    CASE WHEN COUNT(DISTINCT excel_final_charge_raw) = 1 THEN MIN(excel_final_charge_raw) ELSE ROUND(SUM(excel_final_charge_raw), 6) END AS excel_final_charge,
    CAST(NULL AS STRING) AS excel_product_id,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(excel_product_name))) AS excel_product_names,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(excel_final_days_raw AS STRING)))) AS excel_final_days_values,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(excel_monthly_rate_raw AS STRING)))) AS excel_monthly_rate_values,
    COUNT(*) AS excel_row_count,
    DAY(MAX(d2)) AS month_days
  FROM wa_raw
  GROUP BY billing_month, d1, d2, imsi, charge_type
),
status_scope AS (
  SELECT c.billing_month, CAST(s.imsi AS STRING) AS imsi,
    COUNT(*) AS status_snapshot_rows,
    COUNT(DISTINCT CAST(s.product_id AS STRING)) AS status_product_id_count,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(s.product_id AS STRING)))) AS status_product_ids,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(p.platform_product_name))) AS status_product_names,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(s.Cycle_Start_Time AS STRING)))) AS status_cycle_start_values,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(s.Cycle_End_Time AS STRING)))) AS status_cycle_end_values
  FROM cfg c
  JOIN simo_prod.tc_cdr.sim_status_for_sftp_bak s
    ON s.year = 2026 AND s.month = MONTH(c.d1)
  JOIN product_dim p
    ON p.product_id = CAST(s.product_id AS STRING) AND p.supplier_id = 2275
  WHERE NULLIF(TRIM(CAST(s.imsi AS STRING)), '') IS NOT NULL
  GROUP BY c.billing_month, CAST(s.imsi AS STRING)
),
cycle_scope_rows AS (
  SELECT c.billing_month, c.d1, c.d2, CAST(h.imsi AS STRING) AS imsi,
    CAST(h.product_id AS STRING) AS platform_product_id,
    h.cycle_time, h.next_cycle_time, h.package_price AS history_package_price,
    p.platform_product_name, p.product_category, p.platform_owner, p.dim_package_price,
    p.dim_monthly_rent, p.billing_cycle, p.billing_type, p.create_time AS product_create_time, p.modify_time AS product_modify_time
  FROM cfg c
  JOIN simo_prod.ods.resource_res_vsim_cycle_history h
    ON h.cycle_time < CAST(c.d2 AS TIMESTAMP) + INTERVAL 1 DAY
   AND COALESCE(h.next_cycle_time, TIMESTAMP '9999-12-31 00:00:00') >= CAST(c.d1 AS TIMESTAMP)
  JOIN product_dim p
    ON p.product_id = CAST(h.product_id AS STRING) AND p.supplier_id = 2275
   AND (TRY_CAST(p.create_time AS TIMESTAMP) IS NULL OR TRY_CAST(p.create_time AS TIMESTAMP) <= h.cycle_time)
  WHERE NULLIF(TRIM(CAST(h.imsi AS STRING)), '') IS NOT NULL
),
cycle_scope AS (
  SELECT billing_month, imsi,
    COUNT(*) AS cycle_rows,
    COUNT(DISTINCT platform_product_id) AS platform_product_id_count,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(platform_product_id))) AS platform_product_ids,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(platform_product_name))) AS platform_product_names,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(history_package_price AS STRING)))) AS history_package_prices,
    COUNT(DISTINCT history_package_price) AS history_price_count,
    CASE WHEN COUNT(DISTINCT dim_package_price) = 1 THEN MIN(dim_package_price) END AS platform_calculated_price,
    COUNT(DISTINCT dim_package_price) AS dim_price_count,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(dim_package_price AS STRING)))) AS dim_package_prices,
    MIN(CASE WHEN next_cycle_time >= CAST(d1 AS TIMESTAMP) AND next_cycle_time < CAST(d2 AS TIMESTAMP) + INTERVAL 1 DAY THEN next_cycle_time END) AS cycle_boundary_utc,
    MIN(CASE WHEN next_cycle_time >= CAST(d1 AS TIMESTAMP) AND next_cycle_time < CAST(d2 AS TIMESTAMP) + INTERVAL 1 DAY THEN next_cycle_time - INTERVAL 5 HOURS END) AS cycle_boundary_minus5,
    COUNT(DISTINCT platform_product_name) AS platform_product_name_count,
    COUNT(DISTINCT product_category) AS platform_category_count,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(product_category AS STRING)))) AS platform_categories,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(platform_owner AS STRING)))) AS platform_owners,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(product_create_time AS STRING)))) AS product_create_times,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(product_modify_time AS STRING)))) AS product_modify_times
  FROM cycle_scope_rows
  GROUP BY billing_month, imsi
),
platform_keys AS (
  SELECT billing_month, imsi FROM status_scope
  UNION
  SELECT billing_month, imsi FROM cycle_scope
),
status_log_scope AS (
  SELECT k.billing_month, k.imsi,
    COUNT(*) AS status_log_rows,
    COUNT(DISTINCT l.NEXT_STATUS) AS next_status_count,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(l.NEXT_STATUS AS STRING)))) AS next_status_values,
    MIN(CASE WHEN l.NEXT_STATUS = '激活' THEN l.CREATE_DATE END) AS activation_utc,
    MIN(CASE WHEN l.NEXT_STATUS = '作废' THEN l.CREATE_DATE END) AS void_utc
  FROM platform_keys k
  JOIN cfg c ON c.billing_month = k.billing_month
  JOIN simo_prod.ods.resource_res_vsim_status_log l
    ON CAST(l.IMSI AS STRING) = k.imsi
   AND TRY_CAST(l.partition_date AS DATE) >= c.d1
   AND TRY_CAST(l.partition_date AS DATE) < c.d2 + INTERVAL 1 DAY
   AND l.CREATE_DATE >= CAST(c.d1 AS TIMESTAMP)
   AND l.CREATE_DATE < CAST(c.d2 AS TIMESTAMP) + INTERVAL 1 DAY
  GROUP BY k.billing_month, k.imsi
),
platform_fact AS (
  SELECT k.billing_month, k.imsi,
    COALESCE(s.status_snapshot_rows, 0) AS status_snapshot_rows,
    COALESCE(c.cycle_rows, 0) AS cycle_rows,
    COALESCE(l.status_log_rows, 0) AS status_log_rows,
    s.status_product_id_count, s.status_product_ids, s.status_product_names,
    c.platform_product_id_count, c.platform_product_ids, c.platform_product_names,
    c.history_price_count, c.history_package_prices, c.platform_calculated_price,
    c.dim_price_count, c.dim_package_prices, c.cycle_boundary_utc, c.cycle_boundary_minus5,
    c.platform_product_name_count, c.platform_category_count, c.platform_categories, c.platform_owners,
    c.product_create_times, c.product_modify_times,
    l.next_status_count, l.next_status_values, l.activation_utc, l.void_utc
  FROM platform_keys k
  LEFT JOIN status_scope s ON s.billing_month = k.billing_month AND s.imsi = k.imsi
  LEFT JOIN cycle_scope c ON c.billing_month = k.billing_month AND c.imsi = k.imsi
  LEFT JOIN status_log_scope l ON l.billing_month = k.billing_month AND l.imsi = k.imsi
),
scored AS (
  SELECT w.*,
    p.status_snapshot_rows, p.cycle_rows, p.status_log_rows,
    p.status_product_id_count, p.status_product_ids, p.status_product_names,
    p.platform_product_id_count, p.platform_product_ids, p.platform_product_names,
    p.history_price_count, p.history_package_prices, p.platform_calculated_price,
    p.dim_price_count, p.dim_package_prices, p.cycle_boundary_utc, p.cycle_boundary_minus5,
    p.platform_product_name_count, p.platform_category_count, p.platform_categories,
    p.platform_owners, p.product_create_times, p.product_modify_times,
    p.next_status_count, p.next_status_values, p.activation_utc, p.void_utc,
    CASE WHEN w.charge_type = 'Full Cycle Charge' THEN CAST(w.month_days AS DOUBLE)
         WHEN w.charge_type IN ('Full Cycle Charge - Backbilled for FEB Invoice') AND w.excel_final_start_date IS NOT NULL AND w.excel_final_end_date IS NOT NULL THEN CAST(DATEDIFF(w.excel_final_end_date, w.excel_final_start_date) + 1 AS DOUBLE)
         WHEN w.charge_type = 'New Activation: Prorated-in Charge' AND p.activation_utc IS NOT NULL THEN CAST(DATEDIFF(w.d2, TO_DATE(p.activation_utc)) + 1 AS DOUBLE)
         WHEN w.charge_type LIKE 'Partial Charge%' AND p.void_utc IS NOT NULL AND w.excel_final_start_date IS NOT NULL THEN CAST(DATEDIFF(DATE_SUB(TO_DATE(p.void_utc), 1), w.excel_final_start_date) + 1 AS DOUBLE)
         WHEN w.charge_type LIKE 'Prorated Out%' AND p.cycle_boundary_utc IS NOT NULL THEN CAST(DATEDIFF(w.d2, TO_DATE(p.cycle_boundary_utc)) + 1 AS DOUBLE)
         WHEN w.charge_type LIKE 'Prorated-out%' AND p.cycle_boundary_utc IS NOT NULL THEN CAST(DATEDIFF(w.d2, TO_DATE(p.cycle_boundary_utc)) + 1 AS DOUBLE)
         ELSE NULL END AS platform_calculated_days,
    CASE WHEN w.charge_type = 'Full Cycle Charge' THEN 'PLATFORM_MONTH_PARTITION_DAYS'
         WHEN w.charge_type = 'Full Cycle Charge - Backbilled for FEB Invoice' THEN 'PLATFORM_BACKBILL_DATE_SPAN_FOR_REFERENCE'
         WHEN w.charge_type = 'New Activation: Prorated-in Charge' THEN 'PLATFORM_ACTIVATION_UTC_TO_MONTH_END'
         WHEN w.charge_type LIKE 'Partial Charge%' THEN 'PLATFORM_FINAL_START_TO_VOID_UTC_MINUS1'
         WHEN w.charge_type LIKE 'Prorated Out%' OR w.charge_type LIKE 'Prorated-out%' THEN 'PLATFORM_CYCLE_UTC_TO_MONTH_END'
         ELSE 'NO_PLATFORM_DAY_RULE' END AS platform_calculated_days_rule
  FROM wa_card w LEFT JOIN platform_fact p ON p.billing_month = w.billing_month AND p.imsi = w.imsi
),
calculated AS (
  SELECT *,
    CASE WHEN excel_final_days IS NOT NULL AND platform_calculated_days IS NOT NULL THEN excel_final_days - platform_calculated_days END AS excel_minus_platform_days,
    CASE WHEN excel_monthly_rate IS NOT NULL AND platform_calculated_price IS NOT NULL THEN excel_monthly_rate - platform_calculated_price END AS excel_minus_platform_price,
    CASE WHEN charge_type LIKE 'Credit%' THEN NULL
         WHEN platform_calculated_price IS NOT NULL AND platform_calculated_days IS NOT NULL THEN CASE WHEN charge_type IN ('Full Cycle Charge', 'Full Cycle Charge - Backbilled for FEB Invoice') THEN ROUND(platform_calculated_price, 6) ELSE ROUND(platform_calculated_price * platform_calculated_days / month_days, 6) END
         ELSE NULL END AS platform_calculated_amount,
    CASE WHEN charge_type IN ('Full Cycle Charge', 'Full Cycle Charge - Backbilled for FEB Invoice') AND excel_monthly_rate IS NOT NULL THEN ROUND(excel_monthly_rate, 6)
         WHEN charge_type LIKE 'Credit%' THEN NULL
         WHEN excel_monthly_rate IS NOT NULL AND excel_final_days IS NOT NULL THEN ROUND(excel_monthly_rate * excel_final_days / month_days, 6)
         ELSE NULL END AS excel_calculated_amount
  FROM scored
)
SELECT billing_month, charge_type,
  COUNT(*) AS card_count,
  SUM(CASE WHEN excel_final_days IS NOT NULL AND platform_calculated_days IS NOT NULL THEN 1 ELSE 0 END) AS platform_days_evaluable,
  SUM(CASE WHEN excel_final_days IS NOT NULL AND platform_calculated_days IS NOT NULL AND excel_final_days = platform_calculated_days THEN 1 ELSE 0 END) AS platform_days_exact,
  ROUND(SUM(CASE WHEN excel_final_days IS NOT NULL AND platform_calculated_days IS NOT NULL AND excel_final_days = platform_calculated_days THEN 1 ELSE 0 END) / NULLIF(SUM(CASE WHEN excel_final_days IS NOT NULL AND platform_calculated_days IS NOT NULL THEN 1 ELSE 0 END),0), 6) AS platform_days_exact_rate,
  SUM(CASE WHEN excel_final_days IS NOT NULL AND platform_calculated_days IS NOT NULL AND ABS(excel_minus_platform_days) = 1 THEN 1 ELSE 0 END) AS platform_day_error_1,
  SUM(CASE WHEN excel_final_days IS NOT NULL AND platform_calculated_days IS NOT NULL AND ABS(excel_minus_platform_days) >= 2 THEN 1 ELSE 0 END) AS platform_day_error_ge2,
  SUM(CASE WHEN platform_calculated_price IS NOT NULL THEN 1 ELSE 0 END) AS platform_price_evaluable,
  SUM(CASE WHEN excel_monthly_rate IS NOT NULL AND platform_calculated_price IS NOT NULL AND ABS(excel_minus_platform_price) <= 0.01 THEN 1 ELSE 0 END) AS platform_price_exact,
  ROUND(SUM(CASE WHEN excel_monthly_rate IS NOT NULL AND platform_calculated_price IS NOT NULL AND ABS(excel_minus_platform_price) <= 0.01 THEN 1 ELSE 0 END) / NULLIF(SUM(CASE WHEN excel_monthly_rate IS NOT NULL AND platform_calculated_price IS NOT NULL THEN 1 ELSE 0 END),0), 6) AS platform_price_exact_rate,
  SUM(CASE WHEN platform_calculated_amount IS NOT NULL THEN 1 ELSE 0 END) AS platform_amount_evaluable,
  SUM(CASE WHEN platform_calculated_amount IS NOT NULL AND ABS(excel_final_charge - platform_calculated_amount) <= 0.01 THEN 1 ELSE 0 END) AS platform_amount_exact,
  ROUND(SUM(CASE WHEN platform_calculated_amount IS NOT NULL AND ABS(excel_final_charge - platform_calculated_amount) <= 0.01 THEN 1 ELSE 0 END) / NULLIF(SUM(CASE WHEN platform_calculated_amount IS NOT NULL THEN 1 ELSE 0 END),0), 6) AS platform_amount_exact_rate,
  ROUND(SUM(CASE WHEN platform_calculated_amount IS NOT NULL THEN excel_final_charge - platform_calculated_amount ELSE 0 END), 6) AS platform_amount_diff_sum,
  SUM(CASE WHEN history_price_count > 1 THEN 1 ELSE 0 END) AS multiple_history_price_cards,
  SUM(CASE WHEN dim_price_count > 1 THEN 1 ELSE 0 END) AS multiple_dimension_price_cards,
  SUM(CASE WHEN dim_price_count = 0 OR dim_price_count IS NULL THEN 1 ELSE 0 END) AS missing_dimension_price_cards,
  SUM(CASE WHEN history_price_count = 0 OR history_price_count IS NULL THEN 1 ELSE 0 END) AS missing_history_price_cards,
  SUM(CASE WHEN platform_product_id_count IS NULL OR platform_product_id_count = 0 THEN 1 ELSE 0 END) AS missing_platform_product_id_cards
FROM calculated
GROUP BY billing_month, charge_type
ORDER BY billing_month, charge_type