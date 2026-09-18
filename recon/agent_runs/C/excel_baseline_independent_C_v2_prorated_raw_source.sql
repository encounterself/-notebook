-- Batch C raw source_file evidence for prorated; source_file is not trimmed in the grouping key.
WITH b AS (
  SELECT source_file, imsi,
         TRY_CAST(NULLIF(TRIM(final_start_date), '') AS DATE) AS final_start_date,
         TRY_CAST(NULLIF(TRIM(final_end_date), '') AS DATE) AS final_end_date,
         TRY_CAST(NULLIF(TRIM(final_charge_for_usage_days), '') AS DECIMAL(28,8)) AS usage_amount,
         TRY_CAST(NULLIF(TRIM(pending_charge), '') AS DECIMAL(28,8)) AS pending_amount
  FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
)
SELECT
  'wa_invoice_prorated' AS source_table,
  source_file,
  LENGTH(source_file) AS source_file_length,
  CASE WHEN source_file = TRIM(source_file) THEN 1 ELSE 0 END AS raw_equals_trimmed,
  COUNT(*) AS record_count,
  COUNT(DISTINCT imsi) AS imsi_count,
  SUM(usage_amount) AS total_final_charge_for_usage_days,
  SUM(pending_amount) AS total_pending_charge,
  MIN(final_start_date) AS min_final_start_date,
  MAX(final_start_date) AS max_final_start_date,
  MIN(final_end_date) AS min_final_end_date,
  MAX(final_end_date) AS max_final_end_date
FROM b
GROUP BY source_file
ORDER BY source_file;
