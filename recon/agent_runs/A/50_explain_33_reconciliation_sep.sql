EXPLAIN WITH cfg AS (
  SELECT '2025-09' AS billing_month, DATE('2025-09-01') AS month_start, DATE('2025-09-30') AS month_end
), invoice_card AS (
  SELECT c.billing_month, x.imsi, COUNT(*) AS invoice_line_count,
         SUM(TRY_CAST(x.final_charge AS DOUBLE)) AS invoice_amount
  FROM cfg c
  JOIN simo_prod.mysql_cdc_sync.wa_invoice_detail x
    ON TRY_CAST(x.final_start_date AS DATE) BETWEEN c.month_start AND c.month_end
  GROUP BY c.billing_month, x.imsi
), platform_card_fact AS (
  SELECT CAST(NULL AS STRING) AS billing_month, CAST(NULL AS STRING) AS imsi
  WHERE 1 = 0
), full_outer_shell AS (
  SELECT COALESCE(i.billing_month, p.billing_month) AS billing_month,
         COALESCE(i.imsi, p.imsi) AS imsi,
         i.invoice_line_count, i.invoice_amount,
         CASE WHEN i.imsi IS NOT NULL AND p.imsi IS NOT NULL THEN 'MATCHED'
              WHEN i.imsi IS NOT NULL THEN 'WA_ONLY'
              WHEN p.imsi IS NOT NULL THEN 'PLATFORM_ONLY'
              ELSE 'MISSING_DATA' END AS join_status,
         CASE WHEN p.imsi IS NULL AND i.imsi IS NOT NULL THEN 'MISSING_DATA_PLATFORM_SNAPSHOT'
              ELSE 'NOT_APPLICABLE' END AS validation_status
  FROM invoice_card i
  FULL OUTER JOIN platform_card_fact p
    ON i.billing_month = p.billing_month AND i.imsi = p.imsi
)
SELECT * FROM full_outer_shell ORDER BY join_status, imsi;