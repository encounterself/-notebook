-- B replay only: 2025-12 and 2026-02 Excel detail baseline. Read-only.
WITH detail_rows AS (
  SELECT
    TRIM(CAST(d.source_file AS STRING)) AS source_file,
    CASE
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%DEC 2025%' THEN '2025-12'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%FEB 2026%' THEN '2026-02'
      ELSE TRIM(CAST(d.source_file AS STRING))
    END AS invoice_batch_label,
    TRIM(CAST(d.imsi AS STRING)) AS imsi,
    NULLIF(TRIM(CAST(d.charge_type AS STRING)), '') AS charge_type,
    TRY_TO_DATE(TRIM(CAST(d.final_start_date AS STRING))) AS final_start_date,
    TRY_TO_DATE(TRIM(CAST(d.final_end_date AS STRING))) AS final_end_date,
    TRY_CAST(NULLIF(TRIM(CAST(d.final_days AS STRING)), '') AS DECIMAL(38,12)) AS excel_days,
    TRY_CAST(NULLIF(TRIM(CAST(d.monthly_rate AS STRING)), '') AS DECIMAL(38,12)) AS excel_price,
    TRY_CAST(NULLIF(TRIM(CAST(d.final_charge AS STRING)), '') AS DECIMAL(38,12)) AS excel_amount,
    TRIM(CAST(d.product_name AS STRING)) AS excel_product_name
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail d
  WHERE TRIM(CAST(d.source_file AS STRING)) LIKE '%DEC 2025%'
     OR TRIM(CAST(d.source_file AS STRING)) LIKE '%FEB 2026%'
),
source_summary AS (
  SELECT
    source_file,
    invoice_batch_label,
    COUNT(*) AS record_count,
    COUNT(DISTINCT imsi) AS distinct_imsi_count,
    SUM(excel_amount) AS total_final_charge,
    SUM(excel_price) AS total_monthly_rate_sum,
    COUNT(DISTINCT charge_type) AS charge_type_count,
    COUNT(DISTINCT excel_product_name) AS product_count,
    MIN(final_start_date) AS min_final_start_date,
    MAX(final_start_date) AS max_final_start_date,
    MIN(final_end_date) AS min_final_end_date,
    MAX(final_end_date) AS max_final_end_date,
    MIN(DATE_FORMAT(final_start_date, 'yyyy-MM')) AS observed_start_month,
    SUM(CASE WHEN final_start_date IS NULL THEN 1 ELSE 0 END) AS null_final_start_rows,
    SUM(excel_amount) AS row_sum_final_charge
  FROM detail_rows
  GROUP BY source_file, invoice_batch_label
),
charge_summary AS (
  SELECT source_file, invoice_batch_label, charge_type, COUNT(*) AS row_count,
         COUNT(DISTINCT imsi) AS distinct_imsi_count, SUM(excel_amount) AS total_final_charge
  FROM detail_rows
  GROUP BY source_file, invoice_batch_label, charge_type
),
expected_batches AS (
  SELECT '2025-12' AS invoice_batch_label, '2025-12' AS expected_observed_start_month
  UNION ALL SELECT '2026-02', '2026-02'
)
SELECT
  'SOURCE_FILE' AS result_type,
  source_file,
  invoice_batch_label,
  observed_start_month,
  record_count,
  distinct_imsi_count,
  total_final_charge,
  total_monthly_rate_sum,
  charge_type_count,
  product_count,
  min_final_start_date,
  max_final_start_date,
  min_final_end_date,
  max_final_end_date,
  null_final_start_rows,
  row_sum_final_charge - total_final_charge AS row_sum_amount_diff,
  'wa_invoice_detail.final_charge; official Excel invoice truth' AS amount_semantics
FROM source_summary
UNION ALL
SELECT
  'OFFICIAL_BATCH_ZERO_CHECK',
  CAST(NULL AS STRING),
  e.invoice_batch_label,
  e.expected_observed_start_month,
  COALESCE(s.record_count, 0),
  COALESCE(s.distinct_imsi_count, 0),
  COALESCE(s.total_final_charge, CAST(0 AS DECIMAL(38,12))),
  COALESCE(s.total_monthly_rate_sum, CAST(0 AS DECIMAL(38,12))),
  COALESCE(s.charge_type_count, 0),
  COALESCE(s.product_count, 0),
  s.min_final_start_date,
  s.max_final_start_date,
  s.min_final_end_date,
  s.max_final_end_date,
  COALESCE(s.null_final_start_rows, 0),
  CAST(NULL AS DECIMAL(38,12)),
  'official source_file CASE label; no prorated/credit union'
FROM expected_batches e
LEFT JOIN source_summary s ON s.invoice_batch_label = e.invoice_batch_label
UNION ALL
SELECT
  'CHARGE_TYPE', source_file, invoice_batch_label, CAST(NULL AS STRING), row_count,
  distinct_imsi_count, total_final_charge, CAST(NULL AS DECIMAL(38,12)),
  CAST(NULL AS BIGINT), CAST(NULL AS BIGINT), CAST(NULL AS DATE), CAST(NULL AS DATE),
  CAST(NULL AS DATE), CAST(NULL AS DATE), CAST(NULL AS BIGINT), CAST(NULL AS DECIMAL(38,12)),
  'charge_type diagnostic; still detail.final_charge only'
FROM charge_summary
ORDER BY result_type, invoice_batch_label, source_file

