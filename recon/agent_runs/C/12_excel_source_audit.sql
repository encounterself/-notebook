WITH cfg AS (
  SELECT '2026-03' AS billing_month, '01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx' AS source_file
  UNION ALL SELECT '2026-04', '01-SIMO Data Purchase Invoice Details - APR 2026.xlsx'
  UNION ALL SELECT '2026-05', '01-SIMO Data Purchase Invoice Details - MAY 2026.xlsx'
), detail_raw AS (
  SELECT c.billing_month, x.*
  FROM cfg c JOIN simo_prod.mysql_cdc_sync.wa_invoice_detail x ON x.source_file = c.source_file
), detail_card AS (
  SELECT billing_month, CAST(imsi AS STRING) AS imsi, CAST(charge_type AS STRING) AS charge_type,
    COUNT(*) AS raw_rows,
    COUNT(DISTINCT TRY_CAST(final_start_date AS DATE)) AS start_values,
    COUNT(DISTINCT TRY_CAST(final_end_date AS DATE)) AS end_values,
    COUNT(DISTINCT TRY_CAST(final_days AS DOUBLE)) AS days_values,
    COUNT(DISTINCT TRY_CAST(monthly_rate AS DOUBLE)) AS rate_values,
    COUNT(DISTINCT TRY_CAST(final_charge AS DOUBLE)) AS charge_values,
    CASE WHEN COUNT(DISTINCT TRY_CAST(final_charge AS DOUBLE)) = 1 THEN MIN(TRY_CAST(final_charge AS DOUBLE)) ELSE SUM(TRY_CAST(final_charge AS DOUBLE)) END AS dedup_amount
  FROM detail_raw GROUP BY billing_month, CAST(imsi AS STRING), CAST(charge_type AS STRING)
), credit_raw AS (
  SELECT c.billing_month, x.*
  FROM cfg c JOIN simo_prod.mysql_cdc_sync.wa_invoice_credit x ON x.source_file = c.source_file
), credit_card AS (
  SELECT billing_month, CAST(imsi AS STRING) AS imsi, COUNT(*) AS raw_rows,
    COUNT(DISTINCT TRY_CAST(credit_owed AS DOUBLE)) AS credit_values,
    COUNT(DISTINCT TRY_CAST(final_price AS DOUBLE)) AS final_price_values,
    SUM(TRY_CAST(credit_owed AS DOUBLE)) AS credit_owed_sum,
    SUM(TRY_CAST(final_price AS DOUBLE)) AS final_price_sum
  FROM credit_raw GROUP BY billing_month, CAST(imsi AS STRING)
), prorated_raw AS (
  SELECT c.billing_month, x.*
  FROM cfg c JOIN simo_prod.mysql_cdc_sync.wa_invoice_prorated x ON x.source_file = c.source_file
), prorated_card AS (
  SELECT billing_month, CAST(imsi AS STRING) AS imsi, COUNT(*) AS raw_rows,
    COUNT(DISTINCT TRY_CAST(final_charge_for_usage_days AS DOUBLE)) AS usage_charge_values,
    COUNT(DISTINCT TRY_CAST(pending_charge AS DOUBLE)) AS pending_charge_values,
    SUM(TRY_CAST(final_charge_for_usage_days AS DOUBLE)) AS usage_charge_sum,
    SUM(TRY_CAST(pending_charge AS DOUBLE)) AS pending_charge_sum
  FROM prorated_raw GROUP BY billing_month, CAST(imsi AS STRING)
), detail_month AS (
  SELECT billing_month, COUNT(*) AS detail_raw_rows, COUNT(DISTINCT imsi) AS detail_raw_cards,
    COUNT(*) AS detail_dedup_cards, SUM(dedup_amount) AS detail_dedup_amount,
    SUM(CASE WHEN LOWER(charge_type) LIKE '%credit%' THEN dedup_amount ELSE 0 END) AS detail_credit_amount,
    COUNT(DISTINCT CASE WHEN LOWER(charge_type) LIKE '%credit%' THEN imsi END) AS detail_credit_cards
  FROM detail_card GROUP BY billing_month
), credit_month AS (
  SELECT billing_month, SUM(raw_rows) AS credit_raw_rows, COUNT(*) AS credit_raw_cards,
    SUM(credit_owed_sum) AS credit_owed_amount, SUM(final_price_sum) AS credit_final_price_amount
  FROM credit_card GROUP BY billing_month
), prorated_month AS (
  SELECT billing_month, SUM(raw_rows) AS prorated_raw_rows, COUNT(*) AS prorated_raw_cards,
    SUM(usage_charge_sum) AS prorated_usage_amount, SUM(pending_charge_sum) AS prorated_pending_amount
  FROM prorated_card GROUP BY billing_month
), overlaps AS (
  SELECT c.billing_month,
    COUNT(*) AS credit_table_cards,
    COUNT(CASE WHEN d.imsi IS NOT NULL THEN 1 END) AS credit_overlap_detail_cards,
    COUNT(CASE WHEN d.imsi IS NULL THEN 1 END) AS credit_only_cards
  FROM credit_card c LEFT JOIN (SELECT DISTINCT billing_month, imsi FROM detail_card WHERE LOWER(charge_type) LIKE '%credit%') d
    ON d.billing_month = c.billing_month AND d.imsi = c.imsi
  GROUP BY c.billing_month
)
SELECT m.billing_month,
  m.detail_raw_rows, m.detail_raw_cards, m.detail_dedup_cards, ROUND(m.detail_dedup_amount, 6) AS detail_dedup_amount,
  m.detail_credit_cards, ROUND(m.detail_credit_amount, 6) AS detail_credit_amount,
  COALESCE(c.credit_raw_rows, 0) AS credit_raw_rows, COALESCE(c.credit_raw_cards, 0) AS credit_raw_cards,
  ROUND(COALESCE(c.credit_owed_amount, 0), 6) AS credit_owed_amount,
  ROUND(COALESCE(c.credit_final_price_amount, 0), 6) AS credit_final_price_amount,
  COALESCE(o.credit_overlap_detail_cards, 0) AS credit_overlap_detail_cards,
  COALESCE(o.credit_only_cards, 0) AS credit_only_cards,
  COALESCE(p.prorated_raw_rows, 0) AS prorated_raw_rows,
  COALESCE(p.prorated_raw_cards, 0) AS prorated_dedup_cards,
  ROUND(COALESCE(p.prorated_usage_amount, 0), 6) AS prorated_usage_amount,
  ROUND(COALESCE(p.prorated_pending_amount, 0), 6) AS prorated_pending_amount,
  ROUND(m.detail_dedup_amount + COALESCE(p.prorated_usage_amount, 0), 6) AS full_excel_target_amount,
  'detail dedup grain=(billing_month,imsi,charge_type); credit cross-check only; prorated dedup grain=(billing_month,imsi) and attached once to monthly card' AS dedup_rule
FROM detail_month m
LEFT JOIN credit_month c ON c.billing_month = m.billing_month
LEFT JOIN prorated_month p ON p.billing_month = m.billing_month
LEFT JOIN overlaps o ON o.billing_month = m.billing_month
ORDER BY m.billing_month