SELECT
  'simo_prod.mysql_cdc_sync.wa_invoice_credit' AS source_table,
  CAST(source_file AS STRING) AS source_file,
  CAST(NULL AS STRING) AS charge_type,
  CAST(prod AS STRING) AS classification_value,
  'charge_type column absent; credit_owed/final_price are credit measures' AS semantic_note,
  COUNT(*) AS record_count,
  COUNT(DISTINCT CAST(imsi AS STRING)) AS imsi_count,
  ROUND(SUM(TRY_CAST(credit_owed AS DOUBLE)), 6) AS total_credit_owed,
  ROUND(SUM(TRY_CAST(final_price AS DOUBLE)), 6) AS total_final_price,
  ROUND(SUM(TRY_CAST(price AS DOUBLE)), 6) AS total_price,
  MIN(TRY_CAST(cycle_start AS DATE)) AS min_cycle_start,
  MAX(TRY_CAST(cycle_start AS DATE)) AS max_cycle_start,
  MIN(TRY_CAST(cycle_end AS DATE)) AS min_cycle_end,
  MAX(TRY_CAST(cycle_end AS DATE)) AS max_cycle_end,
  MIN(TRY_CAST(date_line_went_down AS DATE)) AS min_line_down_date,
  MAX(TRY_CAST(date_line_went_down AS DATE)) AS max_line_down_date,
  COUNT(DISTINCT CAST(prod AS STRING)) AS product_count
FROM simo_prod.mysql_cdc_sync.wa_invoice_credit
GROUP BY CAST(source_file AS STRING), CAST(prod AS STRING)
ORDER BY source_file, classification_value