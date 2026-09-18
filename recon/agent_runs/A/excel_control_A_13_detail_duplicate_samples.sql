WITH detail_canonical AS (
  SELECT
    NULLIF(TRIM(CAST(imsi AS STRING)), '') AS imsi_std,
    NULLIF(TRIM(CAST(source_file AS STRING)), '') AS source_file_std,
    NULLIF(TRIM(CAST(iccid AS STRING)), '') AS iccid_std,
    NULLIF(TRIM(CAST(product_name AS STRING)), '') AS product_name_std,
    TO_DATE(cycle_start_date) AS cycle_start_std,
    TO_DATE(cycle_end_date) AS cycle_end_std,
    TO_DATE(new_activation_date) AS new_activation_std,
    TO_DATE(offstock_date) AS offstock_std,
    TO_DATE(final_start_date) AS final_start_std,
    TO_DATE(final_end_date) AS final_end_std,
    NULLIF(TRIM(CAST(charge_type AS STRING)), '') AS charge_type_std,
    TRY_CAST(cycle_usage_gb AS DECIMAL(38,12)) AS cycle_usage_std,
    TRY_CAST(data_allowance_gb AS DECIMAL(38,12)) AS allowance_std,
    TRY_CAST(pct_used AS DECIMAL(38,12)) AS pct_used_std,
    TRY_CAST(active_days AS DECIMAL(38,12)) AS active_days_std,
    TRY_CAST(usage_days AS DECIMAL(38,12)) AS usage_days_std,
    TRY_CAST(usage_days_alt AS DECIMAL(38,12)) AS usage_days_alt_std,
    TRY_CAST(usage_days_gt_active AS DECIMAL(38,12)) AS usage_days_gt_active_std,
    TRY_CAST(final_days AS DECIMAL(38,12)) AS final_days_std,
    TRY_CAST(monthly_rate AS DECIMAL(38,12)) AS monthly_rate_std,
    TRY_CAST(final_charge AS DECIMAL(38,12)) AS final_amount_std,
    NULLIF(TRIM(CAST(transferred_to_wing_simbank AS STRING)), '') AS transferred_std,
    NULLIF(TRIM(CAST(note AS STRING)), '') AS note_std,
    NULLIF(TRIM(CAST(status AS STRING)), '') AS status_std,
    NULLIF(TRIM(CAST(new_card_imsi_replacement AS STRING)), '') AS new_card_replacement_std,
    NULLIF(TRIM(CAST(old_card_imsi_replaced AS STRING)), '') AS old_card_replaced_std
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
),
with_fingerprint AS (
  SELECT
    *,
    CONCAT_WS('||',
      COALESCE(iccid_std,'<NULL>'),
      COALESCE(product_name_std,'<NULL>'),
      COALESCE(CAST(cycle_usage_std AS STRING),'<NULL>'),
      COALESCE(CAST(allowance_std AS STRING),'<NULL>'),
      COALESCE(CAST(pct_used_std AS STRING),'<NULL>'),
      COALESCE(CAST(new_activation_std AS STRING),'<NULL>'),
      COALESCE(CAST(offstock_std AS STRING),'<NULL>'),
      COALESCE(CAST(final_start_std AS STRING),'<NULL>'),
      COALESCE(CAST(final_end_std AS STRING),'<NULL>'),
      COALESCE(CAST(active_days_std AS STRING),'<NULL>'),
      COALESCE(CAST(usage_days_std AS STRING),'<NULL>'),
      COALESCE(CAST(usage_days_alt_std AS STRING),'<NULL>'),
      COALESCE(CAST(usage_days_gt_active_std AS STRING),'<NULL>'),
      COALESCE(CAST(final_days_std AS STRING),'<NULL>'),
      COALESCE(CAST(monthly_rate_std AS STRING),'<NULL>'),
      COALESCE(CAST(final_amount_std AS STRING),'<NULL>'),
      COALESCE(transferred_std,'<NULL>'),
      COALESCE(note_std,'<NULL>'),
      COALESCE(status_std,'<NULL>'),
      COALESCE(new_card_replacement_std,'<NULL>'),
      COALESCE(old_card_replaced_std,'<NULL>')
    ) AS non_key_row_fingerprint
  FROM detail_canonical
),
duplicate_groups AS (
  SELECT
    imsi_std,
    source_file_std,
    cycle_start_std,
    cycle_end_std,
    charge_type_std,
    COUNT(*) AS duplicate_row_count,
    COUNT(DISTINCT non_key_row_fingerprint) AS distinct_non_key_fingerprint_count,
    COUNT(DISTINCT final_start_std) AS distinct_final_start_count,
    COUNT(DISTINCT final_end_std) AS distinct_final_end_count,
    COUNT(DISTINCT final_days_std) AS distinct_final_days_count,
    COUNT(DISTINCT monthly_rate_std) AS distinct_monthly_rate_count,
    COUNT(DISTINCT final_amount_std) AS distinct_final_amount_count,
    ROUND(SUM(final_amount_std), 6) AS detail_amount_sum,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(non_key_row_fingerprint))) AS non_key_fingerprint_samples
  FROM with_fingerprint
  WHERE imsi_std IS NOT NULL AND source_file_std IS NOT NULL AND cycle_start_std IS NOT NULL AND cycle_end_std IS NOT NULL
  GROUP BY imsi_std, source_file_std, cycle_start_std, cycle_end_std, charge_type_std
  HAVING COUNT(*) > 1
),
ranked AS (
  SELECT
    ROW_NUMBER() OVER (ORDER BY source_file_std, imsi_std, cycle_start_std, cycle_end_std, charge_type_std) AS sample_no,
    *,
    CASE
      WHEN distinct_non_key_fingerprint_count = 1 THEN 'EXACT_DUPLICATE_ALL_COMPARED_FIELDS'
      ELSE 'MULTIPLE_DETAIL_ROWS_SAME_CYCLE_CHARGE_TYPE_DIFFERENT_FIELDS'
    END AS duplicate_classification,
    CASE
      WHEN distinct_non_key_fingerprint_count = 1 THEN 'DEDUPLICATION_CANDIDATE_BUT_NO_ROW_ID_OR_PK'
      ELSE 'KEEP_MULTIPLE_UNTIL_BUSINESS_RULE_PROVES_DUPLICATE'
    END AS retain_multirow_recommendation
  FROM duplicate_groups
)
SELECT *
FROM ranked
WHERE sample_no <= 20
ORDER BY sample_no
