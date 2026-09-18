-- Batch A / read-only probe.
-- Purpose: map WA source_file to the month actually represented by
-- final_start_date for 2025-09, 2025-10 and 2025-11.
-- Evidence source: simo_prod.mysql_cdc_sync.wa_invoice_detail only.
-- No filename pattern is used to assign a billing month.

WITH x AS (
  SELECT
    source_file,
    imsi,
    charge_type,
    TRY_CAST(final_start_date AS DATE) AS final_start_date_d,
    TRY_CAST(final_end_date AS DATE) AS final_end_date_d,
    TRY_CAST(final_days AS DOUBLE) AS final_days,
    TRY_CAST(monthly_rate AS DOUBLE) AS monthly_rate,
    TRY_CAST(final_charge AS DOUBLE) AS final_charge
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
), scoped AS (
  SELECT *
  FROM x
  WHERE final_start_date_d >= DATE('2025-09-01')
    AND final_start_date_d < DATE('2025-12-01')
)
SELECT
  source_file,
  DATE_FORMAT(final_start_date_d, 'yyyy-MM') AS billing_month_by_final_start,
  charge_type,
  COUNT(*) AS invoice_rows,
  COUNT(DISTINCT imsi) AS distinct_imsi,
  MIN(final_start_date_d) AS min_final_start_date,
  MAX(final_start_date_d) AS max_final_start_date,
  MIN(final_end_date_d) AS min_final_end_date,
  MAX(final_end_date_d) AS max_final_end_date,
  COUNT(DISTINCT monthly_rate) AS distinct_monthly_rate_count,
  SUM(final_days) AS sum_final_days,
  ROUND(SUM(final_charge), 2) AS sum_final_charge
FROM scoped
GROUP BY source_file, DATE_FORMAT(final_start_date_d, 'yyyy-MM'), charge_type
ORDER BY billing_month_by_final_start, source_file, charge_type;