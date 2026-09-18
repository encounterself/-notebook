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
  SELECT cast(supplier_id AS BIGINT) AS platform_supplier_id,
         cast(product_id AS STRING) AS platform_product_id,
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
  SELECT e.*, c.platform_product_id, p.platform_supplier_id, p.platform_product_name,
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
numeric_status AS (
  SELECT r.*,
         CASE
           WHEN r.excel_days IS NULL OR r.platform_calculated_days IS NULL
             OR r.excel_price IS NULL OR r.platform_calculated_price IS NULL
             OR r.excel_amount IS NULL OR r.platform_calculated_amount IS NULL
             THEN 'NUMERIC_NOT_COMPARABLE'
           WHEN abs(r.platform_calculated_days - r.excel_days) <= 0.0001
            AND abs(r.platform_calculated_price - r.excel_price) <= 0.0001
            AND abs(r.platform_calculated_amount - r.excel_amount) <= 0.0001
             THEN 'NUMERIC_MATCH'
           ELSE 'NUMERIC_DIFF'
         END AS numeric_match_status
  FROM residuals r
),
mapping_status AS (
  SELECT n.*,
         CASE
           WHEN n.platform_candidate_count = 0 THEN 'NO_PLATFORM_PRODUCT'
           WHEN n.platform_candidate_product_count > 1 OR n.platform_candidate_window_count > 1 THEN 'MULTIPLE_PLATFORM_PRODUCT_OR_WINDOW'
           WHEN n.platform_product_id IS NULL OR n.platform_supplier_id <> 2275 THEN 'SUPPLIER_OR_PRODUCT_NOT_PROVEN'
           WHEN n.platform_price_state <> 'ONE_PRICE' THEN 'PLATFORM_PRICE_NOT_UNIQUE'
           WHEN n.excel_price IS NULL OR n.platform_calculated_price IS NULL THEN 'PRICE_NOT_COMPARABLE'
           WHEN abs(n.platform_calculated_price - n.excel_price) <= 0.0001 THEN 'PROVEN_BY_PLATFORM_IMSI'
           ELSE 'PLATFORM_PRICE_NOT_EXACT'
         END AS platform_product_mapping_status
  FROM numeric_status n
),
evidence_status AS (
  SELECT m.*,
         CASE
           WHEN m.platform_candidate_count = 0 THEN 'NO_PLATFORM_CARD_WINDOW'
           WHEN m.platform_product_mapping_status <> 'PROVEN_BY_PLATFORM_IMSI' THEN 'PRODUCT_MAPPING_NOT_PROVEN'
           WHEN m.excel_final_start IS NULL OR m.excel_final_end IS NULL THEN 'NO_EXCEL_FINAL_WINDOW'
           WHEN m.rule_id = 'R_DAILY_PRORATED_NEW_ACTIVATION' AND m.activation_event_count = 0 THEN 'NO_ACTIVATION_EVENT_IN_PLATFORM_LOG'
           WHEN m.rule_id IN ('R_DAILY_PRORATED_OFFSTOCK','R_DAILY_CREDIT_OFFSTOCK') AND m.offstock_event_count = 0 THEN 'NO_OFFSTOCK_EVENT_IN_PLATFORM_LOG'
           WHEN m.rule_id IN ('R_DAILY_PRORATED_REPLACEMENT_OLD_CARD','R_DAILY_PRORATED_REPLACEMENT_NEW_CARD') AND m.replacement_event_count = 0 THEN 'NO_EXPLICIT_REPLACEMENT_MAPPING'
           WHEN m.rule_id = 'R_DAILY_PRORATED_SIMBANK_TRANSFER' AND m.transfer_event_count = 0 THEN 'NO_EXPLICIT_SIMBANK_TRANSFER_MAPPING'
           WHEN m.rule_id IN ('R_OFFSTOCK_BEFORE_CYCLE_UNRESOLVED','R_UNSUPPORTED_CHARGE_TYPE') THEN 'RULE_NOT_PROVABLE'
           WHEN m.platform_calculated_amount IS NULL THEN 'NO_PLATFORM_AMOUNT'
           ELSE 'KNOWN'
         END AS platform_amount_evidence_status
  FROM mapping_status m
),
finalized AS (
  SELECT e.*,
         CASE
           WHEN e.platform_candidate_count = 0 THEN 'NO_PLATFORM_CARD_WINDOW'
           WHEN e.platform_candidate_product_count > 1 OR e.platform_candidate_window_count > 1 THEN 'MULTIPLE_PLATFORM_PRODUCT_OR_WINDOW_CANDIDATES'
           WHEN e.platform_product_mapping_status IN ('NO_PLATFORM_PRODUCT','SUPPLIER_OR_PRODUCT_NOT_PROVEN','PLATFORM_PRICE_NOT_UNIQUE','PRICE_NOT_COMPARABLE') THEN 'PRODUCT_MAPPING_NOT_PROVEN'
           WHEN e.excel_final_start IS NULL OR e.excel_final_end IS NULL THEN 'NO_EXCEL_FINAL_WINDOW'
           WHEN e.rule_id = 'R_DAILY_PRORATED_NEW_ACTIVATION' AND e.activation_event_count = 0 THEN 'NO_ACTIVATION_EVENT_IN_PLATFORM_LOG'
           WHEN e.rule_id IN ('R_DAILY_PRORATED_OFFSTOCK','R_DAILY_CREDIT_OFFSTOCK') AND e.offstock_event_count = 0 THEN 'NO_OFFSTOCK_EVENT_IN_PLATFORM_LOG'
           WHEN e.rule_id IN ('R_DAILY_PRORATED_REPLACEMENT_OLD_CARD','R_DAILY_PRORATED_REPLACEMENT_NEW_CARD') AND e.replacement_event_count = 0 THEN 'NO_EXPLICIT_REPLACEMENT_MAPPING'
           WHEN e.rule_id = 'R_DAILY_PRORATED_SIMBANK_TRANSFER' AND e.transfer_event_count = 0 THEN 'NO_EXPLICIT_SIMBANK_TRANSFER_MAPPING'
           WHEN e.rule_id IN ('R_OFFSTOCK_BEFORE_CYCLE_UNRESOLVED','R_UNSUPPORTED_CHARGE_TYPE') THEN 'RULE_NOT_PROVABLE'
           WHEN e.platform_calculated_days IS NULL THEN 'NO_PLATFORM_DAYS'
           WHEN e.platform_window_covers_excel = 0 THEN 'PLATFORM_WINDOW_NOT_COVERING_EXCEL_WINDOW'
           WHEN abs(e.platform_calculated_days - e.excel_days) > 0.0001 THEN 'DAY_DIFF'
           WHEN abs(e.platform_calculated_price - e.excel_price) > 0.0001 THEN 'PRICE_DIFF'
           WHEN abs(e.platform_calculated_amount - e.excel_amount) > 0.0001 THEN 'AMOUNT_DIFF'
           ELSE 'NO_DIFFERENCE'
         END AS difference_reason,
         CASE
           WHEN e.platform_candidate_count = 0 THEN 'WA_ONLY'
           WHEN e.platform_candidate_product_count > 1 OR e.platform_candidate_window_count > 1 THEN 'MISSING_MAPPING'
           WHEN e.platform_product_mapping_status <> 'PROVEN_BY_PLATFORM_IMSI' THEN 'MISSING_MAPPING'
           WHEN e.platform_amount_evidence_status IN ('NO_EXCEL_FINAL_WINDOW','NO_PLATFORM_AMOUNT','NO_ACTIVATION_EVENT_IN_PLATFORM_LOG','NO_OFFSTOCK_EVENT_IN_PLATFORM_LOG') THEN 'MISSING_DATA'
           WHEN e.platform_amount_evidence_status IN ('NO_EXPLICIT_REPLACEMENT_MAPPING','NO_EXPLICIT_SIMBANK_TRANSFER_MAPPING') THEN 'MISSING_MAPPING'
           WHEN e.platform_amount_evidence_status = 'RULE_NOT_PROVABLE' THEN 'UNRESOLVED'
           WHEN e.numeric_match_status = 'NUMERIC_MATCH' THEN 'MATCHED'
           WHEN e.numeric_match_status = 'NUMERIC_NOT_COMPARABLE' THEN 'MISSING_DATA'
           ELSE 'UNRESOLVED'
         END AS formal_match_status,
         CASE WHEN e.platform_amount_evidence_status = 'KNOWN'
                    AND e.platform_calculated_amount IS NOT NULL
              THEN e.platform_calculated_amount
              ELSE CAST(NULL AS DECIMAL(38,10)) END AS platform_calculated_amount_known
  FROM evidence_status e
),
platform_recon_facts AS (
  SELECT
    concat(m.billing_month, '|', m.imsi, '|', m.platform_product_id, '|',
           coalesce(cast(m.snapshot_cycle_start AS STRING), '#'), '|',
           coalesce(cast(m.snapshot_cycle_end AS STRING), '#')) AS platform_fact_key,
    m.billing_month,
    m.imsi,
    m.platform_product_id,
    p.platform_product_name,
    p.platform_supplier_id,
    p.platform_monthly_rent,
    p.platform_package_price,
    p.platform_time_zone,
    m.platform_iccid,
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
  LEFT JOIN target_products p
    ON m.platform_product_id = p.platform_product_id
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
      AND p.platform_cycle_start IS NOT NULL
      AND p.platform_cycle_end IS NOT NULL
      AND p.platform_cycle_start <= e.excel_final_end
      AND p.platform_cycle_end >= e.excel_final_start
  )
),
recon_joined AS (
  SELECT
    e.excel_row_key,
    p.platform_fact_key,
    e.excel_source_file,
    e.official_excel_billing_month,
    coalesce(e.official_excel_billing_month, p.billing_month) AS reconciliation_billing_month,
    coalesce(e.imsi, p.imsi) AS imsi,
    e.excel_product_id,
    e.excel_product_name,
    e.charge_type,
    e.excel_cycle_start,
    e.excel_cycle_end,
    e.excel_final_start,
    e.excel_final_end,
    e.excel_days,
    e.excel_price,
    e.excel_amount,
    p.platform_product_id,
    p.platform_product_name,
    p.platform_supplier_id,
    p.platform_monthly_rent,
    p.platform_package_price,
    p.platform_time_zone,
    p.platform_iccid,
    p.platform_cycle_start,
    p.platform_cycle_end,
    p.platform_cycle_days,
    CASE WHEN e.excel_row_key IS NULL THEN NULL ELSE e.platform_calculated_days END AS platform_calculated_days,
    CASE WHEN e.excel_row_key IS NULL THEN p.platform_fact_price ELSE e.platform_calculated_price END AS platform_calculated_price,
    CASE WHEN e.excel_row_key IS NULL THEN NULL ELSE e.platform_calculated_amount END AS platform_calculated_amount,
    CASE WHEN e.excel_row_key IS NULL THEN NULL ELSE e.day_diff END AS day_diff,
    CASE WHEN e.excel_row_key IS NULL THEN NULL ELSE e.price_diff END AS price_diff,
    CASE WHEN e.excel_row_key IS NULL THEN NULL ELSE e.amount_diff END AS amount_diff,
    e.rule_id,
    e.platform_price_state,
    e.product_mapping_status,
    e.platform_candidate_count,
    e.platform_candidate_product_count,
    e.platform_candidate_window_count,
    e.activation_event_count,
    e.offstock_event_count,
    e.replacement_event_count,
    e.transfer_event_count,
    CASE
      WHEN e.excel_row_key IS NULL THEN 'NO_EXCEL_DETAIL_FOR_PLATFORM_FACT'
      ELSE e.difference_reason
    END AS difference_reason,
    CASE
      WHEN e.excel_row_key IS NULL THEN 'PLATFORM_ONLY'
      ELSE e.formal_match_status
    END AS source_match_status,
    CASE WHEN e.excel_row_key IS NULL THEN NULL ELSE e.numeric_match_status END AS numeric_match_status,
    CASE WHEN e.excel_row_key IS NULL THEN 'PLATFORM_ONLY' ELSE e.formal_match_status END AS formal_match_status,
    CASE WHEN e.excel_row_key IS NULL THEN NULL ELSE e.platform_amount_evidence_status END AS platform_amount_evidence_status,
    CASE WHEN e.excel_row_key IS NULL THEN NULL ELSE e.platform_product_mapping_status END AS platform_product_mapping_status,
    CASE WHEN e.excel_row_key IS NULL THEN NULL ELSE e.platform_calculated_amount_known END AS platform_calculated_amount_known,
    CASE
      WHEN e.excel_row_key IS NULL THEN 'PLATFORM_FACT'
      ELSE 'EXCEL_DETAIL'
    END AS record_side  FROM finalized e
  FULL OUTER JOIN platform_only_facts p
    ON e.excel_row_key = p.platform_fact_key
),
platform_fact_keyed AS (
  SELECT f.*,
         m.month_start,
         date_sub(m.month_end, 1) AS month_last_day,
         CASE WHEN f.platform_cycle_start IS NOT NULL
                    AND f.platform_cycle_end IS NOT NULL
                    AND f.platform_cycle_start <= date_sub(m.month_end, 1)
                    AND f.platform_cycle_end >= m.month_start
              THEN datediff(least(f.platform_cycle_end, date_sub(m.month_end, 1)),
                            greatest(f.platform_cycle_start, m.month_start)) + 1
              ELSE NULL END AS platform_billing_days,
         CASE WHEN f.platform_cycle_start IS NOT NULL
                    AND f.platform_cycle_end IS NOT NULL
                    AND f.platform_cycle_start <= m.month_start
                    AND f.platform_cycle_end >= date_sub(m.month_end, 1)
              THEN 'FULL_MONTH_WINDOW'
              WHEN f.platform_cycle_start IS NOT NULL
                    AND f.platform_cycle_end IS NOT NULL
                    AND f.platform_cycle_start <= date_sub(m.month_end, 1)
                    AND f.platform_cycle_end >= m.month_start
              THEN 'WINDOW_PRORATION'
              ELSE 'NO_TARGET_WINDOW_OVERLAP' END AS platform_baseline_window_rule,
         CASE WHEN f.platform_iccid IS NOT NULL AND trim(f.platform_iccid) <> ''
              THEN concat(f.billing_month, '|ICCID|', trim(f.platform_iccid), '|', f.platform_product_id, '|',
                          coalesce(cast(f.platform_cycle_start AS STRING), '#'), '|',
                          coalesce(cast(f.platform_cycle_end AS STRING), '#'))
              ELSE concat(f.billing_month, '|IMSI|', f.imsi, '|', f.platform_product_id, '|',
                          coalesce(cast(f.platform_cycle_start AS STRING), '#'), '|',
                          coalesce(cast(f.platform_cycle_end AS STRING), '#')) END AS stable_platform_card_key
  FROM platform_recon_facts f
  INNER JOIN month_bounds m ON m.billing_month = f.billing_month
),
platform_product_price_stats AS (
  SELECT platform_product_id,
         count(DISTINCT platform_fact_price) AS platform_price_value_count
  FROM platform_fact_keyed
  GROUP BY platform_product_id
),
platform_fact_dup_stats AS (
  SELECT stable_platform_card_key,
         count(*) AS stable_platform_card_row_count
  FROM platform_fact_keyed
  GROUP BY stable_platform_card_key
),
platform_fact_scoped AS (
  SELECT k.*,
         coalesce(ps.platform_price_value_count, 0) AS platform_price_value_count,
         ds.stable_platform_card_row_count,
         CASE WHEN k.platform_supplier_id = 2275
                    AND k.platform_product_id IS NOT NULL
                    AND coalesce(ps.platform_price_value_count, 0) = 1
                    AND k.platform_fact_price IS NOT NULL
                    AND k.platform_cycle_start IS NOT NULL
                    AND k.platform_cycle_end IS NOT NULL
                    AND k.platform_billing_days IS NOT NULL
                    AND k.platform_cycle_days IS NOT NULL
                    AND k.platform_cycle_days > 0
                    AND ds.stable_platform_card_row_count = 1
              THEN 'KNOWN_FULL_PLATFORM_BASELINE'
              WHEN k.platform_product_id IS NULL OR k.platform_supplier_id IS NULL
              THEN 'MISSING_PLATFORM_PRODUCT_OR_SUPPLIER'
              WHEN coalesce(ps.platform_price_value_count, 0) <> 1 OR k.platform_fact_price IS NULL
              THEN 'PLATFORM_PRICE_NOT_UNIQUE_OR_MISSING'
              WHEN k.platform_cycle_start IS NULL OR k.platform_cycle_end IS NULL OR k.platform_billing_days IS NULL
              THEN 'MISSING_EFFECTIVE_WINDOW'
              WHEN ds.stable_platform_card_row_count <> 1
              THEN 'DUPLICATE_STABLE_PLATFORM_CARD_KEY'
              ELSE 'PLATFORM_BASELINE_NOT_PROVABLE' END AS platform_full_amount_evidence_status,
         cast(CASE WHEN k.platform_fact_price IS NULL OR k.platform_billing_days IS NULL
                         OR k.platform_cycle_days IS NULL OR k.platform_cycle_days <= 0
                    THEN NULL
                   WHEN k.platform_baseline_window_rule = 'FULL_MONTH_WINDOW'
                    THEN k.platform_fact_price
                   WHEN k.platform_baseline_window_rule = 'WINDOW_PRORATION'
                    THEN k.platform_fact_price * k.platform_billing_days / nullif(k.platform_cycle_days, 0)
                   ELSE NULL END AS DECIMAL(38,10)) AS platform_calculated_amount
  FROM platform_fact_keyed k
  LEFT JOIN platform_product_price_stats ps ON ps.platform_product_id = k.platform_product_id
  LEFT JOIN platform_fact_dup_stats ds ON ds.stable_platform_card_key = k.stable_platform_card_key
),
platform_fact_scoped_final AS (
  SELECT f.*, CASE WHEN f.platform_full_amount_evidence_status = 'KNOWN_FULL_PLATFORM_BASELINE'
                   THEN f.platform_calculated_amount ELSE NULL END AS platform_calculated_amount_known
  FROM platform_fact_scoped f
),
platform_total_by_month AS (
  SELECT billing_month,
         count(*) AS platform_fact_row_count,
         count(DISTINCT stable_platform_card_key) AS platform_distinct_card_count,
         sum(platform_calculated_amount_known) AS platform_calculated_amount_known,
         sum(CASE WHEN platform_calculated_amount_known IS NULL THEN 1 ELSE 0 END) AS platform_amount_unknown_row_count,
         sum(CASE WHEN platform_full_amount_evidence_status <> 'KNOWN_FULL_PLATFORM_BASELINE' THEN 1 ELSE 0 END) AS platform_evidence_gap_row_count,
         CASE WHEN sum(CASE WHEN platform_calculated_amount_known IS NULL THEN 1 ELSE 0 END) = 0
                    AND count(*) = count(DISTINCT stable_platform_card_key)
              THEN sum(platform_calculated_amount_known)
              ELSE NULL END AS platform_total,
         CASE WHEN sum(CASE WHEN platform_calculated_amount_known IS NULL THEN 1 ELSE 0 END) = 0
                    AND count(*) = count(DISTINCT stable_platform_card_key)
              THEN 'COMPLETE_FULL_SCOPED_PLATFORM_BASELINE'
              ELSE 'UNRESOLVED_PLATFORM_FACT_GAP' END AS platform_total_status
  FROM platform_fact_scoped_final
  GROUP BY billing_month
),
platform_only_cards AS (
  SELECT f.*,
         'PLATFORM_ONLY' AS bridge_status,
         'NO_OVERLAPPING_EXCEL_DETAIL_WINDOW' AS platform_only_reason
  FROM platform_fact_scoped_final f
  WHERE NOT EXISTS (
    SELECT 1 FROM excel_detail e
    WHERE e.official_excel_billing_month = f.billing_month
      AND e.imsi = f.imsi
      AND e.excel_final_start IS NOT NULL
      AND e.excel_final_end IS NOT NULL
      AND f.platform_cycle_start IS NOT NULL
      AND f.platform_cycle_end IS NOT NULL
      AND f.platform_cycle_start <= e.excel_final_end
      AND f.platform_cycle_end >= e.excel_final_start
  )
),
same_card_platform_facts AS (
  SELECT f.*
  FROM platform_fact_scoped_final f
  WHERE EXISTS (
    SELECT 1 FROM excel_detail e
    WHERE e.official_excel_billing_month = f.billing_month
      AND e.imsi = f.imsi
      AND e.excel_final_start IS NOT NULL
      AND e.excel_final_end IS NOT NULL
      AND f.platform_cycle_start IS NOT NULL
      AND f.platform_cycle_end IS NOT NULL
      AND f.platform_cycle_start <= e.excel_final_end
      AND f.platform_cycle_end >= e.excel_final_start
  )
),
wa_only_rows AS (
  SELECT e.*
  FROM finalized e
  WHERE coalesce(e.platform_candidate_count, 0) = 0
),
same_card_excel_rows AS (
  SELECT e.*,
         CASE WHEN e.platform_iccid IS NOT NULL AND trim(e.platform_iccid) <> ''
              THEN concat(e.official_excel_billing_month, '|ICCID|', trim(e.platform_iccid), '|', e.platform_product_id, '|',
                          coalesce(cast(e.platform_cycle_start AS STRING), '#'), '|',
                          coalesce(cast(e.platform_cycle_end AS STRING), '#'))
              ELSE concat(e.official_excel_billing_month, '|IMSI|', e.imsi, '|', e.platform_product_id, '|',
                          coalesce(cast(e.platform_cycle_start AS STRING), '#'), '|',
                          coalesce(cast(e.platform_cycle_end AS STRING), '#')) END AS stable_platform_card_key,
         CASE
           WHEN e.charge_type = 'Credit for Offstocked Card' THEN 'credit'
           WHEN e.charge_type LIKE '%Backbilled%' THEN 'backbill'
           WHEN e.charge_type LIKE '%Replaced%' OR coalesce(e.replacement_event_count, 0) > 0 THEN 'replacement'
           WHEN e.platform_product_mapping_status <> 'PROVEN_BY_PLATFORM_IMSI' THEN 'product'
           WHEN e.day_diff IS NULL OR abs(e.day_diff) > 0.0001 THEN 'days'
           WHEN e.price_diff IS NULL OR abs(e.price_diff) > 0.0001 THEN 'rate'
           WHEN e.rule_id IN ('R_OFFSTOCK_BEFORE_CYCLE_UNRESOLVED','R_UNSUPPORTED_CHARGE_TYPE') THEN 'charge_type'
           WHEN e.amount_diff IS NULL OR abs(e.amount_diff) > 0.0001 THEN 'other'
           ELSE 'none' END AS same_card_difference_category,
         e.platform_calculated_amount - e.excel_amount AS same_card_rule_amount_diff
  FROM finalized e
  WHERE coalesce(e.platform_candidate_count, 0) > 0
),
excel_total_by_month AS (
  SELECT official_excel_billing_month AS billing_month,
         count(*) AS excel_row_count,
         count(DISTINCT imsi) AS excel_distinct_imsi_count,
         sum(excel_amount) AS excel_total
  FROM excel_detail
  GROUP BY official_excel_billing_month
),
wa_only_by_month AS (
  SELECT official_excel_billing_month AS billing_month,
         count(*) AS wa_only_row_count,
         count(DISTINCT imsi) AS wa_only_distinct_imsi_count,
         sum(excel_amount) AS wa_only_amount
  FROM wa_only_rows
  GROUP BY official_excel_billing_month
),
same_card_excel_by_month AS (
  SELECT official_excel_billing_month AS billing_month,
         count(*) AS same_card_excel_row_count,
         count(DISTINCT imsi) AS same_card_excel_distinct_imsi_count,
         sum(excel_amount) AS same_card_excel_amount,
         sum(same_card_rule_amount_diff) AS same_card_rule_diff_total
  FROM same_card_excel_rows
  GROUP BY official_excel_billing_month
),
same_card_platform_by_month AS (
  SELECT billing_month,
         count(*) AS same_card_platform_fact_row_count,
         count(DISTINCT stable_platform_card_key) AS same_card_platform_card_count,
         sum(platform_calculated_amount_known) AS same_card_platform_amount,
         sum(CASE WHEN platform_calculated_amount_known IS NULL THEN 1 ELSE 0 END) AS same_card_platform_unknown_row_count
  FROM same_card_platform_facts
  GROUP BY billing_month
),
platform_only_by_month AS (
  SELECT billing_month,
         count(*) AS platform_only_row_count,
         count(DISTINCT stable_platform_card_key) AS platform_only_card_count,
         sum(platform_calculated_amount_known) AS platform_only_amount,
         sum(CASE WHEN platform_calculated_amount_known IS NULL THEN 1 ELSE 0 END) AS platform_only_unknown_row_count
  FROM platform_only_cards
  GROUP BY billing_month
),
same_card_difference_by_month AS (
  SELECT official_excel_billing_month AS billing_month,
         same_card_difference_category,
         count(*) AS row_count,
         count(DISTINCT imsi) AS distinct_imsi_count,
         sum(same_card_rule_amount_diff) AS category_amount_diff
  FROM same_card_excel_rows
  GROUP BY official_excel_billing_month, same_card_difference_category
),
bridge_summary AS (
  SELECT m.billing_month,
         e.excel_row_count,
         e.excel_distinct_imsi_count,
         e.excel_total,
         p.platform_fact_row_count,
         p.platform_distinct_card_count,
         p.platform_calculated_amount_known,
         p.platform_total,
         p.platform_total_status,
         coalesce(po.platform_only_row_count, 0) AS platform_only_row_count,
         coalesce(po.platform_only_card_count, 0) AS platform_only_card_count,
         po.platform_only_amount,
         coalesce(sc.same_card_excel_row_count, 0) AS same_card_excel_row_count,
         coalesce(sc.same_card_excel_distinct_imsi_count, 0) AS same_card_excel_distinct_imsi_count,
         sc.same_card_excel_amount,
         sc.same_card_rule_diff_total,
         sf.same_card_platform_fact_row_count,
         sf.same_card_platform_card_count,
         sf.same_card_platform_amount,
         coalesce(wa.wa_only_row_count, 0) AS wa_only_row_count,
         coalesce(wa.wa_only_distinct_imsi_count, 0) AS wa_only_distinct_imsi_count,
         coalesce(wa.wa_only_amount, 0) AS wa_only_amount,
         (sf.same_card_platform_amount - sc.same_card_excel_amount) AS same_card_baseline_diff,
         (sf.same_card_platform_amount - sc.same_card_excel_amount) - sc.same_card_rule_diff_total AS model_adjustment_amount,
         p.platform_total - e.excel_total AS bridge_left_platform_minus_excel,
         po.platform_only_amount + (sf.same_card_platform_amount - sc.same_card_excel_amount) - coalesce(wa.wa_only_amount, 0) AS bridge_right_without_adjustment,
         po.platform_only_amount + sc.same_card_rule_diff_total - coalesce(wa.wa_only_amount, 0)
           + ((sf.same_card_platform_amount - sc.same_card_excel_amount) - sc.same_card_rule_diff_total) AS bridge_right_with_adjustment,
         (p.platform_total - e.excel_total) -
         (po.platform_only_amount + sc.same_card_rule_diff_total - coalesce(wa.wa_only_amount, 0)
           + ((sf.same_card_platform_amount - sc.same_card_excel_amount) - sc.same_card_rule_diff_total)) AS bridge_residual
  FROM month_bounds m
  LEFT JOIN excel_total_by_month e ON e.billing_month = m.billing_month
  LEFT JOIN platform_total_by_month p ON p.billing_month = m.billing_month
  LEFT JOIN platform_only_by_month po ON po.billing_month = m.billing_month
  LEFT JOIN same_card_excel_by_month sc ON sc.billing_month = m.billing_month
  LEFT JOIN same_card_platform_by_month sf ON sf.billing_month = m.billing_month
  LEFT JOIN wa_only_by_month wa ON wa.billing_month = m.billing_month
)SELECT * FROM bridge_summary