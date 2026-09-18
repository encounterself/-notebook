WITH detail_files AS (
  SELECT
    'simo_prod.mysql_cdc_sync.wa_invoice_detail' AS platform_source_table,
    source_file AS platform_source_file,
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
    DATE_FORMAT(MIN(TO_DATE(final_start_date)), 'yyyy-MM') AS observed_start_month,
    CAST(NULL AS STRING) AS observed_cycle_start_month,
    CAST(NULL AS STRING) AS observed_cycle_end_month,
    COUNT(*) AS platform_record_count,
    COUNT(DISTINCT imsi) AS platform_imsi_count,
    SUM(final_charge) AS platform_amount,
    SUM(monthly_rate) AS platform_monthly_rate_sum,
    'final_charge' AS platform_amount_semantics
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  GROUP BY source_file
),
prorated_files AS (
  SELECT
    'simo_prod.mysql_cdc_sync.wa_invoice_prorated' AS platform_source_table,
    source_file AS platform_source_file,
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
    DATE_FORMAT(MIN(TO_DATE(final_start_date)), 'yyyy-MM') AS observed_start_month,
    CAST(NULL AS STRING) AS observed_cycle_start_month,
    CAST(NULL AS STRING) AS observed_cycle_end_month,
    COUNT(*) AS platform_record_count,
    COUNT(DISTINCT imsi) AS platform_imsi_count,
    SUM(final_charge_for_usage_days) AS platform_amount,
    SUM(monthly_rate) AS platform_monthly_rate_sum,
    'final_charge_for_usage_days' AS platform_amount_semantics
  FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
  GROUP BY source_file
),
credit_files AS (
  SELECT
    'simo_prod.mysql_cdc_sync.wa_invoice_credit' AS platform_source_table,
    source_file AS platform_source_file,
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
    CAST(NULL AS STRING) AS observed_start_month,
    DATE_FORMAT(MIN(TO_DATE(cycle_start)), 'yyyy-MM') AS observed_cycle_start_month,
    DATE_FORMAT(MAX(TO_DATE(cycle_end)), 'yyyy-MM') AS observed_cycle_end_month,
    COUNT(*) AS platform_record_count,
    COUNT(DISTINCT imsi) AS platform_imsi_count,
    SUM(credit_owed) AS platform_amount,
    SUM(final_price) AS platform_monthly_rate_sum,
    'credit_owed' AS platform_amount_semantics
  FROM simo_prod.mysql_cdc_sync.wa_invoice_credit
  GROUP BY source_file
)
SELECT * FROM detail_files
UNION ALL
SELECT * FROM prorated_files
UNION ALL
SELECT * FROM credit_files
ORDER BY platform_source_table, platform_source_file
