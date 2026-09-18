WITH detail_base AS (
  SELECT
    source_file, imsi, TRY_CAST(final_charge AS DOUBLE) AS excel_amount,
    DATE_FORMAT(TRY_CAST(final_start_date AS DATE),'yyyy-MM') AS observed_start_month,
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
      ELSE source_file END AS invoice_batch_label
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
), prorated_base AS (
  SELECT
    source_file, imsi, TRY_CAST(final_charge_for_usage_days AS DOUBLE) AS excel_amount,
    DATE_FORMAT(TRY_CAST(final_start_date AS DATE),'yyyy-MM') AS observed_start_month,
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
      ELSE source_file END AS invoice_batch_label
  FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
), credit_base AS (
  SELECT
    source_file, imsi, TRY_CAST(credit_owed AS DOUBLE) AS excel_amount,
    DATE_FORMAT(TRY_CAST(cycle_start AS DATE),'yyyy-MM') AS cycle_start_month,
    DATE_FORMAT(TRY_CAST(cycle_end AS DATE),'yyyy-MM') AS cycle_end_month,
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
      ELSE source_file END AS invoice_batch_label
  FROM simo_prod.mysql_cdc_sync.wa_invoice_credit
), detail_label AS (
  SELECT 'invoice_batch_label' AS basis_type,'wa_invoice_detail' AS source_table,invoice_batch_label AS month_value,COUNT(DISTINCT source_file) AS source_file_count,COUNT(*) AS record_count,COUNT(DISTINCT imsi) AS imsi_count,ROUND(SUM(excel_amount),6) AS excel_amount,'detail.final_charge; candidate invoice truth' AS amount_semantics
  FROM detail_base GROUP BY invoice_batch_label
), detail_observed AS (
  SELECT 'observed_start_month','wa_invoice_detail',observed_start_month,COUNT(DISTINCT source_file),COUNT(*),COUNT(DISTINCT imsi),ROUND(SUM(excel_amount),6),'detail.final_charge; observed final_start_date basis only' FROM detail_base GROUP BY observed_start_month
), prorated_label AS (
  SELECT 'invoice_batch_label','wa_invoice_prorated',invoice_batch_label,COUNT(DISTINCT source_file),COUNT(*),COUNT(DISTINCT imsi),ROUND(SUM(excel_amount),6),'prorated.final_charge_for_usage_days; auxiliary only' FROM prorated_base GROUP BY invoice_batch_label
), prorated_observed AS (
  SELECT 'observed_start_month','wa_invoice_prorated',observed_start_month,COUNT(DISTINCT source_file),COUNT(*),COUNT(DISTINCT imsi),ROUND(SUM(excel_amount),6),'prorated.final_charge_for_usage_days; observed final_start_date basis only' FROM prorated_base GROUP BY observed_start_month
), credit_label AS (
  SELECT 'invoice_batch_label','wa_invoice_credit',invoice_batch_label,COUNT(DISTINCT source_file),COUNT(*),COUNT(DISTINCT imsi),ROUND(SUM(excel_amount),6),'credit.credit_owed; auxiliary only, no final_start_month' FROM credit_base GROUP BY invoice_batch_label
), credit_cycle_start AS (
  SELECT 'credit_cycle_start_month','wa_invoice_credit',cycle_start_month,COUNT(DISTINCT source_file),COUNT(*),COUNT(DISTINCT imsi),ROUND(SUM(excel_amount),6),'credit.credit_owed; cycle_start basis only' FROM credit_base GROUP BY cycle_start_month
), credit_cycle_end AS (
  SELECT 'credit_cycle_end_month','wa_invoice_credit',cycle_end_month,COUNT(DISTINCT source_file),COUNT(*),COUNT(DISTINCT imsi),ROUND(SUM(excel_amount),6),'credit.credit_owed; cycle_end basis only' FROM credit_base GROUP BY cycle_end_month
)
SELECT * FROM detail_label
UNION ALL SELECT * FROM detail_observed
UNION ALL SELECT * FROM prorated_label
UNION ALL SELECT * FROM prorated_observed
UNION ALL SELECT * FROM credit_label
UNION ALL SELECT * FROM credit_cycle_start
UNION ALL SELECT * FROM credit_cycle_end
ORDER BY source_table,basis_type,month_value