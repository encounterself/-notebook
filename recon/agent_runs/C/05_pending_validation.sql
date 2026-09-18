WITH cfg AS (
  SELECT '2026-03' AS billing_month, '01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx' AS source_file
  UNION ALL SELECT '2026-04', '01-SIMO Data Purchase Invoice Details - APR 2026.xlsx'
  UNION ALL SELECT '2026-05', '01-SIMO Data Purchase Invoice Details - MAY 2026.xlsx'
)
SELECT
  c.billing_month,
  CAST(x.source_file AS STRING) AS source_file,
  CAST(x.sheet_name AS STRING) AS sheet_name,
  COUNT(*) AS row_count,
  COUNT(DISTINCT CAST(x.imsi AS STRING)) AS imsi_count,
  CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(x.product_name AS STRING)))) AS product_names,
  CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(TRY_CAST(x.monthly_rate AS DOUBLE) AS STRING)))) AS monthly_rates,
  CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(TRY_CAST(x.active_days AS DOUBLE) AS STRING)))) AS active_days_values,
  CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(TRY_CAST(x.usage_days AS DOUBLE) AS STRING)))) AS usage_days_values,
  COUNT(DISTINCT TRY_CAST(x.final_start_date AS DATE)) AS final_start_date_count,
  COUNT(DISTINCT TRY_CAST(x.final_end_date AS DATE)) AS final_end_date_count,
  ROUND(SUM(TRY_CAST(x.original_charge AS DOUBLE)), 6) AS original_charge_sum,
  ROUND(SUM(TRY_CAST(x.final_charge_for_usage_days AS DOUBLE)), 6) AS final_charge_for_usage_days_sum,
  ROUND(SUM(TRY_CAST(x.pending_charge AS DOUBLE)), 6) AS pending_charge_sum
FROM cfg c
JOIN simo_prod.mysql_cdc_sync.wa_invoice_prorated x
  ON x.source_file = c.source_file
GROUP BY c.billing_month, CAST(x.source_file AS STRING), CAST(x.sheet_name AS STRING)
ORDER BY c.billing_month, sheet_name