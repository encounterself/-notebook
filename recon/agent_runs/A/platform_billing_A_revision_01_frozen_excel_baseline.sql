-- Batch A revision 01: frozen Excel detail control, read-only.
-- Official invoice truth is wa_invoice_detail.final_charge only.
-- wa_invoice_prorated and wa_invoice_credit are intentionally not read here.
WITH detail_rows AS (
  SELECT
    TRIM(CAST(d.source_file AS STRING)) AS source_file,
    CASE
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%JAN 2025%' THEN '2025-01'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%SEP 2025%' THEN '2025-09'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%OCT 2025%'
       AND TRIM(CAST(d.source_file AS STRING)) LIKE '%773,793.84%' THEN '2025-10 (v2)'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%OCT 2025%'
       AND TRIM(CAST(d.source_file AS STRING)) LIKE '%772,765.00%' THEN '2025-10 (v1)'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%DEC 2025%' THEN '2025-12'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%FEB 2026%' THEN '2026-02'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%MAR 2026%' THEN '2026-03'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%APR 2026%' THEN '2026-04'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%MAY 2026%' THEN '2026-05'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%JUNE 2026%' THEN '2026-06'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%JULY 2026%' THEN '2026-07'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%AUGUST 2026%' THEN '2026-08'
      ELSE TRIM(CAST(d.source_file AS STRING))
    END AS invoice_batch_label,
    TRIM(CAST(d.imsi AS STRING)) AS imsi,
    NULLIF(TRIM(CAST(d.charge_type AS STRING)), '') AS charge_type,
    TRY_TO_DATE(TRIM(CAST(d.final_start_date AS STRING))) AS final_start_date,
    TRY_TO_DATE(TRIM(CAST(d.final_end_date AS STRING))) AS final_end_date,
    TRY_CAST(NULLIF(TRIM(CAST(d.final_days AS STRING)), '') AS DECIMAL(38,12)) AS final_days,
    TRY_CAST(NULLIF(TRIM(CAST(d.monthly_rate AS STRING)), '') AS DECIMAL(38,12)) AS monthly_rate,
    TRY_CAST(NULLIF(TRIM(CAST(d.final_charge AS STRING)), '') AS DECIMAL(38,12)) AS final_charge,
    TRIM(CAST(d.product_name AS STRING)) AS product_name,
    TRIM(CAST(d.sheet_name AS STRING)) AS sheet_name
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail d
),
target_detail AS (
  SELECT *
  FROM detail_rows
  WHERE invoice_batch_label IN ('2025-09', '2025-10 (v1)', '2025-10 (v2)')
),
target_batches AS (
  SELECT '2025-09' AS invoice_batch_label, CAST(NULL AS STRING) AS source_file, '2025-09' AS expected_observed_start_month
  UNION ALL SELECT '2025-10 (v1)', CAST(NULL AS STRING), '2025-10'
  UNION ALL SELECT '2025-10 (v2)', CAST(NULL AS STRING), '2025-11'
  UNION ALL SELECT '2026-01', CAST(NULL AS STRING), '2026-01'
),
source_file_summary AS (
  SELECT
    'simo_prod.mysql_cdc_sync.wa_invoice_detail' AS source_table,
    source_file,
    invoice_batch_label,
    COUNT(*) AS record_count,
    COUNT(DISTINCT imsi) AS imsi_count,
    SUM(final_charge) AS total_final_charge,
    SUM(monthly_rate) AS total_monthly_rate_sum,
    COUNT(DISTINCT charge_type) AS charge_type_count,
    COUNT(DISTINCT product_name) AS product_count,
    MIN(final_start_date) AS min_final_start_date,
    MAX(final_start_date) AS max_final_start_date,
    MIN(final_end_date) AS min_final_end_date,
    MAX(final_end_date) AS max_final_end_date,
    MIN(DATE_FORMAT(final_start_date, 'yyyy-MM')) AS observed_start_month,
    SUM(CASE WHEN final_start_date IS NULL THEN 1 ELSE 0 END) AS null_final_start_row_count,
    'detail.final_charge invoice truth' AS amount_semantics
  FROM target_detail
  GROUP BY source_file, invoice_batch_label
),
source_charge_type_summary AS (
  SELECT
    'simo_prod.mysql_cdc_sync.wa_invoice_detail' AS source_table,
    source_file,
    invoice_batch_label,
    charge_type,
    COUNT(*) AS record_count,
    COUNT(DISTINCT imsi) AS imsi_count,
    SUM(final_charge) AS total_final_charge,
    'detail.final_charge invoice truth; charge_type diagnostic' AS amount_semantics
  FROM target_detail
  GROUP BY source_file, invoice_batch_label, charge_type
),
official_month_summary AS (
  SELECT
    'simo_prod.mysql_cdc_sync.wa_invoice_detail' AS source_table,
    s.source_file,
    t.invoice_batch_label,
    t.expected_observed_start_month AS observed_start_month,
    COALESCE(s.record_count, 0) AS record_count,
    COALESCE(s.imsi_count, 0) AS imsi_count,
    COALESCE(s.total_final_charge, CAST(0 AS DECIMAL(38,12))) AS total_final_charge,
    COALESCE(s.total_monthly_rate_sum, CAST(0 AS DECIMAL(38,12))) AS total_monthly_rate_sum,
    COALESCE(s.charge_type_count, 0) AS charge_type_count,
    COALESCE(s.product_count, 0) AS product_count,
    s.min_final_start_date,
    s.max_final_start_date,
    s.min_final_end_date,
    s.max_final_end_date,
    COALESCE(s.null_final_start_row_count, 0) AS null_final_start_row_count,
    'official detail invoice truth; source_file CASE label; no prorated/credit union' AS amount_semantics
  FROM target_batches t
  LEFT JOIN source_file_summary s ON s.invoice_batch_label = t.invoice_batch_label
),
source_file_total_check AS (
  SELECT source_file, SUM(final_charge) AS row_sum_final_charge, COUNT(*) AS row_count_from_rows
  FROM target_detail
  GROUP BY source_file
)
SELECT
  'OFFICIAL_MONTH' AS result_type,
  source_table, source_file, invoice_batch_label, observed_start_month,
  CAST(NULL AS STRING) AS charge_type,
  record_count, imsi_count, total_final_charge, total_monthly_rate_sum,
  charge_type_count, product_count, min_final_start_date, max_final_start_date,
  min_final_end_date, max_final_end_date, null_final_start_row_count,
  amount_semantics, CAST(NULL AS BIGINT) AS row_sum_check_count,
  CAST(NULL AS DECIMAL(38,12)) AS row_sum_check_amount,
  CAST(NULL AS DECIMAL(38,12)) AS row_sum_amount_diff
