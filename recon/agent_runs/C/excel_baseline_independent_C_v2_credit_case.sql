-- Batch C independent live-only candidate CASE summary for wa_invoice_credit.
-- Read-only: SELECT/WITH only. This table is not merged into detail or prorated.
WITH
b AS (
  SELECT
    TRIM(source_file) AS source_file,
    NULLIF(TRIM(imsi), '') AS imsi,
    NULLIF(TRIM(prod), '') AS prod,
    TRY_CAST(NULLIF(TRIM(cycle_start), '') AS DATE) AS cycle_start,
    TRY_CAST(NULLIF(TRIM(cycle_end), '') AS DATE) AS cycle_end,
    TRY_CAST(NULLIF(TRIM(price), '') AS DECIMAL(28,8)) AS price,
    TRY_CAST(NULLIF(TRIM(final_price), '') AS DECIMAL(28,8)) AS final_price,
    TRY_CAST(NULLIF(TRIM(credit_owed), '') AS DECIMAL(28,8)) AS credit_owed
  FROM simo_prod.mysql_cdc_sync.wa_invoice_credit
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
)
SELECT
  'wa_invoice_credit' AS source_table,
  source_file,
  billing_month,
  when_hit_count,
  CASE WHEN when_hit_count = 0 THEN 1 ELSE 0 END AS else_flag,
  CASE WHEN when_hit_count > 1 THEN 'CASE_CONFLICT' WHEN when_hit_count = 0 THEN 'ELSE' ELSE 'SINGLE_CASE_HIT' END AS case_status,
  COUNT(*) AS record_count,
  COUNT(DISTINCT imsi) AS imsi_count,
  SUM(credit_owed) AS total_credit_owed,
  SUM(final_price) AS total_final_price,
  SUM(price) AS total_price,
  COUNT(DISTINCT prod) AS product_count,
  MIN(cycle_start) AS min_cycle_start,
  MAX(cycle_start) AS max_cycle_start,
  MIN(cycle_end) AS min_cycle_end,
  MAX(cycle_end) AS max_cycle_end
FROM h
GROUP BY source_file, billing_month, when_hit_count
ORDER BY source_file;
