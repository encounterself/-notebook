-- B replay only: 2025-12 and 2026-02 platform-imsi formal Candidate SQL.\r\n-- Platform lifecycle scope extends through 2026-01 for the explicit 2026-01 platform-only control.
-- Read-only SELECT/WITH only. Formal billing branch is wa_invoice_detail.
-- Platform price is sourced by product_id from resource_res_vsim_product.
-- Excel product_id is intentionally NULL because wa_invoice_detail has no product_id.
WITH excel_detail_raw AS (
  SELECT
    TRIM(CAST(d.source_file AS STRING)) AS source_file,
    CASE
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%JAN 2025%' THEN '2025-01'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%SEP 2025%' THEN '2025-09'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%OCT 2025%'
       AND TRIM(CAST(d.source_file AS STRING)) LIKE '%773,793.84%' THEN '2025-10 (v2)'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%OCT 2025%'
       AND TRIM(CAST(d.source_file AS STRING)) LIKE '%772,765.00%' THEN '2025-10 (v1)'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%DEC 2025%' THEN '2025-12'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%FEB 2026%' THEN '2026-02'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%MAR 2026%' THEN '2026-03'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%APR 2026%' THEN '2026-04'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%MAY 2026%' THEN '2026-05'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%JUNE 2026%' THEN '2026-06'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%JULY 2026%' THEN '2026-07'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%AUGUST 2026%' THEN '2026-08'
      ELSE TRIM(CAST(d.source_file AS STRING))
    END AS invoice_batch_label,
    TRIM(CAST(d.imsi AS STRING)) AS imsi,
    NULLIF(TRIM(CAST(d.charge_type AS STRING)), '') AS charge_type,
    NULLIF(TRY_TO_DATE(TRIM(CAST(d.cycle_start_date AS STRING))), DATE '0001-01-01') AS excel_cycle_start_date,
    NULLIF(TRY_TO_DATE(TRIM(CAST(d.cycle_end_date AS STRING))), DATE '0001-01-01') AS excel_cycle_end_date,
    NULLIF(TRY_TO_DATE(TRIM(CAST(d.new_activation_date AS STRING))), DATE '0001-01-01') AS excel_new_activation_date,
    NULLIF(TRY_TO_DATE(TRIM(CAST(d.offstock_date AS STRING))), DATE '0001-01-01') AS excel_offstock_date,
    NULLIF(TRY_TO_DATE(TRIM(CAST(d.final_start_date AS STRING))), DATE '0001-01-01') AS excel_final_start_date,
    NULLIF(TRY_TO_DATE(TRIM(CAST(d.final_end_date AS STRING))), DATE '0001-01-01') AS excel_final_end_date,
    TRY_CAST(NULLIF(TRIM(CAST(d.final_days AS STRING)), '') AS DECIMAL(38,12)) AS excel_days,
    TRY_CAST(NULLIF(TRIM(CAST(d.monthly_rate AS STRING)), '') AS DECIMAL(38,12)) AS excel_price,
    TRY_CAST(NULLIF(TRIM(CAST(d.final_charge AS STRING)), '') AS DECIMAL(38,12)) AS excel_amount,
    TRIM(CAST(d.product_name AS STRING)) AS excel_product_name,
    TRIM(CAST(d.new_card_imsi_replacement AS STRING)) AS excel_new_card_imsi_replacement,
    TRIM(CAST(d.old_card_imsi_replaced AS STRING)) AS excel_old_card_imsi_replaced,
    TRIM(CAST(d.transferred_to_wing_simbank AS STRING)) AS excel_transferred_to_wing_simbank,
    CAST(NULL AS STRING) AS excel_product_id,
    TRIM(CAST(d.sheet_name AS STRING)) AS excel_sheet_name,
    TRIM(CAST(d.note AS STRING)) AS excel_note
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail d
  WHERE TRIM(CAST(d.source_file AS STRING)) LIKE '%DEC 2025%'
     OR TRIM(CAST(d.source_file AS STRING)) LIKE '%FEB 2026%'
),
excel_detail_fingerprinted AS (
  SELECT
    e.*,
    DATE_FORMAT(e.excel_final_start_date, 'yyyy-MM') AS observed_start_month,
    SHA2(CONCAT_WS('||',
      COALESCE(e.source_file, '<NULL>'),
      COALESCE(e.imsi, '<NULL>'),
      COALESCE(e.charge_type, '<NULL>'),
      COALESCE(CAST(e.excel_cycle_start_date AS STRING), '<NULL>'),
      COALESCE(CAST(e.excel_cycle_end_date AS STRING), '<NULL>'),
      COALESCE(CAST(e.excel_final_start_date AS STRING), '<NULL>'),
      COALESCE(CAST(e.excel_final_end_date AS STRING), '<NULL>'),
      COALESCE(CAST(e.excel_days AS STRING), '<NULL>'),
      COALESCE(CAST(e.excel_price AS STRING), '<NULL>'),
      COALESCE(CAST(e.excel_amount AS STRING), '<NULL>'),
      COALESCE(e.excel_product_name, '<NULL>')
    ), 256) AS excel_fingerprint
  FROM excel_detail_raw e
),
excel_detail_ranked AS (
  SELECT
    e.*,
    ROW_NUMBER() OVER (
      PARTITION BY e.excel_fingerprint
      ORDER BY e.imsi, e.excel_final_start_date, e.excel_final_end_date,
               e.excel_amount, e.excel_price, e.excel_product_name
    ) AS excel_duplicate_seq
  FROM excel_detail_fingerprinted e
),
excel_detail_invoice AS (
  SELECT
    CONCAT(e.excel_fingerprint, '#', CAST(e.excel_duplicate_seq AS STRING)) AS excel_row_id,
    e.*
  FROM excel_detail_ranked e
  WHERE e.invoice_batch_label IN ('2025-12', '2026-02')
),
target_product_rows AS (
  SELECT
    TRIM(CAST(p.product_id AS STRING)) AS product_id,
    TRIM(CAST(p.product_name AS STRING)) AS product_name,
    CAST(p.supplier_id AS BIGINT) AS supplier_id,
    CAST(p.package_price AS DECIMAL(38,12)) AS package_price,
    CAST(p.package_price_withusd AS DECIMAL(38,12)) AS package_price_withusd,
    CAST(p.monthly_rent AS DECIMAL(38,12)) AS monthly_rent,
    CAST(p.monthly_rent_withusd AS DECIMAL(38,12)) AS monthly_rent_withusd,
    TRIM(CAST(p.time_zone AS STRING)) AS product_time_zone,
    TRIM(CAST(p.billing_cycle AS STRING)) AS billing_cycle,
    CAST(p.status AS INT) AS product_status
  FROM simo_prod.ods.resource_res_vsim_product p
  WHERE CAST(p.supplier_id AS BIGINT) = 2275
),
target_product_evidence AS (
  SELECT
    product_id,
    COUNT(*) AS product_catalog_row_count,
    COUNT(DISTINCT product_name) AS product_name_count,
    COUNT(DISTINCT package_price) AS distinct_package_price_count,
    COUNT(DISTINCT package_price_withusd) AS distinct_package_price_withusd_count,
    CASE WHEN COUNT(DISTINCT package_price) = 1 THEN MIN(package_price) END AS platform_package_price,
    CASE WHEN COUNT(DISTINCT package_price_withusd) = 1 THEN MIN(package_price_withusd) END AS platform_package_price_withusd,
    CASE WHEN COUNT(DISTINCT product_name) = 1 THEN MIN(product_name) END AS platform_product_name,
    CASE WHEN COUNT(DISTINCT product_time_zone) = 1 THEN MIN(product_time_zone) END AS platform_product_time_zone,
    CASE WHEN COUNT(DISTINCT billing_cycle) = 1 THEN MIN(billing_cycle) END AS platform_billing_cycle,
    CASE
      WHEN COUNT(DISTINCT package_price) = 0 THEN 'MISSING_PRICE'
      WHEN COUNT(DISTINCT package_price) = 1 THEN 'ONE_PRICE'
      ELSE 'MULTIPLE_PRICES'
    END AS platform_price_evidence_status
  FROM target_product_rows
  GROUP BY product_id
),
platform_cycle_rows AS (
  SELECT
    TRIM(CAST(h.imsi AS STRING)) AS imsi,
    TRIM(CAST(h.product_id AS STRING)) AS product_id,
    CAST(h.cycle_time AS TIMESTAMP) AS cycle_start_ts,
    CAST(h.next_cycle_time AS TIMESTAMP) AS cycle_end_ts,
    TO_DATE(CAST(h.cycle_time AS TIMESTAMP)) AS cycle_start_date,
    TO_DATE(CAST(h.next_cycle_time AS TIMESTAMP)) AS cycle_end_date,
    CAST(h.package_price AS DECIMAL(38,12)) AS cycle_history_package_price,
    TRIM(CAST(h.time_zone AS STRING)) AS cycle_time_zone
  FROM simo_prod.ods.resource_res_vsim_cycle_history h
  INNER JOIN target_product_evidence p
    ON TRIM(CAST(h.product_id AS STRING)) = p.product_id
  WHERE CAST(h.cycle_time AS TIMESTAMP) < TIMESTAMP '2026-04-01 00:00:00'
    AND CAST(h.next_cycle_time AS TIMESTAMP) > TIMESTAMP '2025-12-01 00:00:00'
),
platform_cycle_lifecycle AS (
  SELECT
    c.imsi,
    c.product_id,
    c.cycle_start_date,
    c.cycle_end_date,
    p.platform_product_name,
    p.platform_package_price,
    p.platform_package_price_withusd,
    p.platform_product_time_zone,
    p.platform_billing_cycle,
    p.platform_price_evidence_status,
    p.product_catalog_row_count,
    p.product_name_count,
    p.distinct_package_price_count,
    COUNT(*) AS cycle_history_row_count,
    COUNT(DISTINCT c.cycle_history_package_price) AS distinct_cycle_history_price_count,
    CASE WHEN COUNT(DISTINCT c.cycle_history_package_price) = 1
         THEN MIN(c.cycle_history_package_price) END AS cycle_history_package_price,
    COUNT(DISTINCT c.cycle_time_zone) AS distinct_cycle_time_zone_count,
    CASE WHEN COUNT(DISTINCT c.cycle_time_zone) = 1
         THEN MIN(c.cycle_time_zone) END AS cycle_history_time_zone
  FROM platform_cycle_rows c
  INNER JOIN target_product_evidence p
    ON c.product_id = p.product_id
  GROUP BY
    c.imsi, c.product_id, c.cycle_start_date, c.cycle_end_date,
    p.platform_product_name, p.platform_package_price,
    p.platform_package_price_withusd, p.platform_product_time_zone,
    p.platform_billing_cycle, p.platform_price_evidence_status,
    p.product_catalog_row_count, p.product_name_count,
    p.distinct_package_price_count
),
platform_card_set AS (
  SELECT DISTINCT imsi, product_id, cycle_start_date, cycle_end_date
  FROM platform_cycle_lifecycle
),
platform_card_imsi_product AS (
  SELECT DISTINCT imsi, product_id
  FROM platform_card_set
),
platform_status_rows_b_scope AS (
  SELECT
    TRIM(CAST(s.imsi AS STRING)) AS imsi,
    TRIM(CAST(s.product_id AS STRING)) AS product_id,
    CAST(s.year AS INT) AS partition_year,
    CAST(s.month AS INT) AS partition_month,
    TRIM(CAST(s.partition_time AS STRING)) AS partition_time,
    TRIM(CAST(s.SimStatus AS STRING)) AS sim_status,
    TRIM(CAST(s.DispatchStatus AS STRING)) AS dispatch_status
  FROM simo_prod.tc_cdr.sim_status_for_sftp_bak s
  INNER JOIN platform_card_imsi_product c
    ON TRIM(CAST(s.imsi AS STRING)) = c.imsi
   AND TRIM(CAST(s.product_id AS STRING)) = c.product_id
  WHERE ((CAST(s.year AS INT) = 2025 AND CAST(s.month AS INT) = 12) OR (CAST(s.year AS INT) = 2026 AND CAST(s.month AS INT) IN (1, 2, 3)))
),
platform_status_summary AS (
  SELECT
    imsi,
    product_id,
    COUNT(*) AS status_snapshot_row_count_b_scope,
    COUNT(DISTINCT partition_time) AS status_snapshot_partition_count_b_scope,
    COUNT(DISTINCT sim_status) AS distinct_sim_status_count_b_scope,
    COUNT(DISTINCT dispatch_status) AS distinct_dispatch_status_count_b_scope,
    MIN(partition_time) AS first_status_partition_time_b_scope,
    MAX(partition_time) AS last_status_partition_time_b_scope
  FROM platform_status_rows_b_scope
  GROUP BY imsi, product_id
),
platform_status_log_summary AS (
  SELECT
    TRIM(CAST(l.IMSI AS STRING)) AS imsi,
    COUNT(*) AS status_log_row_count_target_months,
    COUNT(DISTINCT TRIM(CAST(l.PRE_STATUS AS STRING))) AS status_log_pre_status_count,
    COUNT(DISTINCT TRIM(CAST(l.NEXT_STATUS AS STRING))) AS status_log_next_status_count,
    MIN(CAST(l.CREATE_DATE AS TIMESTAMP)) AS status_log_first_create_date,
    MAX(CAST(l.CREATE_DATE AS TIMESTAMP)) AS status_log_last_create_date
  FROM simo_prod.ods.resource_res_vsim_status_log l
  INNER JOIN (SELECT DISTINCT imsi FROM platform_card_set) c
    ON TRIM(CAST(l.IMSI AS STRING)) = c.imsi
  WHERE TRY_TO_DATE(TRIM(CAST(l.partition_date AS STRING))) >= DATE '2025-12-01'
    AND TRY_TO_DATE(TRIM(CAST(l.partition_date AS STRING))) < DATE '2026-04-01'
  GROUP BY TRIM(CAST(l.IMSI AS STRING))
),
platform_cycle_candidates_raw AS (
  SELECT
    x.*,
    l.product_id AS platform_product_id,
    l.platform_product_name,
    l.platform_package_price,
    l.platform_package_price_withusd,
    l.platform_product_time_zone,
    l.platform_billing_cycle,
    l.platform_price_evidence_status,
    l.product_catalog_row_count,
    l.product_name_count,
    l.distinct_package_price_count,
    l.cycle_start_date AS platform_cycle_start_date,
    l.cycle_end_date AS platform_cycle_end_date,
    l.cycle_history_row_count,
    l.distinct_cycle_history_price_count,
    l.cycle_history_package_price,
    l.distinct_cycle_time_zone_count,
    l.cycle_history_time_zone,
    s.status_snapshot_row_count_b_scope,
    s.status_snapshot_partition_count_b_scope,
    s.distinct_sim_status_count_b_scope,
    s.distinct_dispatch_status_count_b_scope,
    s.first_status_partition_time_b_scope,
    s.last_status_partition_time_b_scope,
    z.status_log_row_count_target_months,
    z.status_log_pre_status_count,
    z.status_log_next_status_count,
    z.status_log_first_create_date,
    z.status_log_last_create_date,
    COUNT(l.imsi) OVER (PARTITION BY x.excel_row_id) AS platform_candidate_count,
    ROW_NUMBER() OVER (
      PARTITION BY x.excel_row_id
      ORDER BY
        CASE
          WHEN x.excel_cycle_start_date IS NOT NULL
           AND x.excel_cycle_end_date IS NOT NULL
           AND l.cycle_start_date = x.excel_cycle_start_date
           AND l.cycle_end_date = x.excel_cycle_end_date THEN 0
          ELSE 1
        END,
        CASE
          WHEN l.cycle_start_date IS NOT NULL
           AND x.excel_final_start_date IS NOT NULL
           AND x.excel_final_end_date IS NOT NULL
          THEN DATEDIFF(
            LEAST(x.excel_final_end_date, l.cycle_end_date),
            GREATEST(x.excel_final_start_date, l.cycle_start_date)
          )
          ELSE 999999
        END DESC,
        l.product_id
    ) AS platform_candidate_rank
  FROM excel_detail_invoice x
  LEFT JOIN platform_cycle_lifecycle l
    ON x.imsi = l.imsi
   AND (
        (
          x.excel_cycle_start_date IS NOT NULL
          AND x.excel_cycle_end_date IS NOT NULL
          AND l.cycle_start_date = x.excel_cycle_start_date
          AND l.cycle_end_date = x.excel_cycle_end_date
        )
        OR
        (
          x.excel_final_start_date IS NOT NULL
          AND x.excel_final_end_date IS NOT NULL
          AND l.cycle_start_date <= x.excel_final_end_date
          AND l.cycle_end_date >= x.excel_final_start_date
        )
      )
  LEFT JOIN platform_status_summary s
    ON l.imsi = s.imsi
   AND l.product_id = s.product_id
  LEFT JOIN platform_status_log_summary z
    ON l.imsi = z.imsi
),
platform_candidate_selected AS (
  SELECT *
  FROM platform_cycle_candidates_raw
  WHERE platform_candidate_rank = 1
),
platform_rule_assigned AS (
  SELECT
    c.*,
    CASE
      WHEN c.charge_type IN ('Full Rate', 'Full Cycle Charge') THEN 'R_FULL_CYCLE_PRICE'
      WHEN c.charge_type LIKE 'Partial Charge%' THEN 'R_PARTIAL_LIFECYCLE_DAYS_ACTIVATION_MONTH'
      WHEN c.charge_type LIKE 'Prorated-in Charge%'
        OR c.charge_type LIKE 'Prorated-out Charge%'
        OR c.charge_type LIKE 'New Activation:%'
        THEN 'R_PRORATED_LIFECYCLE_DAYS_ACTIVATION_MONTH'
      WHEN c.charge_type = 'Credit for Offstocked Card' THEN 'R_CREDIT_REQUIRES_CREDIT_EVIDENCE'
      ELSE 'R_UNMAPPED_CHARGE_TYPE'
    END AS rule_id
  FROM platform_candidate_selected c
),
platform_days_calculated AS (
  SELECT
    c.*,
    CASE
      WHEN c.platform_product_id IS NOT NULL
       AND c.excel_final_start_date IS NOT NULL
       AND c.excel_final_end_date IS NOT NULL
       AND c.platform_cycle_start_date IS NOT NULL
       AND c.platform_cycle_end_date IS NOT NULL
       AND DATEDIFF(
         LEAST(c.excel_final_end_date, c.platform_cycle_end_date),
         GREATEST(c.excel_final_start_date, c.platform_cycle_start_date)
       ) >= 0
      THEN CAST(DATEDIFF(
         LEAST(c.excel_final_end_date, c.platform_cycle_end_date),
         GREATEST(c.excel_final_start_date, c.platform_cycle_start_date)
       ) + 1 AS DECIMAL(38,12))
    END AS platform_calculated_days
  FROM platform_rule_assigned c
),
platform_denominator_assigned AS (
  SELECT
    c.*,
    CASE
      WHEN c.charge_type LIKE 'Partial Charge%' THEN c.excel_cycle_start_date
      WHEN c.charge_type LIKE 'Prorated-in Charge%'
        OR c.charge_type LIKE 'Prorated-out Charge%' THEN c.excel_final_start_date
      WHEN c.charge_type LIKE 'New Activation:%' THEN COALESCE(c.excel_new_activation_date, c.excel_final_start_date)
      ELSE COALESCE(c.excel_new_activation_date, c.excel_final_start_date)
    END AS proration_denominator_date
  FROM platform_days_calculated c
),
platform_amount_calculated AS (
  SELECT
    c.*,
    CASE
      WHEN c.rule_id = 'R_FULL_CYCLE_PRICE'
       AND c.platform_price_evidence_status = 'ONE_PRICE'
      THEN c.platform_package_price
      WHEN c.rule_id IN ('R_PARTIAL_LIFECYCLE_DAYS_ACTIVATION_MONTH',
                         'R_PRORATED_LIFECYCLE_DAYS_ACTIVATION_MONTH')
       AND c.platform_price_evidence_status = 'ONE_PRICE'
       AND c.platform_calculated_days IS NOT NULL
       AND c.proration_denominator_date IS NOT NULL
      THEN CAST(
        c.platform_package_price
        * c.platform_calculated_days
        / CAST(DAY(LAST_DAY(c.proration_denominator_date)) AS DECIMAL(38,12))
        AS DECIMAL(38,12)
      )
    END AS platform_calculated_amount,
    DATE_FORMAT(c.proration_denominator_date, 'yyyy-MM') AS proration_denominator_month,
    DAY(LAST_DAY(c.proration_denominator_date)) AS proration_denominator_days
  FROM platform_denominator_assigned c
),
platform_diffs AS (
  SELECT
    c.*,
    CASE WHEN c.platform_calculated_days IS NOT NULL AND c.excel_days IS NOT NULL
         THEN c.platform_calculated_days - c.excel_days END AS day_diff,
    CASE WHEN c.platform_package_price IS NOT NULL AND c.excel_price IS NOT NULL
         THEN c.platform_package_price - c.excel_price END AS price_diff,
    CASE WHEN c.platform_calculated_amount IS NOT NULL AND c.excel_amount IS NOT NULL
         THEN c.platform_calculated_amount - c.excel_amount END AS amount_diff,
    CASE
      WHEN c.platform_candidate_count = 0 THEN 'NO_PLATFORM_CYCLE_FOR_IMSI_EXCEL_WINDOW'
      WHEN c.platform_candidate_count > 1 THEN 'MULTIPLE_PLATFORM_CYCLE_CANDIDATES'
      WHEN c.platform_price_evidence_status = 'MISSING_PRICE' THEN 'PLATFORM_PRODUCT_PRICE_MISSING'
      WHEN c.platform_price_evidence_status = 'MULTIPLE_PRICES' THEN 'PLATFORM_PRODUCT_HAS_MULTIPLE_PRICES'
      WHEN c.rule_id IN ('R_CREDIT_REQUIRES_CREDIT_EVIDENCE', 'R_UNMAPPED_CHARGE_TYPE')
        THEN 'CHARGE_TYPE_RULE_NOT_PROVEN_FOR_DETAIL_RECALC'
      WHEN c.platform_calculated_days IS NULL
        THEN 'PLATFORM_DAYS_MISSING_FROM_LIFECYCLE_WINDOW'
      WHEN c.platform_calculated_amount IS NULL
        THEN 'PLATFORM_AMOUNT_NOT_CALCULABLE_FROM_CANDIDATE_FIELDS'
      WHEN ABS(c.platform_calculated_days - c.excel_days) > CAST(0.000001 AS DECIMAL(38,12))
        THEN 'DAY_ERROR'
      WHEN ABS(c.platform_package_price - c.excel_price) > CAST(0.000001 AS DECIMAL(38,12))
        THEN 'PRICE_ERROR'
      WHEN ABS(c.platform_calculated_amount - c.excel_amount) > CAST(0.00001 AS DECIMAL(38,12))
        THEN 'AMOUNT_ERROR'
      WHEN c.excel_product_id IS NULL
        THEN 'NUMERIC_MATCH_BUT_EXCEL_PRODUCT_ID_NULL'
      ELSE 'MATCHED_NUMERIC_EVIDENCE'
    END AS difference_reason,
    CASE
      WHEN c.platform_candidate_count = 0 THEN 'NO_PLATFORM'
      WHEN c.platform_candidate_count > 1 THEN 'AMBIGUOUS_PLATFORM_CANDIDATE'
      WHEN c.rule_id IN ('R_CREDIT_REQUIRES_CREDIT_EVIDENCE', 'R_UNMAPPED_CHARGE_TYPE')
        THEN 'UNSUPPORTED_RULE'
      WHEN c.platform_calculated_days IS NULL
        OR c.platform_package_price IS NULL
        OR c.platform_calculated_amount IS NULL
        THEN 'MISSING_DATA'
      WHEN ABS(c.platform_calculated_days - c.excel_days) <= CAST(0.000001 AS DECIMAL(38,12))
       AND ABS(c.platform_package_price - c.excel_price) <= CAST(0.000001 AS DECIMAL(38,12))
       AND ABS(c.platform_calculated_amount - c.excel_amount) <= CAST(0.00001 AS DECIMAL(38,12))
        THEN 'MATCHED'
      ELSE 'NUMERIC_MISMATCH'
    END AS numeric_match_status
  FROM platform_amount_calculated c
),
reconciliation_rows AS (
  SELECT
    p.*,
    CASE
      WHEN p.platform_candidate_count = 0 THEN 'WA_ONLY'
      WHEN p.platform_candidate_count > 1 THEN 'UNRESOLVED'
      WHEN p.platform_price_evidence_status IN ('MISSING_PRICE', 'MULTIPLE_PRICES') THEN 'MISSING_DATA'
      WHEN p.numeric_match_status = 'UNSUPPORTED_RULE' THEN 'UNRESOLVED'
      WHEN p.numeric_match_status = 'MISSING_DATA' THEN 'MISSING_DATA'
      WHEN p.excel_product_id IS NULL THEN 'MISSING_MAPPING'
      WHEN p.numeric_match_status = 'MATCHED' THEN 'MATCHED'
      ELSE 'UNRESOLVED'
    END AS source_match_status
  FROM platform_diffs p
)
, platform_proven_formal_rows AS (
  SELECT
    r.*,
    CASE
      WHEN r.platform_candidate_count = 0 THEN 'NO_PLATFORM_PRODUCT'
      WHEN r.platform_candidate_count > 1 THEN 'MULTIPLE_PLATFORM_PRODUCTS_OR_WINDOWS'
      WHEN r.platform_product_id IS NULL THEN 'MISSING_PLATFORM_PRODUCT'
      WHEN r.platform_price_evidence_status <> 'ONE_PRICE' THEN 'PLATFORM_PRODUCT_PRICE_NOT_PROVEN'
      ELSE 'PROVEN_BY_PLATFORM_IMSI'
    END AS platform_product_mapping_status,
    CASE
      WHEN r.platform_candidate_count = 0 AND r.charge_type = 'Credit for Offstocked Card' THEN 'WA_ONLY'
      WHEN r.platform_candidate_count = 0 THEN 'MISSING_MAPPING'
      WHEN r.platform_candidate_count > 1 THEN 'UNRESOLVED'
      WHEN r.platform_product_id IS NULL THEN 'MISSING_MAPPING'
      WHEN r.platform_price_evidence_status <> 'ONE_PRICE' THEN 'MISSING_MAPPING'
      WHEN r.rule_id IN ('R_CREDIT_REQUIRES_CREDIT_EVIDENCE', 'R_UNMAPPED_CHARGE_TYPE') THEN 'UNRESOLVED'
      WHEN r.platform_calculated_days IS NULL OR r.excel_days IS NULL
        OR r.platform_package_price IS NULL OR r.excel_price IS NULL
        OR r.platform_calculated_amount IS NULL OR r.excel_amount IS NULL THEN 'MISSING_DATA'
      WHEN (LOWER(COALESCE(r.charge_type, '')) LIKE '%replacement%'
         OR LOWER(COALESCE(r.excel_note, '')) LIKE '%replacement%')
       AND NULLIF(COALESCE(r.excel_new_card_imsi_replacement, ''), '') IS NULL
       AND NULLIF(COALESCE(r.excel_old_card_imsi_replaced, ''), '') IS NULL THEN 'MISSING_MAPPING'
      WHEN (LOWER(COALESCE(r.charge_type, '')) LIKE '%transfer%'
         OR LOWER(COALESCE(r.charge_type, '')) LIKE '%simbank%'
         OR LOWER(COALESCE(r.excel_note, '')) LIKE '%transfer%'
         OR LOWER(COALESCE(r.excel_note, '')) LIKE '%simbank%')
       AND NULLIF(COALESCE(r.excel_transferred_to_wing_simbank, ''), '') IS NULL THEN 'MISSING_MAPPING'
      WHEN r.numeric_match_status <> 'MATCHED' THEN 'UNRESOLVED'
      ELSE 'MATCHED'
    END AS formal_match_status,
    CASE
      WHEN r.platform_candidate_count = 1
       AND r.rule_id IN ('R_FULL_CYCLE_PRICE', 'R_PARTIAL_LIFECYCLE_DAYS_ACTIVATION_MONTH', 'R_PRORATED_LIFECYCLE_DAYS_ACTIVATION_MONTH')
       AND r.platform_price_evidence_status = 'ONE_PRICE'
       AND r.platform_calculated_days IS NOT NULL
       AND r.platform_package_price IS NOT NULL
       AND r.platform_calculated_amount IS NOT NULL
      THEN r.platform_calculated_amount
    END AS platform_calculated_amount_known
  FROM reconciliation_rows r
)
, platform_proven_formal_rows_final AS (
  SELECT
    p.*,
    CASE
      WHEN p.formal_match_status = 'MATCHED' THEN 'FORMAL_MATCH_PROVEN_BY_PLATFORM_IMSI'
      WHEN p.formal_match_status = 'WA_ONLY' THEN 'NO_PLATFORM_CANDIDATE_FOR_EXCEL_ROW'
      WHEN p.formal_match_status = 'UNRESOLVED' AND p.platform_candidate_count > 1 THEN 'MULTIPLE_PLATFORM_PRODUCTS_OR_WINDOWS'
      WHEN p.formal_match_status = 'MISSING_MAPPING' THEN p.platform_product_mapping_status
      ELSE p.difference_reason
    END AS formal_difference_reason
  FROM platform_proven_formal_rows p
)
, target_months AS (
  SELECT '2025-12' AS invoice_batch_label, DATE '2025-12-01' AS month_start, DATE '2026-01-01' AS month_end
  UNION ALL SELECT '2026-02', DATE '2026-02-01', DATE '2026-03-01'
)
, platform_cards AS (
  SELECT t.invoice_batch_label,t.month_start,t.month_end,CAST(2275 AS BIGINT) AS platform_supplier_id,
    l.imsi,l.product_id AS platform_product_id,MAX(l.platform_product_name) AS platform_product_name,
    MAX(l.platform_package_price) AS platform_price,MAX(l.platform_price_evidence_status) AS platform_price_evidence_status,
    l.cycle_start_date AS platform_cycle_start_date,l.cycle_end_date AS platform_cycle_end_date,
    SUM(l.cycle_history_row_count) AS platform_source_row_count,
    COUNT(DISTINCT l.platform_package_price) AS stable_key_distinct_price_count,
    DATEDIFF(LEAST(l.cycle_end_date,t.month_end),GREATEST(l.cycle_start_date,t.month_start)) AS target_overlap_days,
    CASE WHEN l.cycle_start_date>=t.month_start AND l.cycle_end_date<=t.month_end THEN 'PROVEN_FULL_WINDOW_IN_TARGET_MONTH'
      ELSE 'OVERLAP_ONLY_CYCLE_CROSSES_TARGET_BOUNDARY' END AS target_period_proof,
    CONCAT_WS('||',t.invoice_batch_label,l.imsi,l.product_id,CAST(l.cycle_start_date AS STRING),CAST(l.cycle_end_date AS STRING)) AS platform_card_window_key,
    'IMSI_PRODUCT_EFFECTIVE_WINDOW' AS platform_card_key_type
  FROM target_months t INNER JOIN platform_cycle_lifecycle l
    ON l.cycle_start_date<t.month_end AND l.cycle_end_date>t.month_start
  GROUP BY t.invoice_batch_label,t.month_start,t.month_end,l.imsi,l.product_id,l.cycle_start_date,l.cycle_end_date
)
, platform_cards_priced AS (
  SELECT p.*,CASE WHEN p.platform_price_evidence_status='ONE_PRICE' AND p.stable_key_distinct_price_count<=1 AND p.platform_price IS NOT NULL THEN p.platform_price END AS platform_amount,
    CASE WHEN p.platform_price_evidence_status='ONE_PRICE' AND p.stable_key_distinct_price_count<=1 AND p.platform_price IS NOT NULL THEN 'FULL_CYCLE_PACKAGE_PRICE' ELSE 'PRICE_NOT_PROVEN' END AS platform_amount_basis
  FROM platform_cards p
)
, candidate_card_presence AS (
  SELECT DISTINCT c.invoice_batch_label,c.platform_product_id,c.platform_cycle_start_date,c.platform_cycle_end_date,
    CONCAT_WS('||',c.invoice_batch_label,c.imsi,c.platform_product_id,CAST(c.platform_cycle_start_date AS STRING),CAST(c.platform_cycle_end_date AS STRING)) AS platform_card_window_key
  FROM platform_cycle_candidates_raw c INNER JOIN platform_cards_priced p
    ON p.invoice_batch_label=c.invoice_batch_label AND p.imsi=c.imsi AND p.platform_product_id=c.platform_product_id
   AND p.platform_cycle_start_date=c.platform_cycle_start_date AND p.platform_cycle_end_date=c.platform_cycle_end_date
  WHERE c.platform_product_id IS NOT NULL
)
, candidate_card_count AS (
  SELECT invoice_batch_label,platform_card_window_key,COUNT(*) AS candidate_presence_count
  FROM candidate_card_presence GROUP BY invoice_batch_label,platform_card_window_key
)
, excel_assign AS (
  SELECT p.*,CASE WHEN p.platform_product_id IS NOT NULL AND p.platform_cycle_start_date IS NOT NULL AND p.platform_cycle_end_date IS NOT NULL
    THEN CONCAT_WS('||',p.invoice_batch_label,p.imsi,p.platform_product_id,CAST(p.platform_cycle_start_date AS STRING),CAST(p.platform_cycle_end_date AS STRING)) END AS selected_card_key
  FROM platform_proven_formal_rows_final p
)
, excel_by_card AS (
  SELECT invoice_batch_label,selected_card_key AS platform_card_window_key,COUNT(*) AS excel_row_count,COUNT(DISTINCT imsi) AS excel_distinct_imsi_count,SUM(excel_amount) AS excel_amount,
    SUM(CASE WHEN formal_match_status='MATCHED' THEN 1 ELSE 0 END) AS formal_match_count,
    SUM(CASE WHEN numeric_match_status='NUMERIC_MATCH' THEN 1 ELSE 0 END) AS numeric_match_count,
    SUM(CASE WHEN day_diff IS NOT NULL AND ABS(day_diff)>CAST(0.000000001 AS DECIMAL(38,12)) THEN 1 ELSE 0 END) AS day_mismatch_count,
    SUM(CASE WHEN price_diff IS NOT NULL AND ABS(price_diff)>CAST(0.000000001 AS DECIMAL(38,12)) THEN 1 ELSE 0 END) AS price_mismatch_count,
    SUM(CASE WHEN amount_diff IS NOT NULL AND ABS(amount_diff)>CAST(0.000001 AS DECIMAL(38,12)) THEN 1 ELSE 0 END) AS amount_mismatch_count,
    MAX(CASE WHEN platform_candidate_count>1 OR platform_product_mapping_status<>'PROVEN_BY_PLATFORM_IMSI' THEN 1 ELSE 0 END) AS product_issue,
    MAX(CASE WHEN LOWER(COALESCE(charge_type,'')) LIKE '%credit%' OR excel_amount<0 THEN 1 ELSE 0 END) AS credit_issue,
    MAX(CASE WHEN LOWER(COALESCE(charge_type,'')) LIKE '%replacement%' OR NULLIF(TRIM(excel_new_card_imsi_replacement),'') IS NOT NULL OR NULLIF(TRIM(excel_old_card_imsi_replaced),'') IS NOT NULL THEN 1 ELSE 0 END) AS replacement_issue,
    MAX(CASE WHEN NULLIF(TRIM(excel_transferred_to_wing_simbank),'') IS NOT NULL THEN 1 ELSE 0 END) AS transfer_issue,
    MAX(CASE WHEN LOWER(COALESCE(charge_type,'')) LIKE '%back%bill%' THEN 1 ELSE 0 END) AS backbill_issue
  FROM excel_assign WHERE selected_card_key IS NOT NULL GROUP BY invoice_batch_label,selected_card_key
)
, card_bridge AS (
  SELECT p.*,COALESCE(e.excel_row_count,0) AS excel_row_count,COALESCE(e.excel_distinct_imsi_count,0) AS excel_distinct_imsi_count,e.excel_amount,
    COALESCE(e.formal_match_count,0) AS formal_match_count,COALESCE(e.numeric_match_count,0) AS numeric_match_count,
    COALESCE(e.day_mismatch_count,0) AS day_mismatch_count,COALESCE(e.price_mismatch_count,0) AS price_mismatch_count,
    COALESCE(e.amount_mismatch_count,0) AS amount_mismatch_count,COALESCE(e.product_issue,0) AS product_issue,
    COALESCE(e.credit_issue,0) AS credit_issue,COALESCE(e.replacement_issue,0) AS replacement_issue,COALESCE(e.transfer_issue,0) AS transfer_issue,COALESCE(e.backbill_issue,0) AS backbill_issue,
    COALESCE(c.candidate_presence_count,0) AS candidate_presence_count,
    CASE WHEN p.platform_amount IS NULL THEN NULL ELSE p.platform_amount-COALESCE(e.excel_amount,CAST(0 AS DECIMAL(38,12))) END AS raw_bridge_amount
  FROM platform_cards_priced p LEFT JOIN excel_by_card e ON p.invoice_batch_label=e.invoice_batch_label AND p.platform_card_window_key=e.platform_card_window_key
    LEFT JOIN candidate_card_count c ON p.invoice_batch_label=c.invoice_batch_label AND p.platform_card_window_key=c.platform_card_window_key
)
, card_bridge_reason AS (
  SELECT b.*,
    CASE WHEN b.excel_row_count=0 AND b.candidate_presence_count=0 THEN 'PLATFORM_ONLY'
      WHEN b.excel_row_count=0 AND b.candidate_presence_count>0 THEN 'UNRESOLVED_CANDIDATE_NOT_SELECTED'
      WHEN b.credit_issue=1 THEN 'CREDIT' WHEN b.replacement_issue=1 THEN 'REPLACEMENT' WHEN b.transfer_issue=1 THEN 'TRANSFER'
      WHEN b.backbill_issue=1 THEN 'BACKBILL' WHEN b.product_issue=1 THEN 'PRODUCT'
      WHEN b.platform_amount IS NULL THEN 'OTHER_MISSING_PLATFORM_AMOUNT'
      WHEN ABS(b.raw_bridge_amount)<=CAST(0.000001 AS DECIMAL(38,12)) AND b.formal_match_count=b.excel_row_count THEN 'MATCHED'
      WHEN b.day_mismatch_count>0 AND b.price_mismatch_count=0 THEN 'DAYS'
      WHEN b.price_mismatch_count>0 THEN 'RATE' WHEN b.excel_row_count>0 THEN 'CHARGE_TYPE' ELSE 'OTHER' END AS bridge_reason,
    CASE WHEN b.excel_row_count=0 THEN b.platform_amount WHEN b.platform_amount IS NULL THEN NULL ELSE b.raw_bridge_amount END AS bridge_amount
  FROM card_bridge b
)
, wa_only AS (
  SELECT invoice_batch_label,excel_row_id,source_file AS excel_source_file,observed_start_month,imsi,excel_product_name,charge_type,
    excel_final_start_date,excel_final_end_date,excel_days,excel_price,excel_amount,platform_candidate_count,'WA_ONLY' AS bridge_reason,-excel_amount AS bridge_amount
  FROM excel_assign WHERE platform_candidate_count=0
)
, month_excel AS (
  SELECT invoice_batch_label,COUNT(*) AS excel_row_count,COUNT(DISTINCT imsi) AS excel_distinct_imsi_count,SUM(excel_amount) AS excel_total,
    SUM(CASE WHEN platform_candidate_count=0 THEN 1 ELSE 0 END) AS wa_only_row_count,
    COUNT(DISTINCT CASE WHEN platform_candidate_count=0 THEN imsi END) AS wa_only_distinct_imsi_count,
    SUM(CASE WHEN platform_candidate_count=0 THEN excel_amount ELSE CAST(0 AS DECIMAL(38,12)) END) AS wa_only_excel_amount
  FROM excel_assign GROUP BY invoice_batch_label
)
, month_platform AS (
  SELECT invoice_batch_label,COUNT(*) AS platform_card_window_count,COUNT(DISTINCT imsi) AS platform_distinct_imsi_count,SUM(platform_source_row_count) AS platform_source_row_count,
    SUM(CASE WHEN platform_amount IS NULL THEN 1 ELSE 0 END) AS unproven_platform_card_count,SUM(platform_amount) AS platform_amount_candidate_sum,
    CASE WHEN SUM(CASE WHEN platform_amount IS NULL THEN 1 ELSE 0 END)=0 THEN SUM(platform_amount) END AS platform_total,
    SUM(CASE WHEN bridge_reason='PLATFORM_ONLY' THEN 1 ELSE 0 END) AS platform_only_card_count,
    COUNT(DISTINCT CASE WHEN bridge_reason='PLATFORM_ONLY' THEN imsi END) AS platform_only_distinct_imsi_count,
    SUM(CASE WHEN bridge_reason='PLATFORM_ONLY' THEN platform_amount ELSE CAST(0 AS DECIMAL(38,12)) END) AS platform_only_amount
  FROM card_bridge_reason GROUP BY invoice_batch_label
)
, buckets AS (
  SELECT invoice_batch_label,bridge_reason,SUM(CASE WHEN excel_row_count=0 THEN 1 ELSE 0 END) AS platform_card_window_count,
    COUNT(DISTINCT CASE WHEN excel_row_count=0 THEN imsi END) AS platform_distinct_imsi_count,SUM(excel_row_count) AS excel_row_count,
    COUNT(DISTINCT CASE WHEN excel_row_count>0 THEN imsi END) AS excel_distinct_imsi_count,SUM(bridge_amount) AS bridge_amount
  FROM card_bridge_reason GROUP BY invoice_batch_label,bridge_reason
  UNION ALL
  SELECT invoice_batch_label,bridge_reason,CAST(0 AS BIGINT),CAST(0 AS BIGINT),COUNT(*),COUNT(DISTINCT imsi),SUM(bridge_amount)
  FROM wa_only GROUP BY invoice_batch_label,bridge_reason
)
, bucket_check AS (
  SELECT invoice_batch_label,SUM(bridge_amount) AS bridge_bucket_sum FROM buckets GROUP BY invoice_batch_label
)
SELECT 'BRIDGE_SUMMARY' AS result_type,p.invoice_batch_label,
  e.excel_row_count,e.excel_distinct_imsi_count,e.excel_total,
  p.platform_card_window_count,p.platform_distinct_imsi_count,p.platform_source_row_count,
  p.unproven_platform_card_count,p.platform_amount_candidate_sum,p.platform_total,
  p.platform_total-e.excel_total AS platform_total_minus_excel_total,
  p.platform_only_card_count,p.platform_only_distinct_imsi_count,p.platform_only_amount,
  e.wa_only_row_count,e.wa_only_distinct_imsi_count,e.wa_only_excel_amount,
  k.bridge_bucket_sum,(p.platform_total-e.excel_total)-k.bridge_bucket_sum AS bridge_residual
FROM month_platform p JOIN month_excel e ON p.invoice_batch_label=e.invoice_batch_label JOIN bucket_check k ON p.invoice_batch_label=k.invoice_batch_label
UNION ALL
SELECT 'BRIDGE_BUCKET',b.invoice_batch_label,
  b.platform_card_window_count,b.platform_distinct_imsi_count,b.bridge_amount,
  CAST(NULL AS BIGINT),CAST(NULL AS BIGINT),CAST(NULL AS BIGINT),CAST(NULL AS BIGINT),CAST(NULL AS DECIMAL(38,12)),CAST(NULL AS DECIMAL(38,12)),CAST(NULL AS DECIMAL(38,12)),
  CAST(NULL AS BIGINT),CAST(NULL AS BIGINT),CAST(NULL AS DECIMAL(38,12)),b.excel_row_count,b.excel_distinct_imsi_count,CAST(NULL AS DECIMAL(38,12)),CAST(NULL AS DECIMAL(38,12)),CAST(NULL AS DECIMAL(38,12))
FROM buckets b
ORDER BY result_type,invoice_batch_label,bridge_reason
