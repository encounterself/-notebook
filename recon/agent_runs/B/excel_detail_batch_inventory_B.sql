WITH detail_raw AS (
  SELECT
    TRIM(CAST(imsi AS STRING)) AS imsi,
    TRIM(CAST(source_file AS STRING)) AS source_file,
    TRY_CAST(final_start_date AS DATE) AS final_start_date,
    TRY_CAST(final_end_date AS DATE) AS final_end_date,
    TRY_CAST(final_days AS DECIMAL(38,12)) AS excel_days,
    TRY_CAST(monthly_rate AS DECIMAL(38,12)) AS excel_price,
    TRY_CAST(final_charge AS DECIMAL(38,12)) AS excel_amount,
    charge_type,
    product_name
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE LOWER(CAST(source_file AS STRING)) LIKE '%dec 2025%'
     OR LOWER(CAST(source_file AS STRING)) LIKE '%jan 2026%'
     OR LOWER(CAST(source_file AS STRING)) LIKE '%feb 2026%'
), labeled AS (
  SELECT *,
    CASE
      WHEN source_file LIKE '%JAN 2025%' THEN '2025-01'
      WHEN source_file LIKE '%SEP 2025%' THEN '2025-09'
      WHEN source_file LIKE '%OCT 2025%' AND source_file LIKE '%773,793.84%' THEN '2025-10 (v2)'
      WHEN source_file LIKE '%OCT 2025%' AND source_file LIKE '%772,765.00%' THEN '2025-10 (v1)'
      WHEN source_file LIKE '%DEC 2025%' THEN '2025-12'
      WHEN source_file LIKE '%FEB 2026%' THEN '2026-02'
      WHEN source_file LIKE '%MAR 2026%' THEN '2026-03'
      WHEN source_file LIKE '%APR 2026%' THEN '2026-04'
      WHEN source_file LIKE '%MAY 2026%' THEN '2026-05'
      WHEN source_file LIKE '%JUNE 2026%' THEN '2026-06'
      WHEN source_file LIKE '%JULY 2026%' THEN '2026-07'
      WHEN source_file LIKE '%AUGUST 2026%' THEN '2026-08'
      ELSE source_file
    END AS invoice_batch_label,
    DATE_FORMAT(final_start_date,'yyyy-MM') AS observed_start_month
  FROM detail_raw
)
SELECT
  source_file,
  invoice_batch_label,
  observed_start_month,
  COUNT(*) AS record_count,
  COUNT(DISTINCT imsi) AS imsi_count,
  SUM(excel_amount) AS total_excel_amount,
  SUM(excel_price) AS total_excel_price,
  COUNT(DISTINCT charge_type) AS charge_type_count,
  COUNT(DISTINCT product_name) AS product_name_count,
  MIN(final_start_date) AS min_final_start_date,
  MAX(final_start_date) AS max_final_start_date,
  MIN(final_end_date) AS min_final_end_date,
  MAX(final_end_date) AS max_final_end_date,
  SUM(CASE WHEN observed_start_month IS NOT NULL AND observed_start_month <> invoice_batch_label THEN 1 ELSE 0 END) AS start_month_label_conflict_rows
FROM labeled
GROUP BY source_file, invoice_batch_label, observed_start_month
ORDER BY source_file, observed_start_month;