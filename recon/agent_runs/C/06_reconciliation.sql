WITH cfg AS (
  SELECT '2026-03' AS billing_month, DATE '2026-03-01' AS d1, DATE '2026-03-31' AS d2
  UNION ALL SELECT '2026-04', DATE '2026-04-01', DATE '2026-04-30'
  UNION ALL SELECT '2026-05', DATE '2026-05-01', DATE '2026-05-31'
),
wa_detail AS (
  SELECT c.billing_month, CAST(x.imsi AS STRING) AS imsi,
    COUNT(*) AS detail_rows, COUNT(DISTINCT x.charge_type) AS charge_type_count,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(x.charge_type AS STRING)))) AS charge_types,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(x.final_days AS STRING)))) AS final_days_values,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(x.monthly_rate AS STRING)))) AS price_values,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(x.product_name AS STRING)))) AS detail_product_names,
    ROUND(SUM(TRY_CAST(x.final_charge AS DOUBLE)), 6) AS detail_amount,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(x.source_file AS STRING)))) AS detail_source_files
  FROM cfg c JOIN simo_prod.mysql_cdc_sync.wa_invoice_detail x
    ON x.source_file = CASE c.billing_month
      WHEN '2026-03' THEN '01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx'
      WHEN '2026-04' THEN '01-SIMO Data Purchase Invoice Details - APR 2026.xlsx'
      WHEN '2026-05' THEN '01-SIMO Data Purchase Invoice Details - MAY 2026.xlsx' END
  GROUP BY c.billing_month, CAST(x.imsi AS STRING)
),
wa_pending AS (
  SELECT c.billing_month, CAST(x.imsi AS STRING) AS imsi,
    COUNT(*) AS pending_rows, ROUND(SUM(TRY_CAST(x.final_charge_for_usage_days AS DOUBLE)), 6) AS pending_amount,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(x.sheet_name AS STRING)))) AS pending_sheets
  FROM cfg c JOIN simo_prod.mysql_cdc_sync.wa_invoice_prorated x
    ON x.source_file = CASE c.billing_month
      WHEN '2026-03' THEN '01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx'
      WHEN '2026-04' THEN '01-SIMO Data Purchase Invoice Details - APR 2026.xlsx'
      WHEN '2026-05' THEN '01-SIMO Data Purchase Invoice Details - MAY 2026.xlsx' END
  GROUP BY c.billing_month, CAST(x.imsi AS STRING)
),
wa_month AS (
  SELECT COALESCE(d.billing_month, p.billing_month) AS billing_month, COALESCE(d.imsi, p.imsi) AS imsi,
    COALESCE(d.detail_rows, 0) AS detail_rows, COALESCE(d.charge_type_count, 0) AS charge_type_count,
    d.charge_types, d.final_days_values, d.price_values, d.detail_product_names, d.detail_amount, d.detail_source_files,
    COALESCE(p.pending_rows, 0) AS pending_rows, p.pending_amount, p.pending_sheets,
    ROUND(COALESCE(d.detail_amount, 0) + COALESCE(p.pending_amount, 0), 6) AS wa_total_amount
  FROM wa_detail d FULL OUTER JOIN wa_pending p ON p.billing_month = d.billing_month AND p.imsi = d.imsi
),
status_month AS (
  SELECT CONCAT(CAST(year AS STRING), '-', LPAD(CAST(month AS STRING), 2, '0')) AS billing_month,
    CAST(imsi AS STRING) AS imsi, COUNT(*) AS status_snapshot_rows,
    COUNT(DISTINCT CAST(product_id AS STRING)) AS status_product_count,
    COUNT(DISTINCT CAST(ICCID AS STRING)) AS status_iccid_count,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(SimStatus AS STRING)))) AS sim_status_values,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(DispatchStatus AS STRING)))) AS dispatch_status_values,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(Cycle_Start_Time AS STRING)))) AS cycle_start_values,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(Cycle_End_Time AS STRING)))) AS cycle_end_values
  FROM simo_prod.tc_cdr.sim_status_for_sftp_bak
  WHERE year = 2026 AND month IN (3, 4, 5) AND NULLIF(TRIM(CAST(imsi AS STRING)), '') IS NOT NULL
  GROUP BY CONCAT(CAST(year AS STRING), '-', LPAD(CAST(month AS STRING), 2, '0')), CAST(imsi AS STRING)
),
cycle_month AS (
  SELECT c.billing_month, CAST(h.imsi AS STRING) AS imsi, COUNT(*) AS cycle_rows,
    COUNT(DISTINCT CAST(h.product_id AS STRING)) AS cycle_product_count,
    COUNT(DISTINCT TO_DATE(h.cycle_time)) AS cycle_time_date_count,
    COUNT(DISTINCT TO_DATE(h.next_cycle_time)) AS next_cycle_date_count,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(h.product_id AS STRING)))) AS cycle_product_ids,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(TO_DATE(h.cycle_time) AS STRING)))) AS cycle_time_dates,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(TO_DATE(h.next_cycle_time) AS STRING)))) AS next_cycle_dates,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(ROUND(h.package_price, 6) AS STRING)))) AS cycle_package_prices,
    COUNT(DISTINCT CASE WHEN LOWER(CAST(p.product_name AS STRING)) LIKE '%(wa)%' THEN CAST(p.product_name AS STRING) END) AS wa_product_name_count,
    COUNT(DISTINCT CASE WHEN LOWER(CAST(p.product_name AS STRING)) LIKE '%(pi)%' THEN CAST(p.product_name AS STRING) END) AS pi_product_name_count,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(p.product_name AS STRING)))) AS platform_product_names
  FROM cfg c JOIN simo_prod.ods.resource_res_vsim_cycle_history h
    ON h.cycle_time < CAST(c.d2 AS TIMESTAMP) + INTERVAL 1 DAY
   AND COALESCE(h.next_cycle_time, TIMESTAMP '9999-12-31 00:00:00') >= CAST(c.d1 AS TIMESTAMP)
  LEFT JOIN simo_prod.ods.resource_res_vsim_product p ON CAST(p.product_id AS STRING) = CAST(h.product_id AS STRING)
  WHERE NULLIF(TRIM(CAST(h.imsi AS STRING)), '') IS NOT NULL
  GROUP BY c.billing_month, CAST(h.imsi AS STRING)
),
status_log_month AS (
  SELECT c.billing_month, CAST(l.IMSI AS STRING) AS imsi, COUNT(*) AS status_log_rows,
    COUNT(DISTINCT CAST(l.NEXT_STATUS AS STRING)) AS next_status_count,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(l.NEXT_STATUS AS STRING)))) AS next_status_values,
    MIN(CASE WHEN l.NEXT_STATUS = '作废' THEN l.CREATE_DATE END) AS first_void_utc,
    MIN(CASE WHEN l.NEXT_STATUS = '激活' THEN l.CREATE_DATE END) AS first_activation_utc
  FROM cfg c JOIN simo_prod.ods.resource_res_vsim_status_log l
    ON l.CREATE_DATE >= CAST(c.d1 AS TIMESTAMP) AND l.CREATE_DATE < CAST(c.d2 AS TIMESTAMP) + INTERVAL 1 DAY
  WHERE NULLIF(TRIM(CAST(l.IMSI AS STRING)), '') IS NOT NULL
  GROUP BY c.billing_month, CAST(l.IMSI AS STRING)
),
platform_keys AS (
  SELECT billing_month, imsi FROM status_month UNION SELECT billing_month, imsi FROM cycle_month UNION SELECT billing_month, imsi FROM status_log_month
),
platform_month AS (
  SELECT k.billing_month, k.imsi,
    COALESCE(s.status_snapshot_rows, 0) AS status_snapshot_rows, COALESCE(c.cycle_rows, 0) AS cycle_rows,
    COALESCE(l.status_log_rows, 0) AS status_log_rows,
    s.status_product_count, s.status_iccid_count, s.sim_status_values, s.dispatch_status_values,
    s.cycle_start_values, s.cycle_end_values, c.cycle_product_count, c.cycle_product_ids,
    c.cycle_time_dates, c.next_cycle_dates, c.cycle_package_prices, c.wa_product_name_count,
    c.pi_product_name_count, c.platform_product_names, l.next_status_count, l.next_status_values,
    l.first_void_utc, l.first_activation_utc,
    CASE WHEN COALESCE(c.wa_product_name_count, 0) > 0 AND COALESCE(c.pi_product_name_count, 0) = 0 THEN 'WA_NAMED'
         WHEN COALESCE(c.wa_product_name_count, 0) = 0 AND COALESCE(c.pi_product_name_count, 0) > 0 THEN 'PI_NAMED'
         WHEN COALESCE(c.wa_product_name_count, 0) > 0 AND COALESCE(c.pi_product_name_count, 0) > 0 THEN 'MULTIPLE_PRODUCT_SCOPE'
         WHEN COALESCE(c.cycle_rows, 0) = 0 THEN 'MISSING_MAPPING'
         ELSE 'UNCLASSIFIED' END AS platform_mapping_status
  FROM platform_keys k LEFT JOIN status_month s ON s.billing_month = k.billing_month AND s.imsi = k.imsi
  LEFT JOIN cycle_month c ON c.billing_month = k.billing_month AND c.imsi = k.imsi
  LEFT JOIN status_log_month l ON l.billing_month = k.billing_month AND l.imsi = k.imsi
),
recon AS (
  SELECT COALESCE(w.billing_month, p.billing_month) AS billing_month,
    COALESCE(w.imsi, p.imsi) AS imsi,
    CASE WHEN w.imsi IS NOT NULL AND p.imsi IS NOT NULL THEN 'MATCHED'
         WHEN w.imsi IS NOT NULL THEN 'WA_ONLY' ELSE 'PLATFORM_ONLY' END AS reconciliation_status,
    'ALL_VISIBLE_PLATFORM' AS platform_population_scope,
    CASE WHEN w.imsi IS NULL THEN p.platform_mapping_status
         WHEN p.imsi IS NULL THEN 'MISSING_PLATFORM_FACT'
         WHEN p.platform_mapping_status IN ('WA_NAMED', 'MULTIPLE_PRODUCT_SCOPE') THEN 'PLATFORM_PRODUCT_PRESENT'
         ELSE 'MISSING_MAPPING' END AS mapping_status,
    w.detail_rows, w.charge_type_count, w.charge_types, w.final_days_values, w.price_values,
    w.detail_product_names, w.detail_amount, w.detail_source_files, w.pending_rows, w.pending_amount,
    w.pending_sheets, w.wa_total_amount, p.status_snapshot_rows, p.cycle_rows, p.status_log_rows,
    p.status_product_count, p.status_iccid_count, p.sim_status_values, p.dispatch_status_values,
    p.cycle_start_values, p.cycle_end_values, p.cycle_product_count, p.cycle_product_ids,
    p.cycle_time_dates, p.next_cycle_dates, p.cycle_package_prices, p.platform_product_names,
    p.platform_mapping_status, p.next_status_count, p.next_status_values, p.first_void_utc, p.first_activation_utc
  FROM wa_month w FULL OUTER JOIN platform_month p ON p.billing_month = w.billing_month AND p.imsi = w.imsi
)
SELECT * FROM recon ORDER BY billing_month, reconciliation_status, mapping_status, imsi