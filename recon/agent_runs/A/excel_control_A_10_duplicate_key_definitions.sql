WITH detail_canonical AS (
  SELECT
    NULLIF(TRIM(CAST(imsi AS STRING)), '') AS imsi_std,
    NULLIF(TRIM(CAST(source_file AS STRING)), '') AS source_file_std,
    NULLIF(TRIM(CAST(product_name AS STRING)), '') AS product_name_std,
    TO_DATE(cycle_start_date) AS cycle_start_std,
    TO_DATE(cycle_end_date) AS cycle_end_std,
    TO_DATE(final_start_date) AS final_start_std,
    TO_DATE(final_end_date) AS final_end_std,
    NULLIF(TRIM(CAST(charge_type AS STRING)), '') AS charge_type_std,
    TRY_CAST(monthly_rate AS DECIMAL(38,12)) AS monthly_rate_std,
    TRY_CAST(final_days AS DECIMAL(38,12)) AS final_days_std,
    TRY_CAST(final_charge AS DECIMAL(38,12)) AS final_amount_std
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
),
key_counts AS (
  SELECT
    'K1_imsi_source_final_dates_charge_type' AS key_definition,
    COUNT(*) AS duplicate_key_count,
    SUM(row_count - 1) AS duplicate_extra_row_count,
    MAX(row_count) AS max_rows_per_key
  FROM (
    SELECT imsi_std, source_file_std, final_start_std, final_end_std, charge_type_std, COUNT(*) AS row_count
    FROM detail_canonical
    WHERE imsi_std IS NOT NULL AND source_file_std IS NOT NULL
    GROUP BY imsi_std, source_file_std, final_start_std, final_end_std, charge_type_std
    HAVING COUNT(*) > 1
  )
  UNION ALL
  SELECT
    'K2_imsi_source_final_dates',
    COUNT(*),
    SUM(row_count - 1),
    MAX(row_count)
  FROM (
    SELECT imsi_std, source_file_std, final_start_std, final_end_std, COUNT(*) AS row_count
    FROM detail_canonical
    WHERE imsi_std IS NOT NULL AND source_file_std IS NOT NULL
    GROUP BY imsi_std, source_file_std, final_start_std, final_end_std
    HAVING COUNT(*) > 1
  )
  UNION ALL
  SELECT
    'K3_imsi_source_cycle_dates_charge_type',
    COUNT(*),
    SUM(row_count - 1),
    MAX(row_count)
  FROM (
    SELECT imsi_std, source_file_std, cycle_start_std, cycle_end_std, charge_type_std, COUNT(*) AS row_count
    FROM detail_canonical
    WHERE imsi_std IS NOT NULL AND source_file_std IS NOT NULL
    GROUP BY imsi_std, source_file_std, cycle_start_std, cycle_end_std, charge_type_std
    HAVING COUNT(*) > 1
  )
  UNION ALL
  SELECT
    'K4_imsi_source_cycle_dates',
    COUNT(*),
    SUM(row_count - 1),
    MAX(row_count)
  FROM (
    SELECT imsi_std, source_file_std, cycle_start_std, cycle_end_std, COUNT(*) AS row_count
    FROM detail_canonical
    WHERE imsi_std IS NOT NULL AND source_file_std IS NOT NULL
    GROUP BY imsi_std, source_file_std, cycle_start_std, cycle_end_std
    HAVING COUNT(*) > 1
  )
  UNION ALL
  SELECT
    'K5_imsi_source_final_dates_charge_type_price',
    COUNT(*),
    SUM(row_count - 1),
    MAX(row_count)
  FROM (
    SELECT imsi_std, source_file_std, final_start_std, final_end_std, charge_type_std, monthly_rate_std, COUNT(*) AS row_count
    FROM detail_canonical
    WHERE imsi_std IS NOT NULL AND source_file_std IS NOT NULL
    GROUP BY imsi_std, source_file_std, final_start_std, final_end_std, charge_type_std, monthly_rate_std
    HAVING COUNT(*) > 1
  )
  UNION ALL
  SELECT
    'K6_imsi_source_final_dates_charge_type_price_amount',
    COUNT(*),
    SUM(row_count - 1),
    MAX(row_count)
  FROM (
    SELECT imsi_std, source_file_std, final_start_std, final_end_std, charge_type_std, monthly_rate_std, final_amount_std, COUNT(*) AS row_count
    FROM detail_canonical
    WHERE imsi_std IS NOT NULL AND source_file_std IS NOT NULL
    GROUP BY imsi_std, source_file_std, final_start_std, final_end_std, charge_type_std, monthly_rate_std, final_amount_std
    HAVING COUNT(*) > 1
  )
  UNION ALL
  SELECT
    'K7_imsi_source_final_dates_charge_type_product',
    COUNT(*),
    SUM(row_count - 1),
    MAX(row_count)
  FROM (
    SELECT imsi_std, source_file_std, final_start_std, final_end_std, charge_type_std, product_name_std, COUNT(*) AS row_count
    FROM detail_canonical
    WHERE imsi_std IS NOT NULL AND source_file_std IS NOT NULL
    GROUP BY imsi_std, source_file_std, final_start_std, final_end_std, charge_type_std, product_name_std
    HAVING COUNT(*) > 1
  )
  UNION ALL
  SELECT
    'K8_imsi_source_cycle_dates_charge_type_price',
    COUNT(*),
    SUM(row_count - 1),
    MAX(row_count)
  FROM (
    SELECT imsi_std, source_file_std, cycle_start_std, cycle_end_std, charge_type_std, monthly_rate_std, COUNT(*) AS row_count
    FROM detail_canonical
    WHERE imsi_std IS NOT NULL AND source_file_std IS NOT NULL
    GROUP BY imsi_std, source_file_std, cycle_start_std, cycle_end_std, charge_type_std, monthly_rate_std
    HAVING COUNT(*) > 1
  )
)
SELECT * FROM key_counts
ORDER BY key_definition