FROM official_month_summary
UNION ALL
SELECT
  'SOURCE_FILE', s.source_table, s.source_file, s.invoice_batch_label, s.observed_start_month,
  CAST(NULL AS STRING), s.record_count, s.imsi_count, s.total_final_charge, s.total_monthly_rate_sum,
  s.charge_type_count, s.product_count, s.min_final_start_date, s.max_final_start_date,
  s.min_final_end_date, s.max_final_end_date, s.null_final_start_row_count, s.amount_semantics,
  c.row_count_from_rows, c.row_sum_final_charge, c.row_sum_final_charge - s.total_final_charge
FROM source_file_summary s INNER JOIN source_file_total_check c USING (source_file)
UNION ALL
SELECT
  'SOURCE_FILE_CHARGE_TYPE', source_table, source_file, invoice_batch_label,
  CAST(NULL AS STRING), charge_type, record_count, imsi_count, total_final_charge,
  CAST(NULL AS DECIMAL(38,12)), CAST(NULL AS BIGINT), CAST(NULL AS BIGINT),
  CAST(NULL AS DATE), CAST(NULL AS DATE), CAST(NULL AS DATE), CAST(NULL AS DATE),
  CAST(NULL AS BIGINT), amount_semantics, CAST(NULL AS BIGINT),
  CAST(NULL AS DECIMAL(38,12)), CAST(NULL AS DECIMAL(38,12))
FROM source_charge_type_summary
ORDER BY result_type, invoice_batch_label, source_file, charge_type
