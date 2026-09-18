-- Batch A / September read-only candidate output with platform scope withheld.
-- The September target-month platform snapshot is not readable, so no platform card set is fabricated.
WITH cfg AS (
  SELECT '2025-09' AS billing_month, DATE('2025-09-01') AS month_start, DATE('2025-09-30') AS month_end, 30 AS days_in_month
), invoice AS (
  SELECT
    c.billing_month, x.imsi, x.iccid, CAST(NULL AS STRING) AS excel_product_id,
    x.product_name AS excel_product_name, x.charge_type,
    TRY_CAST(x.final_start_date AS DATE) AS xl_start_d,
    TRY_CAST(x.final_end_date AS DATE) AS xl_end_d,
    TRY_CAST(x.final_days AS DOUBLE) AS xl_days,
    TRY_CAST(x.monthly_rate AS DOUBLE) AS xl_rate,
    TRY_CAST(x.final_charge AS DOUBLE) AS xl_charge,
    DAY(LAST_DAY(TRY_CAST(x.final_start_date AS DATE))) AS excel_days_in_month,
    ROUND(TRY_CAST(x.monthly_rate AS DOUBLE) / DAY(LAST_DAY(TRY_CAST(x.final_start_date AS DATE))) * TRY_CAST(x.final_days AS DOUBLE), 4) AS excel_calculated_amount,
    ROUND(ROUND(TRY_CAST(x.monthly_rate AS DOUBLE) / DAY(LAST_DAY(TRY_CAST(x.final_start_date AS DATE))) * TRY_CAST(x.final_days AS DOUBLE), 4) - TRY_CAST(x.final_charge AS DOUBLE), 4) AS excel_amount_difference,
    CAST(NULL AS DOUBLE) AS platform_calculated_days,
    CAST(NULL AS DOUBLE) AS platform_calculated_price,
    CAST(NULL AS DOUBLE) AS platform_calculated_amount,
    CAST(NULL AS DOUBLE) AS days_difference,
    CAST(NULL AS DOUBLE) AS price_difference,
    CAST(NULL AS DOUBLE) AS amount_difference,
    'MISSING_DATA_PLATFORM_SNAPSHOT' AS reconciliation_status,
    'MISSING_MAPPING_PLATFORM_CARD_SET' AS platform_scope_status,
    x.source_file
  FROM cfg c
  JOIN simo_prod.mysql_cdc_sync.wa_invoice_detail x
    ON TRY_CAST(x.final_start_date AS DATE) BETWEEN c.month_start AND c.month_end
)
SELECT * FROM invoice ORDER BY imsi, charge_type;