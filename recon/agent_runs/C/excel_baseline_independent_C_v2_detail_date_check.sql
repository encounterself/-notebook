-- Batch C independent live-only final_start_date versus candidate CASE check for detail.
-- Read-only: SELECT/WITH only.
WITH
b AS (
  SELECT
    TRIM(source_file) AS source_file,
    TRY_CAST(NULLIF(TRIM(final_start_date), '') AS DATE) AS final_start_date,
    TRY_CAST(NULLIF(TRIM(final_end_date), '') AS DATE) AS final_end_date,
    NULLIF(TRIM(imsi), '') AS imsi
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
),
m AS (
  SELECT b.*,
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
a AS (
  SELECT
    source_file, billing_month, when_hit_count,
    COUNT(*) AS record_count,
    COUNT(DISTINCT imsi) AS imsi_count,
    COUNT_IF(final_start_date IS NULL) AS final_start_null_rows,
    MIN(final_start_date) AS min_final_start_date,
    MAX(final_start_date) AS max_final_start_date,
    array_join(sort_array(collect_set(CASE WHEN final_start_date IS NOT NULL THEN date_format(final_start_date, 'yyyy-MM') END)), ',') AS final_start_months,
    size(collect_set(CASE WHEN final_start_date IS NOT NULL THEN date_format(final_start_date, 'yyyy-MM') END)) AS final_start_month_count
  FROM h
  GROUP BY source_file, billing_month, when_hit_count
),
x AS (
  SELECT a.*,
    CASE WHEN billing_month LIKE '2025-10%' THEN '2025-10' ELSE billing_month END AS candidate_base_month
  FROM a
)
SELECT
  'wa_invoice_detail' AS source_table,
  source_file,
  billing_month,
  candidate_base_month,
  when_hit_count,
  CASE WHEN when_hit_count > 1 THEN 'CASE_CONFLICT' WHEN when_hit_count = 0 THEN 'ELSE' ELSE 'SINGLE_CASE_HIT' END AS case_status,
  record_count,
  imsi_count,
  final_start_null_rows,
  min_final_start_date,
  max_final_start_date,
  final_start_months,
  final_start_month_count,
  CASE
    WHEN final_start_month_count = 0 THEN 'NO_FINAL_START_DATE'
    WHEN array_contains(split(final_start_months, ','), candidate_base_month) THEN 'NO_CONFLICT'
    ELSE 'FINAL_START_MONTH_CONFLICT'
  END AS final_start_vs_case_status
FROM x
ORDER BY source_file;
