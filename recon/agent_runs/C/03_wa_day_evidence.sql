WITH cfg AS (
  SELECT '2026-03' AS billing_month, '01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx' AS source_file, LAST_DAY(DATE '2026-03-01') AS month_end
  UNION ALL SELECT '2026-04', '01-SIMO Data Purchase Invoice Details - APR 2026.xlsx', LAST_DAY(DATE '2026-04-01')
  UNION ALL SELECT '2026-05', '01-SIMO Data Purchase Invoice Details - MAY 2026.xlsx', LAST_DAY(DATE '2026-05-01')
),
rows AS (
  SELECT
    c.billing_month,
    c.month_end,
    CAST(x.imsi AS STRING) AS imsi,
    CAST(x.charge_type AS STRING) AS charge_type,
    TRY_CAST(x.final_start_date AS DATE) AS final_start_d,
    TRY_CAST(x.final_end_date AS DATE) AS final_end_d,
    TRY_CAST(x.new_activation_date AS DATE) AS activation_d,
    TRY_CAST(x.offstock_date AS DATE) AS offstock_d,
    TRY_CAST(x.final_days AS DOUBLE) AS wa_final_days,
    TRY_CAST(x.active_days AS DOUBLE) AS wa_active_days,
    TRY_CAST(x.usage_days AS DOUBLE) AS wa_usage_days,
    TRY_CAST(x.usage_days_alt AS DOUBLE) AS wa_usage_days_alt,
    TRY_CAST(x.monthly_rate AS DOUBLE) AS wa_price,
    TRY_CAST(x.final_charge AS DOUBLE) AS wa_amount
  FROM cfg c
  JOIN simo_prod.mysql_cdc_sync.wa_invoice_detail x
    ON x.source_file = c.source_file
),
scored AS (
  SELECT
    *,
    DATEDIFF(final_end_d, final_start_d) + 1 AS date_span_days,
    DATEDIFF(month_end, activation_d) + 1 AS activation_to_month_end_days,
    DATEDIFF(month_end, final_start_d) + 1 AS final_start_to_month_end_days,
    DATEDIFF(offstock_d, final_start_d) + 1 AS final_start_to_offstock_days,
    DAY(month_end) AS month_days
  FROM rows
)
SELECT
  billing_month,
  charge_type,
  COUNT(*) AS row_count,
  COUNT(DISTINCT imsi) AS imsi_count,
  SUM(CASE WHEN wa_final_days IS NULL THEN 1 ELSE 0 END) AS null_wa_final_days,
  SUM(CASE WHEN final_start_d IS NULL OR final_end_d IS NULL THEN 1 ELSE 0 END) AS null_final_dates,
  SUM(CASE WHEN wa_final_days = date_span_days THEN 1 ELSE 0 END) AS exact_final_date_span,
  SUM(CASE WHEN wa_final_days = activation_to_month_end_days THEN 1 ELSE 0 END) AS exact_activation_to_month_end,
  SUM(CASE WHEN wa_final_days = final_start_to_month_end_days THEN 1 ELSE 0 END) AS exact_final_start_to_month_end,
  SUM(CASE WHEN wa_final_days = final_start_to_offstock_days THEN 1 ELSE 0 END) AS exact_final_start_to_offstock,
  SUM(CASE WHEN wa_final_days = month_days THEN 1 ELSE 0 END) AS exact_full_month_days,
  SUM(CASE WHEN wa_final_days = wa_active_days THEN 1 ELSE 0 END) AS exact_active_days,
  SUM(CASE WHEN wa_final_days = wa_usage_days THEN 1 ELSE 0 END) AS exact_usage_days,
  SUM(CASE WHEN wa_final_days = wa_usage_days_alt THEN 1 ELSE 0 END) AS exact_usage_days_alt,
  COUNT(DISTINCT wa_price) AS wa_price_count,
  CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(wa_price AS STRING)))) AS wa_prices_seen,
  ROUND(SUM(wa_amount), 6) AS wa_amount_sum
FROM scored
GROUP BY billing_month, charge_type
ORDER BY billing_month, charge_type;