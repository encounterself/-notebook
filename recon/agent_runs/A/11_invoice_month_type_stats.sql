-- Batch A / read-only WA invoice monthly and charge_type facts.
WITH x AS (
  SELECT
    imsi,
    charge_type,
    TRY_CAST(final_start_date AS DATE) AS final_start_date_d,
    TRY_CAST(final_end_date AS DATE) AS final_end_date_d,
    TRY_CAST(active_days AS DOUBLE) AS active_days,
    TRY_CAST(usage_days AS DOUBLE) AS usage_days,
    TRY_CAST(final_days AS DOUBLE) AS final_days,
    TRY_CAST(monthly_rate AS DOUBLE) AS monthly_rate,
    TRY_CAST(final_charge AS DOUBLE) AS final_charge,
    source_file
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
), scoped AS (
  SELECT *, DATE_FORMAT(final_start_date_d, 'yyyy-MM') AS billing_month
  FROM x
  WHERE final_start_date_d >= DATE('2025-09-01')
    AND final_start_date_d < DATE('2025-12-01')
), checked AS (
  SELECT *,
    DAY(LAST_DAY(final_start_date_d)) AS days_in_start_month,
    final_days / DAY(LAST_DAY(final_start_date_d)) * monthly_rate AS formula_amount,
    DATEDIFF(final_end_date_d, final_start_date_d) + 1 AS date_span_days
  FROM scoped
)
SELECT
  billing_month,
  charge_type,
  COUNT(*) AS invoice_rows,
  COUNT(DISTINCT imsi) AS distinct_imsi,
  COUNT(*) - COUNT(DISTINCT imsi) AS duplicate_rows_at_month_imsi_type_grain,
  COUNT(DISTINCT source_file) AS source_file_count,
  COUNT(DISTINCT monthly_rate) AS distinct_monthly_rate_count,
  SUM(CASE WHEN final_start_date_d IS NULL THEN 1 ELSE 0 END) AS missing_final_start_rows,
  SUM(CASE WHEN final_end_date_d IS NULL THEN 1 ELSE 0 END) AS missing_final_end_rows,
  SUM(CASE WHEN final_days IS NULL THEN 1 ELSE 0 END) AS missing_final_days_rows,
  SUM(CASE WHEN monthly_rate IS NULL THEN 1 ELSE 0 END) AS missing_monthly_rate_rows,
  SUM(CASE WHEN final_charge IS NULL THEN 1 ELSE 0 END) AS missing_final_charge_rows,
  SUM(CASE WHEN final_days <> date_span_days THEN 1 ELSE 0 END) AS date_span_mismatch_rows,
  SUM(CASE WHEN ROUND(formula_amount, 2) = ROUND(final_charge, 2) THEN 1 ELSE 0 END) AS formula_cent_match_rows,
  ROUND(SUM(final_days), 2) AS sum_final_days,
  ROUND(SUM(final_charge), 2) AS invoice_amount,
  ROUND(SUM(formula_amount), 2) AS forward_formula_amount,
  ROUND(SUM(formula_amount) - SUM(final_charge), 2) AS forward_formula_diff,
  ROUND(SUM(ABS(formula_amount - final_charge)), 2) AS sum_abs_unrounded_amount_diff
FROM checked
GROUP BY billing_month, charge_type
ORDER BY billing_month, charge_type;