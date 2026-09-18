WITH
month_bounds AS (
  SELECT '2026-03' AS billing_month, DATE '2026-03-01' AS month_start, DATE '2026-04-01' AS month_end
  UNION ALL SELECT '2026-04', DATE '2026-04-01', DATE '2026-05-01'
  UNION ALL SELECT '2026-05', DATE '2026-05-01', DATE '2026-06-01'
),
excel_detail_raw AS (
  SELECT
    trim(source_file) AS excel_source_file,
    CASE WHEN trim(source_file) LIKE '%MAR 2026%' THEN '2026-03'
         WHEN trim(source_file) LIKE '%APR 2026%' THEN '2026-04'
         WHEN trim(source_file) LIKE '%MAY 2026%' THEN '2026-05'
         ELSE trim(source_file) END AS official_excel_billing_month,
    trim(imsi) AS imsi, trim(iccid) AS excel_iccid,
    trim(product_name) AS excel_product_name, CAST(NULL AS STRING) AS excel_product_id, trim(charge_type) AS charge_type,
    to_date(trim(cycle_start_date)) AS excel_cycle_start,
    to_date(trim(cycle_end_date)) AS excel_cycle_end,
    to_date(trim(final_start_date)) AS excel_final_start,
    to_date(trim(final_end_date)) AS excel_final_end,
    try_cast(nullif(trim(final_days), '') AS DECIMAL(38,10)) AS excel_days,
    try_cast(nullif(trim(monthly_rate), '') AS DECIMAL(38,10)) AS excel_price,
    try_cast(nullif(trim(final_charge), '') AS DECIMAL(38,10)) AS excel_amount,
    trim(note) AS excel_note
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE trim(source_file) LIKE '%MAR 2026%'
     OR trim(source_file) LIKE '%APR 2026%'
     OR trim(source_file) LIKE '%MAY 2026%'
),
excel_detail_numbered AS (
  SELECT r.*, row_number() OVER (
    PARTITION BY excel_source_file
    ORDER BY imsi, excel_cycle_start, excel_cycle_end, excel_final_start,
             excel_final_end, charge_type, excel_days, excel_price,
             excel_amount, excel_product_name, excel_note
  ) AS excel_line_no
  FROM excel_detail_raw r
),
excel_detail AS (
  SELECT *, concat(excel_source_file, '#', cast(excel_line_no AS STRING)) AS excel_row_key
  FROM excel_detail_numbered
),
target_products AS (
  SELECT cast(product_id AS STRING) AS platform_product_id,
         trim(product_name) AS platform_product_name,
         cast(monthly_rent AS DECIMAL(38,10)) AS platform_monthly_rent,
         cast(package_price AS DECIMAL(38,10)) AS platform_package_price,
         trim(time_zone) AS platform_time_zone
  FROM simo_prod.ods.resource_res_vsim_product
  WHERE supplier_id = 2275
),
snapshot_filtered AS (
  SELECT concat(cast(year AS STRING), '-', lpad(cast(month AS STRING), 2, '0')) AS billing_month,
         trim(imsi) AS imsi, trim(product_id) AS platform_product_id,
         trim(ICCID) AS platform_iccid,
         to_date(trim(Cycle_Start_Time)) AS snapshot_cycle_start,
         to_date(trim(Cycle_End_Time)) AS snapshot_cycle_end,
         to_timestamp(trim(partition_time)) AS snapshot_partition_ts
  FROM simo_prod.tc_cdr.sim_status_for_sftp_bak
  WHERE year = 2026 AND month IN (3,4,5)
),
snapshot_supplier AS (
  SELECT s.* FROM snapshot_filtered s
  INNER JOIN target_products p ON s.platform_product_id = p.platform_product_id
  INNER JOIN month_bounds m ON s.billing_month = m.billing_month
),
platform_month_cards AS (
  SELECT billing_month, imsi, platform_product_id, platform_iccid,
         snapshot_cycle_start, snapshot_cycle_end, max(snapshot_partition_ts) AS last_snapshot_ts
  FROM snapshot_supplier
  WHERE imsi IS NOT NULL AND imsi <> ''
  GROUP BY billing_month, imsi, platform_product_id, platform_iccid,
           snapshot_cycle_start, snapshot_cycle_end
),
platform_card_keys AS (
  SELECT DISTINCT billing_month, imsi, platform_product_id FROM platform_month_cards
),
platform_card_imsis AS (
  SELECT DISTINCT imsi FROM platform_month_cards
),
cycle_history_scope AS (
  SELECT DISTINCT trim(h.imsi) AS imsi,
         cast(h.product_id AS STRING) AS platform_product_id,
         to_date(h.cycle_time) AS history_cycle_start,
         date_sub(to_date(h.next_cycle_time), 1) AS history_cycle_end,
         cast(h.package_price AS DECIMAL(38,10)) AS history_package_price,
         trim(h.time_zone) AS history_time_zone
  FROM simo_prod.ods.resource_res_vsim_cycle_history h
  INNER JOIN platform_card_keys k
    ON trim(h.imsi) = k.imsi AND cast(h.product_id AS STRING) = k.platform_product_id
  WHERE h.cycle_time < TIMESTAMP '2026-07-01 00:00:00'
    AND h.next_cycle_time >= TIMESTAMP '2026-02-01 00:00:00'
),
status_event_day AS (
  SELECT trim(l.IMSI) AS imsi, to_date(l.CREATE_DATE) AS event_date,
         sum(CASE WHEN trim(l.NEXT_STATUS) = '激活'
                       OR trim(l.DESC_LOG) LIKE '%激活%'
                       OR trim(l.DESCRIPTION) LIKE '%激活%' THEN 1 ELSE 0 END) AS activation_event_count,
         sum(CASE WHEN trim(l.NEXT_STATUS) IN ('作废','下架','预下架')
                       OR trim(l.DESC_LOG) LIKE '%作废%'
                       OR trim(l.DESC_LOG) LIKE '%下架%'
                       OR trim(l.DESCRIPTION) LIKE '%作废%'
                       OR trim(l.DESCRIPTION) LIKE '%下架%' THEN 1 ELSE 0 END) AS offstock_event_count,
         sum(CASE WHEN trim(l.DESC_LOG) LIKE '%替换%'
                       OR trim(l.DESC_LOG) LIKE '%更换%'
                       OR trim(l.DESCRIPTION) LIKE '%替换%'
                       OR trim(l.DESCRIPTION) LIKE '%更换%'
                       OR lower(trim(l.DESC_LOG)) LIKE '%replacement%'
                       OR lower(trim(l.DESCRIPTION)) LIKE '%replacement%' THEN 1 ELSE 0 END) AS replacement_event_count,
         sum(CASE WHEN lower(trim(l.DESC_LOG)) LIKE '%simbank%'
                       OR lower(trim(l.DESCRIPTION)) LIKE '%simbank%'
                       OR trim(l.DESC_LOG) LIKE '%转移%'
                       OR trim(l.DESCRIPTION) LIKE '%转移%'
                       OR trim(l.DESC_LOG) LIKE '%转卡%'
                       OR trim(l.DESCRIPTION) LIKE '%转卡%' THEN 1 ELSE 0 END) AS transfer_event_count
  FROM simo_prod.ods.resource_res_vsim_status_log l
  INNER JOIN platform_card_imsis i ON trim(l.IMSI) = i.imsi
  WHERE to_date(trim(l.partition_date)) >= DATE '2026-02-01'
    AND to_date(trim(l.partition_date)) < DATE '2026-07-01'
    AND to_date(l.CREATE_DATE) >= DATE '2026-02-01'
    AND to_date(l.CREATE_DATE) < DATE '2026-07-01'
  GROUP BY trim(l.IMSI), to_date(l.CREATE_DATE)
),
platform_candidate_base AS (
  SELECT e.*, c.platform_product_id, p.platform_product_name,
         p.platform_monthly_rent, p.platform_package_price, p.platform_time_zone,
         c.platform_iccid, c.snapshot_cycle_start, c.snapshot_cycle_end,
         c.last_snapshot_ts, h.history_cycle_start, h.history_cycle_end,
         h.history_package_price, h.history_time_zone,
         coalesce(h.history_cycle_start, c.snapshot_cycle_start) AS platform_cycle_start,
         coalesce(h.history_cycle_end, c.snapshot_cycle_end) AS platform_cycle_end,
         CASE WHEN h.history_cycle_start IS NOT NULL THEN 'CYCLE_HISTORY'
              ELSE 'MONTH_SNAPSHOT_FALLBACK' END AS platform_window_source
  FROM excel_detail e
  LEFT JOIN platform_month_cards c
    ON c.billing_month = e.official_excel_billing_month
   AND c.imsi = e.imsi
   AND c.snapshot_cycle_start <= e.excel_final_end
   AND c.snapshot_cycle_end >= e.excel_final_start
  LEFT JOIN target_products p
    ON c.platform_product_id = p.platform_product_id
  LEFT JOIN cycle_history_scope h
    ON h.imsi = c.imsi AND h.platform_product_id = c.platform_product_id
   AND h.history_cycle_start <= e.excel_final_end
   AND h.history_cycle_end >= e.excel_final_start
),
candidate_counts AS (
  SELECT excel_row_key, count(platform_product_id) AS platform_candidate_count,
         count(DISTINCT platform_product_id) AS platform_candidate_product_count,
         count(DISTINCT concat(coalesce(cast(platform_cycle_start AS STRING), '#'), '|',
                               coalesce(cast(platform_cycle_end AS STRING), '#'))) AS platform_candidate_window_count
  FROM platform_candidate_base GROUP BY excel_row_key
),
candidate_ranked AS (
  SELECT b.*, cc.platform_candidate_count, cc.platform_candidate_product_count,
         cc.platform_candidate_window_count,
         row_number() OVER (
           PARTITION BY b.excel_row_key
           ORDER BY CASE WHEN b.platform_cycle_start = b.excel_final_start
                              AND b.platform_cycle_end = b.excel_final_end THEN 0
                         WHEN b.platform_cycle_start <= b.excel_final_start
                              AND b.platform_cycle_end >= b.excel_final_end THEN 1
                         ELSE 2 END,
                    CASE WHEN b.history_cycle_start IS NOT NULL THEN 0 ELSE 1 END,
                    b.platform_product_id, b.platform_cycle_start, b.platform_cycle_end
         ) AS candidate_rank
  FROM platform_candidate_base b
  INNER JOIN candidate_counts cc ON b.excel_row_key = cc.excel_row_key
),
selected_candidate AS (
  SELECT * FROM candidate_ranked WHERE candidate_rank = 1
),
status_by_excel_row AS (
  SELECT e.excel_row_key,
         coalesce(sum(s.activation_event_count), 0) AS activation_event_count,
         coalesce(sum(s.offstock_event_count), 0) AS offstock_event_count,
         coalesce(sum(s.replacement_event_count), 0) AS replacement_event_count,
         coalesce(sum(s.transfer_event_count), 0) AS transfer_event_count
  FROM selected_candidate e
  LEFT JOIN status_event_day s
    ON s.imsi = e.imsi AND e.excel_final_start IS NOT NULL
   AND e.excel_final_end IS NOT NULL
   AND s.event_date BETWEEN e.excel_final_start AND e.excel_final_end
  GROUP BY e.excel_row_key
),
rule_base AS (
  SELECT s.*, coalesce(st.activation_event_count, 0) AS activation_event_count,
         coalesce(st.offstock_event_count, 0) AS offstock_event_count,
         coalesce(st.replacement_event_count, 0) AS replacement_event_count,
         coalesce(st.transfer_event_count, 0) AS transfer_event_count,
         CASE
           WHEN s.charge_type = 'Full Cycle Charge' THEN 'R_FULL_CYCLE_MONTHLY'
           WHEN s.charge_type = 'Full Cycle Charge - Backbilled for FEB Invoice' THEN 'R_FULL_CYCLE_BACKBILLED_MONTHLY'
           WHEN s.charge_type = 'New Activation: Prorated-in Charge' THEN 'R_DAILY_PRORATED_NEW_ACTIVATION'
           WHEN s.charge_type = 'Partial Charge - Card Replaced Mid Cycle' THEN 'R_DAILY_PRORATED_REPLACEMENT_OLD_CARD'
           WHEN s.charge_type = 'Partial Charge - New Card Used as Replacement Mid Cycle' THEN 'R_DAILY_PRORATED_REPLACEMENT_NEW_CARD'
           WHEN s.charge_type = 'Credit for Offstocked Card' THEN 'R_DAILY_CREDIT_OFFSTOCK'
           WHEN s.charge_type = concat('Prorated Out - Transferred to Wing', chr(39), 's Simbank') THEN 'R_DAILY_PRORATED_SIMBANK_TRANSFER'
           WHEN s.charge_type = 'Prorated-out Charge - Offstocked Card' THEN 'R_DAILY_PRORATED_OFFSTOCK'
           WHEN s.charge_type = 'Offstocked before cycle start' THEN 'R_OFFSTOCK_BEFORE_CYCLE_UNRESOLVED'
           ELSE 'R_UNSUPPORTED_CHARGE_TYPE' END AS rule_id,
         CASE
           WHEN s.platform_monthly_rent IS NOT NULL
            AND s.platform_package_price IS NOT NULL
            AND s.platform_monthly_rent = s.platform_package_price THEN s.platform_monthly_rent
           WHEN s.platform_monthly_rent IS NOT NULL
            AND s.platform_package_price IS NULL THEN s.platform_monthly_rent
           WHEN s.platform_monthly_rent IS NULL
            AND s.platform_package_price IS NOT NULL THEN s.platform_package_price
           ELSE CAST(NULL AS DECIMAL(38,10)) END AS platform_calculated_price,
         CASE
           WHEN s.platform_monthly_rent IS NULL AND s.platform_package_price IS NULL THEN 'NO_PRICE'
           WHEN s.platform_monthly_rent IS NOT NULL
            AND s.platform_package_price IS NOT NULL
            AND s.platform_monthly_rent <> s.platform_package_price THEN 'PRICE_CONFLICT'
           ELSE 'ONE_PRICE' END AS platform_price_state,
         CASE
           WHEN s.platform_product_id IS NULL THEN 'NO_PLATFORM_PRODUCT_ID'
           WHEN s.excel_product_id IS NULL
            AND (s.excel_product_name IS NULL OR s.excel_product_name = '') THEN 'EXCEL_PRODUCT_ID_NULL'
           WHEN s.excel_product_id IS NULL
            AND s.excel_product_name = s.platform_product_name THEN 'EXCEL_PRODUCT_ID_NULL_NAME_EXACT_ONLY'
           WHEN s.excel_product_id IS NULL THEN 'EXCEL_PRODUCT_ID_NULL_NAME_MISMATCH'
           ELSE 'EXPLICIT_PRODUCT_ID' END AS product_mapping_status
  FROM selected_candidate s
  LEFT JOIN status_by_excel_row st ON s.excel_row_key = st.excel_row_key
),
calculated_base AS (
  SELECT r.*,
         cast(CASE WHEN r.platform_cycle_start IS NOT NULL AND r.platform_cycle_end IS NOT NULL
                   THEN datediff(r.platform_cycle_end, r.platform_cycle_start) + 1 END AS DECIMAL(38,10)) AS platform_cycle_days,
         cast(CASE WHEN r.platform_cycle_start IS NOT NULL AND r.platform_cycle_end IS NOT NULL
                         AND r.excel_final_start IS NOT NULL AND r.excel_final_end IS NOT NULL
                   THEN datediff(least(r.excel_final_end, r.platform_cycle_end),
                                 greatest(r.excel_final_start, r.platform_cycle_start)) + 1 END AS DECIMAL(38,10)) AS platform_calculated_days,
         CASE WHEN r.platform_cycle_start <= r.excel_final_start
                   AND r.platform_cycle_end >= r.excel_final_end THEN 1 ELSE 0 END AS platform_window_covers_excel
  FROM rule_base r
),
calculated AS (
  SELECT b.*,
         CASE
           WHEN b.rule_id IN ('R_FULL_CYCLE_MONTHLY','R_FULL_CYCLE_BACKBILLED_MONTHLY')
             THEN b.platform_calculated_price
           WHEN b.rule_id IN ('R_DAILY_PRORATED_NEW_ACTIVATION',
                              'R_DAILY_PRORATED_REPLACEMENT_OLD_CARD',
                              'R_DAILY_PRORATED_REPLACEMENT_NEW_CARD',
                              'R_DAILY_PRORATED_SIMBANK_TRANSFER',
                              'R_DAILY_PRORATED_OFFSTOCK')
             THEN b.platform_calculated_price * b.platform_calculated_days / nullif(b.platform_cycle_days, 0)
           WHEN b.rule_id = 'R_DAILY_CREDIT_OFFSTOCK'
             THEN -b.platform_calculated_price * b.platform_calculated_days / nullif(b.platform_cycle_days, 0)
           ELSE CAST(NULL AS DECIMAL(38,10)) END AS platform_calculated_amount
  FROM calculated_base b
),
residuals AS (
  SELECT c.*, c.platform_calculated_days - c.excel_days AS day_diff,
         c.platform_calculated_price - c.excel_price AS price_diff,
         c.platform_calculated_amount - c.excel_amount AS amount_diff
  FROM calculated c
),
finalized AS (
  SELECT r.*,
         CASE
           WHEN r.platform_candidate_count = 0 THEN 'NO_PLATFORM_CARD_WINDOW'
           WHEN r.platform_candidate_product_count > 1 OR r.platform_candidate_window_count > 1 THEN 'MULTIPLE_PLATFORM_PRODUCT_OR_WINDOW_CANDIDATES'
           WHEN r.excel_final_start IS NULL OR r.excel_final_end IS NULL THEN 'NO_EXCEL_FINAL_WINDOW'
           WHEN r.platform_price_state <> 'ONE_PRICE' THEN 'PLATFORM_PRICE_NOT_UNIQUE'
           WHEN r.rule_id = 'R_DAILY_PRORATED_NEW_ACTIVATION' AND r.activation_event_count = 0 THEN 'NO_ACTIVATION_EVENT_IN_PLATFORM_LOG'
           WHEN r.rule_id IN ('R_DAILY_PRORATED_OFFSTOCK','R_DAILY_CREDIT_OFFSTOCK') AND r.offstock_event_count = 0 THEN 'NO_OFFSTOCK_EVENT_IN_PLATFORM_LOG'
           WHEN r.rule_id IN ('R_DAILY_PRORATED_REPLACEMENT_OLD_CARD','R_DAILY_PRORATED_REPLACEMENT_NEW_CARD') AND r.replacement_event_count = 0 THEN 'NO_EXPLICIT_REPLACEMENT_MAPPING'
           WHEN r.rule_id = 'R_DAILY_PRORATED_SIMBANK_TRANSFER' AND r.transfer_event_count = 0 THEN 'NO_EXPLICIT_SIMBANK_TRANSFER_MAPPING'
           WHEN r.rule_id IN ('R_OFFSTOCK_BEFORE_CYCLE_UNRESOLVED','R_UNSUPPORTED_CHARGE_TYPE') THEN 'RULE_NOT_PROVABLE'
           WHEN r.platform_calculated_days IS NULL THEN 'NO_PLATFORM_DAYS'
           WHEN r.platform_window_covers_excel = 0 THEN 'PLATFORM_WINDOW_NOT_COVERING_EXCEL_WINDOW'
           WHEN abs(r.platform_calculated_days - r.excel_days) > 0.0001 THEN 'DAY_DIFF'
           WHEN abs(r.platform_calculated_price - r.excel_price) > 0.0001 THEN 'PRICE_DIFF'
           WHEN abs(r.platform_calculated_amount - r.excel_amount) > 0.0001 THEN 'AMOUNT_DIFF'
           ELSE 'NO_DIFFERENCE' END AS difference_reason,
         CASE
           WHEN r.platform_candidate_count = 0 THEN 'WA_ONLY'
           WHEN r.platform_candidate_product_count > 1 OR r.platform_candidate_window_count > 1 THEN 'MISSING_MAPPING'
           WHEN r.excel_final_start IS NULL OR r.excel_final_end IS NULL
             OR r.platform_price_state <> 'ONE_PRICE'
             OR r.platform_calculated_days IS NULL THEN 'MISSING_DATA'
           WHEN r.rule_id = 'R_DAILY_PRORATED_NEW_ACTIVATION' AND r.activation_event_count = 0 THEN 'MISSING_DATA'
           WHEN r.rule_id IN ('R_DAILY_PRORATED_OFFSTOCK','R_DAILY_CREDIT_OFFSTOCK') AND r.offstock_event_count = 0 THEN 'MISSING_DATA'
           WHEN r.rule_id IN ('R_DAILY_PRORATED_REPLACEMENT_OLD_CARD','R_DAILY_PRORATED_REPLACEMENT_NEW_CARD') AND r.replacement_event_count = 0 THEN 'MISSING_MAPPING'
           WHEN r.rule_id = 'R_DAILY_PRORATED_SIMBANK_TRANSFER' AND r.transfer_event_count = 0 THEN 'MISSING_MAPPING'
           WHEN r.rule_id IN ('R_OFFSTOCK_BEFORE_CYCLE_UNRESOLVED','R_UNSUPPORTED_CHARGE_TYPE') THEN 'UNRESOLVED'
           WHEN abs(r.platform_calculated_days - r.excel_days) <= 0.0001
            AND abs(r.platform_calculated_price - r.excel_price) <= 0.0001
            AND abs(r.platform_calculated_amount - r.excel_amount) <= 0.0001 THEN 'MATCHED'
           ELSE 'UNRESOLVED' END AS source_match_status
  FROM residuals r
),
platform_recon_facts AS (
  SELECT
    concat(m.billing_month, '|', m.imsi, '|', m.platform_product_id, '|',
           coalesce(cast(m.snapshot_cycle_start AS STRING), '#'), '|',
           coalesce(cast(m.snapshot_cycle_end AS STRING), '#')) AS platform_fact_key,
    m.billing_month, m.imsi, m.platform_product_id,
    p.platform_product_name, p.platform_monthly_rent, p.platform_package_price,
    p.platform_time_zone, m.platform_iccid,
    m.snapshot_cycle_start AS platform_cycle_start,
    m.snapshot_cycle_end AS platform_cycle_end,
    cast(CASE WHEN m.snapshot_cycle_start IS NOT NULL AND m.snapshot_cycle_end IS NOT NULL
              THEN datediff(m.snapshot_cycle_end, m.snapshot_cycle_start) + 1 END AS DECIMAL(38,10)) AS platform_cycle_days,
    m.last_snapshot_ts,
    CASE
      WHEN p.platform_monthly_rent IS NOT NULL
       AND p.platform_package_price IS NOT NULL
       AND p.platform_monthly_rent = p.platform_package_price THEN p.platform_monthly_rent
      WHEN p.platform_monthly_rent IS NOT NULL
       AND p.platform_package_price IS NULL THEN p.platform_monthly_rent
      WHEN p.platform_monthly_rent IS NULL
       AND p.platform_package_price IS NOT NULL THEN p.platform_package_price
      ELSE CAST(NULL AS DECIMAL(38,10))
    END AS platform_fact_price
  FROM platform_month_cards m
  LEFT JOIN target_products p ON m.platform_product_id = p.platform_product_id
),
platform_only_facts AS (
  SELECT p.*
  FROM platform_recon_facts p
  WHERE NOT EXISTS (
    SELECT 1
    FROM excel_detail e
    WHERE e.official_excel_billing_month = p.billing_month
      AND e.imsi = p.imsi
      AND e.excel_final_start IS NOT NULL
      AND e.excel_final_end IS NOT NULL
      AND p.platform_cycle_start <= e.excel_final_end
      AND p.platform_cycle_end >= e.excel_final_start
  )
),
recon_joined AS (
  SELECT
    e.excel_row_key,
    p.platform_fact_key,
    CASE WHEN e.excel_row_key IS NULL THEN 'PLATFORM_FACT' ELSE 'EXCEL_DETAIL' END AS record_side,
    CASE WHEN e.excel_row_key IS NULL THEN 'PLATFORM_ONLY' ELSE e.source_match_status END AS source_match_status,
    CASE WHEN e.excel_row_key IS NULL THEN 'NO_EXCEL_DETAIL_FOR_PLATFORM_FACT' ELSE e.difference_reason END AS difference_reason,
    coalesce(e.official_excel_billing_month, p.billing_month) AS reconciliation_billing_month,
    e.excel_source_file,
    e.official_excel_billing_month,
    coalesce(e.imsi, p.imsi) AS imsi,
    e.excel_product_id,
    e.excel_product_name,
    e.charge_type,
    e.excel_cycle_start, e.excel_cycle_end, e.excel_final_start, e.excel_final_end,
    e.excel_days, e.excel_price, e.excel_amount,
    coalesce(e.platform_product_id, p.platform_product_id) AS platform_product_id,
    coalesce(e.platform_product_name, p.platform_product_name) AS platform_product_name,
    coalesce(e.platform_monthly_rent, p.platform_monthly_rent) AS platform_monthly_rent,
    coalesce(e.platform_package_price, p.platform_package_price) AS platform_package_price,
    coalesce(e.platform_time_zone, p.platform_time_zone) AS platform_time_zone,
    coalesce(e.platform_iccid, p.platform_iccid) AS platform_iccid,
    coalesce(e.platform_cycle_start, p.platform_cycle_start) AS platform_cycle_start,
    coalesce(e.platform_cycle_end, p.platform_cycle_end) AS platform_cycle_end,
    coalesce(e.platform_cycle_days, p.platform_cycle_days) AS platform_cycle_days,
    CASE WHEN e.excel_row_key IS NULL THEN NULL ELSE e.platform_calculated_days END AS platform_calculated_days,
    CASE WHEN e.excel_row_key IS NULL THEN p.platform_fact_price ELSE e.platform_calculated_price END AS platform_calculated_price,
    CASE WHEN e.excel_row_key IS NULL THEN NULL ELSE e.platform_calculated_amount END AS platform_calculated_amount,
    CASE WHEN e.excel_row_key IS NULL THEN NULL ELSE e.day_diff END AS day_diff,
    CASE WHEN e.excel_row_key IS NULL THEN NULL ELSE e.price_diff END AS price_diff,
    CASE WHEN e.excel_row_key IS NULL THEN NULL ELSE e.amount_diff END AS amount_diff,
    e.rule_id, e.platform_price_state, e.product_mapping_status,
    e.platform_candidate_count, e.platform_candidate_product_count,
    e.platform_candidate_window_count, e.activation_event_count,
    e.offstock_event_count, e.replacement_event_count, e.transfer_event_count
  FROM finalized e
  FULL OUTER JOIN platform_only_facts p
    ON e.excel_row_key = p.platform_fact_key
)
SELECT
  excel_row_key, platform_fact_key, record_side, source_match_status,
  difference_reason, reconciliation_billing_month, excel_source_file,
  official_excel_billing_month, imsi, excel_product_id, excel_product_name,
  charge_type, excel_cycle_start, excel_cycle_end, excel_final_start,
  excel_final_end, excel_days, excel_price, excel_amount, platform_product_id,
  platform_product_name, platform_monthly_rent, platform_package_price,
  platform_time_zone, platform_iccid, platform_cycle_start, platform_cycle_end,
  platform_cycle_days, platform_calculated_days, platform_calculated_price,
  platform_calculated_amount, day_diff, price_diff, amount_diff, rule_id,
  product_mapping_status, platform_candidate_count, platform_candidate_product_count,
  platform_candidate_window_count, activation_event_count, offstock_event_count,
  replacement_event_count, transfer_event_count
FROM recon_joined