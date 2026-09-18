-- Batch A Excel detail scope for formal platform recalculation. Read-only only.
WITH excel_detail_invoice AS (
  SELECT
    TRIM(CAST(d.source_file AS STRING)) AS source_file,
    CASE
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%JAN 2025%' THEN '2025-01'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%SEP 2025%' THEN '2025-09'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%OCT 2025%'
       AND TRIM(CAST(d.source_file AS STRING)) LIKE '%773,793.84%' THEN '2025-10 (v2)'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%OCT 2025%'
       AND TRIM(CAST(d.source_file AS STRING)) LIKE '%772,765.00%' THEN '2025-10 (v1)'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%DEC 2025%' THEN '2025-12'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%FEB 2026%' THEN '2026-02'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%MAR 2026%' THEN '2026-03'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%APR 2026%' THEN '2026-04'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%MAY 2026%' THEN '2026-05'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%JUNE 2026%' THEN '2026-06'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%JULY 2026%' THEN '2026-07'
      WHEN TRIM(CAST(d.source_file AS STRING)) LIKE '%AUGUST 2026%' THEN '2026-08'
      ELSE TRIM(CAST(d.source_file AS STRING))
    END AS invoice_batch_label,
    TRIM(CAST(d.imsi AS STRING)) AS imsi,
    NULLIF(TRIM(CAST(d.charge_type AS STRING)), '') AS charge_type,
    NULLIF(TRY_TO_DATE(TRIM(CAST(d.cycle_start_date AS STRING))), DATE '0001-01-01') AS cycle_start_date,
    NULLIF(TRY_TO_DATE(TRIM(CAST(d.cycle_end_date AS STRING))), DATE '0001-01-01') AS cycle_end_date,
    NULLIF(TRY_TO_DATE(TRIM(CAST(d.final_start_date AS STRING))), DATE '0001-01-01') AS final_start_date,
    NULLIF(TRY_TO_DATE(TRIM(CAST(d.final_end_date AS STRING))), DATE '0001-01-01') AS final_end_date,
    TRY_CAST(NULLIF(TRIM(CAST(d.final_days AS STRING)), '') AS DECIMAL(38,12)) AS excel_days,
    TRY_CAST(NULLIF(TRIM(CAST(d.monthly_rate AS STRING)), '') AS DECIMAL(38,12)) AS excel_price,
    TRY_CAST(NULLIF(TRIM(CAST(d.final_charge AS STRING)), '') AS DECIMAL(38,12)) AS excel_amount,
    TRIM(CAST(d.product_name AS STRING)) AS excel_product_name
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail d
  WHERE TRIM(CAST(d.source_file AS STRING)) LIKE '%SEP 2025%'
     OR TRIM(CAST(d.source_file AS STRING)) LIKE '%OCT 2025%'
),
scoped AS (
  SELECT *
  FROM excel_detail_invoice
  WHERE invoice_batch_label IN ('2025-09', '2025-10 (v1)', '2025-10 (v2)')
),
charge_summary AS (
  SELECT
    source_file,
    invoice_batch_label,
    COALESCE(charge_type, '<NULL>') AS charge_type,
    excel_price,
    COUNT(*) AS record_count,
    COUNT(DISTINCT imsi) AS imsi_count,
    SUM(excel_amount) AS excel_total_final_charge,
    MIN(final_start_date) AS min_final_start_date,
    MAX(final_end_date) AS max_final_end_date,
    MIN(cycle_start_date) AS min_cycle_start_date,
    MAX(cycle_end_date) AS max_cycle_end_date,
    COUNT(DISTINCT excel_days) AS distinct_excel_days
  FROM scoped
  GROUP BY source_file, invoice_batch_label, COALESCE(charge_type, '<NULL>'), excel_price
),
month_summary AS (
  SELECT
    'MONTH_TOTAL' AS result_type,
    invoice_batch_label,
    CAST(NULL AS STRING) AS source_file,
    CAST(NULL AS STRING) AS charge_type,
    CAST(NULL AS DECIMAL(38,12)) AS excel_price,
    COUNT(*) AS record_count,
    COUNT(DISTINCT imsi) AS imsi_count,
    SUM(excel_amount) AS excel_total_final_charge,
    MIN(final_start_date) AS min_final_start_date,
    MAX(final_end_date) AS max_final_end_date,
    MIN(cycle_start_date) AS min_cycle_start_date,
    MAX(cycle_end_date) AS max_cycle_end_date,
    COUNT(DISTINCT excel_days) AS distinct_excel_days
  FROM scoped
  GROUP BY invoice_batch_label
),
charge_rows AS (
  SELECT
    'CHARGE_TYPE_PRICE' AS result_type,
    invoice_batch_label,
    source_file,
    charge_type,
    excel_price,
    record_count,
    imsi_count,
    excel_total_final_charge,
    min_final_start_date,
    max_final_end_date,
    min_cycle_start_date,
    max_cycle_end_date,
    distinct_excel_days
  FROM charge_summary
)
SELECT * FROM month_summary
UNION ALL
SELECT * FROM charge_rows
ORDER BY result_type, invoice_batch_label, source_file, charge_type, excel_price;