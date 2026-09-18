-- Batch A / read-only mapping probe for invoice offstock_date to status_log events.
WITH inv AS (
  SELECT
    DATE_FORMAT(TRY_CAST(final_start_date AS DATE), 'yyyy-MM') AS billing_month,
    imsi,
    TRY_CAST(offstock_date AS DATE) AS invoice_offstock_d,
    TRY_CAST(final_end_date AS DATE) AS invoice_end_d
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE TRY_CAST(final_start_date AS DATE) >= DATE('2025-09-01')
    AND TRY_CAST(final_start_date AS DATE) < DATE('2025-12-01')
    AND charge_type LIKE 'Prorated-out%'
), events AS (
  SELECT
    i.billing_month,
    i.imsi,
    i.invoice_offstock_d,
    i.invoice_end_d,
    l.PRE_STATUS,
    l.NEXT_STATUS,
    CAST(l.CREATE_DATE AS DATE) AS event_date_raw,
    CAST(l.CREATE_DATE - INTERVAL 5 HOURS AS DATE) AS event_date_minus5h
  FROM inv i
  LEFT JOIN simo_prod.ods.resource_res_vsim_status_log l
    ON l.IMSI = i.imsi
   AND l.CREATE_DATE >= TIMESTAMP('2025-08-01 00:00:00')
   AND l.CREATE_DATE < TIMESTAMP('2026-01-15 00:00:00')
)
SELECT
  billing_month,
  PRE_STATUS,
  NEXT_STATUS,
  COUNT(DISTINCT imsi) AS status_event_cards,
  COUNT(DISTINCT CASE WHEN event_date_raw = invoice_offstock_d THEN imsi END) AS raw_date_offstock_match_cards,
  COUNT(DISTINCT CASE WHEN event_date_minus5h = invoice_offstock_d THEN imsi END) AS minus5h_date_offstock_match_cards,
  COUNT(DISTINCT CASE WHEN DATE_SUB(event_date_raw, 1) = invoice_end_d THEN imsi END) AS raw_date_end_minus1_match_cards,
  COUNT(DISTINCT CASE WHEN DATE_SUB(event_date_minus5h, 1) = invoice_end_d THEN imsi END) AS minus5h_date_end_minus1_match_cards
FROM events
GROUP BY billing_month, PRE_STATUS, NEXT_STATUS
ORDER BY billing_month, NEXT_STATUS, PRE_STATUS;