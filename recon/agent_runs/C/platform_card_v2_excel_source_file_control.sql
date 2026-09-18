WITH detail AS (
  SELECT
    trim(source_file) AS source_file,
    CASE
      WHEN trim(source_file) LIKE '%JAN 2025%' THEN '2025-01'
      WHEN trim(source_file) LIKE '%SEP 2025%' THEN '2025-09'
      WHEN trim(source_file) LIKE '%OCT 2025%' AND trim(source_file) LIKE '%773,793.84%' THEN '2025-10 (v2)'
      WHEN trim(source_file) LIKE '%OCT 2025%' AND trim(source_file) LIKE '%772,765.00%' THEN '2025-10 (v1)'
      WHEN trim(source_file) LIKE '%DEC 2025%' THEN '2025-12'
      WHEN trim(source_file) LIKE '%FEB 2026%' THEN '2026-02'
      WHEN trim(source_file) LIKE '%MAR 2026%' THEN '2026-03'
      WHEN trim(source_file) LIKE '%APR 2026%' THEN '2026-04'
      WHEN trim(source_file) LIKE '%MAY 2026%' THEN '2026-05'
      WHEN trim(source_file) LIKE '%JUNE 2026%' THEN '2026-06'
      WHEN trim(source_file) LIKE '%JULY 2026%' THEN '2026-07'
      WHEN trim(source_file) LIKE '%AUGUST 2026%' THEN '2026-08'
      ELSE trim(source_file)
    END AS invoice_batch_label,
    trim(imsi) AS imsi,
    to_date(trim(final_start_date)) AS final_start_date,
    to_date(trim(final_end_date)) AS final_end_date,
    try_cast(nullif(trim(final_charge), '') AS DECIMAL(38,10)) AS final_charge,
    try_cast(nullif(trim(monthly_rate), '') AS DECIMAL(38,10)) AS monthly_rate,
    trim(charge_type) AS charge_type,
    trim(product_name) AS product_name
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
)
SELECT
  source_file,
  invoice_batch_label,
  count(*) AS record_count,
  count(DISTINCT imsi) AS distinct_imsi_count,
  sum(final_charge) AS total_final_charge,
  sum(monthly_rate) AS total_monthly_rate_sum,
  count(DISTINCT charge_type) AS charge_type_count,
  count(DISTINCT product_name) AS product_count,
  min(final_start_date) AS min_final_start_date,
  max(final_start_date) AS max_final_start_date,
  min(final_end_date) AS min_final_end_date,
  max(final_end_date) AS max_final_end_date,
  count(DISTINCT date_format(final_start_date, 'yyyy-MM')) AS observed_start_month_count,
  min(date_format(final_start_date, 'yyyy-MM')) AS observed_start_month_min,
  max(date_format(final_start_date, 'yyyy-MM')) AS observed_start_month_max
FROM detail
GROUP BY source_file, invoice_batch_label
ORDER BY source_file