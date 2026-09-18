WITH detail_source AS (
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
    CASE WHEN COUNT(DISTINCT DATE_FORMAT(TRY_CAST(final_start_date AS DATE),'yyyy-MM'))=1 THEN MIN(DATE_FORMAT(TRY_CAST(final_start_date AS DATE),'yyyy-MM')) ELSE 'MULTIPLE' END AS observed_start_month,
    CONCAT_WS(',',SORT_ARRAY(COLLECT_SET(DATE_FORMAT(TRY_CAST(final_start_date AS DATE),'yyyy-MM')))) AS observed_start_month_values,
    CAST(NULL AS STRING) AS credit_cycle_start_month,
    CAST(NULL AS STRING) AS credit_cycle_end_month,
    COUNT(*) AS record_count,
    COUNT(DISTINCT imsi) AS imsi_count,
    ROUND(SUM(TRY_CAST(final_charge AS DOUBLE)),6) AS excel_amount,
    ROUND(SUM(TRY_CAST(monthly_rate AS DOUBLE)),6) AS total_monthly_rate_sum,
    COUNT(DISTINCT charge_type) AS charge_type_count,
    COUNT(DISTINCT product_name) AS product_count,
    'detail.final_charge; candidate Excel invoice truth' AS amount_semantics
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  GROUP BY source_file, invoice_batch_label
), prorated_source AS (
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
    CASE WHEN COUNT(DISTINCT DATE_FORMAT(TRY_CAST(final_start_date AS DATE),'yyyy-MM'))=1 THEN MIN(DATE_FORMAT(TRY_CAST(final_start_date AS DATE),'yyyy-MM')) ELSE 'MULTIPLE' END AS observed_start_month,
    CONCAT_WS(',',SORT_ARRAY(COLLECT_SET(DATE_FORMAT(TRY_CAST(final_start_date AS DATE),'yyyy-MM')))) AS observed_start_month_values,
    CAST(NULL AS STRING) AS credit_cycle_start_month,
    CAST(NULL AS STRING) AS credit_cycle_end_month,
    COUNT(*) AS record_count,
    COUNT(DISTINCT imsi) AS imsi_count,
    ROUND(SUM(TRY_CAST(final_charge_for_usage_days AS DOUBLE)),6) AS excel_amount,
    CAST(NULL AS DOUBLE) AS total_monthly_rate_sum,
    CAST(NULL AS BIGINT) AS charge_type_count,
    COUNT(DISTINCT product_name) AS product_count,
    'prorated.final_charge_for_usage_days; auxiliary prorated amount, not invoice truth' AS amount_semantics
  FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
  GROUP BY source_file, invoice_batch_label
), credit_source AS (
  SELECT
    'wa_invoice_credit' AS source_table,
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
    CAST(NULL AS STRING) AS observed_start_month,
    CAST(NULL AS STRING) AS observed_start_month_values,
    CONCAT_WS(',',SORT_ARRAY(COLLECT_SET(DATE_FORMAT(TRY_CAST(cycle_start AS DATE),'yyyy-MM')))) AS credit_cycle_start_month,
    CONCAT_WS(',',SORT_ARRAY(COLLECT_SET(DATE_FORMAT(TRY_CAST(cycle_end AS DATE),'yyyy-MM')))) AS credit_cycle_end_month,
    COUNT(*) AS record_count,
    COUNT(DISTINCT imsi) AS imsi_count,
    ROUND(SUM(TRY_CAST(credit_owed AS DOUBLE)),6) AS excel_amount,
    CAST(NULL AS DOUBLE) AS total_monthly_rate_sum,
    CAST(NULL AS BIGINT) AS charge_type_count,
    COUNT(DISTINCT COALESCE(prod,replacement_product)) AS product_count,
    'credit.credit_owed; auxiliary credit amount, no observed_start_month' AS amount_semantics
  FROM simo_prod.mysql_cdc_sync.wa_invoice_credit
  GROUP BY source_file, invoice_batch_label
)
SELECT * FROM detail_source
UNION ALL SELECT * FROM prorated_source
UNION ALL SELECT * FROM credit_source
ORDER BY source_table, source_file