WITH excel_detail AS (
  SELECT DISTINCT
    TRIM(CAST(d.imsi AS STRING)) AS imsi,
    TRY_TO_DATE(TRIM(CAST(d.cycle_start_date AS STRING))) AS excel_cycle_start_date,
    TRY_TO_DATE(TRIM(CAST(d.cycle_end_date AS STRING))) AS excel_cycle_end_date,
    TRY_TO_DATE(TRIM(CAST(d.final_start_date AS STRING))) AS excel_final_start_date,
    TRY_TO_DATE(TRIM(CAST(d.final_end_date AS STRING))) AS excel_final_end_date
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail d
  WHERE TRIM(CAST(d.source_file AS STRING)) LIKE '%SEP 2025%'
     OR TRIM(CAST(d.source_file AS STRING)) LIKE '%OCT 2025%'
),
target_products AS (
  SELECT DISTINCT TRIM(CAST(product_id AS STRING)) AS product_id
  FROM simo_prod.ods.resource_res_vsim_product
  WHERE CAST(supplier_id AS BIGINT) = 2275
),
platform_cycles AS (
  SELECT DISTINCT
    TRIM(CAST(h.imsi AS STRING)) AS imsi,
    TRIM(CAST(h.product_id AS STRING)) AS product_id,
    TO_DATE(CAST(h.cycle_time AS TIMESTAMP)) AS platform_cycle_start_date,
    TO_DATE(CAST(h.next_cycle_time AS TIMESTAMP)) AS platform_cycle_end_date
  FROM simo_prod.ods.resource_res_vsim_cycle_history h
  INNER JOIN target_products p
    ON TRIM(CAST(h.product_id AS STRING)) = p.product_id
  WHERE CAST(h.cycle_time AS TIMESTAMP) < TIMESTAMP '2026-01-01 00:00:00'
    AND CAST(h.next_cycle_time AS TIMESTAMP) > TIMESTAMP '2025-09-01 00:00:00'
),
imsi_overlap AS (
  SELECT
    COUNT(DISTINCT e.imsi) AS excel_imsi_count,
    COUNT(DISTINCT p.imsi) AS platform_imsi_count,
    COUNT(DISTINCT CASE WHEN p.imsi IS NOT NULL THEN e.imsi END) AS shared_imsi_count
  FROM excel_detail e
  LEFT JOIN platform_cycles p ON e.imsi = p.imsi
),
exact_cycle_overlap AS (
  SELECT
    COUNT(*) AS excel_platform_exact_cycle_pairs,
    COUNT(DISTINCT e.imsi) AS exact_cycle_shared_imsi_count
  FROM excel_detail e
  INNER JOIN platform_cycles p
    ON e.imsi = p.imsi
   AND e.excel_cycle_start_date = p.platform_cycle_start_date
   AND e.excel_cycle_end_date = p.platform_cycle_end_date
),
date_overlap AS (
  SELECT
    COUNT(*) AS excel_platform_date_overlap_pairs,
    COUNT(DISTINCT e.imsi) AS date_overlap_shared_imsi_count
  FROM excel_detail e
  INNER JOIN platform_cycles p
    ON e.imsi = p.imsi
   AND e.excel_final_start_date IS NOT NULL
   AND e.excel_final_end_date IS NOT NULL
   AND p.platform_cycle_start_date <= e.excel_final_end_date
   AND p.platform_cycle_end_date >= e.excel_final_start_date
),
sample_excel AS (
  SELECT e.*
  FROM excel_detail e
  ORDER BY e.imsi, e.excel_cycle_start_date, e.excel_final_start_date
  LIMIT 100
),
sample_join AS (
  SELECT
    'SAMPLE' AS result_type,
    e.imsi,
    e.excel_cycle_start_date,
    e.excel_cycle_end_date,
    e.excel_final_start_date,
    e.excel_final_end_date,
    p.product_id,
    p.platform_cycle_start_date,
    p.platform_cycle_end_date
  FROM sample_excel e
  LEFT JOIN platform_cycles p
    ON e.imsi = p.imsi
)
SELECT 'SUMMARY_IMSI' AS result_type, CAST(NULL AS STRING) AS imsi,
       CAST(NULL AS DATE) AS excel_cycle_start_date, CAST(NULL AS DATE) AS excel_cycle_end_date,
       CAST(NULL AS DATE) AS excel_final_start_date, CAST(NULL AS DATE) AS excel_final_end_date,
       CAST(NULL AS STRING) AS product_id, CAST(NULL AS DATE) AS platform_cycle_start_date,
       CAST(NULL AS DATE) AS platform_cycle_end_date,
       excel_imsi_count, platform_imsi_count, shared_imsi_count,
       CAST(NULL AS BIGINT) AS excel_platform_exact_cycle_pairs, CAST(NULL AS BIGINT) AS exact_cycle_shared_imsi_count,
       CAST(NULL AS BIGINT) AS excel_platform_date_overlap_pairs, CAST(NULL AS BIGINT) AS date_overlap_shared_imsi_count
FROM imsi_overlap
CROSS JOIN exact_cycle_overlap
CROSS JOIN date_overlap
UNION ALL
SELECT result_type, imsi, excel_cycle_start_date, excel_cycle_end_date, excel_final_start_date, excel_final_end_date,
       product_id, platform_cycle_start_date, platform_cycle_end_date,
       CAST(NULL AS BIGINT), CAST(NULL AS BIGINT), CAST(NULL AS BIGINT),
       CAST(NULL AS BIGINT), CAST(NULL AS BIGINT), CAST(NULL AS BIGINT), CAST(NULL AS BIGINT)
FROM sample_join
ORDER BY result_type, imsi;