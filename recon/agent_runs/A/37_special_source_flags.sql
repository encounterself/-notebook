-- Batch A / read-only inspection of replacement, transfer and auxiliary invoice sources.
WITH detail_flags AS (
  SELECT
    'wa_invoice_detail' AS source_table,
    SUBSTR(CAST(TRY_CAST(final_start_date AS DATE) AS STRING), 1, 7) AS billing_month,
    charge_type,
    transferred_to_wing_simbank,
    COUNT(*) AS row_count,
    COUNT(DISTINCT imsi) AS card_count,
    ROUND(SUM(TRY_CAST(final_charge AS DOUBLE)), 4) AS amount
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE TRY_CAST(final_start_date AS DATE) BETWEEN DATE('2025-09-01') AND DATE('2025-11-30')
  GROUP BY SUBSTR(CAST(TRY_CAST(final_start_date AS DATE) AS STRING), 1, 7), charge_type, transferred_to_wing_simbank
), credit_scope AS (
  SELECT
    'wa_invoice_credit' AS source_table,
    CAST(NULL AS STRING) AS billing_month,
    CAST(NULL AS STRING) AS charge_type,
    CAST(NULL AS STRING) AS transferred_to_wing_simbank,
    COUNT(*) AS row_count,
    COUNT(DISTINCT imsi) AS card_count,
    ROUND(SUM(TRY_CAST(credit_owed AS DOUBLE)), 4) AS amount
  FROM simo_prod.mysql_cdc_sync.wa_invoice_credit
  WHERE source_file LIKE '%SEP 2025%' OR source_file LIKE '%OCT 2025%'
), prorated_scope AS (
  SELECT
    'wa_invoice_prorated' AS source_table,
    SUBSTR(CAST(TRY_CAST(final_start_date AS DATE) AS STRING), 1, 7) AS billing_month,
    CAST(NULL AS STRING) AS charge_type,
    CAST(NULL AS STRING) AS transferred_to_wing_simbank,
    COUNT(*) AS row_count,
    COUNT(DISTINCT imsi) AS card_count,
    ROUND(SUM(TRY_CAST(final_charge_for_usage_days AS DOUBLE)), 4) AS amount
  FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
  WHERE TRY_CAST(final_start_date AS DATE) BETWEEN DATE('2025-09-01') AND DATE('2025-11-30')
  GROUP BY SUBSTR(CAST(TRY_CAST(final_start_date AS DATE) AS STRING), 1, 7)
)
SELECT * FROM detail_flags
UNION ALL SELECT * FROM credit_scope
UNION ALL SELECT * FROM prorated_scope
ORDER BY source_table, billing_month, charge_type, transferred_to_wing_simbank;