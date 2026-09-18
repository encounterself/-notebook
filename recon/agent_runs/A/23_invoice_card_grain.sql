-- Batch A / read-only invoice card-month grain check.
WITH x AS (
  SELECT
    DATE_FORMAT(TRY_CAST(final_start_date AS DATE), 'yyyy-MM') AS billing_month,
    imsi,
    charge_type
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE TRY_CAST(final_start_date AS DATE) >= DATE('2025-09-01')
    AND TRY_CAST(final_start_date AS DATE) < DATE('2025-12-01')
)
SELECT
  billing_month,
  imsi,
  COUNT(*) AS invoice_rows_per_card_month,
  COUNT(DISTINCT charge_type) AS charge_type_count,
  SORT_ARRAY(COLLECT_SET(charge_type)) AS charge_types_observed
FROM x
GROUP BY billing_month, imsi
HAVING COUNT(*) > 1
ORDER BY billing_month, imsi;