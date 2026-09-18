WITH detail_rows AS (
  SELECT
    NULLIF(TRIM(CAST(imsi AS STRING)), '') AS imsi_std,
    NULLIF(TRIM(CAST(source_file AS STRING)), '') AS source_file_std,
    TO_DATE(cycle_start_date) AS cycle_start_std,
    TO_DATE(cycle_end_date) AS cycle_end_std,
    NULLIF(TRIM(CAST(charge_type AS STRING)), '') AS charge_type_std,
    CONCAT_WS('||',
      COALESCE(NULLIF(TRIM(CAST(iccid AS STRING)), ''), '<NULL>'),
      COALESCE(NULLIF(TRIM(CAST(product_name AS STRING)), ''), '<NULL>'),
      COALESCE(CAST(TO_DATE(new_activation_date) AS STRING), '<NULL>'),
      COALESCE(CAST(TO_DATE(offstock_date) AS STRING), '<NULL>'),
      COALESCE(CAST(TO_DATE(final_start_date) AS STRING), '<NULL>'),
      COALESCE(CAST(TO_DATE(final_end_date) AS STRING), '<NULL>'),
      COALESCE(CAST(TRY_CAST(active_days AS DECIMAL(38,12)) AS STRING), '<NULL>'),
      COALESCE(CAST(TRY_CAST(usage_days AS DECIMAL(38,12)) AS STRING), '<NULL>'),
      COALESCE(CAST(TRY_CAST(usage_days_alt AS DECIMAL(38,12)) AS STRING), '<NULL>'),
      COALESCE(CAST(TRY_CAST(usage_days_gt_active AS DECIMAL(38,12)) AS STRING), '<NULL>'),
      COALESCE(CAST(TRY_CAST(final_days AS DECIMAL(38,12)) AS STRING), '<NULL>'),
      COALESCE(CAST(TRY_CAST(monthly_rate AS DECIMAL(38,12)) AS STRING), '<NULL>'),
      COALESCE(CAST(TRY_CAST(final_charge AS DECIMAL(38,12)) AS STRING), '<NULL>'),
      COALESCE(NULLIF(TRIM(CAST(transferred_to_wing_simbank AS STRING)), ''), '<NULL>'),
      COALESCE(NULLIF(TRIM(CAST(note AS STRING)), ''), '<NULL>'),
      COALESCE(NULLIF(TRIM(CAST(status AS STRING)), ''), '<NULL>'),
      COALESCE(NULLIF(TRIM(CAST(new_card_imsi_replacement AS STRING)), ''), '<NULL>'),
      COALESCE(NULLIF(TRIM(CAST(old_card_imsi_replaced AS STRING)), ''), '<NULL>')
    ) AS non_key_row_fingerprint,
    TRY_CAST(final_charge AS DECIMAL(38,12)) AS amount_std
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
),
duplicate_groups AS (
  SELECT
    imsi_std, source_file_std, cycle_start_std, cycle_end_std, charge_type_std,
    COUNT(*) AS duplicate_row_count,
    COUNT(DISTINCT non_key_row_fingerprint) AS distinct_non_key_fingerprint_count,
    ROUND(SUM(amount_std), 6) AS amount_sum
  FROM detail_rows
  WHERE imsi_std IS NOT NULL AND source_file_std IS NOT NULL AND cycle_start_std IS NOT NULL AND cycle_end_std IS NOT NULL
  GROUP BY imsi_std, source_file_std, cycle_start_std, cycle_end_std, charge_type_std
  HAVING COUNT(*) > 1
)
SELECT
  CASE WHEN distinct_non_key_fingerprint_count = 1 THEN 'EXACT_DUPLICATE_ALL_COMPARED_FIELDS'
       ELSE 'MULTIPLE_DETAIL_ROWS_SAME_CYCLE_CHARGE_TYPE_DIFFERENT_FIELDS' END AS duplicate_classification,
  COUNT(*) AS duplicate_key_count,
  SUM(duplicate_row_count) AS duplicate_row_count,
  SUM(duplicate_row_count - 1) AS duplicate_extra_row_count,
  MAX(duplicate_row_count) AS max_rows_per_key,
  ROUND(SUM(amount_sum), 6) AS amount_sum_on_duplicate_groups,
  COUNT(CASE WHEN distinct_non_key_fingerprint_count = 1 THEN 1 END) AS exact_duplicate_key_count,
  COUNT(CASE WHEN distinct_non_key_fingerprint_count > 1 THEN 1 END) AS different_field_key_count
FROM duplicate_groups
GROUP BY CASE WHEN distinct_non_key_fingerprint_count = 1 THEN 'EXACT_DUPLICATE_ALL_COMPARED_FIELDS'
         ELSE 'MULTIPLE_DETAIL_ROWS_SAME_CYCLE_CHARGE_TYPE_DIFFERENT_FIELDS' END
ORDER BY duplicate_classification
