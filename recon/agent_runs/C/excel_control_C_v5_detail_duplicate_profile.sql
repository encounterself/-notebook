WITH
d AS (
  SELECT
    trim(source_file) AS source_file,
    trim(imsi) AS imsi,
    trim(iccid) AS iccid,
    trim(product_name) AS product_name,
    to_date(trim(cycle_start_date)) AS cycle_start,
    to_date(trim(cycle_end_date)) AS cycle_end,
    to_date(trim(final_start_date)) AS final_start,
    to_date(trim(final_end_date)) AS final_end,
    try_cast(nullif(trim(final_days), '') AS DECIMAL(38,10)) AS final_days,
    try_cast(nullif(trim(monthly_rate), '') AS DECIMAL(38,10)) AS monthly_rate,
    try_cast(nullif(trim(final_charge), '') AS DECIMAL(38,10)) AS detail_amount,
    trim(charge_type) AS charge_type,
    trim(status) AS status,
    trim(new_card_imsi_replacement) AS new_card_imsi_replacement,
    trim(old_card_imsi_replaced) AS old_card_imsi_replaced
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
),
dup_profile AS (
  SELECT
    source_file,
    imsi,
    cycle_start,
    cycle_end,
    COUNT(*) AS detail_rows,
    COUNT(DISTINCT concat_ws('|', coalesce(cast(final_start AS STRING), '#'), coalesce(cast(final_end AS STRING), '#'))) AS final_window_variants,
    COUNT(DISTINCT coalesce(cast(final_days AS STRING), '#')) AS final_days_variants,
    COUNT(DISTINCT coalesce(cast(monthly_rate AS STRING), '#')) AS monthly_rate_variants,
    COUNT(DISTINCT coalesce(cast(detail_amount AS STRING), '#')) AS amount_variants,
    COUNT(DISTINCT coalesce(charge_type, '#')) AS charge_type_variants,
    COUNT(DISTINCT coalesce(status, '#')) AS status_variants,
    COUNT(DISTINCT coalesce(new_card_imsi_replacement, '#')) AS replacement_new_imsi_variants,
    COUNT(DISTINCT coalesce(old_card_imsi_replaced, '#')) AS replacement_old_imsi_variants
  FROM d
  GROUP BY source_file, imsi, cycle_start, cycle_end
  HAVING COUNT(*) > 1
)
SELECT
  CASE
    WHEN final_window_variants = 1
     AND final_days_variants = 1
     AND monthly_rate_variants = 1
     AND amount_variants = 1
     AND charge_type_variants = 1
    THEN 'EXACT_ON_NON_KEY_FIELDS'
    ELSE 'DISTINCT_BILLING_ATTRIBUTES'
  END AS duplicate_assessment,
  COUNT(*) AS duplicate_key_count,
  SUM(detail_rows) AS duplicate_row_count,
  SUM(detail_rows - 1) AS extra_row_count,
  MAX(detail_rows) AS max_rows_per_key,
  SUM(CASE WHEN final_window_variants > 1 THEN 1 ELSE 0 END) AS keys_with_multiple_final_windows,
  SUM(CASE WHEN amount_variants > 1 THEN 1 ELSE 0 END) AS keys_with_multiple_amounts,
  SUM(CASE WHEN charge_type_variants > 1 THEN 1 ELSE 0 END) AS keys_with_multiple_charge_types,
  SUM(CASE WHEN replacement_new_imsi_variants > 1 OR replacement_old_imsi_variants > 1 THEN 1 ELSE 0 END) AS keys_with_replacement_variation
FROM dup_profile
GROUP BY
  CASE
    WHEN final_window_variants = 1
     AND final_days_variants = 1
     AND monthly_rate_variants = 1
     AND amount_variants = 1
     AND charge_type_variants = 1
    THEN 'EXACT_ON_NON_KEY_FIELDS'
    ELSE 'DISTINCT_BILLING_ATTRIBUTES'
  END