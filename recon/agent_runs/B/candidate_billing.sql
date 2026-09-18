WITH cfg AS (
  SELECT '2025-12' AS billing_month, DATE '2025-12-01' AS month_start, LAST_DAY(DATE '2025-12-01') AS month_end, 2025 AS snap_year, 12 AS snap_month, 31 AS snap_day
  UNION ALL SELECT '2026-01', DATE '2026-01-01', LAST_DAY(DATE '2026-01-01'), 2026, 1, 31
  UNION ALL SELECT '2026-02', DATE '2026-02-01', LAST_DAY(DATE '2026-02-01'), 2026, 2, 28
), excel_detail_raw AS (
  SELECT c.billing_month, c.month_start, c.month_end,
         CAST(x.imsi AS STRING) AS imsi, CAST(x.iccid AS STRING) AS excel_iccid,
         CAST(NULL AS STRING) AS excel_product_id, CAST(x.product_name AS STRING) AS excel_product_name,
         CAST(x.charge_type AS STRING) AS charge_type,
         TRY_CAST(x.cycle_start_date AS DATE) AS excel_cycle_start_date,
         TRY_CAST(x.cycle_end_date AS DATE) AS excel_cycle_end_date,
         TRY_CAST(x.new_activation_date AS DATE) AS excel_new_activation_date,
         TRY_CAST(x.offstock_date AS DATE) AS excel_offstock_date,
         TRY_CAST(x.final_start_date AS DATE) AS excel_final_start_date,
         TRY_CAST(x.final_end_date AS DATE) AS excel_final_end_date,
         TRY_CAST(x.final_days AS DOUBLE) AS excel_days,
         TRY_CAST(x.monthly_rate AS DOUBLE) AS excel_price,
         TRY_CAST(x.final_charge AS DOUBLE) AS excel_amount,
         CAST(x.new_card_imsi_replacement AS STRING) AS new_card_imsi_replacement,
         CAST(x.old_card_imsi_replaced AS STRING) AS old_card_imsi_replaced,
         CAST(x.transferred_to_wing_simbank AS STRING) AS transferred_to_wing_simbank,
         CAST(x.source_file AS STRING) AS source_file, CAST(x.sheet_name AS STRING) AS sheet_name,
         ROW_NUMBER() OVER (PARTITION BY c.billing_month ORDER BY CAST(x.imsi AS STRING), TRY_CAST(x.final_start_date AS DATE), TRY_CAST(x.final_end_date AS DATE), CAST(x.charge_type AS STRING), CAST(x.source_file AS STRING), CAST(x.sheet_name AS STRING), CAST(x.iccid AS STRING), CAST(x.product_name AS STRING)) AS line_id
  FROM cfg c JOIN simo_prod.mysql_cdc_sync.wa_invoice_detail x
    ON TRY_CAST(x.final_start_date AS DATE) BETWEEN c.month_start AND c.month_end
  WHERE NULLIF(TRIM(CAST(x.imsi AS STRING)), '') IS NOT NULL
), excel_detail AS (
  SELECT *, DATEDIFF(excel_cycle_end_date, excel_cycle_start_date) + 1 AS excel_cycle_days,
         DATEDIFF(excel_final_end_date, excel_final_start_date) + 1 AS excel_date_span_days,
         CASE
           WHEN charge_type LIKE '%Full Cycle%' OR charge_type LIKE '%Backbilled%' THEN excel_price
           WHEN charge_type LIKE '%Prorated-Out%' THEN -excel_price * excel_days / NULLIF(DATEDIFF(excel_cycle_end_date, excel_cycle_start_date) + 1, 0)
           WHEN charge_type LIKE '%Credit%' THEN -excel_price * ((DATEDIFF(excel_cycle_end_date, excel_cycle_start_date) + 1) - excel_days) / NULLIF(DATEDIFF(excel_cycle_end_date, excel_cycle_start_date) + 1, 0)
           WHEN charge_type LIKE '%New Activation%' OR charge_type LIKE '%Product Transfer%' OR charge_type LIKE '%Card Replaced%' OR charge_type LIKE '%Replacement%' THEN excel_price * excel_days / NULLIF(DATEDIFF(excel_cycle_end_date, excel_cycle_start_date) + 1, 0)
           ELSE NULL END AS excel_formula_amount
  FROM excel_detail_raw
), excel_card AS (
  SELECT billing_month, imsi, COUNT(*) AS excel_line_count, COUNT(DISTINCT charge_type) AS excel_charge_type_count,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(charge_type))) AS excel_charge_types,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(excel_product_name))) AS excel_product_names,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(CAST(excel_days AS STRING)))) AS excel_days_values,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(CAST(excel_price AS STRING)))) AS excel_price_values,
         ROUND(SUM(excel_amount), 6) AS excel_amount, ROUND(SUM(excel_days), 6) AS excel_days,
         CASE WHEN COUNT(DISTINCT excel_price) = 1 THEN element_at(SORT_ARRAY(COLLECT_SET(excel_price)), 1) END AS excel_price,
         MIN(excel_final_start_date) AS excel_min_start_date, MAX(excel_final_end_date) AS excel_max_end_date
  FROM excel_detail GROUP BY billing_month, imsi
), product_values AS (
  SELECT CAST(product_id AS STRING) AS platform_product_id,
         CASE WHEN COUNT(DISTINCT CAST(supplier_id AS BIGINT)) = 1 THEN element_at(SORT_ARRAY(COLLECT_SET(CAST(supplier_id AS BIGINT))), 1) END AS supplier_id,
         CASE WHEN COUNT(DISTINCT CAST(product_name AS STRING)) = 1 THEN element_at(SORT_ARRAY(COLLECT_SET(CAST(product_name AS STRING))), 1) ELSE CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(CAST(product_name AS STRING)))) END AS platform_product_name,
         COUNT(DISTINCT CAST(supplier_id AS BIGINT)) AS supplier_id_count, COUNT(DISTINCT CAST(product_name AS STRING)) AS product_name_count,
         COUNT(DISTINCT monthly_rent) AS monthly_rent_count,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(CAST(ROUND(monthly_rent, 6) AS STRING)))) AS monthly_rent_values,
         CASE WHEN COUNT(DISTINCT monthly_rent) = 1 THEN element_at(SORT_ARRAY(COLLECT_SET(monthly_rent)), 1) END AS platform_price,
         COUNT(DISTINCT monthly_rent_withusd) AS monthly_rent_withusd_count,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(CAST(ROUND(monthly_rent_withusd, 6) AS STRING)))) AS monthly_rent_withusd_values,
         COUNT(DISTINCT package_price) AS package_price_count,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(CAST(ROUND(package_price, 6) AS STRING)))) AS package_price_values,
         COUNT(DISTINCT package_price_withusd) AS package_price_withusd_count,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(CAST(ROUND(package_price_withusd, 6) AS STRING)))) AS package_price_withusd_values,
         CASE
           WHEN COUNT(DISTINCT CAST(supplier_id AS BIGINT)) = 1 AND element_at(SORT_ARRAY(COLLECT_SET(CAST(supplier_id AS BIGINT))), 1) = 2275 AND LOWER(CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(CAST(product_name AS STRING))))) LIKE '%(wa)%' AND LOWER(CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(CAST(product_name AS STRING))))) NOT LIKE '%unassigned%' THEN 'KEEP_WA'
           WHEN COUNT(DISTINCT CAST(supplier_id AS BIGINT)) = 1 AND element_at(SORT_ARRAY(COLLECT_SET(CAST(supplier_id AS BIGINT))), 1) = 2275 AND LOWER(CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(CAST(product_name AS STRING))))) LIKE '%(pi)%' THEN 'EXCLUDE_PI'
           WHEN COUNT(DISTINCT CAST(supplier_id AS BIGINT)) = 1 AND element_at(SORT_ARRAY(COLLECT_SET(CAST(supplier_id AS BIGINT))), 1) = 2275 AND LOWER(CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(CAST(product_name AS STRING))))) LIKE '%unassigned%' THEN 'EXCLUDE_UNASSIGNED'
           ELSE 'EXCLUDE_SUPPLIER_NOT_2275_OR_MISSING' END AS product_scope_class
  FROM simo_prod.ods.resource_res_vsim_product GROUP BY CAST(product_id AS STRING)
), excel_imsis AS (SELECT DISTINCT billing_month, imsi FROM excel_card), snapshot_month_end AS (
  SELECT '2025-12' AS billing_month, CAST(imsi AS STRING) AS imsi, CAST(product_id AS STRING) AS platform_product_id, CAST(partition_time AS DATE) AS snapshot_date FROM simo_prod.tc_cdr.sim_status_for_sftp_bak WHERE year = 2025 AND month = 12 AND day = 31
  UNION ALL SELECT '2026-01', CAST(imsi AS STRING), CAST(product_id AS STRING), CAST(partition_time AS DATE) FROM simo_prod.tc_cdr.sim_status_for_sftp_bak WHERE year = 2026 AND month = 1 AND day = 31
  UNION ALL SELECT '2026-02', CAST(imsi AS STRING), CAST(product_id AS STRING), CAST(partition_time AS DATE) FROM simo_prod.tc_cdr.sim_status_for_sftp_bak WHERE year = 2026 AND month = 2 AND day = 28
), seed_cycle AS (
  SELECT DISTINCT e.billing_month, e.imsi, CAST(h.product_id AS STRING) AS platform_product_id, 'cycle_history_same_local_start' AS seed_source
  FROM excel_detail e JOIN simo_prod.ods.resource_res_vsim_cycle_history h
    ON CAST(h.imsi AS STRING) = e.imsi AND CAST(h.cycle_time - INTERVAL 5 HOURS AS DATE) = e.excel_final_start_date
), seed_snapshot AS (
  SELECT DISTINCT e.billing_month, e.imsi, s.platform_product_id, 'month_end_snapshot' AS seed_source
  FROM excel_imsis e JOIN snapshot_month_end s ON s.billing_month = e.billing_month AND s.imsi = e.imsi
), seed_product_ids AS (
  SELECT DISTINCT billing_month, platform_product_id FROM seed_cycle
  UNION SELECT DISTINCT billing_month, platform_product_id FROM seed_snapshot
), platform_snapshot_all AS (
  SELECT DISTINCT s.billing_month, s.imsi, s.platform_product_id, 'tc_cdr.sim_status_for_sftp_bak' AS source_table, s.snapshot_date
  FROM snapshot_month_end s JOIN seed_product_ids k ON k.billing_month = s.billing_month AND k.platform_product_id = s.platform_product_id
  WHERE NULLIF(TRIM(s.imsi), '') IS NOT NULL
), platform_cycle_all AS (
  SELECT DISTINCT c.billing_month, CAST(h.imsi AS STRING) AS imsi, CAST(h.product_id AS STRING) AS platform_product_id,
         'ods.resource_res_vsim_cycle_history' AS source_table,
         CAST(h.cycle_time - INTERVAL 5 HOURS AS DATE) AS segment_start_date,
         CAST(h.next_cycle_time - INTERVAL 5 HOURS AS DATE) AS next_cycle_date,
         CASE WHEN h.next_cycle_time IS NULL THEN c.month_end ELSE DATE_SUB(CAST(h.next_cycle_time - INTERVAL 5 HOURS AS DATE), 1) END AS segment_end_date
  FROM cfg c JOIN simo_prod.ods.resource_res_vsim_cycle_history h
    ON h.cycle_time < CAST(c.month_end AS TIMESTAMP) + INTERVAL 1 DAY
   AND COALESCE(h.next_cycle_time, TIMESTAMP '9999-12-31 00:00:00') >= CAST(c.month_start AS TIMESTAMP)
  JOIN seed_product_ids k ON k.billing_month = c.billing_month AND k.platform_product_id = CAST(h.product_id AS STRING)
  WHERE NULLIF(TRIM(CAST(h.imsi AS STRING)), '') IS NOT NULL
), platform_source_rows_all AS (
  SELECT billing_month, imsi, platform_product_id, source_table, CAST(NULL AS DATE) AS segment_start_date, CAST(NULL AS DATE) AS next_cycle_date, CAST(NULL AS DATE) AS segment_end_date FROM platform_snapshot_all
  UNION ALL
  SELECT billing_month, imsi, platform_product_id, source_table, segment_start_date, next_cycle_date, segment_end_date FROM platform_cycle_all
), platform_source_rows_enriched AS (
  SELECT a.billing_month, a.imsi, a.platform_product_id, a.source_table, a.segment_start_date, a.next_cycle_date, a.segment_end_date,
         p.platform_product_name, p.supplier_id, p.monthly_rent_count, p.monthly_rent_values, p.platform_price,
         p.monthly_rent_withusd_values, p.package_price_values, p.package_price_withusd_values, p.product_scope_class
  FROM platform_source_rows_all a LEFT JOIN product_values p ON p.platform_product_id = a.platform_product_id
), platform_keep_rows AS (
  SELECT * FROM platform_source_rows_enriched WHERE product_scope_class = 'KEEP_WA'
), platform_excluded_summary AS (
  SELECT billing_month, imsi,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(platform_product_id))) AS excluded_platform_product_ids,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(COALESCE(platform_product_name, '<MISSING_PRODUCT_ID>')))) AS excluded_platform_product_names,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(COALESCE(CAST(supplier_id AS STRING), '<NULL>')))) AS excluded_supplier_ids,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(COALESCE(product_scope_class, 'MISSING_PRODUCT_MAPPING')))) AS excluded_reasons,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(source_table))) AS excluded_source_tables
  FROM platform_source_rows_enriched
  WHERE product_scope_class <> 'KEEP_WA' OR product_scope_class IS NULL
  GROUP BY billing_month, imsi
), cycle_segments AS (
  SELECT r.billing_month, r.imsi, r.platform_product_id, p.platform_product_name, p.supplier_id,
         r.segment_start_date, r.next_cycle_date, r.segment_end_date,
         CASE WHEN r.segment_start_date <= c.month_end AND r.segment_end_date >= c.month_start THEN DATEDIFF(LEAST(r.segment_end_date, c.month_end), GREATEST(r.segment_start_date, c.month_start)) + 1 END AS platform_month_days,
         p.monthly_rent_count, p.monthly_rent_values, p.platform_price, p.product_scope_class
  FROM platform_cycle_all r JOIN cfg c ON c.billing_month = r.billing_month
  JOIN product_values p ON p.platform_product_id = r.platform_product_id AND p.product_scope_class = 'KEEP_WA'
  WHERE r.segment_start_date <= c.month_end AND r.segment_end_date >= c.month_start
), cycle_card_agg AS (
  SELECT billing_month, imsi, COUNT(*) AS cycle_segment_count, SUM(platform_month_days) AS cycle_platform_days,
         COUNT(DISTINCT platform_product_id) AS cycle_platform_product_count,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(platform_product_id))) AS cycle_platform_product_ids,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(platform_product_name))) AS cycle_platform_product_names,
         COUNT(DISTINCT platform_price) AS cycle_price_count,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(CAST(platform_price AS STRING)))) AS cycle_price_values,
         SUM(CASE WHEN platform_price IS NULL THEN 1 ELSE 0 END) AS cycle_missing_price_segments,
         CASE WHEN COUNT(DISTINCT platform_price) = 1 AND SUM(CASE WHEN platform_price IS NULL THEN 1 ELSE 0 END) = 0 THEN element_at(SORT_ARRAY(COLLECT_SET(platform_price)), 1) END AS cycle_platform_price,
         MIN(segment_start_date) AS cycle_min_start_date, MAX(segment_end_date) AS cycle_max_end_date
  FROM cycle_segments GROUP BY billing_month, imsi
), snapshot_card_agg AS (
  SELECT r.billing_month, r.imsi, COUNT(DISTINCT r.platform_product_id) AS snapshot_product_count,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(r.platform_product_id))) AS snapshot_product_ids,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(r.platform_product_name))) AS snapshot_product_names,
         COUNT(DISTINCT r.platform_price) AS snapshot_price_count,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(CAST(r.platform_price AS STRING)))) AS snapshot_price_values,
         CASE WHEN COUNT(DISTINCT r.platform_price) = 1 THEN element_at(SORT_ARRAY(COLLECT_SET(r.platform_price)), 1) END AS snapshot_platform_price
  FROM platform_keep_rows r WHERE r.source_table = 'tc_cdr.sim_status_for_sftp_bak'
  GROUP BY r.billing_month, r.imsi
),platform_cards AS (
  SELECT r.billing_month, r.imsi, COUNT(DISTINCT r.platform_product_id) AS platform_product_count,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(r.platform_product_id))) AS platform_product_ids,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(r.platform_product_name))) AS platform_product_names,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(CAST(r.supplier_id AS STRING)))) AS platform_supplier_ids,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(r.source_table))) AS platform_source_tables,
         COALESCE(c.cycle_segment_count, 0) AS cycle_segment_count, COALESCE(c.cycle_platform_days, 0) AS cycle_platform_days,
         CASE WHEN c.cycle_segment_count > 0 AND c.cycle_price_count = 1 AND c.cycle_missing_price_segments = 0 THEN c.cycle_platform_price
              WHEN COALESCE(c.cycle_segment_count, 0) = 0 AND s.snapshot_price_count = 1 THEN s.snapshot_platform_price END AS platform_calculated_price,
         CASE WHEN c.cycle_segment_count > 0 THEN c.cycle_platform_days ELSE DAY(cfg.month_end) END AS platform_calculated_days,
         CASE WHEN c.cycle_segment_count > 0 AND c.cycle_price_count = 1 AND c.cycle_missing_price_segments = 0 THEN 'CYCLE_HISTORY_OVERLAP'
              WHEN COALESCE(c.cycle_segment_count, 0) = 0 AND s.snapshot_price_count = 1 THEN 'MONTH_END_SNAPSHOT_FULL_MONTH_FALLBACK'
              WHEN COALESCE(c.cycle_segment_count, 0) = 0 THEN 'MISSING_CYCLE_AND_AMBIGUOUS_OR_MISSING_SNAPSHOT_PRICE'
              ELSE 'MULTIPLE_OR_MISSING_CYCLE_PRICE' END AS platform_calculated_amount_rule,
         c.cycle_price_count, c.cycle_price_values, c.cycle_missing_price_segments, s.snapshot_price_count, s.snapshot_price_values,
         ex.excluded_platform_product_ids, ex.excluded_platform_product_names, ex.excluded_supplier_ids, ex.excluded_reasons, ex.excluded_source_tables,
         CASE WHEN ex.imsi IS NULL THEN 'KEEP_WA_SUPPLIER_2275_AND_NAME_WA' ELSE 'KEEP_WA_WITH_EXCLUDED_PI_OR_UNASSIGNED_OBSERVATIONS' END AS platform_scope_reason
  FROM platform_keep_rows r JOIN cfg ON cfg.billing_month = r.billing_month
  LEFT JOIN cycle_card_agg c ON c.billing_month = r.billing_month AND c.imsi = r.imsi
  LEFT JOIN snapshot_card_agg s ON s.billing_month = r.billing_month AND s.imsi = r.imsi
  LEFT JOIN platform_excluded_summary ex ON ex.billing_month = r.billing_month AND ex.imsi = r.imsi
  GROUP BY r.billing_month, r.imsi, c.cycle_segment_count, c.cycle_platform_days, c.cycle_price_count, c.cycle_missing_price_segments, c.cycle_platform_price, c.cycle_price_values, s.snapshot_platform_price, s.snapshot_price_count, s.snapshot_price_values, cfg.month_end, ex.imsi, ex.excluded_platform_product_ids, ex.excluded_platform_product_names, ex.excluded_supplier_ids, ex.excluded_reasons, ex.excluded_source_tables
), line_cycle_joined AS (
  SELECT e.line_id, c.billing_month, c.imsi, c.platform_product_id, c.platform_product_name, c.supplier_id, c.segment_start_date, c.segment_end_date, c.platform_month_days, c.platform_price
  FROM excel_detail e LEFT JOIN cycle_segments c
    ON c.billing_month = e.billing_month AND c.imsi = e.imsi
   AND c.segment_start_date <= e.excel_final_end_date AND c.segment_end_date >= e.excel_final_start_date
), line_cycle_calc AS (
  SELECT line_id, COUNT(platform_product_id) AS line_cycle_segment_count, SUM(platform_month_days) AS line_cycle_month_days,
         COUNT(DISTINCT platform_product_id) AS line_cycle_product_count,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(platform_product_id))) AS line_cycle_product_ids,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(platform_product_name))) AS line_cycle_product_names,
         COUNT(DISTINCT platform_price) AS line_cycle_price_count,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(CAST(platform_price AS STRING)))) AS line_cycle_price_values,
         SUM(CASE WHEN platform_product_id IS NOT NULL AND platform_price IS NULL THEN 1 ELSE 0 END) AS line_cycle_missing_price_segments,
         CASE WHEN COUNT(DISTINCT platform_price) = 1 AND SUM(CASE WHEN platform_product_id IS NOT NULL AND platform_price IS NULL THEN 1 ELSE 0 END) = 0 THEN element_at(SORT_ARRAY(COLLECT_SET(platform_price)), 1) END AS line_cycle_price,
         MIN(CASE WHEN platform_product_id IS NOT NULL THEN segment_start_date END) AS line_cycle_min_start_date,
         MAX(CASE WHEN platform_product_id IS NOT NULL THEN segment_end_date END) AS line_cycle_max_end_date
  FROM line_cycle_joined GROUP BY line_id
), activation_ranked AS (
  SELECT e.line_id, CAST(l.CREATE_DATE - INTERVAL 5 HOURS AS DATE) AS activation_event_date,
         ABS(DATEDIFF(CAST(l.CREATE_DATE - INTERVAL 5 HOURS AS DATE), e.excel_final_start_date)) AS activation_day_delta,
         ROW_NUMBER() OVER (PARTITION BY e.line_id ORDER BY ABS(DATEDIFF(CAST(l.CREATE_DATE - INTERVAL 5 HOURS AS DATE), e.excel_final_start_date)), l.CREATE_DATE DESC) AS rn
  FROM excel_detail e JOIN simo_prod.ods.resource_res_vsim_status_log l
    ON CAST(l.IMSI AS STRING) = e.imsi AND l.NEXT_STATUS = '激活'
   AND l.CREATE_DATE >= CAST(DATE_SUB(e.month_start, 120) AS TIMESTAMP)
   AND l.CREATE_DATE < CAST(DATE_ADD(e.month_end, 46) AS TIMESTAMP)
), activation_best AS (SELECT line_id, activation_event_date, activation_day_delta FROM activation_ranked WHERE rn = 1),
void_ranked AS (
  SELECT e.line_id, CAST(l.CREATE_DATE - INTERVAL 5 HOURS AS DATE) AS void_event_date,
         ABS(DATEDIFF(CAST(l.CREATE_DATE - INTERVAL 5 HOURS AS DATE), e.excel_final_end_date)) AS void_day_delta,
         ROW_NUMBER() OVER (PARTITION BY e.line_id ORDER BY ABS(DATEDIFF(CAST(l.CREATE_DATE - INTERVAL 5 HOURS AS DATE), e.excel_final_end_date)), l.CREATE_DATE ASC) AS rn
  FROM excel_detail e JOIN simo_prod.ods.resource_res_vsim_status_log l
    ON CAST(l.IMSI AS STRING) = e.imsi AND l.NEXT_STATUS = '作废'
   AND l.CREATE_DATE >= CAST(DATE_SUB(e.month_start, 2) AS TIMESTAMP)
   AND l.CREATE_DATE < CAST(DATE_ADD(e.month_end, 46) AS TIMESTAMP)
), void_best AS (SELECT line_id, void_event_date, void_day_delta FROM void_ranked WHERE rn = 1),transition_history AS (
  SELECT CAST(h.imsi AS STRING) AS imsi, CAST(h.product_id AS STRING) AS new_product_id,
         CAST(LAG(h.product_id) OVER (PARTITION BY h.imsi ORDER BY h.cycle_time, h.product_id) AS STRING) AS old_product_id,
         CAST(h.cycle_time - INTERVAL 5 HOURS AS DATE) AS transition_date
  FROM simo_prod.ods.resource_res_vsim_cycle_history h
  JOIN (SELECT DISTINCT imsi FROM excel_imsis) i ON i.imsi = CAST(h.imsi AS STRING)
  WHERE h.cycle_time >= TIMESTAMP '2025-08-01 00:00:00' AND h.cycle_time < TIMESTAMP '2026-04-15 00:00:00'
), transition_candidates AS (
  SELECT e.line_id, t.transition_date, t.old_product_id, t.new_product_id, p.platform_product_name, p.platform_price,
         CASE WHEN t.transition_date = e.excel_final_start_date OR t.transition_date = DATE_ADD(e.excel_final_end_date, 1) THEN 1 ELSE 0 END AS boundary_flag
  FROM excel_detail e JOIN transition_history t ON t.imsi = e.imsi
   AND t.old_product_id IS NOT NULL AND t.old_product_id <> t.new_product_id
   AND t.transition_date BETWEEN DATE_SUB(e.excel_final_start_date, 2) AND DATE_ADD(e.excel_final_end_date, 2)
  LEFT JOIN product_values p ON p.platform_product_id = t.new_product_id
), transition_calc AS (
  SELECT line_id, COUNT(*) AS transition_evidence_count, SUM(boundary_flag) AS transition_boundary_count,
         COUNT(DISTINCT new_product_id) AS transition_product_count,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(CAST(transition_date AS STRING)))) AS transition_dates,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(old_product_id))) AS transition_old_product_ids,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(new_product_id))) AS transition_new_product_ids,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(platform_product_name))) AS transition_new_product_names,
         COUNT(DISTINCT platform_price) AS transition_price_count,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(CAST(platform_price AS STRING)))) AS transition_price_values,
         SUM(CASE WHEN platform_price IS NULL THEN 1 ELSE 0 END) AS transition_missing_price_rows,
         CASE WHEN SUM(boundary_flag) = 1 AND COUNT(DISTINCT new_product_id) = 1 AND COUNT(DISTINCT platform_price) = 1 AND SUM(CASE WHEN platform_price IS NULL THEN 1 ELSE 0 END) = 0 THEN element_at(SORT_ARRAY(COLLECT_SET(platform_price)), 1) END AS transition_platform_price,
         CASE WHEN SUM(boundary_flag) = 1 AND COUNT(DISTINCT new_product_id) = 1 AND COUNT(DISTINCT platform_price) = 1 AND SUM(CASE WHEN platform_price IS NULL THEN 1 ELSE 0 END) = 0 THEN 'PRODUCT_TRANSFER_CYCLE_BOUNDARY' ELSE 'PRODUCT_TRANSFER_EVIDENCE_NOT_ALIGNED_OR_AMBIGUOUS' END AS transition_evidence_rule
  FROM transition_candidates GROUP BY line_id
), backbill_candidates AS (
  SELECT e.line_id, c.segment_start_date, c.segment_end_date, c.platform_price, c.platform_product_id
  FROM excel_detail e JOIN cycle_segments c ON c.imsi = e.imsi AND c.billing_month = e.billing_month AND c.segment_start_date = e.excel_final_start_date
  WHERE e.charge_type LIKE '%Backbilled%'
), backbill_calc AS (
  SELECT line_id, COUNT(*) AS backbill_row_count, COUNT(DISTINCT segment_start_date) AS backbill_start_count,
         COUNT(DISTINCT segment_end_date) AS backbill_end_count, COUNT(DISTINCT platform_product_id) AS backbill_product_count, COUNT(DISTINCT platform_price) AS backbill_price_count,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(CAST(segment_start_date AS STRING)))) AS backbill_start_values,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(CAST(segment_end_date AS STRING)))) AS backbill_end_values,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(CAST(platform_price AS STRING)))) AS backbill_price_values,
         CASE WHEN COUNT(DISTINCT segment_start_date) = 1 AND COUNT(DISTINCT segment_end_date) = 1 THEN element_at(SORT_ARRAY(COLLECT_SET(segment_start_date)), 1) END AS backbill_platform_start_date,
         CASE WHEN COUNT(DISTINCT segment_start_date) = 1 AND COUNT(DISTINCT segment_end_date) = 1 THEN element_at(SORT_ARRAY(COLLECT_SET(segment_end_date)), 1) END AS backbill_platform_end_date,
         CASE WHEN COUNT(DISTINCT platform_price) = 1 AND SUM(CASE WHEN platform_price IS NULL THEN 1 ELSE 0 END) = 0 THEN element_at(SORT_ARRAY(COLLECT_SET(platform_price)), 1) END AS backbill_platform_price,
         CASE WHEN COUNT(DISTINCT segment_start_date) = 1 AND COUNT(DISTINCT segment_end_date) = 1 AND COUNT(DISTINCT platform_price) = 1 AND SUM(CASE WHEN platform_price IS NULL THEN 1 ELSE 0 END) = 0 THEN 'BACKBILLED_EXACT_CYCLE_START' ELSE 'BACKBILLED_CYCLE_START_MISSING_OR_AMBIGUOUS' END AS backbill_evidence_rule
  FROM backbill_candidates GROUP BY line_id
), candidate_base AS (
  SELECT e.*, lc.line_cycle_segment_count, lc.line_cycle_month_days, lc.line_cycle_product_count, lc.line_cycle_product_ids, lc.line_cycle_product_names, lc.line_cycle_price_count, lc.line_cycle_price_values, lc.line_cycle_missing_price_segments, lc.line_cycle_price, lc.line_cycle_min_start_date, lc.line_cycle_max_end_date,
         ab.activation_event_date, ab.activation_day_delta, vb.void_event_date, vb.void_day_delta,
         tc.transition_evidence_count, tc.transition_boundary_count, tc.transition_product_count, tc.transition_dates, tc.transition_old_product_ids, tc.transition_new_product_ids, tc.transition_new_product_names, tc.transition_price_count, tc.transition_price_values, tc.transition_platform_price, tc.transition_evidence_rule,
         bb.backbill_row_count, bb.backbill_start_count, bb.backbill_end_count, bb.backbill_product_count, bb.backbill_price_count, bb.backbill_start_values, bb.backbill_end_values, bb.backbill_price_values, bb.backbill_platform_start_date, bb.backbill_platform_end_date, bb.backbill_platform_price, bb.backbill_evidence_rule,
         pc.imsi AS platform_card_imsi, pc.platform_product_ids, pc.platform_product_names, pc.platform_supplier_ids, pc.platform_source_tables, pc.platform_calculated_days AS platform_month_days, pc.platform_calculated_price AS platform_month_price, pc.platform_calculated_amount_rule, pc.platform_scope_reason, pc.excluded_platform_product_ids, pc.excluded_platform_product_names, pc.excluded_supplier_ids, pc.excluded_reasons,
         CASE WHEN lc.line_cycle_segment_count > 0 AND lc.line_cycle_price_count = 1 AND lc.line_cycle_missing_price_segments = 0 THEN lc.line_cycle_price ELSE pc.platform_calculated_price END AS baseline_platform_price,
         CASE WHEN lc.line_cycle_segment_count > 0 THEN lc.line_cycle_month_days END AS baseline_platform_days,
         CASE WHEN lc.line_cycle_segment_count > 0 THEN lc.line_cycle_min_start_date END AS baseline_platform_start_date,
         CASE WHEN lc.line_cycle_segment_count > 0 THEN lc.line_cycle_max_end_date END AS baseline_platform_end_date
  FROM excel_detail e LEFT JOIN line_cycle_calc lc ON lc.line_id = e.line_id
  LEFT JOIN activation_best ab ON ab.line_id = e.line_id LEFT JOIN void_best vb ON vb.line_id = e.line_id
  LEFT JOIN transition_calc tc ON tc.line_id = e.line_id LEFT JOIN backbill_calc bb ON bb.line_id = e.line_id
  LEFT JOIN platform_cards pc ON pc.billing_month = e.billing_month AND pc.imsi = e.imsi
),candidate_logic AS (
  SELECT *,
    CASE
      WHEN charge_type LIKE '%Full Cycle%' AND baseline_platform_price IS NOT NULL AND baseline_platform_days IS NOT NULL THEN baseline_platform_start_date
      WHEN charge_type LIKE '%New Activation%' AND activation_event_date IS NOT NULL AND activation_event_date <= excel_final_end_date THEN GREATEST(activation_event_date, excel_final_start_date)
      WHEN charge_type LIKE '%Product Transfer%' AND transition_evidence_rule = 'PRODUCT_TRANSFER_CYCLE_BOUNDARY' AND baseline_platform_days IS NOT NULL THEN baseline_platform_start_date
      WHEN charge_type LIKE '%Backbilled%' AND backbill_evidence_rule = 'BACKBILLED_EXACT_CYCLE_START' THEN backbill_platform_start_date
      WHEN (charge_type LIKE '%Credit%' OR charge_type LIKE '%Prorated-Out%' OR charge_type LIKE '%Card Replaced%' OR charge_type LIKE '%Replacement%' OR charge_type LIKE '%Offstocked%') AND void_event_date IS NOT NULL AND void_event_date > excel_final_start_date THEN excel_final_start_date
      ELSE NULL END AS platform_calculated_start_date,
    CASE
      WHEN charge_type LIKE '%Full Cycle%' AND baseline_platform_price IS NOT NULL AND baseline_platform_days IS NOT NULL THEN baseline_platform_end_date
      WHEN charge_type LIKE '%New Activation%' AND activation_event_date IS NOT NULL AND activation_event_date <= excel_final_end_date THEN excel_final_end_date
      WHEN charge_type LIKE '%Product Transfer%' AND transition_evidence_rule = 'PRODUCT_TRANSFER_CYCLE_BOUNDARY' AND baseline_platform_days IS NOT NULL THEN baseline_platform_end_date
      WHEN charge_type LIKE '%Backbilled%' AND backbill_evidence_rule = 'BACKBILLED_EXACT_CYCLE_START' THEN backbill_platform_end_date
      WHEN (charge_type LIKE '%Credit%' OR charge_type LIKE '%Prorated-Out%' OR charge_type LIKE '%Card Replaced%' OR charge_type LIKE '%Replacement%' OR charge_type LIKE '%Offstocked%') AND void_event_date IS NOT NULL AND void_event_date > excel_final_start_date THEN DATE_SUB(void_event_date, 1)
      ELSE NULL END AS platform_calculated_end_date,
    CASE
      WHEN charge_type LIKE '%Full Cycle%' AND baseline_platform_price IS NOT NULL AND baseline_platform_days IS NOT NULL THEN baseline_platform_days
      WHEN charge_type LIKE '%New Activation%' AND activation_event_date IS NOT NULL AND activation_event_date <= excel_final_end_date THEN DATEDIFF(excel_final_end_date, GREATEST(activation_event_date, excel_final_start_date)) + 1
      WHEN charge_type LIKE '%Product Transfer%' AND transition_evidence_rule = 'PRODUCT_TRANSFER_CYCLE_BOUNDARY' AND baseline_platform_days IS NOT NULL THEN baseline_platform_days
      WHEN charge_type LIKE '%Backbilled%' AND backbill_evidence_rule = 'BACKBILLED_EXACT_CYCLE_START' THEN DATEDIFF(backbill_platform_end_date, backbill_platform_start_date) + 1
      WHEN (charge_type LIKE '%Credit%' OR charge_type LIKE '%Prorated-Out%' OR charge_type LIKE '%Card Replaced%' OR charge_type LIKE '%Replacement%' OR charge_type LIKE '%Offstocked%') AND void_event_date IS NOT NULL AND void_event_date > excel_final_start_date THEN DATEDIFF(DATE_SUB(void_event_date, 1), excel_final_start_date) + 1
      ELSE NULL END AS platform_calculated_days,
    CASE
      WHEN charge_type LIKE '%Product Transfer%' AND transition_evidence_rule = 'PRODUCT_TRANSFER_CYCLE_BOUNDARY' THEN transition_platform_price
      WHEN charge_type LIKE '%Backbilled%' AND backbill_evidence_rule = 'BACKBILLED_EXACT_CYCLE_START' THEN backbill_platform_price
      WHEN charge_type LIKE '%Full Cycle%' OR charge_type LIKE '%New Activation%' OR charge_type LIKE '%Credit%' OR charge_type LIKE '%Prorated-Out%' OR charge_type LIKE '%Card Replaced%' OR charge_type LIKE '%Replacement%' OR charge_type LIKE '%Offstocked%' THEN baseline_platform_price
      ELSE NULL END AS platform_calculated_price
  FROM candidate_base
), candidate_amount AS (
  SELECT *,
    CASE
      WHEN charge_type LIKE '%Credit%' AND void_event_date IS NOT NULL AND void_event_date > excel_final_start_date THEN -platform_calculated_price * (COALESCE(excel_cycle_days, excel_date_span_days) - platform_calculated_days) / NULLIF(COALESCE(excel_cycle_days, excel_date_span_days), 0)
      WHEN charge_type LIKE '%Prorated-Out%' AND platform_calculated_days IS NOT NULL THEN -platform_calculated_price * platform_calculated_days / NULLIF(COALESCE(excel_cycle_days, excel_date_span_days), 0)
      WHEN (charge_type LIKE '%Card Replaced%' OR charge_type LIKE '%Replacement%' OR charge_type LIKE '%Offstocked%') AND platform_calculated_days IS NOT NULL THEN platform_calculated_price * platform_calculated_days / NULLIF(COALESCE(excel_cycle_days, excel_date_span_days), 0)
      WHEN platform_calculated_price IS NOT NULL AND platform_calculated_days IS NOT NULL THEN platform_calculated_price * platform_calculated_days / NULLIF(COALESCE(excel_cycle_days, excel_date_span_days), 0)
      ELSE NULL END AS platform_calculated_amount_raw
  FROM candidate_logic
), candidate_line AS (
  SELECT *, ROUND(platform_calculated_amount_raw, 6) AS platform_calculated_amount,
         ROUND(platform_calculated_days - excel_days, 6) AS day_error,
         ROUND(platform_calculated_price - excel_price, 6) AS price_error,
         ROUND(platform_calculated_amount_raw - excel_amount, 6) AS amount_diff,
         CASE WHEN platform_calculated_days IS NULL THEN NULL WHEN platform_calculated_days = excel_days THEN 1 ELSE 0 END AS day_match,
         CASE WHEN platform_calculated_price IS NULL OR excel_price IS NULL THEN NULL WHEN ABS(platform_calculated_price - excel_price) <= 0.000001 THEN 1 ELSE 0 END AS price_match,
         CASE WHEN platform_calculated_amount_raw IS NULL THEN 'UNRESOLVED' ELSE 'CALCULATED' END AS population_status,
         CASE
           WHEN charge_type LIKE '%Full Cycle%' AND baseline_platform_price IS NULL THEN 'MISSING_OR_AMBIGUOUS_PRODUCT_ID_PRICE'
           WHEN charge_type LIKE '%Full Cycle%' AND baseline_platform_days IS NULL THEN 'MISSING_CYCLE_HISTORY_FOR_EXACT_PERIOD'
           WHEN charge_type LIKE '%New Activation%' AND activation_event_date IS NULL THEN 'MISSING_ACTIVATION_STATUS_EVENT'
           WHEN charge_type LIKE '%New Activation%' AND baseline_platform_price IS NULL THEN 'MISSING_OR_AMBIGUOUS_PRODUCT_ID_PRICE'
           WHEN charge_type LIKE '%Product Transfer%' AND transition_evidence_count IS NULL THEN 'MISSING_PRODUCT_TRANSFER_EVENT'
           WHEN charge_type LIKE '%Product Transfer%' AND transition_evidence_rule <> 'PRODUCT_TRANSFER_CYCLE_BOUNDARY' THEN transition_evidence_rule
           WHEN charge_type LIKE '%Backbilled%' AND backbill_evidence_rule <> 'BACKBILLED_EXACT_CYCLE_START' THEN backbill_evidence_rule
           WHEN (charge_type LIKE '%Credit%' OR charge_type LIKE '%Prorated-Out%' OR charge_type LIKE '%Card Replaced%' OR charge_type LIKE '%Replacement%' OR charge_type LIKE '%Offstocked%') AND void_event_date IS NULL THEN 'MISSING_VOID_OR_REPLACEMENT_STATUS_EVENT'
           WHEN platform_calculated_amount_raw IS NULL AND platform_card_imsi IS NULL THEN 'MISSING_PLATFORM_CARD_FROM_SCOPED_WA_PRODUCT_SET'
           WHEN platform_calculated_amount_raw IS NULL THEN 'UNRESOLVED_PLATFORM_CANDIDATE'
           WHEN ABS(platform_calculated_amount_raw - excel_amount) <= 0.000001 AND ABS(platform_calculated_price - excel_price) <= 0.000001 AND platform_calculated_days = excel_days THEN 'EXACT_DAY_PRICE_AMOUNT_MATCH'
           WHEN ABS(platform_calculated_price - excel_price) > 0.000001 THEN 'PRICE_DIFFERENCE'
           WHEN platform_calculated_days <> excel_days THEN 'DAY_DIFFERENCE'
           ELSE 'AMOUNT_DIFFERENCE_AFTER_DAY_PRICE_CHECK' END AS difference_reason
  FROM candidate_amount
)SELECT billing_month, line_id, imsi, charge_type,
       excel_product_id, excel_product_name, excel_iccid, excel_cycle_start_date, excel_cycle_end_date, excel_final_start_date, excel_final_end_date,
       excel_days, excel_price, excel_amount, excel_formula_amount, excel_cycle_days, excel_date_span_days,
       platform_product_ids, platform_product_names, platform_supplier_ids, platform_source_tables, platform_scope_reason,
       excluded_platform_product_ids, excluded_platform_product_names, excluded_supplier_ids, excluded_reasons,
       line_cycle_product_ids AS platform_line_product_ids, line_cycle_product_names AS platform_line_product_names,
       transition_old_product_ids, transition_new_product_ids, transition_new_product_names, transition_dates,
       activation_event_date, activation_day_delta, void_event_date, void_day_delta,
       platform_calculated_start_date, platform_calculated_end_date, platform_calculated_days, platform_calculated_price, platform_calculated_amount,
       day_error, price_error, amount_diff, day_match, price_match, population_status, difference_reason,
       source_file, sheet_name, new_card_imsi_replacement, old_card_imsi_replaced, transferred_to_wing_simbank
FROM candidate_line
ORDER BY billing_month, imsi, line_id