EXPLAIN WITH cfg AS (
  SELECT '2025-10' AS billing_month, 2025 AS y, 10 AS m,
         DATE('2025-10-01') AS month_start, DATE('2025-10-31') AS month_end,
         31 AS days_in_month,
         TIMESTAMP('2025-05-01 00:00:00') AS event_window_start_ts,
         TIMESTAMP('2026-01-15 00:00:00') AS event_window_end_ts
), inv_base AS (
  SELECT
    c.billing_month, c.month_start, c.month_end, c.days_in_month,
    x.imsi,
    CAST(NULL AS STRING) AS excel_product_id,
    x.product_name AS excel_product_name,
    x.iccid AS excel_iccid,
    x.charge_type,
    TRY_CAST(x.final_start_date AS DATE) AS xl_start_d,
    TRY_CAST(x.final_end_date AS DATE) AS xl_end_d,
    TRY_CAST(x.final_days AS DOUBLE) AS xl_days,
    TRY_CAST(x.active_days AS DOUBLE) AS xl_active_days,
    TRY_CAST(x.usage_days AS DOUBLE) AS xl_usage_days,
    TRY_CAST(x.monthly_rate AS DOUBLE) AS xl_rate,
    TRY_CAST(x.final_charge AS DOUBLE) AS xl_charge,
    TRY_CAST(x.offstock_date AS DATE) AS xl_offstock_d,
    TRY_CAST(x.new_activation_date AS DATE) AS xl_activation_d,
    x.transferred_to_wing_simbank,
    x.note,
    x.source_file,
    ROW_NUMBER() OVER (PARTITION BY c.billing_month, x.imsi ORDER BY x.charge_type) AS invoice_line_no
  FROM cfg c
  JOIN simo_prod.mysql_cdc_sync.wa_invoice_detail x
    ON TRY_CAST(x.final_start_date AS DATE) BETWEEN c.month_start AND c.month_end
), product_map AS (
  SELECT
    c.billing_month,
    CAST(p.product_id AS STRING) AS product_id,
    p.product_name AS platform_product_name,
    p.supplier_id,
    p.package_price AS platform_package_price,
    p.create_time AS platform_product_create_time,
    p.modify_time AS platform_product_modify_time
  FROM cfg c
  JOIN simo_prod.ods.resource_res_vsim_product p
    ON p.supplier_id = 2275
), snap_wa AS (
  SELECT
    c.billing_month, c.month_start, c.month_end, c.days_in_month,
    c.event_window_start_ts, c.event_window_end_ts,
    s.imsi,
    CAST(s.product_id AS STRING) AS product_id,
    pm.platform_product_name,
    pm.platform_package_price,
    pm.platform_product_create_time,
    pm.platform_product_modify_time,
    CAST(s.partition_time AS DATE) AS presence_d,
    TRY_CAST(s.Cycle_Start_Time AS TIMESTAMP) AS cycle_start_ts,
    TRY_CAST(s.Cycle_End_Time AS TIMESTAMP) AS cycle_end_ts
  FROM cfg c
  JOIN simo_prod.tc_cdr.sim_status_for_sftp_bak s
    ON s.year = c.y AND s.month = c.m
  JOIN product_map pm
    ON pm.billing_month = c.billing_month
   AND pm.product_id = CAST(s.product_id AS STRING)
), presence AS (
  SELECT
    billing_month, month_start, month_end, days_in_month,
    event_window_start_ts, event_window_end_ts, imsi,
    COUNT(DISTINCT presence_d) AS presence_days,
    MIN(presence_d) AS first_seen_d,
    MAX(presence_d) AS last_seen_d,
    CASE WHEN MIN(presence_d) = month_start
           AND MAX(presence_d) = month_end
           AND COUNT(DISTINCT presence_d) = days_in_month
         THEN days_in_month ELSE COUNT(DISTINCT presence_d) END AS base_presence_days,
    MIN(CAST(cycle_start_ts AS DATE)) AS min_cycle_start_d_raw,
    MAX(CAST(cycle_end_ts AS DATE)) AS max_cycle_end_d
  FROM snap_wa
  GROUP BY billing_month, month_start, month_end, days_in_month,
           event_window_start_ts, event_window_end_ts, imsi
), mapped AS (
  SELECT
    billing_month, imsi,
    COUNT(DISTINCT product_id) AS distinct_product_id_count,
    COUNT(DISTINCT product_id) AS wa_product_id_count,
    CAST(0 AS BIGINT) AS missing_product_id_count,
    COUNT(DISTINCT platform_package_price) AS distinct_wa_package_price_count,
    SORT_ARRAY(COLLECT_SET(CAST(platform_package_price AS STRING))) AS wa_package_prices_observed,
    SORT_ARRAY(COLLECT_SET(product_id)) AS wa_product_ids_observed,
    SORT_ARRAY(COLLECT_SET(platform_product_name)) AS wa_product_names_observed,
    SORT_ARRAY(COLLECT_SET(CAST(platform_product_create_time AS STRING))) AS wa_product_create_times_observed,
    SORT_ARRAY(COLLECT_SET(CAST(platform_product_modify_time AS STRING))) AS wa_product_modify_times_observed
  FROM snap_wa
  GROUP BY billing_month, imsi
), cycle_events AS (
  SELECT
    p.billing_month, p.imsi,
    COUNT(*) AS cycle_event_count_all_window,
    SUM(CASE WHEN CAST(h.next_cycle_time - INTERVAL 5 HOURS AS DATE)
                  BETWEEN p.month_start AND p.month_end THEN 1 ELSE 0 END) AS cycle_event_count_in_month,
    MIN(CASE WHEN CAST(h.next_cycle_time - INTERVAL 5 HOURS AS DATE)
                  BETWEEN p.month_start AND p.month_end
             THEN CAST(h.next_cycle_time - INTERVAL 5 HOURS AS DATE) END) AS cycle_start_d5
  FROM presence p
  JOIN simo_prod.ods.resource_res_vsim_cycle_history h
    ON h.imsi = p.imsi
  WHERE h.next_cycle_time >= TIMESTAMP('2025-05-01 00:00:00')
    AND h.next_cycle_time < TIMESTAMP('2026-01-15 00:00:00')
  GROUP BY p.billing_month, p.imsi
), status_events AS (
  SELECT
    p.billing_month, p.imsi,
    SUM(CASE WHEN l.NEXT_STATUS = '作废'
               AND CAST(l.CREATE_DATE - INTERVAL 5 HOURS AS DATE)
                   BETWEEN p.month_start AND p.month_end THEN 1 ELSE 0 END) AS offstock_event_count_in_month,
    MIN(CASE WHEN l.NEXT_STATUS = '作废'
               AND CAST(l.CREATE_DATE - INTERVAL 5 HOURS AS DATE)
                   BETWEEN p.month_start AND DATE_ADD(p.month_end, 30)
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
), platform AS (
  SELECT
    p.billing_month, p.imsi,
    p.presence_days, p.first_seen_d, p.last_seen_d, p.base_presence_days,
    p.min_cycle_start_d_raw, p.max_cycle_end_d,
    p.event_window_start_ts, p.event_window_end_ts,
    m.distinct_product_id_count, m.wa_product_id_count,
    m.missing_product_id_count, m.distinct_wa_package_price_count,
    CONCAT_WS(',', m.wa_package_prices_observed) AS wa_package_prices_observed,
    CONCAT_WS(',', m.wa_product_ids_observed) AS wa_product_ids_observed,
    CONCAT_WS(',', m.wa_product_names_observed) AS wa_product_names_observed,
    CONCAT_WS(',', m.wa_product_create_times_observed) AS wa_product_create_times_observed,
    CONCAT_WS(',', m.wa_product_modify_times_observed) AS wa_product_modify_times_observed,
    CASE WHEN m.distinct_wa_package_price_count = 1
         THEN CAST(ELEMENT_AT(m.wa_package_prices_observed, 1) AS DOUBLE) END AS platform_price_if_unique,
    'NO_HISTORICAL_EFFECTIVE_INTERVAL_IN_RESOURCE_RES_VSIM_PRODUCT'
      AS platform_price_effective_condition_status,
    COALESCE(ce.cycle_event_count_all_window, 0) AS cycle_event_count_all_window,
    COALESCE(ce.cycle_event_count_in_month, 0) AS cycle_event_count_in_month,
    ce.cycle_start_d5,
    COALESCE(se.offstock_event_count_in_month, 0) AS offstock_event_count_in_month,
    se.offstock_d5, se.activation_d5,
    COALESCE(se.activation_event_count_in_window, 0) AS activation_event_count_in_window
  FROM presence p
  JOIN mapped m ON m.billing_month = p.billing_month AND m.imsi = p.imsi
  LEFT JOIN cycle_events ce ON ce.billing_month = p.billing_month AND ce.imsi = p.imsi
  LEFT JOIN status_events se ON se.billing_month = p.billing_month AND se.imsi = p.imsi
), joined AS (
  SELECT
    COALESCE(i.billing_month, p.billing_month) AS billing_month,
    COALESCE(i.imsi, p.imsi) AS imsi,
    i.invoice_line_no,
    i.excel_product_id, i.excel_product_name, i.excel_iccid,
    i.charge_type, i.xl_start_d, i.xl_end_d, i.xl_days,
    i.xl_active_days, i.xl_usage_days, i.xl_rate, i.xl_charge,
    i.xl_offstock_d, i.xl_activation_d,
    i.transferred_to_wing_simbank, i.note, i.source_file,
    i.month_start, i.month_end, i.days_in_month,
    p.presence_days, p.first_seen_d, p.last_seen_d, p.base_presence_days,
    p.min_cycle_start_d_raw, p.max_cycle_end_d,
    p.event_window_start_ts, p.event_window_end_ts,
    p.distinct_product_id_count, p.wa_product_id_count,
    p.missing_product_id_count, p.distinct_wa_package_price_count,
    p.wa_package_prices_observed, p.wa_product_ids_observed,
    p.wa_product_names_observed, p.wa_product_create_times_observed,
    p.wa_product_modify_times_observed, p.platform_price_if_unique,
    p.platform_price_effective_condition_status,
    p.cycle_event_count_all_window, p.cycle_event_count_in_month,
    p.cycle_start_d5, p.offstock_event_count_in_month, p.offstock_d5,
    p.activation_d5, p.activation_event_count_in_window,
    CASE WHEN i.imsi IS NOT NULL AND p.imsi IS NOT NULL THEN 'MATCHED'
         WHEN i.imsi IS NOT NULL THEN 'WA_ONLY' ELSE 'PLATFORM_ONLY' END AS join_status,
    CASE WHEN i.charge_type = 'Full Cycle Charge' THEN 'G_FULL_MONTH_CALENDAR'
         WHEN i.charge_type LIKE 'Prorated-out%' THEN 'C_CYCLE_START_TO_OFFSTOCK'
         WHEN i.charge_type LIKE 'New Activation%' THEN 'E_ACTIVATION_TO_CYCLE_END'
         ELSE 'UNRESOLVED_CHARGE_TYPE' END AS candidate_rule,
    CASE WHEN i.charge_type = 'Full Cycle Charge' THEN i.month_start
         WHEN i.charge_type LIKE 'Prorated-out%' THEN p.cycle_start_d5
         WHEN i.charge_type LIKE 'New Activation%' THEN p.activation_d5 END AS candidate_start_d,
    CASE WHEN i.charge_type = 'Full Cycle Charge' THEN i.month_end
         WHEN i.charge_type LIKE 'Prorated-out%' THEN p.offstock_d5
         WHEN i.charge_type LIKE 'New Activation%' THEN DATE_SUB(p.max_cycle_end_d, 1) END AS candidate_end_d,
    CASE WHEN i.charge_type = 'Full Cycle Charge' THEN i.days_in_month
         WHEN i.charge_type LIKE 'Prorated-out%'
          AND p.cycle_start_d5 IS NOT NULL AND p.offstock_d5 IS NOT NULL
          AND p.offstock_d5 >= p.cycle_start_d5
           THEN DATEDIFF(p.offstock_d5, p.cycle_start_d5) + 1
         WHEN i.charge_type LIKE 'New Activation%'
          AND p.activation_d5 IS NOT NULL AND p.max_cycle_end_d IS NOT NULL
          AND DATE_SUB(p.max_cycle_end_d, 1) >= p.activation_d5
           THEN DATEDIFF(DATE_SUB(p.max_cycle_end_d, 1), p.activation_d5) + 1 END AS candidate_days,
    CASE WHEN i.charge_type LIKE 'New Activation%'
          AND p.activation_d5 IS NOT NULL AND p.max_cycle_end_d IS NOT NULL
          AND DATE_SUB(p.max_cycle_end_d, 1) >= p.activation_d5
           THEN DATEDIFF(DATE_SUB(p.max_cycle_end_d, 1), DATE_ADD(p.activation_d5, 1)) + 1 END AS candidate_days_plus1_minus1,
    CASE WHEN i.charge_type LIKE 'New Activation%'
          AND p.activation_d5 IS NOT NULL AND p.max_cycle_end_d IS NOT NULL
          AND DATE_SUB(p.max_cycle_end_d, 1) >= p.activation_d5
           THEN DATEDIFF(p.max_cycle_end_d, p.activation_d5) + 1 END AS candidate_days_activation_end_inclusive
  FROM inv_base i
  FULL OUTER JOIN platform p
    ON i.billing_month = p.billing_month AND i.imsi = p.imsi
)
, detail AS (
  SELECT joined.*,
    candidate_days AS platform_calculated_days,
    platform_price_if_unique AS platform_calculated_price,
    CASE WHEN join_status = 'MATCHED' AND candidate_days IS NOT NULL AND platform_price_if_unique IS NOT NULL
         THEN ROUND(platform_price_if_unique / days_in_month * candidate_days, 4) END AS platform_calculated_amount,
    CASE WHEN join_status = 'MATCHED' AND candidate_days IS NOT NULL AND xl_days IS NOT NULL
         THEN candidate_days - xl_days END AS days_difference,
    CASE WHEN join_status = 'MATCHED' AND platform_price_if_unique IS NOT NULL AND xl_rate IS NOT NULL
         THEN platform_price_if_unique - xl_rate END AS price_difference,
    CASE WHEN join_status = 'MATCHED' AND candidate_days IS NOT NULL AND platform_price_if_unique IS NOT NULL AND xl_charge IS NOT NULL
         THEN ROUND(platform_price_if_unique / days_in_month * candidate_days - xl_charge, 4) END AS amount_difference,
    CASE WHEN candidate_start_d IS NULL OR candidate_end_d IS NULL THEN 'UNRESOLVED_MISSING_LIFECYCLE_FIELD' WHEN candidate_end_d < candidate_start_d THEN 'UNRESOLVED_INVALID_DATE_WINDOW' ELSE 'CANDIDATE_WINDOW_VALID' END AS candidate_window_status,
    CASE WHEN join_status <> 'MATCHED' THEN 'NOT_APPLICABLE'
         WHEN excel_product_id IS NULL THEN 'MISSING_MAPPING_EXCEL_PRODUCT_ID'
         ELSE 'MAPPED_BY_PRODUCT_ID_AND_MONTH' END AS product_mapping_status,
    CASE WHEN join_status <> 'MATCHED' THEN 'NOT_APPLICABLE'
         WHEN distinct_wa_package_price_count > 1 THEN 'UNRESOLVED_MULTIPLE_PLATFORM_PRICES'
         WHEN platform_price_if_unique IS NULL THEN 'MISSING_MAPPING_OR_PRICE'
         WHEN platform_price_effective_condition_status <> 'HISTORICAL_EFFECTIVE_CONDITION_CONFIRMED'
           THEN 'UNRESOLVED_NO_HISTORICAL_PRICE_EFFECTIVE_CONDITION'
         ELSE 'HISTORICAL_PRICE_EFFECTIVE_CONDITION_CONFIRMED' END AS platform_price_status,
    CASE WHEN join_status <> 'MATCHED' THEN 'NOT_APPLICABLE'
         WHEN charge_type IS NULL THEN 'NOT_APPLICABLE'
         WHEN candidate_days IS NULL THEN 'UNRESOLVED_MISSING_LIFECYCLE_FIELD'
         WHEN candidate_days = xl_days THEN 'EXACT_DAY_MATCH'
         ELSE 'DAY_MISMATCH' END AS day_validation_status,
    CASE WHEN join_status <> 'MATCHED' THEN 'NOT_APPLICABLE'
         WHEN distinct_wa_package_price_count > 1 THEN 'UNRESOLVED_MULTIPLE_PLATFORM_PRICES'
         WHEN platform_price_if_unique IS NULL THEN 'MISSING_MAPPING_OR_PRICE'
         WHEN platform_price_if_unique = xl_rate THEN 'PRICE_MATCH_OBSERVED'
         ELSE 'PRICE_MISMATCH_OBSERVED' END AS price_validation_status
  FROM joined
)
SELECT billing_month, imsi, invoice_line_no, excel_product_id, excel_product_name, excel_iccid,
  charge_type, join_status, xl_start_d, xl_end_d, xl_days, xl_rate, xl_charge,
  candidate_rule, candidate_start_d, candidate_end_d, candidate_days,
  candidate_days_plus1_minus1, candidate_days_activation_end_inclusive,
  platform_calculated_days, platform_calculated_price, platform_calculated_amount,
  days_difference, price_difference, amount_difference,
    CASE WHEN candidate_start_d IS NULL OR candidate_end_d IS NULL THEN 'UNRESOLVED_MISSING_LIFECYCLE_FIELD' WHEN candidate_end_d < candidate_start_d THEN 'UNRESOLVED_INVALID_DATE_WINDOW' ELSE 'CANDIDATE_WINDOW_VALID' END AS candidate_window_status,
  wa_product_ids_observed, wa_product_names_observed, wa_package_prices_observed,
  wa_product_create_times_observed, wa_product_modify_times_observed,
  product_mapping_status, platform_price_status, day_validation_status,
  price_validation_status, event_window_start_ts, event_window_end_ts,
  cycle_start_d5, max_cycle_end_d, offstock_d5, activation_d5, source_file
FROM detail
ORDER BY billing_month, COALESCE(imsi, ''), invoice_line_no;