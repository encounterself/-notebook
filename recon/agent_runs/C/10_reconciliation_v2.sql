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
    CAST(2275 AS BIGINT) AS platform_supplier_id,
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
wa_pending AS (
  SELECT c.billing_month, CAST(x.imsi AS STRING) AS imsi,
    COUNT(*) AS pending_rows,
    ROUND(SUM(TRY_CAST(x.final_charge_for_usage_days AS DOUBLE)), 6) AS pending_final_charge_for_usage_days,
    ROUND(SUM(TRY_CAST(x.pending_charge AS DOUBLE)), 6) AS pending_charge,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(x.product_name AS STRING)))) AS pending_product_names,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(x.monthly_rate AS STRING)))) AS pending_monthly_rates,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(x.sheet_name AS STRING)))) AS pending_sheets
  FROM cfg c JOIN simo_prod.mysql_cdc_sync.wa_invoice_prorated x ON x.source_file = CASE c.billing_month
    WHEN '2026-03' THEN '01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx'
    WHEN '2026-04' THEN '01-SIMO Data Purchase Invoice Details - APR 2026.xlsx'
    WHEN '2026-05' THEN '01-SIMO Data Purchase Invoice Details - MAY 2026.xlsx' END
  GROUP BY c.billing_month, CAST(x.imsi AS STRING)
),
wa_month AS (
  SELECT w.billing_month, w.imsi,
    SUM(excel_row_count) AS detail_rows,
    COUNT(DISTINCT charge_type) AS charge_type_count,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(charge_type))) AS charge_types,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(excel_product_names))) AS excel_product_names,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(excel_final_days_values))) AS excel_final_days_values,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(excel_monthly_rate_values))) AS excel_monthly_rates,
    ROUND(SUM(excel_final_charge), 6) AS detail_amount,
    COALESCE(MAX(p.pending_rows), 0) AS pending_rows,
    MAX(p.pending_final_charge_for_usage_days) AS pending_final_charge_for_usage_days,
    MAX(p.pending_charge) AS pending_charge,
    MAX(p.pending_product_names) AS pending_product_names,
    MAX(p.pending_monthly_rates) AS pending_monthly_rates,
    MAX(p.pending_sheets) AS pending_sheets,
    ROUND(SUM(excel_final_charge) + COALESCE(MAX(p.pending_final_charge_for_usage_days), 0), 6) AS excel_total_amount
  FROM wa_card w
  LEFT JOIN wa_pending p ON p.billing_month = w.billing_month AND p.imsi = w.imsi
  GROUP BY w.billing_month, w.imsi
  UNION ALL
  SELECT p.billing_month, p.imsi,
    0 AS detail_rows, 0 AS charge_type_count, CAST(NULL AS STRING) AS charge_types,
    p.pending_product_names AS excel_product_names, CAST(NULL AS STRING) AS excel_final_days_values,
    p.pending_monthly_rates AS excel_monthly_rates, CAST(NULL AS DOUBLE) AS detail_amount,
    p.pending_rows, p.pending_final_charge_for_usage_days, p.pending_charge,
    p.pending_product_names, p.pending_monthly_rates, p.pending_sheets,
    p.pending_final_charge_for_usage_days AS excel_total_amount
  FROM wa_pending p
  WHERE NOT EXISTS (SELECT 1 FROM wa_card w WHERE w.billing_month = p.billing_month AND w.imsi = p.imsi)
),
recon AS (
  SELECT COALESCE(w.billing_month, p.billing_month) AS billing_month,
    COALESCE(w.imsi, p.imsi) AS imsi,
    CASE WHEN w.imsi IS NOT NULL AND p.imsi IS NOT NULL THEN 'MATCHED'
         WHEN w.imsi IS NOT NULL THEN 'WA_ONLY'
         ELSE 'PLATFORM_ONLY' END AS reconciliation_status,
    CASE WHEN p.imsi IS NULL THEN 'NO_SCOPED_PLATFORM_FACT'
         ELSE 'WING_ALPHA_PRODUCT_ID_SCOPE' END AS platform_scope_status,
    CASE WHEN p.imsi IS NULL THEN 'MISSING_PLATFORM_FACT'
         WHEN p.platform_product_id_count IS NULL OR p.platform_product_id_count = 0 THEN 'MISSING_PLATFORM_PRODUCT_ID'
         WHEN p.dim_price_count = 1 THEN 'PRODUCT_ID_PRICE_PRESENT_NO_VALID_TO_HISTORY'
         ELSE 'PRODUCT_ID_PRICE_MULTIPLE_OR_MISSING' END AS platform_price_status,
    CASE WHEN p.imsi IS NULL THEN 'NO_PLATFORM_KEY'
         WHEN COALESCE(p.status_snapshot_rows, 0) > 0 AND COALESCE(p.cycle_rows, 0) > 0 THEN 'STATUS_SNAPSHOT_AND_CYCLE'
         WHEN COALESCE(p.status_snapshot_rows, 0) > 0 THEN 'STATUS_SNAPSHOT_ONLY'
         WHEN COALESCE(p.cycle_rows, 0) > 0 THEN 'CYCLE_HISTORY_ONLY'
         WHEN COALESCE(p.status_log_rows, 0) > 0 THEN 'SCOPED_STATUS_LOG_ONLY'
         ELSE 'SCOPED_KEY_NO_EVENT_ROW' END AS platform_source_status,
    CASE WHEN w.imsi IS NULL AND p.imsi IS NOT NULL THEN 'PLATFORM_ONLY_NO_EXACT_EXCEL_IMSI_AFTER_DETAIL_PRORATED_DEDUP'
         WHEN w.imsi IS NOT NULL AND p.imsi IS NULL THEN 'WA_ONLY_NO_SUPPLIER_2275_PLATFORM_FACT'
         ELSE NULL END AS platform_exclusion_reason,
    'platform status partition + cycle window first filtered to supplier_id=2275 and product_id; status_log joined only to scoped keys and target partition' AS platform_scope_basis,
    w.detail_rows, w.charge_type_count, w.charge_types, w.excel_product_names, w.excel_final_days_values,
    w.excel_monthly_rates, w.detail_amount, w.pending_rows, w.pending_final_charge_for_usage_days,
    w.pending_charge, w.pending_product_names, w.pending_monthly_rates, w.pending_sheets, w.excel_total_amount,
    CAST(NULL AS STRING) AS excel_product_id,
    p.platform_supplier_id,
    p.status_snapshot_rows, p.cycle_rows, p.status_log_rows,
    p.status_product_ids, p.status_product_names, p.platform_product_ids, p.platform_product_names,
    p.history_package_prices, p.history_price_count, p.dim_package_prices, p.dim_price_count,
    p.platform_calculated_price, p.platform_product_id_count, p.platform_product_name_count,
    p.platform_categories, p.platform_owners, p.product_create_times, p.product_modify_times,
    p.cycle_boundary_utc, p.cycle_boundary_minus5, p.next_status_values, p.activation_utc, p.void_utc,
    CASE WHEN p.dim_price_count = 1 THEN 'PRODUCT_ID_TARGET_MONTH_CURRENT_DIMENSION_NO_VALID_TO'
         WHEN p.dim_price_count > 1 THEN 'PRODUCT_ID_MULTIPLE_CURRENT_PRICES'
         ELSE 'MISSING_PRODUCT_ID_PRICE' END AS product_effective_status
  FROM wa_month w FULL OUTER JOIN platform_fact p
    ON p.billing_month = w.billing_month AND p.imsi = w.imsi
)
SELECT * FROM recon ORDER BY billing_month, reconciliation_status, platform_price_status, imsi