WITH cfg AS (
  SELECT '2026-03' AS billing_month, '01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx' AS source_file
  UNION ALL SELECT '2026-04', '01-SIMO Data Purchase Invoice Details - APR 2026.xlsx'
  UNION ALL SELECT '2026-05', '01-SIMO Data Purchase Invoice Details - MAY 2026.xlsx'
),
detail_rows AS (
  SELECT
    c.billing_month,
    'mysql_cdc_sync.wa_invoice_detail' AS source_table,
    x.source_file,
    x.sheet_name,
    CAST(x.imsi AS STRING) AS imsi,
    CAST(x.iccid AS STRING) AS iccid,
    CAST(x.charge_type AS STRING) AS charge_type,
    CAST(x.cycle_start_date AS STRING) AS cycle_start_raw,
    CAST(x.cycle_end_date AS STRING) AS cycle_end_raw,
    CAST(x.new_activation_date AS STRING) AS new_activation_raw,
    CAST(x.offstock_date AS STRING) AS offstock_raw,
    CAST(x.final_start_date AS STRING) AS final_start_raw,
    CAST(x.final_end_date AS STRING) AS final_end_raw,
    CAST(x.active_days AS STRING) AS active_days_raw,
    CAST(x.usage_days AS STRING) AS usage_days_raw,
    CAST(x.usage_days_alt AS STRING) AS usage_days_alt_raw,
    CAST(x.final_days AS STRING) AS final_days_raw,
    CAST(x.monthly_rate AS STRING) AS price_raw,
    CAST(x.final_charge AS STRING) AS amount_raw,
    CAST(x.transferred_to_wing_simbank AS STRING) AS simbank_raw,
    CAST(x.new_card_imsi_replacement AS STRING) AS replacement_new_raw,
    CAST(x.old_card_imsi_replaced AS STRING) AS replacement_old_raw,
    CAST(x.note AS STRING) AS note_raw
  FROM cfg c
  JOIN simo_prod.mysql_cdc_sync.wa_invoice_detail x
    ON x.source_file = c.source_file
),
prorated_rows AS (
  SELECT
    c.billing_month,
    'mysql_cdc_sync.wa_invoice_prorated' AS source_table,
    x.source_file,
    x.sheet_name,
    CAST(x.imsi AS STRING) AS imsi,
    CAST(x.iccid AS STRING) AS iccid,
    'PRORATED_PENDING' AS charge_type,
    CAST(x.cycle_start_date AS STRING) AS cycle_start_raw,
    CAST(x.cycle_end_date AS STRING) AS cycle_end_raw,
    CAST(x.new_activation_date AS STRING) AS new_activation_raw,
    NULL AS offstock_raw,
    CAST(x.final_start_date AS STRING) AS final_start_raw,
    CAST(x.final_end_date AS STRING) AS final_end_raw,
    CAST(x.active_days AS STRING) AS active_days_raw,
    CAST(x.usage_days AS STRING) AS usage_days_raw,
    NULL AS usage_days_alt_raw,
    NULL AS final_days_raw,
    CAST(x.monthly_rate AS STRING) AS price_raw,
    CAST(x.final_charge_for_usage_days AS STRING) AS amount_raw,
    NULL AS simbank_raw,
    NULL AS replacement_new_raw,
    NULL AS replacement_old_raw,
    CAST(x.pending_charge AS STRING) AS note_raw
  FROM cfg c
  JOIN simo_prod.mysql_cdc_sync.wa_invoice_prorated x
    ON x.source_file = c.source_file
),
all_rows AS (
  SELECT * FROM detail_rows
  UNION ALL
  SELECT * FROM prorated_rows
),
summary AS (
  SELECT
    billing_month,
    source_table,
    source_file,
    sheet_name,
    charge_type,
    COUNT(*) AS row_count,
    COUNT(DISTINCT NULLIF(TRIM(imsi), '')) AS imsi_count,
    COUNT(DISTINCT NULLIF(TRIM(iccid), '')) AS iccid_count,
    COUNT(DISTINCT NULLIF(TRIM(price_raw), '')) AS price_text_count,
    COUNT(DISTINCT TRY_CAST(price_raw AS DECIMAL(18,6))) AS price_numeric_count,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(COALESCE(NULLIF(TRIM(price_raw), ''), '<NULL>')))) AS price_values_seen,
    COUNT(DISTINCT NULLIF(TRIM(final_days_raw), '')) AS final_days_text_count,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(COALESCE(NULLIF(TRIM(final_days_raw), ''), '<NULL>')))) AS final_days_values_seen,
    ROUND(SUM(TRY_CAST(amount_raw AS DOUBLE)), 6) AS amount_sum,
    ROUND(SUM(TRY_CAST(price_raw AS DOUBLE)), 6) AS price_sum_not_used_as_rule,
    SUM(CASE WHEN LOWER(COALESCE(simbank_raw, '')) RLIKE 'yes|true|simbank|transfer' THEN 1 ELSE 0 END) AS simbank_flag_rows,
    SUM(CASE WHEN NULLIF(TRIM(replacement_new_raw), '') IS NOT NULL OR NULLIF(TRIM(replacement_old_raw), '') IS NOT NULL THEN 1 ELSE 0 END) AS replacement_flag_rows
  FROM all_rows
  GROUP BY billing_month, source_table, source_file, sheet_name, charge_type
),
credit_probe AS (
  SELECT
    c.billing_month,
    'mysql_cdc_sync.wa_invoice_credit' AS source_table,
    c.source_file,
    CAST(NULL AS STRING) AS sheet_name,
    'CREDIT_TABLE_ROW' AS charge_type,
    COUNT(x.imsi) AS row_count,
    COUNT(DISTINCT NULLIF(TRIM(x.imsi), '')) AS imsi_count,
    COUNT(DISTINCT NULLIF(TRIM(x.iccid), '')) AS iccid_count,
    COUNT(DISTINCT NULLIF(TRIM(x.price), '')) AS price_text_count,
    COUNT(DISTINCT TRY_CAST(x.price AS DECIMAL(18,6))) AS price_numeric_count,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(COALESCE(NULLIF(TRIM(x.price), ''), '<NULL>')))) AS price_values_seen,
    COUNT(DISTINCT NULLIF(TRIM(x.days_without_service), '')) AS final_days_text_count,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(COALESCE(NULLIF(TRIM(x.days_without_service), ''), '<NULL>'))) ) AS final_days_values_seen,
    ROUND(SUM(TRY_CAST(x.credit_owed AS DOUBLE)), 6) AS amount_sum,
    CAST(NULL AS DOUBLE) AS price_sum_not_used_as_rule,
    CAST(NULL AS BIGINT) AS simbank_flag_rows,
    SUM(CASE WHEN NULLIF(TRIM(x.if_replaced_whats_new_imsi), '') IS NOT NULL THEN 1 ELSE 0 END) AS replacement_flag_rows
  FROM cfg c
  LEFT JOIN simo_prod.mysql_cdc_sync.wa_invoice_credit x
    ON x.source_file = c.source_file
  GROUP BY c.billing_month, c.source_file
)
SELECT * FROM summary
UNION ALL
SELECT * FROM credit_probe
ORDER BY billing_month, source_table, source_file, sheet_name, charge_type;