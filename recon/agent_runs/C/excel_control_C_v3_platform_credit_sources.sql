-- Live platform credit source facts; read-only SELECT/WITH, no UNION.
WITH raw AS (
  SELECT source_file, NULLIF(TRIM(imsi),'') AS imsi,
         NULLIF(TRIM(prod),'') AS product_name,
         TRY_CAST(NULLIF(TRIM(cycle_start),'') AS DATE) AS cycle_start,
         TRY_CAST(NULLIF(TRIM(cycle_end),'') AS DATE) AS cycle_end,
         TRY_CAST(NULLIF(TRIM(price),'') AS DECIMAL(28,8)) AS price,
         TRY_CAST(NULLIF(TRIM(final_price),'') AS DECIMAL(28,8)) AS final_price,
         TRY_CAST(NULLIF(TRIM(correct_price),'') AS DECIMAL(28,8)) AS correct_price,
         TRY_CAST(NULLIF(TRIM(credit_owed),'') AS DECIMAL(28,8)) AS excel_amount
  FROM simo_prod.mysql_cdc_sync.wa_invoice_credit
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
    date_format(cycle_start,'yyyy-MM') AS cycle_start_month,
    date_format(cycle_end,'yyyy-MM') AS cycle_end_month
  FROM raw
)
SELECT 'simo_prod.mysql_cdc_sync.wa_invoice_credit' AS source_table,
       source_file AS platform_source_file,
       invoice_batch_label,
       CAST(NULL AS STRING) AS observed_start_month,
       array_join(sort_array(collect_set(cycle_start_month)), ',') AS observed_cycle_start_month,
       array_join(sort_array(collect_set(cycle_end_month)), ',') AS observed_cycle_end_month,
       COUNT(*) AS record_count,
       COUNT(DISTINCT imsi) AS imsi_count,
       SUM(excel_amount) AS total_credit_owed,
       SUM(price) AS total_price,
       SUM(final_price) AS total_final_price,
       SUM(correct_price) AS total_correct_price,
       COUNT(DISTINCT product_name) AS product_count,
       MIN(cycle_start) AS min_cycle_start,
       MAX(cycle_start) AS max_cycle_start,
       MIN(cycle_end) AS min_cycle_end,
       MAX(cycle_end) AS max_cycle_end
FROM labeled
GROUP BY source_file, invoice_batch_label
ORDER BY source_file;
