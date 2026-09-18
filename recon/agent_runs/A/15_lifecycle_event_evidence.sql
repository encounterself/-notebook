-- Batch A / read-only lifecycle-event evidence joined to WA invoice cards.
WITH cfg AS (
  SELECT '2025-09' AS billing_month, DATE('2025-09-01') AS month_start, DATE('2025-09-30') AS month_end
  UNION ALL SELECT '2025-10', DATE('2025-10-01'), DATE('2025-10-31')
  UNION ALL SELECT '2025-11', DATE('2025-11-01'), DATE('2025-11-30')
), inv AS (
  SELECT
    c.billing_month,
    x.imsi,
    x.charge_type,
    TRY_CAST(x.final_start_date AS DATE) AS xl_start_d,
    TRY_CAST(x.final_end_date AS DATE) AS xl_end_d,
    TRY_CAST(x.final_days AS DOUBLE) AS xl_days
  FROM cfg c
  JOIN simo_prod.mysql_cdc_sync.wa_invoice_detail x
    ON TRY_CAST(x.final_start_date AS DATE) >= c.month_start
   AND TRY_CAST(x.final_start_date AS DATE) <= c.month_end
), cards AS (
  SELECT billing_month, imsi, COUNT(*) AS invoice_type_rows
  FROM inv
  GROUP BY billing_month, imsi
), cycle_events AS (
  SELECT
    c.billing_month,
    c.imsi,
    COUNT(*) AS cycle_event_count_all_window,
    SUM(CASE WHEN CAST(h.next_cycle_time - INTERVAL 5 HOURS AS DATE) BETWEEN cfg.month_start AND cfg.month_end THEN 1 ELSE 0 END) AS cycle_event_count_in_month,
    MIN(CASE WHEN CAST(h.next_cycle_time - INTERVAL 5 HOURS AS DATE) BETWEEN cfg.month_start AND cfg.month_end
             THEN CAST(h.next_cycle_time - INTERVAL 5 HOURS AS DATE) END) AS cycle_start_d5
  FROM cards c
  JOIN cfg ON cfg.billing_month = c.billing_month
  JOIN simo_prod.ods.resource_res_vsim_cycle_history h ON h.imsi = c.imsi
  WHERE h.next_cycle_time >= TIMESTAMP('2025-05-01 00:00:00')
    AND h.next_cycle_time < TIMESTAMP('2026-01-15 00:00:00')
  GROUP BY c.billing_month, c.imsi
), offstock_events AS (
  SELECT
    c.billing_month,
    c.imsi,
    COUNT(*) AS offstock_event_count_window,
    SUM(CASE WHEN CAST(l.CREATE_DATE - INTERVAL 5 HOURS AS DATE) BETWEEN cfg.month_start AND cfg.month_end THEN 1 ELSE 0 END) AS offstock_event_count_in_month,
    MIN(CASE WHEN CAST(l.CREATE_DATE - INTERVAL 5 HOURS AS DATE) BETWEEN cfg.month_start AND cfg.month_end
             THEN CAST(l.CREATE_DATE - INTERVAL 5 HOURS AS DATE) END) AS offstock_d5
  FROM cards c
  JOIN cfg ON cfg.billing_month = c.billing_month
  JOIN simo_prod.ods.resource_res_vsim_status_log l ON l.IMSI = c.imsi
  WHERE l.NEXT_STATUS = '作废'
    AND l.CREATE_DATE >= TIMESTAMP('2025-08-01 00:00:00')
    AND l.CREATE_DATE < TIMESTAMP('2026-01-05 00:00:00')
  GROUP BY c.billing_month, c.imsi
), activation_events AS (
  SELECT
    c.billing_month,
    c.imsi,
    COUNT(*) AS activation_event_count_window,
    MAX(CASE WHEN l.CREATE_DATE - INTERVAL 5 HOURS >= CAST(cfg.month_start AS TIMESTAMP) - INTERVAL 120 DAYS
              AND l.CREATE_DATE - INTERVAL 5 HOURS < CAST(cfg.month_end AS TIMESTAMP) + INTERVAL 41 DAYS
             THEN CAST(l.CREATE_DATE - INTERVAL 5 HOURS AS DATE) END) AS activation_d5
  FROM cards c
  JOIN cfg ON cfg.billing_month = c.billing_month
  JOIN simo_prod.ods.resource_res_vsim_status_log l ON l.IMSI = c.imsi
  WHERE l.NEXT_STATUS = '激活'
    AND l.CREATE_DATE >= TIMESTAMP('2025-05-01 00:00:00')
    AND l.CREATE_DATE < TIMESTAMP('2026-01-15 00:00:00')
  GROUP BY c.billing_month, c.imsi
), enriched AS (
  SELECT
    i.*,
    ce.cycle_event_count_all_window,
    ce.cycle_event_count_in_month,
    ce.cycle_start_d5,
    oe.offstock_event_count_window,
    oe.offstock_event_count_in_month,
    oe.offstock_d5,
    ae.activation_event_count_window,
    ae.activation_d5
  FROM inv i
  LEFT JOIN cycle_events ce ON ce.billing_month = i.billing_month AND ce.imsi = i.imsi
  LEFT JOIN offstock_events oe ON oe.billing_month = i.billing_month AND oe.imsi = i.imsi
  LEFT JOIN activation_events ae ON ae.billing_month = i.billing_month AND ae.imsi = i.imsi
)
SELECT
  billing_month,
  charge_type,
  COUNT(*) AS invoice_rows,
  SUM(CASE WHEN cycle_start_d5 IS NOT NULL THEN 1 ELSE 0 END) AS rows_with_cycle_start_in_month,
  SUM(CASE WHEN cycle_start_d5 = xl_start_d THEN 1 ELSE 0 END) AS cycle_start_exact_match_rows,
  SUM(CASE WHEN cycle_event_count_in_month > 1 THEN 1 ELSE 0 END) AS cards_with_multiple_cycle_events_in_month,
  SUM(CASE WHEN offstock_d5 IS NOT NULL THEN 1 ELSE 0 END) AS rows_with_offstock_in_month,
  SUM(CASE WHEN DATE_SUB(offstock_d5, 1) = xl_end_d THEN 1 ELSE 0 END) AS offstock_minus1_exact_end_rows,
  SUM(CASE WHEN activation_d5 IS NOT NULL THEN 1 ELSE 0 END) AS rows_with_activation_in_window,
  SUM(CASE WHEN DATE_ADD(activation_d5, 1) = xl_start_d THEN 1 ELSE 0 END) AS activation_plus1_exact_start_rows,
  SUM(CASE WHEN xl_days = DATEDIFF(xl_end_d, xl_start_d) + 1 THEN 1 ELSE 0 END) AS invoice_date_span_day_rows
FROM enriched
GROUP BY billing_month, charge_type
ORDER BY billing_month, charge_type;