WITH e AS (
  SELECT
    trim(source_file) AS source_file,
    trim(imsi) AS imsi,
    trim(charge_type) AS charge_type,
    to_date(trim(final_start_date)) AS final_start,
    to_date(trim(final_end_date)) AS final_end,
    try_cast(nullif(trim(final_days), '') AS DECIMAL(38,10)) AS excel_days,
    try_cast(nullif(trim(monthly_rate), '') AS DECIMAL(38,10)) AS excel_price,
    try_cast(nullif(trim(final_charge), '') AS DECIMAL(38,10)) AS excel_amount,
    trim(product_name) AS excel_product_name,
    trim(note) AS note
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE trim(source_file) LIKE '%MAR 2026%'
     OR trim(source_file) LIKE '%APR 2026%'
     OR trim(source_file) LIKE '%MAY 2026%'
)
SELECT
  source_file,
  charge_type,
  COUNT(*) AS record_count,
  COUNT(DISTINCT imsi) AS imsi_count,
  SUM(excel_amount) AS excel_total,
  SUM(excel_days) AS excel_days_sum,
  SUM(excel_price) AS excel_price_sum,
  MIN(final_start) AS min_final_start,
  MAX(final_start) AS max_final_start,
  MIN(final_end) AS min_final_end,
  MAX(final_end) AS max_final_end,
  COUNT(DISTINCT excel_price) AS distinct_excel_prices,
  COUNT(DISTINCT excel_days) AS distinct_excel_days
FROM e
GROUP BY source_file, charge_type
ORDER BY source_file, charge_type