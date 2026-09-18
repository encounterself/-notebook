WITH mapped AS (
  SELECT
    'wa_invoice_prorated' AS source_table,
    source_file,
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
      ELSE source_file END AS invoice_batch_label,
    DATE_FORMAT(TRY_CAST(final_start_date AS DATE),'yyyy-MM') AS observed_start_month,
    imsi,
    TRY_CAST(active_days AS DOUBLE) AS excel_days,
    TRY_CAST(monthly_rate AS DOUBLE) AS excel_price,
    TRY_CAST(final_charge_for_usage_days AS DOUBLE) AS excel_amount,
    TRY_CAST(pending_charge AS DOUBLE) AS pending_charge
  FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
)
SELECT
  source_table, source_file, invoice_batch_label, observed_start_month,
  imsi, CAST(NULL AS STRING) AS charge_type,
  SUM(excel_days) AS excel_days,
  CONCAT_WS(',',SORT_ARRAY(COLLECT_SET(CAST(excel_days AS STRING)))) AS excel_days_values,
  CASE WHEN COUNT(DISTINCT excel_price)=1 THEN MIN(excel_price) ELSE CAST(NULL AS DOUBLE) END AS excel_price,
  CONCAT_WS(',',SORT_ARRAY(COLLECT_SET(CAST(excel_price AS STRING)))) AS excel_price_values,
  SUM(excel_amount) AS excel_amount,
  COUNT(*) AS source_row_count,
  'prorated.final_charge_for_usage_days; auxiliary prorated amount, not official detail invoice truth' AS amount_semantics,
  'active_days' AS excel_days_field,
  'monthly_rate' AS excel_price_field,
  SUM(pending_charge) AS pending_charge_diagnostic
FROM mapped
GROUP BY source_table, source_file, invoice_batch_label, observed_start_month, imsi
ORDER BY source_file, imsi