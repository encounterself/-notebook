-- Batch A / read-only WA invoice price evidence.
-- One output row per observed monthly_rate; no price is collapsed by MAX/MIN.
WITH x AS (
  SELECT
    imsi,
    charge_type,
    TRY_CAST(final_start_date AS DATE) AS final_start_date_d,
    TRY_CAST(final_days AS DOUBLE) AS final_days,
    TRY_CAST(monthly_rate AS DOUBLE) AS monthly_rate,
    TRY_CAST(final_charge AS DOUBLE) AS final_charge
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
), scoped AS (
  SELECT *, DATE_FORMAT(final_start_date_d, 'yyyy-MM') AS billing_month
  FROM x
  WHERE final_start_date_d >= DATE('2025-09-01')
    AND final_start_date_d < DATE('2025-12-01')
)
SELECT
  billing_month,
  charge_type,
  monthly_rate,
  COUNT(*) AS invoice_rows,
  COUNT(DISTINCT imsi) AS distinct_imsi,
  ROUND(SUM(final_days), 2) AS sum_final_days,
  ROUND(SUM(final_charge), 2) AS invoice_amount
FROM scoped
GROUP BY billing_month, charge_type, monthly_rate
ORDER BY billing_month, charge_type, monthly_rate;