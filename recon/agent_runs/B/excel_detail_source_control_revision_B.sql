SELECT
  CAST(source_file AS STRING) AS source_file,
  COUNT(*) AS record_count,
  COUNT(DISTINCT TRIM(CAST(imsi AS STRING))) AS distinct_imsi_count,
  SUM(TRY_CAST(final_charge AS DECIMAL(38,12))) AS detail_total_final_charge,
  SUM(TRY_CAST(monthly_rate AS DECIMAL(38,12))) AS detail_total_monthly_rate,
  MIN(TRY_CAST(final_start_date AS DATE)) AS min_final_start_date,
  MAX(TRY_CAST(final_start_date AS DATE)) AS max_final_start_date,
  MIN(TRY_CAST(final_end_date AS DATE)) AS min_final_end_date,
  MAX(TRY_CAST(final_end_date AS DATE)) AS max_final_end_date
FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
WHERE CAST(source_file AS STRING) LIKE '%OCT 2025%'
   OR CAST(source_file AS STRING) LIKE '%DEC 2025%'
   OR CAST(source_file AS STRING) LIKE '%JAN 2026%'
   OR CAST(source_file AS STRING) LIKE '%FEB 2026%'
GROUP BY CAST(source_file AS STRING)
ORDER BY source_file;