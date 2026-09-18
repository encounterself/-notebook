WITH detail_mapped AS (
  SELECT
    'wa_invoice_detail' AS table_name,
    source_file,
    imsi,
    TRY_CAST(final_start_date AS DATE) AS final_start_date,
    TRY_CAST(final_end_date AS DATE) AS final_end_date,
    TRY_CAST(final_charge AS DOUBLE) AS amount_value,
    TRY_CAST(monthly_rate AS DOUBLE) AS auxiliary_amount_value,
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
    END AS billing_month,
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
    CASE WHEN source_file LIKE '%OCT 2025%' AND source_file LIKE '%773,793.84%' THEN 1 ELSE 0 END AS oct_773793_hit,
    CASE WHEN source_file LIKE '%OCT 2025%' AND source_file LIKE '%772,765.00%' THEN 1 ELSE 0 END AS oct_772765_hit
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
), credit_mapped AS (
  SELECT
    'wa_invoice_credit' AS table_name,
    source_file,
    imsi,
    CAST(NULL AS DATE) AS final_start_date,
    CAST(NULL AS DATE) AS final_end_date,
    TRY_CAST(credit_owed AS DOUBLE) AS amount_value,
    TRY_CAST(final_price AS DOUBLE) AS auxiliary_amount_value,
    CAST(NULL AS STRING) AS charge_type,
    COALESCE(prod, replacement_product) AS product_name,
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
    END AS billing_month,
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
    CASE WHEN source_file LIKE '%OCT 2025%' AND source_file LIKE '%773,793.84%' THEN 1 ELSE 0 END AS oct_773793_hit,
    CASE WHEN source_file LIKE '%OCT 2025%' AND source_file LIKE '%772,765.00%' THEN 1 ELSE 0 END AS oct_772765_hit
  FROM simo_prod.mysql_cdc_sync.wa_invoice_credit
), prorated_mapped AS (
  SELECT
    'wa_invoice_prorated' AS table_name,
    source_file,
    imsi,
    TRY_CAST(final_start_date AS DATE) AS final_start_date,
    TRY_CAST(final_end_date AS DATE) AS final_end_date,
    TRY_CAST(final_charge_for_usage_days AS DOUBLE) AS amount_value,
    TRY_CAST(pending_charge AS DOUBLE) AS auxiliary_amount_value,
    CAST(NULL AS STRING) AS charge_type,
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
    END AS billing_month,
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
    CASE WHEN source_file LIKE '%OCT 2025%' AND source_file LIKE '%773,793.84%' THEN 1 ELSE 0 END AS oct_773793_hit,
    CASE WHEN source_file LIKE '%OCT 2025%' AND source_file LIKE '%772,765.00%' THEN 1 ELSE 0 END AS oct_772765_hit
  FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
), all_mapped AS (
  SELECT * FROM detail_mapped
  UNION ALL SELECT * FROM credit_mapped
  UNION ALL SELECT * FROM prorated_mapped
), source_check AS (
  SELECT
    table_name,
    source_file,
    billing_month,
    COUNT(*) AS record_count,
    COUNT(DISTINCT imsi) AS imsi_count,
    ROUND(SUM(amount_value),6) AS total_amount,
    ROUND(SUM(COALESCE(amount_value,0D)),6) AS recomputed_total_amount,
    ROUND(SUM(auxiliary_amount_value),6) AS total_auxiliary_amount,
    COUNT(DISTINCT charge_type) AS charge_type_count,
    COUNT(DISTINCT product_name) AS product_count,
    CONCAT_WS(' || ',SORT_ARRAY(COLLECT_SET(CAST(charge_type AS STRING)))) AS charge_type_values,
    MIN(final_start_date) AS min_final_start_date,
    MAX(final_start_date) AS max_final_start_date,
    MIN(final_end_date) AS min_final_end_date,
    MAX(final_end_date) AS max_final_end_date,
    CONCAT_WS(',',SORT_ARRAY(COLLECT_SET(DATE_FORMAT(final_start_date,'yyyy-MM')))) AS final_start_month_values,
    MAX(when_hit_count) AS source_file_when_hit_count,
    MAX(oct_773793_hit) AS oct_773793_hit,
    MAX(oct_772765_hit) AS oct_772765_hit,
    CASE WHEN MAX(when_hit_count)=0 THEN 'ELSE_SOURCE_FILE'
         WHEN MAX(when_hit_count)>1 THEN 'MULTIPLE_WHEN_MATCH'
         WHEN MAX(oct_773793_hit)+MAX(oct_772765_hit)=2 THEN 'OCT_BOTH_AMOUNT_FRAGMENTS'
         WHEN MAX(oct_773793_hit)+MAX(oct_772765_hit)=1 THEN 'OCT_ONE_AMOUNT_FRAGMENT'
         ELSE 'ONE_CASE_MATCH' END AS case_check_status,
    CASE WHEN table_name='wa_invoice_credit' THEN 'NOT_APPLICABLE_NO_FINAL_START_DATE'
         WHEN MAX(when_hit_count)=0 THEN 'ELSE_SOURCE_FILE_NO_CANONICAL_MONTH'
         WHEN COUNT(final_start_date)=0 THEN 'MISSING_FINAL_START_DATE'
         WHEN SUM(CASE WHEN DATE_FORMAT(final_start_date,'yyyy-MM') <> CASE WHEN billing_month LIKE '2025-10%' THEN '2025-10' ELSE billing_month END THEN 1 ELSE 0 END)>0 THEN 'FINAL_START_MONTH_CONFLICT'
         ELSE 'FINAL_START_MONTH_MATCHES_CANDIDATE'
    END AS final_start_vs_candidate_status,
    SUM(CASE WHEN amount_value IS NULL THEN 1 ELSE 0 END) AS null_amount_rows,
    CASE WHEN ROUND(SUM(amount_value),6)=ROUND(SUM(COALESCE(amount_value,0D)),6) THEN 'ROW_SUM_RECOMPUTES'
         ELSE 'ROW_SUM_DIFFERS_OR_NULL_ONLY' END AS amount_recompute_status
  FROM all_mapped
  GROUP BY table_name, source_file, billing_month
)
SELECT * FROM source_check
ORDER BY table_name, source_file