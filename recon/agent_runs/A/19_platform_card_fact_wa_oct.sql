-- Batch A / read-only platform monthly card facts for 2025-10 and 2025-11.
-- This query preserves product and price multiplicity at card-month grain.
WITH cfg AS (
  SELECT '2025-10' AS billing_month, 2025 AS y, 10 AS m, DATE('2025-10-01') AS month_start, DATE('2025-10-31') AS month_end, 31 AS days_in_month
  UNION ALL SELECT '2025-11', 2025, 11, DATE('2025-11-01'), DATE('2025-11-30'), 30
), snap AS (
  SELECT
    c.billing_month,
    c.month_start,
    c.month_end,
    c.days_in_month,
    s.imsi,
    s.product_id,
    CAST(s.partition_time AS DATE) AS presence_d,
    TRY_CAST(s.Cycle_Start_Time AS TIMESTAMP) AS cycle_start_ts,
    TRY_CAST(s.Cycle_End_Time AS TIMESTAMP) AS cycle_end_ts
  FROM cfg c
  JOIN simo_prod.tc_cdr.sim_status_for_sftp_bak s
    ON s.year = c.y AND s.month = c.m
), presence AS (
  SELECT
    billing_month,
    month_start,
    month_end,
    days_in_month,
    imsi,
    COUNT(DISTINCT presence_d) AS presence_days,
    MIN(presence_d) AS first_seen_d,
    MAX(presence_d) AS last_seen_d,
    CASE WHEN MIN(presence_d) = month_start
           AND MAX(presence_d) = month_end
           AND COUNT(DISTINCT presence_d) = days_in_month
         THEN days_in_month ELSE COUNT(DISTINCT presence_d) END AS base_presence_days,
    MIN(cycle_start_ts) AS min_cycle_start_ts_raw,
    MAX(cycle_start_ts) AS max_cycle_start_ts_raw,
    MIN(cycle_end_ts) AS min_cycle_end_ts_raw,
    MAX(cycle_end_ts) AS max_cycle_end_ts_raw,
    MIN(CASE WHEN CAST(cycle_start_ts AS DATE) > month_start THEN CAST(cycle_start_ts AS DATE) END) AS min_cycle_start_after_month_start,
    MAX(CAST(cycle_end_ts AS DATE)) AS max_cycle_end_d
  FROM snap
  GROUP BY billing_month, month_start, month_end, days_in_month, imsi
), card_products AS (
  SELECT DISTINCT billing_month, imsi, product_id
  FROM snap
), product_map AS (
  SELECT DISTINCT
    CAST(product_id AS STRING) AS product_id,
    supplier_id,
    package_price
  FROM simo_prod.ods.resource_res_vsim_product
), mapped AS (
  SELECT
    cp.billing_month,
    cp.imsi,
    COUNT(DISTINCT cp.product_id) AS distinct_product_id_count,
    COUNT(DISTINCT CASE WHEN pm.supplier_id = 2275 THEN cp.product_id END) AS wa_product_id_count,
    COUNT(DISTINCT CASE WHEN pm.product_id IS NULL THEN cp.product_id END) AS missing_product_id_count,
    COUNT(DISTINCT CASE WHEN pm.supplier_id = 2275 THEN pm.package_price END) AS distinct_wa_package_price_count,
    SORT_ARRAY(COLLECT_SET(CASE WHEN pm.supplier_id = 2275 THEN CAST(pm.package_price AS STRING) END)) AS wa_package_prices_observed,
    SORT_ARRAY(COLLECT_SET(CASE WHEN pm.supplier_id = 2275 THEN cp.product_id END)) AS wa_product_ids_observed
  FROM card_products cp
  LEFT JOIN product_map pm ON pm.product_id = cp.product_id
  GROUP BY cp.billing_month, cp.imsi
), cycle_events AS (
  SELECT
    p.billing_month,
    p.imsi,
    COUNT(*) AS cycle_event_count_all_window,
    SUM(CASE WHEN CAST(h.next_cycle_time - INTERVAL 5 HOURS AS DATE) BETWEEN p.month_start AND p.month_end THEN 1 ELSE 0 END) AS cycle_event_count_in_month,
    MIN(CASE WHEN CAST(h.next_cycle_time - INTERVAL 5 HOURS AS DATE) BETWEEN p.month_start AND p.month_end
             THEN CAST(h.next_cycle_time - INTERVAL 5 HOURS AS DATE) END) AS cycle_start_d5
  FROM presence p
  JOIN simo_prod.ods.resource_res_vsim_cycle_history h ON h.imsi = p.imsi
  WHERE h.next_cycle_time >= TIMESTAMP('2025-05-01 00:00:00')
    AND h.next_cycle_time < TIMESTAMP('2026-01-15 00:00:00')
  GROUP BY p.billing_month, p.imsi
), status_events AS (
  SELECT
    p.billing_month,
    p.imsi,
    SUM(CASE WHEN l.NEXT_STATUS = '作废'
               AND CAST(l.CREATE_DATE - INTERVAL 5 HOURS AS DATE) BETWEEN p.month_start AND p.month_end
             THEN 1 ELSE 0 END) AS offstock_event_count_in_month,
    MIN(CASE WHEN l.NEXT_STATUS = '作废'
               AND CAST(l.CREATE_DATE - INTERVAL 5 HOURS AS DATE) BETWEEN p.month_start AND DATE_ADD(p.month_end, 30)
             THEN CAST(l.CREATE_DATE - INTERVAL 5 HOURS AS DATE) END) AS offstock_d5,
    MAX(CASE WHEN l.NEXT_STATUS = '激活'
               AND l.CREATE_DATE - INTERVAL 5 HOURS >= CAST(p.month_start AS TIMESTAMP) - INTERVAL 120 DAYS
               AND l.CREATE_DATE - INTERVAL 5 HOURS < CAST(p.month_end AS TIMESTAMP) + INTERVAL 41 DAYS
             THEN CAST(l.CREATE_DATE - INTERVAL 5 HOURS AS DATE) END) AS activation_d5,
    SUM(CASE WHEN l.NEXT_STATUS = '激活'
               AND l.CREATE_DATE - INTERVAL 5 HOURS >= CAST(p.month_start AS TIMESTAMP) - INTERVAL 120 DAYS
               AND l.CREATE_DATE - INTERVAL 5 HOURS < CAST(p.month_end AS TIMESTAMP) + INTERVAL 41 DAYS
             THEN 1 ELSE 0 END) AS activation_event_count_in_window
  FROM presence p
  LEFT JOIN simo_prod.ods.resource_res_vsim_status_log l
    ON l.IMSI = p.imsi
   AND l.CREATE_DATE >= TIMESTAMP('2025-05-01 00:00:00')
   AND l.CREATE_DATE < TIMESTAMP('2026-01-15 00:00:00')
  GROUP BY p.billing_month, p.imsi
)
SELECT
  p.billing_month,
  p.imsi,
  p.presence_days,
  p.first_seen_d,
  p.last_seen_d,
  p.base_presence_days,
  p.min_cycle_start_ts_raw,
  p.max_cycle_start_ts_raw,
  p.min_cycle_end_ts_raw,
  p.max_cycle_end_ts_raw,
  p.min_cycle_start_after_month_start,
  p.max_cycle_end_d,
  COALESCE(m.distinct_product_id_count, 0) AS distinct_product_id_count,
  COALESCE(m.wa_product_id_count, 0) AS wa_product_id_count,
  COALESCE(m.missing_product_id_count, 0) AS missing_product_id_count,
  COALESCE(m.distinct_wa_package_price_count, 0) AS distinct_wa_package_price_count,
  CONCAT_WS(',', m.wa_package_prices_observed) AS wa_package_prices_observed,
  CONCAT_WS(',', m.wa_product_ids_observed) AS wa_product_ids_observed,
  CASE
    WHEN COALESCE(m.wa_product_id_count, 0) > 0 AND COALESCE(m.missing_product_id_count, 0) = 0 THEN 'WA_PRODUCT_MATCH'
    WHEN COALESCE(m.missing_product_id_count, 0) > 0 THEN 'MISSING_MAPPING'
    ELSE 'NON_WA_OR_UNMAPPED'
  END AS platform_scope_status,
  CASE WHEN COALESCE(m.distinct_wa_package_price_count, 0) = 1
       THEN CAST(ELEMENT_AT(m.wa_package_prices_observed, 1) AS DOUBLE) END AS platform_price_if_unique,
  COALESCE(ce.cycle_event_count_all_window, 0) AS cycle_event_count_all_window,
  COALESCE(ce.cycle_event_count_in_month, 0) AS cycle_event_count_in_month,
  ce.cycle_start_d5,
  COALESCE(se.offstock_event_count_in_month, 0) AS offstock_event_count_in_month,
  se.offstock_d5,
  se.activation_d5,
  COALESCE(se.activation_event_count_in_window, 0) AS activation_event_count_in_window
FROM presence p
LEFT JOIN mapped m ON m.billing_month = p.billing_month AND m.imsi = p.imsi
LEFT JOIN cycle_events ce ON ce.billing_month = p.billing_month AND ce.imsi = p.imsi
LEFT JOIN status_events se ON se.billing_month = p.billing_month AND se.imsi = p.imsi
WHERE p.billing_month = '2025-10' AND COALESCE(m.wa_product_id_count, 0) > 0 AND COALESCE(m.missing_product_id_count, 0) = 0
ORDER BY p.billing_month, p.imsi;