WITH official_detail AS (
  SELECT
    CAST(source_file AS STRING) AS excel_source_file,
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
      ELSE CAST(source_file AS STRING)
    END AS official_excel_billing_month,
    CAST(imsi AS STRING) AS imsi,
    TRY_CAST(final_charge AS DOUBLE) AS final_charge,
    TRY_CAST(monthly_rate AS DOUBLE) AS monthly_rate,
    CAST(charge_type AS STRING) AS charge_type,
    CAST(product_name AS STRING) AS product_name
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
)
SELECT
  excel_source_file,
  official_excel_billing_month,
  COUNT(*) AS record_count,
  COUNT(DISTINCT imsi) AS imsi_count,
  ROUND(SUM(final_charge), 6) AS total_final_charge,
  ROUND(SUM(monthly_rate), 6) AS total_monthly_rate_sum,
  COUNT(DISTINCT charge_type) AS charge_type_count,
  COUNT(DISTINCT product_name) AS product_count
FROM official_detail
GROUP BY excel_source_file, official_excel_billing_month
ORDER BY excel_source_file, official_excel_billing_month