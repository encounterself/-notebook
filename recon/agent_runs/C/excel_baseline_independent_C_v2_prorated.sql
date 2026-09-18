SELECT
  'simo_prod.mysql_cdc_sync.wa_invoice_prorated' AS source_table,
  CAST(source_file AS STRING) AS source_file,
  CAST(NULL AS STRING) AS charge_type,
  CAST(sheet_name AS STRING) AS classification_value,
  'charge_type column absent; final_charge_for_usage_days/pending_charge are prorated measures' AS semantic_note,
  COUNT(*) AS record_count,
  COUNT(DISTINCT CAST(imsi AS STRING)) AS imsi_count,
  ROUND(SUM(TRY_CAST(final_charge_for_usage_days AS DOUBLE)), 6) AS total_final_charge_for_usage_days,
  ROUND(SUM(TRY_CAST(pending_charge AS DOUBLE)), 6) AS total_pending_charge,
  ROUND(SUM(TRY_CAST(monthly_rate AS DOUBLE)), 6) AS total_monthly_rate_sum,
  MIN(TRY_CAST(final_start_date AS DATE)) AS min_final_start_date,
  MAX(TRY_CAST(final_start_date AS DATE)) AS max_final_start_date,
  MIN(TRY_CAST(final_end_date AS DATE)) AS min_final_end_date,
  MAX(TRY_CAST(final_end_date AS DATE)) AS max_final_end_date,
  COUNT(DISTINCT CAST(product_name AS STRING)) AS product_count
FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
GROUP BY CAST(source_file AS STRING), CAST(sheet_name AS STRING)
ORDER BY source_file, classification_value