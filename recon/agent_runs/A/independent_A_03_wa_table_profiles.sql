WITH detail_profile AS (
  SELECT
    'wa_invoice_detail' AS table_name,
    COUNT(*) AS record_count,
    COUNT(DISTINCT imsi) AS imsi_count,
    COUNT(DISTINCT source_file) AS source_file_count,
    MIN(TRY_CAST(final_start_date AS DATE)) AS min_primary_date,
    MAX(TRY_CAST(final_start_date AS DATE)) AS max_primary_date,
    MIN(TRY_CAST(final_end_date AS DATE)) AS min_secondary_date,
    MAX(TRY_CAST(final_end_date AS DATE)) AS max_secondary_date,
    'final_charge' AS amount_field,
    ROUND(SUM(TRY_CAST(final_charge AS DOUBLE)), 6) AS amount_sum,
    'monthly_rate' AS auxiliary_amount_field,
    ROUND(SUM(TRY_CAST(monthly_rate AS DOUBLE)), 6) AS auxiliary_amount_sum,
    COUNT(DISTINCT charge_type) AS charge_type_count
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
), credit_profile AS (
  SELECT
    'wa_invoice_credit' AS table_name,
    COUNT(*) AS record_count,
    COUNT(DISTINCT imsi) AS imsi_count,
    COUNT(DISTINCT source_file) AS source_file_count,
    MIN(TRY_CAST(date_line_went_down AS DATE)) AS min_primary_date,
    MAX(TRY_CAST(date_line_went_down AS DATE)) AS max_primary_date,
    MIN(TRY_CAST(cycle_start AS DATE)) AS min_secondary_date,
    MAX(TRY_CAST(cycle_end AS DATE)) AS max_secondary_date,
    'credit_owed' AS amount_field,
    ROUND(SUM(TRY_CAST(credit_owed AS DOUBLE)), 6) AS amount_sum,
    'final_price' AS auxiliary_amount_field,
    ROUND(SUM(TRY_CAST(final_price AS DOUBLE)), 6) AS auxiliary_amount_sum,
    CAST(NULL AS BIGINT) AS charge_type_count
  FROM simo_prod.mysql_cdc_sync.wa_invoice_credit
), prorated_profile AS (
  SELECT
    'wa_invoice_prorated' AS table_name,
    COUNT(*) AS record_count,
    COUNT(DISTINCT imsi) AS imsi_count,
    COUNT(DISTINCT source_file) AS source_file_count,
    MIN(TRY_CAST(final_start_date AS DATE)) AS min_primary_date,
    MAX(TRY_CAST(final_start_date AS DATE)) AS max_primary_date,
    MIN(TRY_CAST(final_end_date AS DATE)) AS min_secondary_date,
    MAX(TRY_CAST(final_end_date AS DATE)) AS max_secondary_date,
    'final_charge_for_usage_days' AS amount_field,
    ROUND(SUM(TRY_CAST(final_charge_for_usage_days AS DOUBLE)), 6) AS amount_sum,
    'pending_charge' AS auxiliary_amount_field,
    ROUND(SUM(TRY_CAST(pending_charge AS DOUBLE)), 6) AS auxiliary_amount_sum,
    CAST(NULL AS BIGINT) AS charge_type_count
  FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
)
SELECT * FROM detail_profile
UNION ALL SELECT * FROM credit_profile
UNION ALL SELECT * FROM prorated_profile
ORDER BY table_name