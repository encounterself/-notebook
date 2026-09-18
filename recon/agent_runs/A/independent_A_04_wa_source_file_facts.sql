WITH detail_source AS (
  SELECT
    'wa_invoice_detail' AS table_name,
    source_file,
    COUNT(*) AS record_count,
    COUNT(DISTINCT imsi) AS imsi_count,
    ROUND(SUM(TRY_CAST(final_charge AS DOUBLE)), 6) AS total_amount,
    'final_charge' AS amount_field,
    ROUND(SUM(TRY_CAST(monthly_rate AS DOUBLE)), 6) AS total_auxiliary_amount,
    'monthly_rate' AS auxiliary_amount_field,
    COUNT(DISTINCT charge_type) AS charge_type_count,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(charge_type AS STRING)))) AS charge_type_values,
    COUNT(DISTINCT product_name) AS product_count,
    MIN(TRY_CAST(final_start_date AS DATE)) AS min_start_date,
    MAX(TRY_CAST(final_start_date AS DATE)) AS max_start_date,
    MIN(TRY_CAST(final_end_date AS DATE)) AS min_end_date,
    MAX(TRY_CAST(final_end_date AS DATE)) AS max_end_date
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  GROUP BY source_file
), credit_source AS (
  SELECT
    'wa_invoice_credit' AS table_name,
    source_file,
    COUNT(*) AS record_count,
    COUNT(DISTINCT imsi) AS imsi_count,
    ROUND(SUM(TRY_CAST(credit_owed AS DOUBLE)), 6) AS total_amount,
    'credit_owed' AS amount_field,
    ROUND(SUM(TRY_CAST(final_price AS DOUBLE)), 6) AS total_auxiliary_amount,
    'final_price' AS auxiliary_amount_field,
    CAST(NULL AS BIGINT) AS charge_type_count,
    CAST(NULL AS STRING) AS charge_type_values,
    COUNT(DISTINCT COALESCE(prod, replacement_product)) AS product_count,
    MIN(TRY_CAST(date_line_went_down AS DATE)) AS min_start_date,
    MAX(TRY_CAST(date_line_went_down AS DATE)) AS max_start_date,
    MIN(TRY_CAST(cycle_end AS DATE)) AS min_end_date,
    MAX(TRY_CAST(cycle_end AS DATE)) AS max_end_date
  FROM simo_prod.mysql_cdc_sync.wa_invoice_credit
  GROUP BY source_file
), prorated_source AS (
  SELECT
    'wa_invoice_prorated' AS table_name,
    source_file,
    COUNT(*) AS record_count,
    COUNT(DISTINCT imsi) AS imsi_count,
    ROUND(SUM(TRY_CAST(final_charge_for_usage_days AS DOUBLE)), 6) AS total_amount,
    'final_charge_for_usage_days' AS amount_field,
    ROUND(SUM(TRY_CAST(pending_charge AS DOUBLE)), 6) AS total_auxiliary_amount,
    'pending_charge' AS auxiliary_amount_field,
    CAST(NULL AS BIGINT) AS charge_type_count,
    CAST(NULL AS STRING) AS charge_type_values,
    COUNT(DISTINCT product_name) AS product_count,
    MIN(TRY_CAST(final_start_date AS DATE)) AS min_start_date,
    MAX(TRY_CAST(final_start_date AS DATE)) AS max_start_date,
    MIN(TRY_CAST(final_end_date AS DATE)) AS min_end_date,
    MAX(TRY_CAST(final_end_date AS DATE)) AS max_end_date
  FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
  GROUP BY source_file
)
SELECT * FROM detail_source
UNION ALL SELECT * FROM credit_source
UNION ALL SELECT * FROM prorated_source
ORDER BY table_name, source_file