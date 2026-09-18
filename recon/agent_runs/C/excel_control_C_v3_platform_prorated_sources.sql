-- Live platform prorated source facts; read-only SELECT/WITH, no UNION.
WITH raw AS (
  SELECT source_file, NULLIF(TRIM(imsi),'') AS imsi,
         NULLIF(TRIM(product_name),'') AS product_name,
         TRY_CAST(NULLIF(TRIM(final_start_date),'') AS DATE) AS final_start_date,
         TRY_CAST(NULLIF(TRIM(final_end_date),'') AS DATE) AS final_end_date,
         TRY_CAST(NULLIF(TRIM(usage_days),'') AS DECIMAL(28,8)) AS excel_days,
         TRY_CAST(NULLIF(TRIM(monthly_rate),'') AS DECIMAL(28,8)) AS excel_price,
         TRY_CAST(NULLIF(TRIM(final_charge_for_usage_days),'') AS DECIMAL(28,8)) AS excel_amount,
         TRY_CAST(NULLIF(TRIM(pending_charge),'') AS DECIMAL(28,8)) AS pending_charge
  FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
),
labeled AS (
  SELECT raw.*, CASE
    WHEN source_file LIKE '%JAN 2025%' THEN '2025-01'
    WHEN source_file LIKE '%SEP 2025%' THEN '2025-09'
    WHEN source_file LIKE '%OCT 2025%' AND source_file LIKE '%773,793.84%' THEN '2025-10 (v2)'
    WHEN source_file LIKE '%OCT 2025%' AND source_file LIKE '%772,765.00%' THEN '2025-10 (v1)'
    WHEN source_file LIKE '%DEC 2025%' THEN '2025-12'
    WHEN source_file LIKE '%FEB 2026%' THEN '2026-02'
    WHEN source_file LIKE '%MAR 2026%' THEN '2026-03'
    WHEN source_file LIKE '%APR 2026%' THEN '2026-04'
    WHEN source_file LIKE '%MAY 2026%' THEN '2026-05'
    WHEN source_file LIKE '%JUNE 2026%' THEN '2026-06'
    WHEN source_file LIKE '%JULY 2026%' THEN '2026-07'
    WHEN source_file LIKE '%AUGUST 2026%' THEN '2026-08'
    ELSE source_file END AS invoice_batch_label,
    date_format(final_start_date,'yyyy-MM') AS observed_start_month
  FROM raw
)
SELECT 'simo_prod.mysql_cdc_sync.wa_invoice_prorated' AS source_table,
       source_file AS platform_source_file,
       invoice_batch_label,
       array_join(sort_array(collect_set(observed_start_month)), ',') AS observed_start_month,
       COUNT(*) AS record_count,
       COUNT(DISTINCT imsi) AS imsi_count,
       SUM(excel_amount) AS total_final_charge_for_usage_days,
       SUM(pending_charge) AS total_pending_charge,
       SUM(excel_price) AS total_monthly_rate_sum,
       COUNT(DISTINCT product_name) AS product_count,
       MIN(final_start_date) AS min_final_start_date,
       MAX(final_start_date) AS max_final_start_date,
       MIN(final_end_date) AS min_final_end_date,
       MAX(final_end_date) AS max_final_end_date
FROM labeled
GROUP BY source_file, invoice_batch_label
ORDER BY source_file;
