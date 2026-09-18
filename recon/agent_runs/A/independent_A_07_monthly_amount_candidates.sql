WITH detail_mapped AS (
  SELECT
    source_file,
    imsi,
    TRY_CAST(final_charge AS DOUBLE) AS final_charge,
    TRY_CAST(monthly_rate AS DOUBLE) AS monthly_rate,
    charge_type,
    product_name,
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
    END AS billing_month
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
), credit_mapped AS (
  SELECT
    source_file,
    imsi,
    TRY_CAST(credit_owed AS DOUBLE) AS credit_owed,
    TRY_CAST(final_price AS DOUBLE) AS final_price,
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
    END AS billing_month
  FROM simo_prod.mysql_cdc_sync.wa_invoice_credit
), prorated_mapped AS (
  SELECT
    source_file,
    imsi,
    TRY_CAST(final_charge_for_usage_days AS DOUBLE) AS final_charge_for_usage_days,
    TRY_CAST(pending_charge AS DOUBLE) AS pending_charge,
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
    END AS billing_month
  FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
), detail_month AS (
  SELECT
    'DETAIL_ONLY_CANDIDATE' AS fact_role,
    'wa_invoice_detail' AS table_name,
    billing_month,
    COUNT(DISTINCT source_file) AS source_file_count,
    CONCAT_WS(' || ',SORT_ARRAY(COLLECT_SET(CAST(source_file AS STRING)))) AS source_files,
    COUNT(*) AS record_count,
    COUNT(DISTINCT imsi) AS imsi_count,
    ROUND(SUM(final_charge),6) AS total_amount,
    'final_charge' AS amount_field,
    ROUND(SUM(monthly_rate),6) AS auxiliary_amount,
    'monthly_rate' AS auxiliary_amount_field,
    COUNT(DISTINCT charge_type) AS charge_type_count,
    COUNT(DISTINCT product_name) AS product_count,
    'Only detail is a candidate official Excel billing target; no credit/prorated union.' AS target_status
  FROM detail_mapped
  GROUP BY billing_month
), credit_month AS (
  SELECT
    'CREDIT_SEPARATE_AUXILIARY' AS fact_role,
    'wa_invoice_credit' AS table_name,
    billing_month,
    COUNT(DISTINCT source_file) AS source_file_count,
    CONCAT_WS(' || ',SORT_ARRAY(COLLECT_SET(CAST(source_file AS STRING)))) AS source_files,
    COUNT(*) AS record_count,
    COUNT(DISTINCT imsi) AS imsi_count,
    ROUND(SUM(credit_owed),6) AS total_amount,
    'credit_owed' AS amount_field,
    ROUND(SUM(final_price),6) AS auxiliary_amount,
    'final_price' AS auxiliary_amount_field,
    CAST(NULL AS BIGINT) AS charge_type_count,
    CAST(NULL AS BIGINT) AS product_count,
    'Separate credit fact; negative sign preserved; not part of official detail target.' AS target_status
  FROM credit_mapped
  GROUP BY billing_month
), prorated_month AS (
  SELECT
    'PRORATED_SEPARATE_AUXILIARY' AS fact_role,
    'wa_invoice_prorated' AS table_name,
    billing_month,
    COUNT(DISTINCT source_file) AS source_file_count,
    CONCAT_WS(' || ',SORT_ARRAY(COLLECT_SET(CAST(source_file AS STRING)))) AS source_files,
    COUNT(*) AS record_count,
    COUNT(DISTINCT imsi) AS imsi_count,
    ROUND(SUM(final_charge_for_usage_days),6) AS total_amount,
    'final_charge_for_usage_days' AS amount_field,
    ROUND(SUM(pending_charge),6) AS auxiliary_amount,
    'pending_charge' AS auxiliary_amount_field,
    CAST(NULL AS BIGINT) AS charge_type_count,
    CAST(NULL AS BIGINT) AS product_count,
    'Separate prorated fact; overlap exists; not part of official detail target.' AS target_status
  FROM prorated_mapped
  GROUP BY billing_month
), expected_batch AS (
  SELECT '2025-09' AS billing_month
  UNION ALL SELECT '2025-10 (v1)'
  UNION ALL SELECT '2025-10 (v2)'
  UNION ALL SELECT '2025-11'
), expected_status AS (
  SELECT
    'BATCH_A_EXPECTED_MONTH' AS fact_role,
    'official_detail_presence_check' AS table_name,
    e.billing_month,
    COALESCE(d.source_file_count,0) AS source_file_count,
    COALESCE(d.source_files,'') AS source_files,
    COALESCE(d.record_count,0) AS record_count,
    COALESCE(d.imsi_count,0) AS imsi_count,
    COALESCE(d.total_amount,0D) AS total_amount,
    'final_charge' AS amount_field,
    COALESCE(d.auxiliary_amount,0D) AS auxiliary_amount,
    'monthly_rate' AS auxiliary_amount_field,
    COALESCE(d.charge_type_count,0) AS charge_type_count,
    COALESCE(d.product_count,0) AS product_count,
    CASE WHEN d.billing_month IS NULL THEN 'NO_DETAIL_SOURCE_MATCH' ELSE 'DETAIL_SOURCE_PRESENT' END AS target_status
  FROM expected_batch e LEFT JOIN detail_month d ON d.billing_month=e.billing_month
)
SELECT * FROM detail_month
UNION ALL SELECT * FROM credit_month
UNION ALL SELECT * FROM prorated_month
UNION ALL SELECT * FROM expected_status
ORDER BY billing_month, fact_role