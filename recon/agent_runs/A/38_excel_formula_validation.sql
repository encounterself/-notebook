-- Batch A / read-only Excel self-calculation validation.
WITH base AS (
  SELECT
    SUBSTR(CAST(TRY_CAST(final_start_date AS DATE) AS STRING), 1, 7) AS billing_month,
    imsi, charge_type,
    TRY_CAST(final_start_date AS DATE) AS final_start_d,
    TRY_CAST(final_end_date AS DATE) AS final_end_d,
    TRY_CAST(final_days AS DOUBLE) AS final_days,
    TRY_CAST(monthly_rate AS DOUBLE) AS monthly_rate,
    TRY_CAST(final_charge AS DOUBLE) AS final_charge,
    DAY(LAST_DAY(TRY_CAST(final_start_date AS DATE))) AS days_in_month,
    DATEDIFF(TRY_CAST(final_end_date AS DATE), TRY_CAST(final_start_date AS DATE)) + 1 AS date_span_days
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE TRY_CAST(final_start_date AS DATE) BETWEEN DATE('2025-09-01') AND DATE('2025-11-30')
), calc AS (
  SELECT *,
    ROUND(monthly_rate / days_in_month * final_days, 4) AS excel_calculated_amount,
    ROUND(ROUND(monthly_rate / days_in_month * final_days, 4) - final_charge, 4) AS amount_difference,
    date_span_days - final_days AS date_days_difference
  FROM base
)
SELECT
  billing_month, charge_type,
  COUNT(*) AS invoice_rows, COUNT(DISTINCT imsi) AS distinct_card_count,
  COUNT(CASE WHEN monthly_rate IS NULL OR final_days IS NULL OR final_charge IS NULL THEN 1 END) AS missing_formula_input_rows,
  SUM(final_days) AS final_days_sum, ROUND(SUM(final_charge), 4) AS invoice_amount,
  ROUND(SUM(excel_calculated_amount), 4) AS excel_calculated_amount,
  ROUND(SUM(amount_difference), 4) AS formula_amount_difference,
  SUM(CASE WHEN ROUND(excel_calculated_amount, 2) = ROUND(final_charge, 2) THEN 1 ELSE 0 END) AS formula_cent_exact_rows,
  SUM(CASE WHEN ABS(amount_difference) > 0.005 THEN 1 ELSE 0 END) AS formula_non_exact_rows,
  SUM(CASE WHEN date_span_days IS NOT NULL AND ABS(date_days_difference) > 0.001 THEN 1 ELSE 0 END) AS date_span_mismatch_rows,
  SUM(CASE WHEN date_span_days IS NOT NULL AND ABS(date_days_difference) <= 0.001 THEN 1 ELSE 0 END) AS date_span_exact_rows
FROM calc
GROUP BY billing_month, charge_type
ORDER BY billing_month, charge_type;