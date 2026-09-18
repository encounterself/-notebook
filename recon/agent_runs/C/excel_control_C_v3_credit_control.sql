-- Batch C Excel truth control: credit card/group level.
-- Credit has no final_start_date; observed_start_month is intentionally NULL.
-- Read-only: SELECT/WITH only. No UNION and no platform JOIN.
WITH
raw AS (
  SELECT
    source_file,
    NULLIF(TRIM(imsi), '') AS imsi,
    NULLIF(TRIM(prod), '') AS product_name,
    TRY_CAST(NULLIF(TRIM(cycle_start), '') AS DATE) AS cycle_start,
    TRY_CAST(NULLIF(TRIM(cycle_end), '') AS DATE) AS cycle_end,
    TRY_CAST(NULLIF(TRIM(price), '') AS DECIMAL(28,8)) AS price,
    TRY_CAST(NULLIF(TRIM(final_price), '') AS DECIMAL(28,8)) AS final_price,
    TRY_CAST(NULLIF(TRIM(correct_price), '') AS DECIMAL(28,8)) AS correct_price,
    TRY_CAST(NULLIF(TRIM(credit_owed), '') AS DECIMAL(28,8)) AS excel_amount
  FROM simo_prod.mysql_cdc_sync.wa_invoice_credit
),
labeled AS (
  SELECT raw.*,
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
    date_format(cycle_start, 'yyyy-MM') AS observed_cycle_start_month,
    date_format(cycle_end, 'yyyy-MM') AS observed_cycle_end_month,
    'credit.credit_owed' AS amount_semantics
  FROM raw
),
source_all AS (
  SELECT source_file, invoice_batch_label,
         COUNT(*) AS source_record_count,
         COUNT(DISTINCT imsi) AS source_imsi_count,
         SUM(excel_amount) AS source_excel_amount,
         SUM(price) AS source_price_sum,
         SUM(final_price) AS source_final_price_sum,
         COUNT(DISTINCT product_name) AS source_product_count
  FROM labeled
  GROUP BY source_file, invoice_batch_label
),
control_groups AS (
  SELECT
    source_file, invoice_batch_label, observed_start_month,
    observed_cycle_start_month, observed_cycle_end_month,
    imsi,
    CAST(NULL AS STRING) AS charge_type,
    CAST(NULL AS DECIMAL(28,8)) AS excel_days,
    correct_price AS excel_price,
    excel_amount,
    price, final_price, correct_price, product_name,
    amount_semantics,
    COUNT(*) AS control_row_count,
    MIN(cycle_start) AS min_cycle_start,
    MAX(cycle_start) AS max_cycle_start,
    MIN(cycle_end) AS min_cycle_end,
    MAX(cycle_end) AS max_cycle_end
  FROM labeled
  GROUP BY source_file, invoice_batch_label, observed_start_month,
           observed_cycle_start_month, observed_cycle_end_month, imsi,
           correct_price, excel_amount, price, final_price, product_name, amount_semantics
)
SELECT
  'wa_invoice_credit' AS source_table,
  'ALL_CREDIT_ROWS' AS control_scope,
  g.source_file,
  g.invoice_batch_label,
  g.observed_start_month,
  g.observed_cycle_start_month,
  g.observed_cycle_end_month,
  g.imsi,
  g.charge_type,
  g.excel_days,
  g.excel_price,
  g.excel_amount,
  g.amount_semantics,
  g.price,
  g.final_price,
  g.correct_price,
  g.product_name,
  g.control_row_count,
  g.min_cycle_start,
  g.max_cycle_start,
  g.min_cycle_end,
  g.max_cycle_end,
  s.source_record_count,
  s.source_imsi_count,
  s.source_excel_amount,
  s.source_price_sum,
  s.source_final_price_sum,
  s.source_product_count
FROM control_groups g
JOIN source_all s
  ON g.source_file = s.source_file AND g.invoice_batch_label = s.invoice_batch_label
ORDER BY g.source_file, g.observed_cycle_start_month, g.imsi, g.excel_price, g.excel_amount;
