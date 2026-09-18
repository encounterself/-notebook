-- Batch C Excel truth control: prorated card/group level.
-- Scope: candidate invoice_batch_label 2026-03, 2026-04, 2026-05.
-- Read-only: SELECT/WITH only. No UNION and no platform JOIN.
WITH
raw AS (
  SELECT
    source_file,
    NULLIF(TRIM(imsi), '') AS imsi,
    NULLIF(TRIM(product_name), '') AS product_name,
    NULLIF(TRIM(cycle_start_date), '') AS cycle_start_date,
    NULLIF(TRIM(cycle_end_date), '') AS cycle_end_date,
    TRY_CAST(NULLIF(TRIM(final_start_date), '') AS DATE) AS final_start_date,
    TRY_CAST(NULLIF(TRIM(final_end_date), '') AS DATE) AS final_end_date,
    TRY_CAST(NULLIF(TRIM(usage_days), '') AS DECIMAL(28,8)) AS excel_days,
    TRY_CAST(NULLIF(TRIM(monthly_rate), '') AS DECIMAL(28,8)) AS excel_price,
    TRY_CAST(NULLIF(TRIM(final_charge_for_usage_days), '') AS DECIMAL(28,8)) AS excel_amount,
    TRY_CAST(NULLIF(TRIM(pending_charge), '') AS DECIMAL(28,8)) AS pending_charge,
    TRY_CAST(NULLIF(TRIM(original_charge), '') AS DECIMAL(28,8)) AS original_charge
  FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
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
    date_format(final_start_date, 'yyyy-MM') AS observed_start_month,
    'prorated.final_charge_for_usage_days' AS amount_semantics
  FROM raw
),
source_all AS (
  SELECT source_file, invoice_batch_label,
         COUNT(*) AS source_record_count,
         COUNT(DISTINCT imsi) AS source_imsi_count,
         SUM(excel_amount) AS source_excel_amount,
         SUM(pending_charge) AS source_pending_charge,
         SUM(excel_price) AS source_monthly_rate_sum,
         COUNT(DISTINCT product_name) AS source_product_count
  FROM labeled
  GROUP BY source_file, invoice_batch_label
),
month_all AS (
  SELECT source_file, invoice_batch_label, observed_start_month,
         COUNT(*) AS observed_record_count,
         COUNT(DISTINCT imsi) AS observed_imsi_count,
         SUM(excel_amount) AS observed_excel_amount,
         SUM(pending_charge) AS observed_pending_charge,
         SUM(excel_price) AS observed_monthly_rate_sum
  FROM labeled
  GROUP BY source_file, invoice_batch_label, observed_start_month
),
control_groups AS (
  SELECT
    source_file, invoice_batch_label, observed_start_month, imsi,
    CAST(NULL AS STRING) AS charge_type,
    excel_days, excel_price, excel_amount, amount_semantics,
    SUM(pending_charge) AS pending_charge,
    SUM(original_charge) AS original_charge,
    COUNT(*) AS control_row_count,
    MIN(final_start_date) AS min_final_start_date,
    MAX(final_start_date) AS max_final_start_date,
    MIN(final_end_date) AS min_final_end_date,
    MAX(final_end_date) AS max_final_end_date,
    MIN(cycle_start_date) AS cycle_start_date,
    MAX(cycle_end_date) AS cycle_end_date
  FROM labeled
  WHERE invoice_batch_label IN ('2026-03', '2026-04', '2026-05')
  GROUP BY source_file, invoice_batch_label, observed_start_month, imsi,
           excel_days, excel_price, excel_amount, amount_semantics
)
SELECT
  'wa_invoice_prorated' AS source_table,
  'C_TARGET' AS control_scope,
  g.source_file,
  g.invoice_batch_label,
  g.observed_start_month,
  g.imsi,
  g.charge_type,
  g.excel_days,
  g.excel_price,
  g.excel_amount,
  g.amount_semantics,
  g.pending_charge,
  g.original_charge,
  g.control_row_count,
  g.min_final_start_date,
  g.max_final_start_date,
  g.min_final_end_date,
  g.max_final_end_date,
  g.cycle_start_date,
  g.cycle_end_date,
  s.source_record_count,
  s.source_imsi_count,
  s.source_excel_amount,
  s.source_pending_charge,
  s.source_monthly_rate_sum,
  s.source_product_count,
  m.observed_record_count,
  m.observed_imsi_count,
  m.observed_excel_amount,
  m.observed_pending_charge,
  m.observed_monthly_rate_sum
FROM control_groups g
JOIN source_all s
  ON g.source_file = s.source_file AND g.invoice_batch_label = s.invoice_batch_label
JOIN month_all m
  ON g.source_file = m.source_file
 AND g.invoice_batch_label = m.invoice_batch_label
 AND (g.observed_start_month = m.observed_start_month OR (g.observed_start_month IS NULL AND m.observed_start_month IS NULL))
ORDER BY g.source_file, g.observed_start_month, g.imsi, g.excel_price, g.excel_days, g.excel_amount;
