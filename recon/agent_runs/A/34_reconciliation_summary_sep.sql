-- Batch A / September read-only missing-data summary.
WITH cfg AS (
  SELECT DATE('2025-09-01') AS month_start, DATE('2025-09-30') AS month_end
)
SELECT '2025-09' AS billing_month,
       'MISSING_DATA' AS reconciliation_status,
       COUNT(*) AS invoice_rows,
       COUNT(DISTINCT x.imsi) AS invoice_card_count,
       ROUND(SUM(TRY_CAST(x.final_charge AS DOUBLE)), 4) AS invoice_amount,
       'PLATFORM_CARD_SET_NOT_MATERIALIZED_DUE_UNREADABLE_SNAPSHOT' AS platform_status
FROM cfg c
JOIN simo_prod.mysql_cdc_sync.wa_invoice_detail x
  ON TRY_CAST(x.final_start_date AS DATE) BETWEEN c.month_start AND c.month_end;