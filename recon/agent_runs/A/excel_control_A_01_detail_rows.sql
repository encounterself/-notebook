WITH mapped AS (
  SELECT
    'wa_invoice_detail' AS source_table,
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
    imsi, charge_type,
    TRY_CAST(final_days AS DOUBLE) AS final_days,
    TRY_CAST(monthly_rate AS DOUBLE) AS monthly_rate,
    TRY_CAST(final_charge AS DOUBLE) AS final_charge
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
), grouped AS (
  SELECT
    source_table, source_file, invoice_batch_label,
    CASE WHEN COUNT(DISTINCT observed_start_month)=1 THEN MIN(observed_start_month) ELSE 'MULTIPLE' END AS observed_start_month,
    CONCAT_WS(',',SORT_ARRAY(COLLECT_SET(observed_start_month))) AS observed_start_month_values,
    imsi, charge_type,
    SUM(final_days) AS excel_days,
    CONCAT_WS(',',SORT_ARRAY(COLLECT_SET(CAST(final_days AS STRING)))) AS excel_days_values,
    CASE WHEN COUNT(DISTINCT monthly_rate)=1 THEN MIN(monthly_rate) ELSE CAST(NULL AS DOUBLE) END AS excel_price,
    CONCAT_WS(',',SORT_ARRAY(COLLECT_SET(CAST(monthly_rate AS STRING)))) AS excel_price_values,
    SUM(final_charge) AS excel_amount,
    COUNT(*) AS source_row_count,
    'detail.final_charge; official invoice-detail candidate amount' AS amount_semantics,
    'final_days' AS excel_days_field,
    'monthly_rate' AS excel_price_field
  FROM mapped
  GROUP BY source_table, source_file, invoice_batch_label, imsi, charge_type
)
SELECT * FROM grouped
ORDER BY source_file, imsi, charge_type