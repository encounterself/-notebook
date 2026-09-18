SELECT
  'simo_prod.mysql_cdc_sync.wa_invoice_detail' AS source_table,
  CAST(source_file AS STRING) AS source_file,
  CAST(charge_type AS STRING) AS charge_type,
  COUNT(*) AS record_count,
  COUNT(DISTINCT CAST(imsi AS STRING)) AS imsi_count,
  ROUND(SUM(TRY_CAST(final_charge AS DOUBLE)), 6) AS total_final_charge,
  ROUND(SUM(TRY_CAST(monthly_rate AS DOUBLE)), 6) AS total_monthly_rate_sum,
  MIN(TRY_CAST(final_start_date AS DATE)) AS min_final_start_date,
  MAX(TRY_CAST(final_start_date AS DATE)) AS max_final_start_date,
  MIN(TRY_CAST(final_end_date AS DATE)) AS min_final_end_date,
  MAX(TRY_CAST(final_end_date AS DATE)) AS max_final_end_date,
  COUNT(DISTINCT CAST(product_name AS STRING)) AS product_count
FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
GROUP BY CAST(source_file AS STRING), CAST(charge_type AS STRING)
ORDER BY source_file, charge_type