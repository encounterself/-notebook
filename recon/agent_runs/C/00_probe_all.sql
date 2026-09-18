WITH invoice_sources AS (
  SELECT
    'mysql_cdc_sync.wa_invoice_detail' AS source_table,
    CAST(source_file AS STRING) AS source_file,
    CAST(sheet_name AS STRING) AS sheet_name,
    CAST(imsi AS STRING) AS imsi,
    CAST(cycle_start_date AS STRING) AS cycle_start_date,
    CAST(cycle_end_date AS STRING) AS cycle_end_date,
    CAST(final_start_date AS STRING) AS final_start_date,
    CAST(final_end_date AS STRING) AS final_end_date,
    CAST(charge_type AS STRING) AS charge_type
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE source_file IS NOT NULL
  UNION ALL
  SELECT
    'mysql_cdc_sync.wa_invoice_credit',
    CAST(source_file AS STRING),
    NULL,
    CAST(imsi AS STRING),
    CAST(cycle_start AS STRING),
    CAST(cycle_end AS STRING),
    CAST(date_replacement_was_activated AS STRING),
    CAST(date_line_went_down AS STRING),
    'CREDIT'
  FROM simo_prod.mysql_cdc_sync.wa_invoice_credit
  WHERE source_file IS NOT NULL
  UNION ALL
  SELECT
    'mysql_cdc_sync.wa_invoice_prorated',
    CAST(source_file AS STRING),
    CAST(sheet_name AS STRING),
    CAST(imsi AS STRING),
    CAST(cycle_start_date AS STRING),
    CAST(cycle_end_date AS STRING),
    CAST(final_start_date AS STRING),
    CAST(final_end_date AS STRING),
    'PRORATED'
  FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
  WHERE source_file IS NOT NULL
)
SELECT
  source_table,
  source_file,
  sheet_name,
  COUNT(*) AS row_count,
  COUNT(DISTINCT NULLIF(TRIM(imsi), '')) AS imsi_count,
  MIN(cycle_start_date) AS min_cycle_start_raw,
  MAX(cycle_end_date) AS max_cycle_end_raw,
  MIN(final_start_date) AS min_final_start_raw,
  MAX(final_end_date) AS max_final_end_raw,
  COUNT(DISTINCT charge_type) AS charge_type_count,
  CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(charge_type))) AS charge_types_seen
FROM invoice_sources
GROUP BY source_table, source_file, sheet_name
ORDER BY source_table, source_file, sheet_name;