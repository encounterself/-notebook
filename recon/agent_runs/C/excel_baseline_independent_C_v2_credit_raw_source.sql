-- Batch C raw source_file evidence for credit; source_file is not trimmed in the grouping key.
WITH b AS (
  SELECT source_file, imsi,
         TRY_CAST(NULLIF(TRIM(cycle_start), '') AS DATE) AS cycle_start,
         TRY_CAST(NULLIF(TRIM(cycle_end), '') AS DATE) AS cycle_end,
         TRY_CAST(NULLIF(TRIM(credit_owed), '') AS DECIMAL(28,8)) AS credit_owed,
         TRY_CAST(NULLIF(TRIM(final_price), '') AS DECIMAL(28,8)) AS final_price
  FROM simo_prod.mysql_cdc_sync.wa_invoice_credit
)
SELECT
  'wa_invoice_credit' AS source_table,
  source_file,
  LENGTH(source_file) AS source_file_length,
  CASE WHEN source_file = TRIM(source_file) THEN 1 ELSE 0 END AS raw_equals_trimmed,
  COUNT(*) AS record_count,
  COUNT(DISTINCT imsi) AS imsi_count,
  SUM(credit_owed) AS total_credit_owed,
  SUM(final_price) AS total_final_price,
  MIN(cycle_start) AS min_cycle_start,
  MAX(cycle_start) AS max_cycle_start,
  MIN(cycle_end) AS min_cycle_end,
  MAX(cycle_end) AS max_cycle_end
FROM b
GROUP BY source_file
ORDER BY source_file;
