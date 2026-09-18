WITH x AS (
  SELECT
    TRIM(CAST(source_file AS STRING)) AS source_file,
    TRIM(CAST(imsi AS STRING)) AS imsi,
    NULLIF(TRIM(CAST(charge_type AS STRING)), '') AS charge_type,
    TRY_TO_DATE(TRIM(CAST(cycle_start_date AS STRING))) AS cycle_start_date,
    TRY_TO_DATE(TRIM(CAST(cycle_end_date AS STRING))) AS cycle_end_date,
    TRY_TO_DATE(TRIM(CAST(new_activation_date AS STRING))) AS new_activation_date,
    TRY_TO_DATE(TRIM(CAST(offstock_date AS STRING))) AS offstock_date,
    TRY_TO_DATE(TRIM(CAST(final_start_date AS STRING))) AS final_start_date,
    TRY_TO_DATE(TRIM(CAST(final_end_date AS STRING))) AS final_end_date,
    TRY_CAST(TRIM(CAST(final_days AS STRING)) AS DECIMAL(38,12)) AS excel_days,
    TRY_CAST(TRIM(CAST(monthly_rate AS STRING)) AS DECIMAL(38,12)) AS excel_price,
    TRY_CAST(TRIM(CAST(final_charge AS STRING)) AS DECIMAL(38,12)) AS excel_amount,
    TRIM(CAST(product_name AS STRING)) AS product_name
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE (TRIM(CAST(source_file AS STRING)) LIKE '%SEP 2025%'
      OR TRIM(CAST(source_file AS STRING)) LIKE '%OCT 2025%')
),
ranked AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY source_file, COALESCE(charge_type,'<NULL>'), excel_price ORDER BY imsi) AS rn
  FROM x
)
SELECT source_file, imsi, charge_type, cycle_start_date, cycle_end_date, new_activation_date, offstock_date, final_start_date, final_end_date, excel_days, excel_price, excel_amount, product_name
FROM ranked
WHERE rn <= 10
ORDER BY source_file, charge_type, excel_price, rn;