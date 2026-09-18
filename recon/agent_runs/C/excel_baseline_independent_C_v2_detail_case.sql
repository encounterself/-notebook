-- Batch C independent live-only candidate CASE summary for wa_invoice_detail.
-- Read-only: SELECT/WITH only. No other wa table is merged into this result.
WITH
b AS (
  SELECT
    TRIM(source_file) AS source_file,
    NULLIF(TRIM(imsi), '') AS imsi,
    NULLIF(TRIM(charge_type), '') AS charge_type,
    NULLIF(TRIM(product_name), '') AS product_name,
    TRY_CAST(NULLIF(TRIM(final_start_date), '') AS DATE) AS final_start_date,
    TRY_CAST(NULLIF(TRIM(final_end_date), '') AS DATE) AS final_end_date,
    TRY_CAST(NULLIF(TRIM(final_charge), '') AS DECIMAL(28,8)) AS final_charge,
    TRY_CAST(NULLIF(TRIM(monthly_rate), '') AS DECIMAL(28,8)) AS monthly_rate
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
),
m AS (
  SELECT
    b.*,
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
    CASE WHEN source_file LIKE '%JAN 2025%' THEN 1 ELSE 0 END AS jan_hit,
    CASE WHEN source_file LIKE '%SEP 2025%' THEN 1 ELSE 0 END AS sep_hit,
    CASE WHEN source_file LIKE '%OCT 2025%' AND source_file LIKE '%773,793.84%' THEN 1 ELSE 0 END AS oct_v2_hit,
    CASE WHEN source_file LIKE '%OCT 2025%' AND source_file LIKE '%772,765.00%' THEN 1 ELSE 0 END AS oct_v1_hit,
    CASE WHEN source_file LIKE '%DEC 2025%' THEN 1 ELSE 0 END AS dec_hit,
    CASE WHEN source_file LIKE '%FEB 2026%' THEN 1 ELSE 0 END AS feb_hit,
    CASE WHEN source_file LIKE '%MAR 2026%' THEN 1 ELSE 0 END AS mar_hit,
    CASE WHEN source_file LIKE '%APR 2026%' THEN 1 ELSE 0 END AS apr_hit,
    CASE WHEN source_file LIKE '%MAY 2026%' THEN 1 ELSE 0 END AS may_hit,
    CASE WHEN source_file LIKE '%JUNE 2026%' THEN 1 ELSE 0 END AS june_hit,
    CASE WHEN source_file LIKE '%JULY 2026%' THEN 1 ELSE 0 END AS july_hit,
    CASE WHEN source_file LIKE '%AUGUST 2026%' THEN 1 ELSE 0 END AS august_hit
  FROM b
),
h AS (
  SELECT m.*, jan_hit + sep_hit + oct_v2_hit + oct_v1_hit + dec_hit + feb_hit + mar_hit + apr_hit + may_hit + june_hit + july_hit + august_hit AS when_hit_count
  FROM m
),
src AS (
  SELECT
    source_file, billing_month,
    MAX(when_hit_count) AS when_hit_count,
    MAX(CASE WHEN when_hit_count = 0 THEN 1 ELSE 0 END) AS else_flag,
    COUNT(*) AS source_record_count,
    COUNT(DISTINCT imsi) AS source_imsi_count,
    SUM(final_charge) AS source_total_final_charge,
    SUM(monthly_rate) AS source_total_monthly_rate_sum,
    COUNT(DISTINCT charge_type) AS charge_type_count,
    COUNT(DISTINCT product_name) AS product_count,
    MIN(final_start_date) AS source_min_final_start_date,
    MAX(final_start_date) AS source_max_final_start_date,
    MIN(final_end_date) AS source_min_final_end_date,
    MAX(final_end_date) AS source_max_final_end_date
  FROM h
  GROUP BY source_file, billing_month
),
ct AS (
  SELECT
    source_file, billing_month, charge_type,
    COUNT(*) AS charge_type_record_count,
    COUNT(DISTINCT imsi) AS charge_type_imsi_count,
    SUM(final_charge) AS charge_type_total_final_charge,
    SUM(monthly_rate) AS charge_type_total_monthly_rate_sum,
    MIN(final_start_date) AS charge_type_min_final_start_date,
    MAX(final_start_date) AS charge_type_max_final_start_date,
    MIN(final_end_date) AS charge_type_min_final_end_date,
    MAX(final_end_date) AS charge_type_max_final_end_date
  FROM h
  GROUP BY source_file, billing_month, charge_type
)
SELECT
  'wa_invoice_detail' AS source_table,
  src.source_file,
  src.billing_month,
  src.when_hit_count,
  src.else_flag,
  CASE WHEN src.when_hit_count > 1 THEN 'CASE_CONFLICT' WHEN src.else_flag = 1 THEN 'ELSE' ELSE 'SINGLE_CASE_HIT' END AS case_status,
  src.source_record_count AS record_count,
  src.source_imsi_count AS imsi_count,
  src.source_total_final_charge AS total_final_charge,
  src.source_total_monthly_rate_sum AS total_monthly_rate_sum,
  src.charge_type_count,
  src.product_count,
  src.source_min_final_start_date,
  src.source_max_final_start_date,
  src.source_min_final_end_date,
  src.source_max_final_end_date,
  ct.charge_type,
  ct.charge_type_record_count,
  ct.charge_type_imsi_count,
  ct.charge_type_total_final_charge,
  ct.charge_type_total_monthly_rate_sum,
  ct.charge_type_min_final_start_date,
  ct.charge_type_max_final_start_date,
  ct.charge_type_min_final_end_date,
  ct.charge_type_max_final_end_date
FROM src
JOIN ct USING (source_file, billing_month)
ORDER BY src.source_file, ct.charge_type;
