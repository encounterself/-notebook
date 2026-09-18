/*
 Batch B candidate billing, read-only SELECT/WITH only.
 Excel truth branch: wa_invoice_detail.final_charge, one row retained.
 Target source files are DEC 2025 and FEB 2026; no JAN 2026 source_file was found.
 Excel has no product_id, so excel_product_id stays NULL and platform_product_id is independent.
 Price evidence uses resource_res_vsim_product.monthly_rent only when one distinct value exists per product_id;
 cycle_history.package_price is deliberately not used.
*/
WITH target_months AS (
  SELECT '2025-12' AS billing_month, CAST('2025-12-01' AS DATE) AS month_start, CAST('2025-12-31' AS DATE) AS month_end, 31 AS calendar_days
  UNION ALL SELECT '2026-01', CAST('2026-01-01' AS DATE), CAST('2026-01-31' AS DATE), 31
  UNION ALL SELECT '2026-02', CAST('2026-02-01' AS DATE), CAST('2026-02-28' AS DATE), 28
),
product_records AS (
  SELECT
    CAST(product_id AS STRING) AS platform_product_id,
    CAST(supplier_id AS BIGINT) AS supplier_id,
    CAST(product_name AS STRING) AS product_name,
    TRY_CAST(monthly_rent AS DECIMAL(38,12)) AS monthly_rent,
    TRY_CAST(package_price AS DECIMAL(38,12)) AS product_package_price,
    ROW_NUMBER() OVER (PARTITION BY CAST(product_id AS STRING) ORDER BY TRY_CAST(modify_time AS TIMESTAMP) DESC NULLS LAST, TRY_CAST(create_time AS TIMESTAMP) DESC NULLS LAST) AS rn
  FROM simo_prod.ods.resource_res_vsim_product
  WHERE supplier_id=2275
),
product_values AS (
  SELECT
    platform_product_id,
    COUNT(DISTINCT monthly_rent) AS price_value_count,
    CONCAT_WS(',', SORT_ARRAY(COLLECT_SET(CAST(monthly_rent AS STRING)))) AS price_values,
    CASE WHEN COUNT(DISTINCT monthly_rent)=1 THEN MIN(monthly_rent) ELSE CAST(NULL AS DECIMAL(38,12)) END AS unique_monthly_rent,
    CONCAT_WS(',', SORT_ARRAY(COLLECT_SET(COALESCE(product_name,'')))) AS product_name_values,
    CONCAT_WS(',', SORT_ARRAY(COLLECT_SET(CAST(product_package_price AS STRING)))) AS product_package_values,
    MIN(supplier_id) AS supplier_id
  FROM product_records
  GROUP BY platform_product_id
),
product_dim AS (
  SELECT
    v.platform_product_id, v.supplier_id, v.price_value_count, v.price_values, v.unique_monthly_rent,
    v.product_name_values, v.product_package_values,
    CASE
      WHEN UPPER(v.product_name_values) LIKE '%(PI)%' THEN 'EXCLUDED_PI'
      WHEN UPPER(v.product_name_values) LIKE '%UNASSIGNED%' THEN 'EXCLUDED_UNASSIGNED'
      WHEN UPPER(v.product_name_values) LIKE '%TEST%' OR v.product_name_values LIKE '%测试%' THEN 'EXCLUDED_TEST'
      WHEN UPPER(v.product_name_values) LIKE '%(WA)%' OR UPPER(v.product_name_values) LIKE '% WA%' THEN 'WA_CANDIDATE'
      ELSE 'SUPPLIER_2275_NAME_UNCONFIRMED'
    END AS product_population_status
  FROM product_values v
),
excel_raw AS (
  SELECT
    TRIM(CAST(imsi AS STRING)) AS imsi,
    TRIM(CAST(source_file AS STRING)) AS excel_source_file,
    CAST(NULL AS STRING) AS excel_product_id,
    CAST(product_name AS STRING) AS excel_product_name,
    charge_type AS excel_charge_type,
    TRY_CAST(new_activation_date AS DATE) AS excel_new_activation_date,
    TRY_CAST(final_start_date AS DATE) AS excel_final_start_date,
    TRY_CAST(final_end_date AS DATE) AS excel_final_end_date,
    TRY_CAST(final_days AS DECIMAL(38,12)) AS excel_days,
    TRY_CAST(monthly_rate AS DECIMAL(38,12)) AS excel_price,
    TRY_CAST(final_charge AS DECIMAL(38,12)) AS excel_amount,
    TRY_CAST(offstock_date AS DATE) AS excel_offstock_date,
    TRIM(CAST(new_card_imsi_replacement AS STRING)) AS excel_new_card_imsi_replacement,
    TRIM(CAST(old_card_imsi_replaced AS STRING)) AS excel_old_card_imsi_replaced
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE source_file LIKE '%DEC 2025%' OR source_file LIKE '%JAN 2026%' OR source_file LIKE '%FEB 2026%'
),
excel_detail AS (
  SELECT
    ROW_NUMBER() OVER (ORDER BY excel_source_file, imsi, excel_final_start_date, excel_final_end_date, excel_charge_type, excel_amount, excel_price, excel_product_name) AS excel_row_id,
    r.*,
    CASE
      WHEN excel_source_file LIKE '%JAN 2025%' THEN '2025-01'
      WHEN excel_source_file LIKE '%SEP 2025%' THEN '2025-09'
      WHEN excel_source_file LIKE '%OCT 2025%' AND excel_source_file LIKE '%773,793.84%' THEN '2025-10 (v2)'
      WHEN excel_source_file LIKE '%OCT 2025%' AND excel_source_file LIKE '%772,765.00%' THEN '2025-10 (v1)'
      WHEN excel_source_file LIKE '%DEC 2025%' THEN '2025-12'
      WHEN excel_source_file LIKE '%FEB 2026%' THEN '2026-02'
      WHEN excel_source_file LIKE '%MAR 2026%' THEN '2026-03'
      WHEN excel_source_file LIKE '%APR 2026%' THEN '2026-04'
      WHEN excel_source_file LIKE '%MAY 2026%' THEN '2026-05'
      WHEN excel_source_file LIKE '%JUNE 2026%' THEN '2026-06'
      WHEN excel_source_file LIKE '%JULY 2026%' THEN '2026-07'
      WHEN excel_source_file LIKE '%AUGUST 2026%' THEN '2026-08'
      ELSE excel_source_file
    END AS official_excel_billing_month,
    DATE_FORMAT(excel_final_start_date,'yyyy-MM') AS observed_start_month,
    CASE
      WHEN excel_source_file LIKE '%DEC 2025%' THEN 31
      WHEN excel_source_file LIKE '%FEB 2026%' THEN 28
      WHEN excel_source_file LIKE '%JAN 2026%' THEN 31
      ELSE NULL
    END AS excel_calendar_days
  FROM excel_raw r
),
cycle_raw AS (
  SELECT
    TRIM(CAST(c.imsi AS STRING)) AS imsi,
    CAST(c.product_id AS STRING) AS platform_product_id,
    c.cycle_time AS platform_cycle_start_time,
    c.next_cycle_time AS platform_cycle_end_time,
    TO_DATE(c.cycle_time) AS platform_cycle_start_date,
    TO_DATE(c.next_cycle_time) AS platform_cycle_end_date,
    DATEDIFF(TO_DATE(c.next_cycle_time),TO_DATE(c.cycle_time))+1 AS platform_cycle_days,
    p.supplier_id, p.product_name_values, p.price_value_count, p.price_values, p.unique_monthly_rent,
    p.product_population_status
  FROM simo_prod.ods.resource_res_vsim_cycle_history c
  JOIN product_dim p ON CAST(c.product_id AS STRING)=p.platform_product_id
  WHERE p.supplier_id=2275 AND p.product_population_status='WA_CANDIDATE'
    AND c.cycle_time < CAST('2026-03-01' AS TIMESTAMP)
    AND c.next_cycle_time >= CAST('2025-12-01' AS TIMESTAMP)
    AND c.next_cycle_time IS NOT NULL
),
cycle_overlap AS (
  SELECT
    e.excel_row_id, e.imsi, e.official_excel_billing_month,
    e.excel_final_start_date, e.excel_final_end_date, e.excel_charge_type,
    c.platform_product_id, c.supplier_id, c.product_name_values, c.price_value_count, c.price_values, c.unique_monthly_rent,
    c.platform_cycle_start_time, c.platform_cycle_end_time, c.platform_cycle_start_date, c.platform_cycle_end_date, c.platform_cycle_days,
    CASE
      WHEN c.platform_cycle_start_date=e.excel_final_start_date AND c.platform_cycle_end_date=e.excel_final_end_date THEN 0
      WHEN c.platform_cycle_start_date=e.excel_final_start_date OR c.platform_cycle_end_date=e.excel_final_end_date THEN 1
      ELSE 2
    END AS candidate_score,
    ABS(DATEDIFF(c.platform_cycle_start_date,e.excel_final_start_date))+ABS(DATEDIFF(c.platform_cycle_end_date,e.excel_final_end_date)) AS date_distance
  FROM excel_detail e
  JOIN cycle_raw c ON c.imsi=e.imsi
    AND e.excel_final_start_date IS NOT NULL AND e.excel_final_end_date IS NOT NULL
    AND c.platform_cycle_start_date<=e.excel_final_end_date
    AND c.platform_cycle_end_date>=e.excel_final_start_date
),
cycle_min_score AS (
  SELECT excel_row_id, MIN(candidate_score) AS min_candidate_score
  FROM cycle_overlap
  GROUP BY excel_row_id
),
cycle_best_stats AS (
  SELECT
    o.excel_row_id,
    COUNT(*) AS best_candidate_count,
    COUNT(DISTINCT o.platform_product_id) AS best_candidate_product_count,
    CONCAT_WS(',',SORT_ARRAY(COLLECT_SET(o.platform_product_id))) AS best_candidate_product_ids,
    MIN(o.candidate_score) AS selected_score
  FROM cycle_overlap o
  JOIN cycle_min_score m ON o.excel_row_id=m.excel_row_id AND o.candidate_score=m.min_candidate_score
  GROUP BY o.excel_row_id
),
cycle_best_ranked AS (
  SELECT
    o.*,
    ROW_NUMBER() OVER (PARTITION BY o.excel_row_id ORDER BY o.candidate_score, o.date_distance, o.platform_cycle_start_time, o.platform_product_id) AS rn
  FROM cycle_overlap o
),
cycle_selected AS (
  SELECT
    b.excel_row_id,
    s.best_candidate_count, s.best_candidate_product_count, s.best_candidate_product_ids, s.selected_score,
    b.platform_product_id, b.supplier_id, b.product_name_values, b.price_value_count, b.price_values, b.unique_monthly_rent,
    b.platform_cycle_start_time, b.platform_cycle_end_time, b.platform_cycle_start_date, b.platform_cycle_end_date, b.platform_cycle_days
  FROM cycle_best_ranked b
  JOIN cycle_best_stats s ON b.excel_row_id=s.excel_row_id
  WHERE b.rn=1
),
activation_events AS (
  SELECT
    TRIM(CAST(IMSI AS STRING)) AS imsi,
    CREATE_DATE AS platform_activation_event_time,
    TO_DATE(CREATE_DATE) AS platform_activation_event_date,
    TRIM(CAST(PRE_STATUS AS STRING)) AS activation_pre_status,
    TRIM(CAST(NEXT_STATUS AS STRING)) AS activation_next_status,
    TRIM(CAST(DESC_LOG AS STRING)) AS activation_desc_log,
    TRIM(CAST(DESCRIPTION AS STRING)) AS activation_description
  FROM simo_prod.ods.resource_res_vsim_status_log
  WHERE CREATE_DATE>=CAST('2025-11-01' AS TIMESTAMP) AND CREATE_DATE<CAST('2026-04-01' AS TIMESTAMP)
    AND TRIM(CAST(NEXT_STATUS AS STRING))='激活'
    AND (CAST(DESC_LOG AS STRING) LIKE '%激活%' OR CAST(DESCRIPTION AS STRING) LIKE '%激活%')
),
activation_ranked AS (
  SELECT
    e.excel_row_id, a.platform_activation_event_time, a.platform_activation_event_date,
    a.activation_pre_status, a.activation_next_status, a.activation_desc_log, a.activation_description,
    ABS(DATEDIFF(a.platform_activation_event_date,COALESCE(e.excel_new_activation_date,e.excel_final_start_date))) AS activation_date_distance,
    ROW_NUMBER() OVER (PARTITION BY e.excel_row_id ORDER BY ABS(DATEDIFF(a.platform_activation_event_date,COALESCE(e.excel_new_activation_date,e.excel_final_start_date))), a.platform_activation_event_time) AS rn
  FROM excel_detail e
  JOIN activation_events a ON e.imsi=a.imsi
  WHERE e.excel_charge_type='New Activation: Prorated-in Charge'
),
activation_selected AS (
  SELECT * FROM activation_ranked WHERE rn=1
),
snapshot_raw AS (
  SELECT
    CASE WHEN s.year=2025 AND s.month=12 THEN '2025-12' WHEN s.year=2026 AND s.month=1 THEN '2026-01' WHEN s.year=2026 AND s.month=2 THEN '2026-02' END AS platform_month,
    TRIM(CAST(s.imsi AS STRING)) AS imsi,
    CAST(s.product_id AS STRING) AS platform_product_id,
    TRY_CAST(TRIM(s.Cycle_Start_Time) AS TIMESTAMP) AS snapshot_cycle_start_time,
    TRY_CAST(TRIM(s.Cycle_End_Time) AS TIMESTAMP) AS snapshot_cycle_end_time,
    TO_DATE(TRY_CAST(TRIM(s.Cycle_Start_Time) AS TIMESTAMP)) AS snapshot_cycle_start_date,
    TO_DATE(TRY_CAST(TRIM(s.Cycle_End_Time) AS TIMESTAMP)) AS snapshot_cycle_end_date,
    TRIM(CAST(s.SimStatus AS STRING)) AS sim_status,
    TRIM(CAST(s.DispatchStatus AS STRING)) AS dispatch_status,
    TRY_CAST(TRIM(s.partition_time) AS TIMESTAMP) AS snapshot_partition_time,
    p.supplier_id, p.product_name_values, p.price_value_count, p.price_values, p.unique_monthly_rent
  FROM simo_prod.tc_cdr.sim_status_for_sftp_bak s
  JOIN product_dim p ON CAST(s.product_id AS STRING)=p.platform_product_id
  WHERE p.supplier_id=2275 AND p.product_population_status='WA_CANDIDATE'
    AND ((s.year=2025 AND s.month=12) OR (s.year=2026 AND s.month IN (1,2)))
),
snapshot_product_agg AS (
  SELECT
    platform_month, imsi, platform_product_id, supplier_id, product_name_values, price_value_count, price_values, unique_monthly_rent,
    COUNT(*) AS snapshot_row_count,
    MIN(snapshot_cycle_start_date) AS snapshot_min_cycle_start_date,
    MAX(snapshot_cycle_end_date) AS snapshot_max_cycle_end_date,
    CONCAT_WS(',',SORT_ARRAY(COLLECT_SET(COALESCE(sim_status,'')))) AS lifecycle_status_values,
    CONCAT_WS(',',SORT_ARRAY(COLLECT_SET(COALESCE(dispatch_status,'')))) AS dispatch_status_values,
    MAX(snapshot_partition_time) AS latest_snapshot_partition_time
  FROM snapshot_raw
  GROUP BY platform_month, imsi, platform_product_id, supplier_id, product_name_values, price_value_count, price_values, unique_monthly_rent
),
snapshot_imsi_agg AS (
  SELECT
    platform_month, imsi,
    COUNT(DISTINCT platform_product_id) AS snapshot_product_count,
    CONCAT_WS(',',SORT_ARRAY(COLLECT_SET(platform_product_id))) AS snapshot_platform_product_ids,
    CASE WHEN COUNT(DISTINCT platform_product_id)=1 THEN MIN(platform_product_id) ELSE CAST(NULL AS STRING) END AS snapshot_only_platform_product_id,
    CONCAT_WS(',',SORT_ARRAY(COLLECT_SET(product_name_values))) AS snapshot_product_names,
    CONCAT_WS(',',SORT_ARRAY(COLLECT_SET(lifecycle_status_values))) AS snapshot_lifecycle_status_values,
    CONCAT_WS(',',SORT_ARRAY(COLLECT_SET(dispatch_status_values))) AS snapshot_dispatch_status_values
  FROM snapshot_product_agg
  GROUP BY platform_month, imsi
),
candidate_base AS (
  SELECT
    e.*,
    c.best_candidate_count AS cycle_best_candidate_count,
    c.best_candidate_product_count AS cycle_best_candidate_product_count,
    c.best_candidate_product_ids AS cycle_best_candidate_product_ids,
    c.selected_score AS cycle_selected_score,
    c.platform_product_id AS cycle_platform_product_id,
    c.supplier_id AS cycle_supplier_id,
    c.product_name_values AS cycle_product_name_values,
    c.price_value_count AS cycle_price_value_count,
    c.price_values AS cycle_price_values,
    c.unique_monthly_rent AS cycle_unique_monthly_rent,
    c.platform_cycle_start_time, c.platform_cycle_end_time, c.platform_cycle_start_date, c.platform_cycle_end_date, c.platform_cycle_days,
    a.platform_activation_event_time, a.platform_activation_event_date,
    a.activation_pre_status, a.activation_next_status, a.activation_desc_log, a.activation_description,
    a.activation_date_distance,
    s.snapshot_product_count, s.snapshot_platform_product_ids, s.snapshot_only_platform_product_id,
    s.snapshot_product_names, s.snapshot_lifecycle_status_values, s.snapshot_dispatch_status_values
  FROM excel_detail e
  LEFT JOIN cycle_selected c ON e.excel_row_id=c.excel_row_id
  LEFT JOIN activation_selected a ON e.excel_row_id=a.excel_row_id
  LEFT JOIN snapshot_imsi_agg s ON e.official_excel_billing_month=s.platform_month AND e.imsi=s.imsi
),
calculated AS (
  SELECT
    b.*,
    CASE WHEN b.cycle_best_candidate_count=1 THEN b.cycle_platform_product_id
         WHEN b.cycle_best_candidate_count IS NULL AND b.snapshot_product_count=1 THEN b.snapshot_only_platform_product_id
         ELSE NULL END AS platform_product_id,
    CASE WHEN b.cycle_best_candidate_count=1 THEN b.cycle_supplier_id
         WHEN b.cycle_best_candidate_count IS NULL AND b.snapshot_product_count=1 THEN 2275
         ELSE NULL END AS platform_supplier_id,
    CASE WHEN b.cycle_best_candidate_count=1 THEN b.cycle_product_name_values
         WHEN b.cycle_best_candidate_count IS NULL AND b.snapshot_product_count=1 THEN b.snapshot_product_names
         ELSE NULL END AS platform_product_name,
    CASE WHEN b.cycle_best_candidate_count=1 THEN b.cycle_price_value_count
         WHEN b.cycle_best_candidate_count IS NULL AND b.snapshot_product_count=1 THEN NULL
         ELSE NULL END AS platform_price_value_count,
    CASE WHEN b.cycle_best_candidate_count=1 THEN b.cycle_price_values ELSE NULL END AS platform_price_values,
    CASE WHEN b.cycle_best_candidate_count=1 AND b.cycle_price_value_count=1 THEN b.cycle_unique_monthly_rent ELSE NULL END AS candidate_price_from_cycle,
    CASE WHEN b.cycle_best_candidate_count IS NOT NULL OR b.snapshot_product_count IS NOT NULL THEN 1 ELSE 0 END AS platform_card_present,
    CASE
      WHEN b.excel_charge_type='Full Cycle Charge' AND b.cycle_best_candidate_count=1 AND b.cycle_selected_score=0 THEN b.platform_cycle_days
      WHEN b.excel_charge_type='New Activation: Prorated-in Charge' AND b.platform_activation_event_date IS NOT NULL AND b.excel_final_end_date IS NOT NULL AND b.platform_activation_event_date<=b.excel_final_end_date THEN DATEDIFF(b.excel_final_end_date,b.platform_activation_event_date)+1
      WHEN b.excel_charge_type='Partial Charge - Card Replaced Mid Cycle' AND b.cycle_best_candidate_count=1 AND b.platform_cycle_start_date IS NOT NULL AND b.platform_cycle_end_date IS NOT NULL AND b.excel_final_start_date IS NOT NULL AND b.excel_final_end_date IS NOT NULL THEN DATEDIFF(LEAST(b.excel_final_end_date,b.platform_cycle_end_date),GREATEST(b.excel_final_start_date,b.platform_cycle_start_date))+1
      ELSE NULL
    END AS platform_calculated_days,
    CASE WHEN b.cycle_best_candidate_count=1 AND b.cycle_price_value_count=1 THEN b.cycle_unique_monthly_rent ELSE NULL END AS platform_calculated_price,
    CASE
      WHEN b.excel_charge_type='Full Cycle Charge' AND b.cycle_best_candidate_count=1 AND b.cycle_selected_score=0 AND b.cycle_price_value_count=1 THEN b.cycle_unique_monthly_rent
      WHEN b.excel_charge_type='New Activation: Prorated-in Charge' AND b.cycle_best_candidate_count IS NOT NULL AND b.cycle_price_value_count=1 AND b.platform_activation_event_date IS NOT NULL AND b.excel_final_end_date IS NOT NULL AND b.platform_activation_event_date<=b.excel_final_end_date THEN ROUND(CAST(b.cycle_unique_monthly_rent AS DOUBLE)*(DATEDIFF(b.excel_final_end_date,b.platform_activation_event_date)+1)/b.excel_calendar_days,10)
      WHEN b.excel_charge_type='Partial Charge - Card Replaced Mid Cycle' AND b.cycle_best_candidate_count=1 AND b.cycle_price_value_count=1 AND b.platform_cycle_start_date IS NOT NULL AND b.platform_cycle_end_date IS NOT NULL THEN ROUND(CAST(b.cycle_unique_monthly_rent AS DOUBLE)*(DATEDIFF(LEAST(b.excel_final_end_date,b.platform_cycle_end_date),GREATEST(b.excel_final_start_date,b.platform_cycle_start_date))+1)/b.excel_calendar_days,10)
      ELSE NULL
    END AS platform_calculated_amount
  FROM candidate_base b
),
final_candidate AS (
  SELECT
    c.*,
    CAST(c.platform_calculated_days AS DECIMAL(38,12))-c.excel_days AS day_diff,
    CAST(c.platform_calculated_price AS DECIMAL(38,12))-c.excel_price AS price_diff,
    CAST(c.platform_calculated_amount AS DECIMAL(38,12))-c.excel_amount AS amount_diff,
    CASE
      WHEN c.excel_charge_type='Full Cycle Charge' AND c.cycle_best_candidate_count=1 AND c.cycle_selected_score=0 THEN 'RULE_FULL_CYCLE_EXACT_PLATFORM_CYCLE'
      WHEN c.excel_charge_type='Full Cycle Charge' AND c.cycle_best_candidate_count IS NOT NULL THEN 'RULE_FULL_CYCLE_OVERLAP_UNRESOLVED'
      WHEN c.excel_charge_type='Full Cycle Charge' AND c.cycle_best_candidate_count IS NULL THEN 'RULE_FULL_CYCLE_NO_PLATFORM_CYCLE'
      WHEN c.excel_charge_type='New Activation: Prorated-in Charge' AND c.platform_activation_event_date IS NOT NULL AND c.activation_date_distance=0 THEN 'RULE_NEW_ACTIVATION_STATUS_DATE_EXACT'
      WHEN c.excel_charge_type='New Activation: Prorated-in Charge' AND c.platform_activation_event_date IS NOT NULL AND c.activation_date_distance=1 THEN 'RULE_NEW_ACTIVATION_STATUS_DATE_PM1'
      WHEN c.excel_charge_type='New Activation: Prorated-in Charge' AND c.platform_activation_event_date IS NOT NULL THEN 'RULE_NEW_ACTIVATION_STATUS_DATE_RESIDUAL'
      WHEN c.excel_charge_type='New Activation: Prorated-in Charge' THEN 'RULE_NEW_ACTIVATION_NO_STATUS_EVENT'
      WHEN c.excel_charge_type='Partial Charge - Card Replaced Mid Cycle' THEN 'RULE_REPLACEMENT_RELATION_UNPROVEN'
      WHEN c.excel_charge_type='Offstocked before cycle start' THEN 'RULE_OFFSTOCKED_DATE_RELATION_UNPROVEN'
      ELSE 'RULE_UNCLASSIFIED_CHARGE_TYPE'
    END AS rule_id,
    CASE
      WHEN c.imsi IS NULL OR c.official_excel_billing_month IS NULL OR (c.excel_charge_type<>'Offstocked before cycle start' AND c.excel_amount IS NULL) THEN 'MISSING_DATA_EXCEL_KEY_OR_AMOUNT'
      WHEN c.platform_card_present=0 THEN 'WA_ONLY_NO_WA_PLATFORM_CARD_IN_TARGET_WINDOW'
      WHEN c.cycle_best_candidate_count>1 OR c.cycle_best_candidate_product_count>1 THEN 'UNRESOLVED_MULTIPLE_CYCLE_CANDIDATES'
      WHEN c.cycle_best_candidate_count=1 AND c.cycle_price_value_count<>1 THEN 'MISSING_MAPPING_MULTIPLE_OR_NULL_PLATFORM_MONTHLY_RENT'
      WHEN c.cycle_best_candidate_count IS NULL AND c.snapshot_product_count>1 THEN 'MISSING_MAPPING_MULTIPLE_PLATFORM_PRODUCTS'
      WHEN c.cycle_best_candidate_count IS NULL AND c.snapshot_product_count=1 THEN 'MISSING_DATA_NO_CYCLE_HISTORY_FOR_SNAPSHOT_CARD'
      WHEN c.excel_charge_type='Full Cycle Charge' AND c.cycle_selected_score<>0 THEN 'UNRESOLVED_CYCLE_DATE_NOT_EXACT'
      WHEN c.excel_charge_type='New Activation: Prorated-in Charge' AND c.platform_activation_event_date IS NULL THEN 'MISSING_DATA_NO_ACTIVATION_STATUS_EVENT'
      WHEN c.excel_charge_type='New Activation: Prorated-in Charge' AND c.activation_date_distance>1 THEN 'UNRESOLVED_ACTIVATION_DATE_RESIDUAL'
      WHEN c.excel_charge_type='Partial Charge - Card Replaced Mid Cycle' THEN 'MISSING_MAPPING_NO_PLATFORM_REPLACEMENT_RELATION'
      WHEN c.excel_charge_type='Offstocked before cycle start' THEN 'UNRESOLVED_NO_OFFSTOCK_BILLING_RULE'
      WHEN c.platform_calculated_days IS NULL OR c.platform_calculated_price IS NULL OR c.platform_calculated_amount IS NULL THEN 'MISSING_DATA_PLATFORM_CALCULATION_INPUT'
      WHEN ABS(CAST(c.platform_calculated_days AS DOUBLE)-CAST(c.excel_days AS DOUBLE))>0.000001 OR ABS(CAST(c.platform_calculated_price AS DOUBLE)-CAST(c.excel_price AS DOUBLE))>0.000001 OR ABS(CAST(c.platform_calculated_amount AS DOUBLE)-CAST(c.excel_amount AS DOUBLE))>0.000001 THEN 'UNRESOLVED_EXCEL_PLATFORM_VALUE_DIFFERENCE'
      ELSE 'EXACT_VALUES'
    END AS difference_reason,
    CASE
      WHEN c.imsi IS NULL OR c.official_excel_billing_month IS NULL OR (c.excel_charge_type<>'Offstocked before cycle start' AND c.excel_amount IS NULL) THEN 'MISSING_DATA'
      WHEN c.platform_card_present=0 THEN 'WA_ONLY'
      WHEN c.cycle_best_candidate_count>1 OR c.cycle_best_candidate_product_count>1 OR (c.cycle_best_candidate_count=1 AND c.cycle_price_value_count<>1) OR (c.cycle_best_candidate_count IS NULL AND c.snapshot_product_count>1) THEN 'MISSING_MAPPING'
      WHEN c.cycle_best_candidate_count IS NULL AND c.snapshot_product_count=1 THEN 'MISSING_DATA'
      WHEN c.excel_charge_type='New Activation: Prorated-in Charge' AND c.activation_date_distance>1 THEN 'UNRESOLVED'
      WHEN c.platform_calculated_days IS NULL OR c.platform_calculated_price IS NULL OR c.platform_calculated_amount IS NULL THEN 'UNRESOLVED'
      WHEN ABS(CAST(c.platform_calculated_days AS DOUBLE)-CAST(c.excel_days AS DOUBLE))<=0.000001 AND ABS(CAST(c.platform_calculated_price AS DOUBLE)-CAST(c.excel_price AS DOUBLE))<=0.000001 AND ABS(CAST(c.platform_calculated_amount AS DOUBLE)-CAST(c.excel_amount AS DOUBLE))<=0.000001 THEN 'MATCHED'
      ELSE 'UNRESOLVED'
    END AS source_match_status,
    CASE WHEN c.cycle_best_candidate_count=1 THEN 'simo_prod.ods.resource_res_vsim_cycle_history' WHEN c.snapshot_product_count IS NOT NULL THEN 'simo_prod.tc_cdr.sim_status_for_sftp_bak' ELSE NULL END AS platform_source_table
  FROM calculated c
)
,platform_cycle_month_rows AS (
  SELECT t.billing_month, t.calendar_days, c.*
  FROM target_months t
  JOIN cycle_raw c ON c.platform_cycle_start_date<=t.month_end AND c.platform_cycle_end_date>=t.month_start
),
platform_cycle_month_agg0 AS (
  SELECT billing_month, calendar_days, imsi, platform_product_id, supplier_id, product_name_values,
    price_value_count, price_values, unique_monthly_rent,
    COUNT(*) AS cycle_row_count,
    SUM(CAST(platform_cycle_days AS DECIMAL(38,12))) AS platform_days,
    MIN(platform_cycle_start_date) AS platform_window_start,
    MAX(platform_cycle_end_date) AS platform_window_end
  FROM platform_cycle_month_rows
  GROUP BY billing_month, calendar_days, imsi, platform_product_id, supplier_id, product_name_values,
    price_value_count, price_values, unique_monthly_rent
),
platform_cycle_month AS (
  SELECT a.*, s.lifecycle_status_values, s.dispatch_status_values
  FROM platform_cycle_month_agg0 a
  LEFT JOIN snapshot_product_agg s
    ON s.platform_month=a.billing_month AND s.imsi=a.imsi AND s.platform_product_id=a.platform_product_id
),
platform_snapshot_only AS (
  SELECT
    s.platform_month AS billing_month, s.imsi, s.platform_product_id, s.supplier_id, s.product_name_values,
    'simo_prod.tc_cdr.sim_status_for_sftp_bak' AS platform_source_table,
    s.lifecycle_status_values, s.dispatch_status_values,
    CAST(NULL AS DECIMAL(38,12)) AS platform_calculated_days,
    CASE WHEN s.price_value_count=1 THEN s.unique_monthly_rent ELSE CAST(NULL AS DECIMAL(38,12)) END AS platform_calculated_price,
    CAST(NULL AS DECIMAL(38,12)) AS platform_calculated_amount,
    'RULE_PLATFORM_SNAPSHOT_ONLY_NO_CYCLE' AS rule_id,
    'MISSING_DATA_NO_CYCLE_HISTORY_FOR_SNAPSHOT_CARD' AS difference_reason,
    s.snapshot_min_cycle_start_date AS platform_window_start,
    s.snapshot_max_cycle_end_date AS platform_window_end
  FROM snapshot_product_agg s
  LEFT JOIN platform_cycle_month c
    ON c.billing_month=s.platform_month AND c.imsi=s.imsi AND c.platform_product_id=s.platform_product_id
  WHERE c.platform_product_id IS NULL
),
platform_population AS (
  SELECT
    a.billing_month, a.imsi, a.platform_product_id, a.supplier_id, a.product_name_values,
    'simo_prod.ods.resource_res_vsim_cycle_history' AS platform_source_table,
    a.lifecycle_status_values, a.dispatch_status_values,
    a.platform_days AS platform_calculated_days,
    CASE WHEN a.price_value_count=1 THEN a.unique_monthly_rent ELSE CAST(NULL AS DECIMAL(38,12)) END AS platform_calculated_price,
    CASE WHEN a.cycle_row_count=1 AND a.price_value_count=1 THEN
      CASE WHEN a.platform_days>=a.calendar_days THEN a.unique_monthly_rent
           ELSE ROUND(CAST(a.unique_monthly_rent AS DOUBLE)*CAST(a.platform_days AS DOUBLE)/a.calendar_days,10) END
      ELSE CAST(NULL AS DECIMAL(38,12)) END AS platform_calculated_amount,
    'RULE_PLATFORM_CYCLE_WINDOW' AS rule_id,
    CASE WHEN a.cycle_row_count<>1 THEN 'UNRESOLVED_MULTIPLE_PLATFORM_CYCLES'
         WHEN a.price_value_count<>1 THEN 'MISSING_MAPPING_MULTIPLE_OR_NULL_PLATFORM_MONTHLY_RENT'
         ELSE 'PLATFORM_CYCLE_CANDIDATE' END AS difference_reason,
    a.platform_window_start, a.platform_window_end
  FROM platform_cycle_month a
  UNION ALL
  SELECT billing_month, imsi, platform_product_id, supplier_id, product_name_values,
    platform_source_table, lifecycle_status_values, dispatch_status_values,
    platform_calculated_days, platform_calculated_price, platform_calculated_amount,
    rule_id, difference_reason, platform_window_start, platform_window_end
  FROM platform_snapshot_only
),
excel_population AS (
  SELECT official_excel_billing_month AS billing_month, imsi,
    COUNT(*) AS excel_row_count,
    COUNT(DISTINCT excel_charge_type) AS excel_charge_type_count,
    SUM(excel_amount) AS excel_amount,
    SUM(platform_calculated_amount) AS platform_calculated_amount_known,
    SUM(CASE WHEN source_match_status='MATCHED' THEN 1 ELSE 0 END) AS matched_row_count,
    SUM(CASE WHEN source_match_status='WA_ONLY' THEN 1 ELSE 0 END) AS wa_only_row_count,
    SUM(CASE WHEN source_match_status='UNRESOLVED' THEN 1 ELSE 0 END) AS unresolved_row_count,
    SUM(CASE WHEN source_match_status='MISSING_DATA' THEN 1 ELSE 0 END) AS missing_data_row_count,
    SUM(CASE WHEN source_match_status='MISSING_MAPPING' THEN 1 ELSE 0 END) AS missing_mapping_row_count
  FROM final_candidate
  GROUP BY official_excel_billing_month, imsi
),
platform_population_agg AS (
  SELECT billing_month, imsi,
    COUNT(*) AS platform_product_row_count,
    COUNT(DISTINCT platform_product_id) AS platform_product_count,
    CONCAT_WS(',',SORT_ARRAY(COLLECT_SET(platform_product_id))) AS platform_product_ids,
    CONCAT_WS(',',SORT_ARRAY(COLLECT_SET(CAST(supplier_id AS STRING)))) AS platform_supplier_ids,
    CONCAT_WS(',',SORT_ARRAY(COLLECT_SET(product_name_values))) AS platform_product_names,
    CONCAT_WS(',',SORT_ARRAY(COLLECT_SET(platform_source_table))) AS platform_source_tables,
    CONCAT_WS(',',SORT_ARRAY(COLLECT_SET(COALESCE(lifecycle_status_values,'')))) AS platform_lifecycle_status_values,
    CONCAT_WS(',',SORT_ARRAY(COLLECT_SET(COALESCE(dispatch_status_values,'')))) AS platform_dispatch_status_values,
    SUM(platform_calculated_amount) AS platform_calculated_amount_known,
    SUM(CASE WHEN platform_calculated_amount IS NULL THEN 1 ELSE 0 END) AS platform_unresolved_amount_row_count,
    SUM(CASE WHEN platform_calculated_amount IS NOT NULL THEN platform_calculated_amount ELSE CAST(0 AS DECIMAL(38,12)) END) AS platform_amount_impact_known
  FROM platform_population
  GROUP BY billing_month, imsi
),
population_full_outer AS (
  SELECT
    COALESCE(e.billing_month,p.billing_month) AS billing_month,
    COALESCE(e.imsi,p.imsi) AS imsi,
    e.excel_row_count, e.excel_charge_type_count, e.excel_amount,
    e.platform_calculated_amount_known AS excel_row_platform_amount_known,
    e.matched_row_count, e.wa_only_row_count, e.unresolved_row_count, e.missing_data_row_count, e.missing_mapping_row_count,
    p.platform_product_row_count, p.platform_product_count, p.platform_product_ids, p.platform_supplier_ids,
    p.platform_product_names, p.platform_source_tables, p.platform_lifecycle_status_values, p.platform_dispatch_status_values,
    p.platform_calculated_amount_known, p.platform_unresolved_amount_row_count, p.platform_amount_impact_known,
    CASE WHEN e.imsi IS NULL THEN 'PLATFORM_ONLY'
         WHEN p.imsi IS NULL THEN 'WA_ONLY'
         ELSE 'MATCHED' END AS population_status
  FROM excel_population e
  FULL OUTER JOIN platform_population_agg p ON e.billing_month=p.billing_month AND e.imsi=p.imsi
),
platform_only_keys AS (
  SELECT billing_month, imsi FROM population_full_outer WHERE population_status='PLATFORM_ONLY'
),
row_level AS (
  SELECT
    'ROW_LEVEL' AS result_section, 'EXCEL_DETAIL' AS row_type,
    f.excel_row_id, f.excel_source_file, f.official_excel_billing_month, f.observed_start_month,
    f.imsi, f.excel_product_id, f.platform_product_id, f.platform_supplier_id,
    f.excel_product_name, f.platform_product_name, f.excel_charge_type,
    f.excel_new_activation_date, f.excel_final_start_date, f.excel_final_end_date,
    f.excel_days, f.platform_calculated_days, f.excel_price, f.platform_calculated_price,
    f.excel_amount, f.platform_calculated_amount, f.day_diff, f.price_diff, f.amount_diff,
    f.rule_id, f.difference_reason, f.source_match_status, f.platform_source_table,
    f.platform_cycle_start_date, f.platform_cycle_end_date, f.platform_activation_event_date,
    f.activation_date_distance, f.snapshot_lifecycle_status_values, f.snapshot_dispatch_status_values
  FROM final_candidate f
  UNION ALL
  SELECT
    'ROW_LEVEL', 'PLATFORM_ONLY',
    CAST(NULL AS BIGINT), CAST(NULL AS STRING), p.billing_month, CAST(NULL AS STRING),
    p.imsi, CAST(NULL AS STRING), p.platform_product_id, p.supplier_id,
    CAST(NULL AS STRING), p.product_name_values, CAST('PLATFORM_ONLY' AS STRING),
    CAST(NULL AS DATE), CAST(NULL AS DATE), CAST(NULL AS DATE),
    CAST(NULL AS DECIMAL(38,12)), p.platform_calculated_days, CAST(NULL AS DECIMAL(38,12)), p.platform_calculated_price,
    CAST(NULL AS DECIMAL(38,12)), p.platform_calculated_amount, CAST(NULL AS DECIMAL(38,12)), CAST(NULL AS DECIMAL(38,12)), CAST(NULL AS DECIMAL(38,12)),
    p.rule_id, p.difference_reason, 'PLATFORM_ONLY', p.platform_source_table,
    p.platform_window_start, p.platform_window_end, CAST(NULL AS DATE), CAST(NULL AS BIGINT),
    p.lifecycle_status_values, p.dispatch_status_values
  FROM platform_population p
  JOIN platform_only_keys k ON p.billing_month=k.billing_month AND p.imsi=k.imsi
)
SELECT * FROM row_level
ORDER BY official_excel_billing_month, imsi, row_type, excel_row_id;