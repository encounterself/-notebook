WITH cfg AS (
  SELECT '2026-03' AS billing_month, '01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx' AS source_file
  UNION ALL SELECT '2026-04', '01-SIMO Data Purchase Invoice Details - APR 2026.xlsx'
  UNION ALL SELECT '2026-05', '01-SIMO Data Purchase Invoice Details - MAY 2026.xlsx'
),
detail AS (
  SELECT c.billing_month, CAST(x.imsi AS STRING) AS imsi, CAST(x.charge_type AS STRING) AS charge_type,
    TRY_CAST(x.monthly_rate AS DOUBLE) AS price, TRY_CAST(x.final_days AS DOUBLE) AS final_days,
    TRY_CAST(x.final_charge AS DOUBLE) AS amount
  FROM cfg c JOIN simo_prod.mysql_cdc_sync.wa_invoice_detail x ON x.source_file = c.source_file
),
card_grain AS (
  SELECT
    billing_month,
    imsi,
    COUNT(*) AS row_count,
    COUNT(DISTINCT charge_type) AS charge_type_count,
    COUNT(DISTINCT price) AS price_count,
    COUNT(DISTINCT final_days) AS final_days_count,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(charge_type))) AS charge_types,
    ROUND(SUM(amount), 6) AS amount_sum
  FROM detail
  GROUP BY billing_month, imsi
),
charge_grain AS (
  SELECT billing_month, imsi, charge_type, COUNT(*) AS rows_at_charge_grain
  FROM detail
  GROUP BY billing_month, imsi, charge_type
)
SELECT
  g.billing_month,
  COUNT(*) AS card_month_rows,
  SUM(CASE WHEN g.row_count > 1 THEN 1 ELSE 0 END) AS cards_with_multiple_detail_rows,
  SUM(CASE WHEN g.charge_type_count > 1 THEN 1 ELSE 0 END) AS cards_with_multiple_charge_types,
  SUM(CASE WHEN g.price_count > 1 THEN 1 ELSE 0 END) AS cards_with_multiple_prices,
  SUM(CASE WHEN g.final_days_count > 1 THEN 1 ELSE 0 END) AS cards_with_multiple_final_days,
  COUNT(DISTINCT CASE WHEN cg.rows_at_charge_grain > 1 THEN CONCAT(g.billing_month, '|', g.imsi, '|', cg.charge_type) END) AS duplicate_charge_grain_keys,
  ROUND(SUM(g.amount_sum), 6) AS amount_sum
FROM card_grain g
LEFT JOIN charge_grain cg
  ON cg.billing_month = g.billing_month AND cg.imsi = g.imsi
GROUP BY g.billing_month
ORDER BY g.billing_month;