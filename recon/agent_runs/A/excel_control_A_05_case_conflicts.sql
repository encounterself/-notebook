WITH detail_source AS (
  SELECT
    'simo_prod.mysql_cdc_sync.wa_invoice_detail' AS source_table,
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
      ELSE source_file
    END AS invoice_batch_label,
    DATE_FORMAT(TO_DATE(final_start_date), 'yyyy-MM') AS observed_start_month_row,
    final_charge AS amount_value,
    monthly_rate AS auxiliary_amount_value,
    final_start_date,
    final_end_date,
    imsi,
    charge_type,
    product_name,
    (CASE WHEN source_file LIKE '%JAN 2025%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%SEP 2025%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%OCT 2025%' AND source_file LIKE '%773,793.84%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%OCT 2025%' AND source_file LIKE '%772,765.00%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%DEC 2025%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%FEB 2026%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%MAR 2026%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%APR 2026%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%MAY 2026%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%JUNE 2026%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%JULY 2026%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%AUGUST 2026%' THEN 1 ELSE 0 END) AS when_hit_count,
    CASE WHEN source_file LIKE '%OCT 2025%' AND source_file LIKE '%773,793.84%' THEN 1 ELSE 0 END AS oct_v2_hit,
    CASE WHEN source_file LIKE '%OCT 2025%' AND source_file LIKE '%772,765.00%' THEN 1 ELSE 0 END AS oct_v1_hit
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
),
detail_grouped AS (
  SELECT
    source_table, source_file, invoice_batch_label,
    MIN(observed_start_month_row) AS observed_start_month_min,
    MAX(observed_start_month_row) AS observed_start_month_max,
    CONCAT_WS(',', SORT_ARRAY(COLLECT_SET(observed_start_month_row))) AS observed_start_month_values,
    COUNT(DISTINCT observed_start_month_row) AS observed_start_month_count,
    COUNT(*) AS record_count,
    COUNT(DISTINCT imsi) AS imsi_count,
    ROUND(SUM(amount_value), 6) AS excel_amount,
    ROUND(SUM(COALESCE(amount_value, 0D)), 6) AS recomputed_excel_amount,
    SUM(CASE WHEN amount_value IS NULL THEN 1 ELSE 0 END) AS null_amount_rows,
    ROUND(SUM(auxiliary_amount_value), 6) AS auxiliary_amount_sum,
    COUNT(DISTINCT charge_type) AS charge_type_count,
    COUNT(DISTINCT product_name) AS product_count,
    MAX(when_hit_count) AS case_when_hit_count,
    MAX(oct_v2_hit) AS oct_v2_hit,
    MAX(oct_v1_hit) AS oct_v1_hit,
    MIN(TO_DATE(final_start_date)) AS min_final_start_date,
    MAX(TO_DATE(final_start_date)) AS max_final_start_date,
    MIN(TO_DATE(final_end_date)) AS min_final_end_date,
    MAX(TO_DATE(final_end_date)) AS max_final_end_date
  FROM detail_source
  GROUP BY source_table, source_file, invoice_batch_label
),
prorated_source AS (
  SELECT
    'simo_prod.mysql_cdc_sync.wa_invoice_prorated' AS source_table,
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
      ELSE source_file
    END AS invoice_batch_label,
    DATE_FORMAT(TO_DATE(final_start_date), 'yyyy-MM') AS observed_start_month_row,
    final_charge_for_usage_days AS amount_value,
    pending_charge AS auxiliary_amount_value,
    final_start_date,
    final_end_date,
    imsi,
    CAST(NULL AS STRING) AS charge_type,
    product_name,
    (CASE WHEN source_file LIKE '%JAN 2025%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%SEP 2025%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%OCT 2025%' AND source_file LIKE '%773,793.84%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%OCT 2025%' AND source_file LIKE '%772,765.00%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%DEC 2025%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%FEB 2026%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%MAR 2026%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%APR 2026%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%MAY 2026%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%JUNE 2026%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%JULY 2026%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%AUGUST 2026%' THEN 1 ELSE 0 END) AS when_hit_count,
    CASE WHEN source_file LIKE '%OCT 2025%' AND source_file LIKE '%773,793.84%' THEN 1 ELSE 0 END AS oct_v2_hit,
    CASE WHEN source_file LIKE '%OCT 2025%' AND source_file LIKE '%772,765.00%' THEN 1 ELSE 0 END AS oct_v1_hit
  FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
),
prorated_grouped AS (
  SELECT
    source_table, source_file, invoice_batch_label,
    MIN(observed_start_month_row) AS observed_start_month_min,
    MAX(observed_start_month_row) AS observed_start_month_max,
    CONCAT_WS(',', SORT_ARRAY(COLLECT_SET(observed_start_month_row))) AS observed_start_month_values,
    COUNT(DISTINCT observed_start_month_row) AS observed_start_month_count,
    COUNT(*) AS record_count,
    COUNT(DISTINCT imsi) AS imsi_count,
    ROUND(SUM(amount_value), 6) AS excel_amount,
    ROUND(SUM(COALESCE(amount_value, 0D)), 6) AS recomputed_excel_amount,
    SUM(CASE WHEN amount_value IS NULL THEN 1 ELSE 0 END) AS null_amount_rows,
    ROUND(SUM(auxiliary_amount_value), 6) AS auxiliary_amount_sum,
    COUNT(DISTINCT charge_type) AS charge_type_count,
    COUNT(DISTINCT product_name) AS product_count,
    MAX(when_hit_count) AS case_when_hit_count,
    MAX(oct_v2_hit) AS oct_v2_hit,
    MAX(oct_v1_hit) AS oct_v1_hit,
    MIN(TO_DATE(final_start_date)) AS min_final_start_date,
    MAX(TO_DATE(final_start_date)) AS max_final_start_date,
    MIN(TO_DATE(final_end_date)) AS min_final_end_date,
    MAX(TO_DATE(final_end_date)) AS max_final_end_date
  FROM prorated_source
  GROUP BY source_table, source_file, invoice_batch_label
),
credit_source AS (
  SELECT
    'simo_prod.mysql_cdc_sync.wa_invoice_credit' AS source_table,
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
      ELSE source_file
    END AS invoice_batch_label,
    credit_owed AS amount_value,
    final_price AS auxiliary_amount_value,
    imsi,
    prod,
    cycle_start,
    cycle_end,
    (CASE WHEN source_file LIKE '%JAN 2025%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%SEP 2025%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%OCT 2025%' AND source_file LIKE '%773,793.84%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%OCT 2025%' AND source_file LIKE '%772,765.00%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%DEC 2025%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%FEB 2026%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%MAR 2026%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%APR 2026%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%MAY 2026%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%JUNE 2026%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%JULY 2026%' THEN 1 ELSE 0 END
     + CASE WHEN source_file LIKE '%AUGUST 2026%' THEN 1 ELSE 0 END) AS when_hit_count,
    CASE WHEN source_file LIKE '%OCT 2025%' AND source_file LIKE '%773,793.84%' THEN 1 ELSE 0 END AS oct_v2_hit,
    CASE WHEN source_file LIKE '%OCT 2025%' AND source_file LIKE '%772,765.00%' THEN 1 ELSE 0 END AS oct_v1_hit
  FROM simo_prod.mysql_cdc_sync.wa_invoice_credit
),
credit_grouped AS (
  SELECT
    source_table, source_file, invoice_batch_label,
    CAST(NULL AS STRING) AS observed_start_month_min,
    CAST(NULL AS STRING) AS observed_start_month_max,
    CAST(NULL AS STRING) AS observed_start_month_values,
    CAST(NULL AS BIGINT) AS observed_start_month_count,
    COUNT(*) AS record_count,
    COUNT(DISTINCT imsi) AS imsi_count,
    ROUND(SUM(amount_value), 6) AS excel_amount,
    ROUND(SUM(COALESCE(amount_value, 0D)), 6) AS recomputed_excel_amount,
    SUM(CASE WHEN amount_value IS NULL THEN 1 ELSE 0 END) AS null_amount_rows,
    ROUND(SUM(auxiliary_amount_value), 6) AS auxiliary_amount_sum,
    CAST(NULL AS BIGINT) AS charge_type_count,
    COUNT(DISTINCT prod) AS product_count,
    MAX(when_hit_count) AS case_when_hit_count,
    MAX(oct_v2_hit) AS oct_v2_hit,
    MAX(oct_v1_hit) AS oct_v1_hit,
    CAST(NULL AS DATE) AS min_final_start_date,
    CAST(NULL AS DATE) AS max_final_start_date,
    CAST(NULL AS DATE) AS min_final_end_date,
    CAST(NULL AS DATE) AS max_final_end_date
  FROM credit_source
  GROUP BY source_table, source_file, invoice_batch_label
),
all_source_groups AS (
  SELECT * FROM detail_grouped
  UNION ALL SELECT * FROM prorated_grouped
  UNION ALL SELECT * FROM credit_grouped
)
SELECT
  source_table,
  source_file,
  invoice_batch_label,
  observed_start_month_min,
  observed_start_month_max,
  observed_start_month_values,
  observed_start_month_count,
  record_count,
  imsi_count,
  excel_amount,
  recomputed_excel_amount,
  ROUND(recomputed_excel_amount - excel_amount, 6) AS amount_recompute_diff,
  null_amount_rows,
  auxiliary_amount_sum,
  charge_type_count,
  product_count,
  case_when_hit_count,
  oct_v2_hit,
  oct_v1_hit,
  CASE
    WHEN case_when_hit_count = 0 THEN 'ELSE_SOURCE_FILE'
    WHEN case_when_hit_count > 1 THEN 'MULTIPLE_WHEN_MATCH'
    WHEN oct_v2_hit + oct_v1_hit = 2 THEN 'OCT_BOTH_AMOUNT_FRAGMENTS'
    WHEN oct_v2_hit + oct_v1_hit = 1 THEN 'OCT_ONE_AMOUNT_FRAGMENT'
    ELSE 'ONE_CASE_MATCH'
  END AS case_status,
  CASE
    WHEN source_table LIKE '%wa_invoice_credit' THEN 'NOT_APPLICABLE_NO_FINAL_START_DATE'
    WHEN observed_start_month_count IS NULL THEN 'MISSING_FINAL_START_DATE'
    WHEN observed_start_month_count = 1
         AND observed_start_month_min = CASE WHEN invoice_batch_label LIKE '2025-10%' THEN '2025-10' ELSE invoice_batch_label END
      THEN 'FINAL_START_MONTH_MATCHES_CANDIDATE'
    ELSE 'FINAL_START_MONTH_CONFLICT'
  END AS final_start_vs_candidate_status,
  min_final_start_date,
  max_final_start_date,
  min_final_end_date,
  max_final_end_date,
  CASE WHEN ROUND(recomputed_excel_amount, 6) = ROUND(excel_amount, 6)
       THEN 'ROW_SUM_RECOMPUTES' ELSE 'ROW_SUM_DIFFERS' END AS amount_recompute_status
FROM all_source_groups
ORDER BY source_table, source_file
