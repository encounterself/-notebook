SELECT
  CAST(source_file AS STRING) AS source_file,
  COUNT(*) AS record_count,
  COUNT(DISTINCT CAST(imsi AS STRING)) AS imsi_count,
  ROUND(SUM(TRY_CAST(final_charge AS DOUBLE)), 6) AS total_final_charge,
  MIN(TRY_CAST(final_start_date AS DATE)) AS min_final_start_date,
  MAX(TRY_CAST(final_start_date AS DATE)) AS max_final_start_date,
  MIN(TRY_CAST(final_end_date AS DATE)) AS min_final_end_date,
  MAX(TRY_CAST(final_end_date AS DATE)) AS max_final_end_date
FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
GROUP BY CAST(source_file AS STRING)
ORDER BY source_file