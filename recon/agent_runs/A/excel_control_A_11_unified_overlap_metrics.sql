WITH detail_canonical AS (
  SELECT
    NULLIF(TRIM(CAST(imsi AS STRING)), '') AS imsi_std,
    NULLIF(TRIM(CAST(source_file AS STRING)), '') AS source_file_std,
    NULLIF(TRIM(CAST(product_name AS STRING)), '') AS product_name_std,
    TO_DATE(cycle_start_date) AS cycle_start_std,
    TO_DATE(cycle_end_date) AS cycle_end_std,
    TO_DATE(final_start_date) AS final_start_std,
    TO_DATE(final_end_date) AS final_end_std,
    NULLIF(TRIM(CAST(charge_type AS STRING)), '') AS charge_type_std,
    TRY_CAST(monthly_rate AS DECIMAL(38,12)) AS monthly_rate_std,
    TRY_CAST(final_days AS DECIMAL(38,12)) AS final_days_std,
    TRY_CAST(final_charge AS DECIMAL(38,12)) AS amount_std
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
),
prorated_canonical AS (
  SELECT
    NULLIF(TRIM(CAST(imsi AS STRING)), '') AS imsi_std,
    NULLIF(TRIM(CAST(source_file AS STRING)), '') AS source_file_std,
    NULLIF(TRIM(CAST(product_name AS STRING)), '') AS product_name_std,
    TO_DATE(cycle_start_date) AS cycle_start_std,
    TO_DATE(cycle_end_date) AS cycle_end_std,
    TO_DATE(final_start_date) AS final_start_std,
    TO_DATE(final_end_date) AS final_end_std,
    TRY_CAST(monthly_rate AS DECIMAL(38,12)) AS monthly_rate_std,
    TRY_CAST(usage_days AS DECIMAL(38,12)) AS usage_days_std,
    TRY_CAST(final_charge_for_usage_days AS DECIMAL(38,12)) AS amount_std,
    TRY_CAST(pending_charge AS DECIMAL(38,12)) AS pending_amount_std
  FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
),
detail_keys AS (
  SELECT
    *,
    CONCAT_WS('||', source_file_std, imsi_std, CAST(cycle_start_std AS STRING), CAST(cycle_end_std AS STRING)) AS base_key,
    CONCAT_WS('||', source_file_std, imsi_std, CAST(cycle_start_std AS STRING), CAST(cycle_end_std AS STRING), CAST(final_start_std AS STRING), CAST(final_end_std AS STRING)) AS full_lifecycle_key,
    CONCAT_WS('||', source_file_std, imsi_std, product_name_std, CAST(cycle_start_std AS STRING), CAST(cycle_end_std AS STRING), CAST(final_start_std AS STRING), CAST(final_end_std AS STRING), CAST(monthly_rate_std AS STRING)) AS common_fields_key
  FROM detail_canonical
),
prorated_keys AS (
  SELECT
    *,
    CONCAT_WS('||', source_file_std, imsi_std, CAST(cycle_start_std AS STRING), CAST(cycle_end_std AS STRING)) AS base_key,
    CONCAT_WS('||', source_file_std, imsi_std, CAST(cycle_start_std AS STRING), CAST(cycle_end_std AS STRING), CAST(final_start_std AS STRING), CAST(final_end_std AS STRING)) AS full_lifecycle_key,
    CONCAT_WS('||', source_file_std, imsi_std, product_name_std, CAST(cycle_start_std AS STRING), CAST(cycle_end_std AS STRING), CAST(final_start_std AS STRING), CAST(final_end_std AS STRING), CAST(monthly_rate_std AS STRING)) AS common_fields_key
  FROM prorated_canonical
),
detail_imsi_groups AS (
  SELECT imsi_std AS overlap_key, COUNT(*) AS detail_row_count, ROUND(SUM(amount_std), 6) AS detail_amount
  FROM detail_keys
  WHERE imsi_std IS NOT NULL
  GROUP BY imsi_std
),
prorated_imsi_groups AS (
  SELECT imsi_std AS overlap_key, COUNT(*) AS prorated_row_count, ROUND(SUM(amount_std), 6) AS prorated_amount, ROUND(SUM(pending_amount_std), 6) AS pending_amount
  FROM prorated_keys
  WHERE imsi_std IS NOT NULL
  GROUP BY imsi_std
),
detail_base_groups AS (
  SELECT base_key AS overlap_key, COUNT(*) AS detail_row_count, ROUND(SUM(amount_std), 6) AS detail_amount
  FROM detail_keys
  WHERE imsi_std IS NOT NULL AND source_file_std IS NOT NULL AND cycle_start_std IS NOT NULL AND cycle_end_std IS NOT NULL
  GROUP BY base_key
),
prorated_base_groups AS (
  SELECT base_key AS overlap_key, COUNT(*) AS prorated_row_count, ROUND(SUM(amount_std), 6) AS prorated_amount, ROUND(SUM(pending_amount_std), 6) AS pending_amount
  FROM prorated_keys
  WHERE imsi_std IS NOT NULL AND source_file_std IS NOT NULL AND cycle_start_std IS NOT NULL AND cycle_end_std IS NOT NULL
  GROUP BY base_key
),
detail_full_groups AS (
  SELECT full_lifecycle_key AS overlap_key, COUNT(*) AS detail_row_count, ROUND(SUM(amount_std), 6) AS detail_amount
  FROM detail_keys
  WHERE imsi_std IS NOT NULL AND source_file_std IS NOT NULL AND cycle_start_std IS NOT NULL AND cycle_end_std IS NOT NULL AND final_start_std IS NOT NULL AND final_end_std IS NOT NULL
  GROUP BY full_lifecycle_key
),
prorated_full_groups AS (
  SELECT full_lifecycle_key AS overlap_key, COUNT(*) AS prorated_row_count, ROUND(SUM(amount_std), 6) AS prorated_amount, ROUND(SUM(pending_amount_std), 6) AS pending_amount
  FROM prorated_keys
  WHERE imsi_std IS NOT NULL AND source_file_std IS NOT NULL AND cycle_start_std IS NOT NULL AND cycle_end_std IS NOT NULL AND final_start_std IS NOT NULL AND final_end_std IS NOT NULL
  GROUP BY full_lifecycle_key
),
detail_common_groups AS (
  SELECT common_fields_key AS overlap_key, COUNT(*) AS detail_row_count, ROUND(SUM(amount_std), 6) AS detail_amount
  FROM detail_keys
  WHERE imsi_std IS NOT NULL AND source_file_std IS NOT NULL AND product_name_std IS NOT NULL AND cycle_start_std IS NOT NULL AND cycle_end_std IS NOT NULL AND final_start_std IS NOT NULL AND final_end_std IS NOT NULL AND monthly_rate_std IS NOT NULL
  GROUP BY common_fields_key
),
prorated_common_groups AS (
  SELECT common_fields_key AS overlap_key, COUNT(*) AS prorated_row_count, ROUND(SUM(amount_std), 6) AS prorated_amount, ROUND(SUM(pending_amount_std), 6) AS pending_amount
  FROM prorated_keys
  WHERE imsi_std IS NOT NULL AND source_file_std IS NOT NULL AND product_name_std IS NOT NULL AND cycle_start_std IS NOT NULL AND cycle_end_std IS NOT NULL AND final_start_std IS NOT NULL AND final_end_std IS NOT NULL AND monthly_rate_std IS NOT NULL
  GROUP BY common_fields_key
),
overlap_metrics AS (
  SELECT
    'IMSI_OVERLAP' AS overlap_type,
    'imsi' AS key_fields,
    COUNT(*) AS shared_key_count,
    SUM(d.detail_row_count) AS detail_rows_on_shared_keys,
    SUM(p.prorated_row_count) AS prorated_rows_on_shared_keys,
    SUM(CASE WHEN d.detail_row_count = 1 AND p.prorated_row_count = 1 THEN 1 ELSE 0 END) AS one_to_one_key_count,
    SUM(CASE WHEN d.detail_row_count > 1 OR p.prorated_row_count > 1 THEN 1 ELSE 0 END) AS non_one_to_one_key_count,
    ROUND(SUM(d.detail_amount), 6) AS detail_amount_on_shared_keys,
    ROUND(SUM(p.prorated_amount), 6) AS prorated_amount_on_shared_keys,
    ROUND(SUM(p.pending_amount), 6) AS prorated_pending_on_shared_keys
  FROM detail_imsi_groups d
  JOIN prorated_imsi_groups p ON d.overlap_key = p.overlap_key
  UNION ALL
  SELECT
    'COMMON_FIELDS_EXACT_OVERLAP',
    'source_file|imsi|product_name|cycle_start|cycle_end|final_start|final_end|monthly_rate',
    COUNT(*),
    SUM(d.detail_row_count),
    SUM(p.prorated_row_count),
    SUM(CASE WHEN d.detail_row_count = 1 AND p.prorated_row_count = 1 THEN 1 ELSE 0 END),
    SUM(CASE WHEN d.detail_row_count > 1 OR p.prorated_row_count > 1 THEN 1 ELSE 0 END),
    ROUND(SUM(d.detail_amount), 6),
    ROUND(SUM(p.prorated_amount), 6),
    ROUND(SUM(p.pending_amount), 6)
  FROM detail_common_groups d
  JOIN prorated_common_groups p ON d.overlap_key = p.overlap_key
  UNION ALL
  SELECT
    'SOURCE_IMSI_CYCLE_EXACT_OVERLAP',
    'source_file|imsi|cycle_start|cycle_end',
    COUNT(*),
    SUM(d.detail_row_count),
    SUM(p.prorated_row_count),
    SUM(CASE WHEN d.detail_row_count = 1 AND p.prorated_row_count = 1 THEN 1 ELSE 0 END),
    SUM(CASE WHEN d.detail_row_count > 1 OR p.prorated_row_count > 1 THEN 1 ELSE 0 END),
    ROUND(SUM(d.detail_amount), 6),
    ROUND(SUM(p.prorated_amount), 6),
    ROUND(SUM(p.pending_amount), 6)
  FROM detail_base_groups d
  JOIN prorated_base_groups p ON d.overlap_key = p.overlap_key
  UNION ALL
  SELECT
    'SOURCE_IMSI_CYCLE_FINAL_EXACT_OVERLAP',
    'source_file|imsi|cycle_start|cycle_end|final_start|final_end',
    COUNT(*),
    SUM(d.detail_row_count),
    SUM(p.prorated_row_count),
    SUM(CASE WHEN d.detail_row_count = 1 AND p.prorated_row_count = 1 THEN 1 ELSE 0 END),
    SUM(CASE WHEN d.detail_row_count > 1 OR p.prorated_row_count > 1 THEN 1 ELSE 0 END),
    ROUND(SUM(d.detail_amount), 6),
    ROUND(SUM(p.prorated_amount), 6),
    ROUND(SUM(p.pending_amount), 6)
  FROM detail_full_groups d
  JOIN prorated_full_groups p ON d.overlap_key = p.overlap_key
)
SELECT * FROM overlap_metrics
ORDER BY overlap_type
