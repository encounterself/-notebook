WITH x AS (
  SELECT
    TRIM(CAST(imsi AS STRING)) AS imsi,
    TRY_TO_DATE(TRIM(CAST(cycle_start_date AS STRING))) AS excel_cycle_start,
    TRY_TO_DATE(TRIM(CAST(cycle_end_date AS STRING))) AS excel_cycle_end,
    TRY_TO_DATE(TRIM(CAST(final_start_date AS STRING))) AS excel_final_start,
    TRY_TO_DATE(TRIM(CAST(final_end_date AS STRING))) AS excel_final_end
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE TRIM(CAST(imsi AS STRING)) = '083901300080581202'
    AND TRIM(CAST(source_file AS STRING)) LIKE '%SEP 2025%'
),
target_products AS (
  SELECT DISTINCT TRIM(CAST(product_id AS STRING)) AS product_id
  FROM simo_prod.ods.resource_res_vsim_product
  WHERE CAST(supplier_id AS BIGINT) = 2275
),
h AS (
  SELECT
    TRIM(CAST(h.imsi AS STRING)) AS imsi,
    TRIM(CAST(h.product_id AS STRING)) AS product_id,
    TO_DATE(CAST(h.cycle_time AS TIMESTAMP)) AS platform_cycle_start,
    TO_DATE(CAST(h.next_cycle_time AS TIMESTAMP)) AS platform_cycle_end
  FROM simo_prod.ods.resource_res_vsim_cycle_history h
  INNER JOIN target_products p ON TRIM(CAST(h.product_id AS STRING)) = p.product_id
  WHERE TRIM(CAST(h.imsi AS STRING)) = '083901300080581202'
    AND CAST(h.cycle_time AS TIMESTAMP) < TIMESTAMP '2026-01-01 00:00:00'
    AND CAST(h.next_cycle_time AS TIMESTAMP) > TIMESTAMP '2025-09-01 00:00:00'
)
SELECT
  x.imsi,
  x.excel_cycle_start,
  x.excel_cycle_end,
  x.excel_final_start,
  x.excel_final_end,
  h.product_id,
  h.platform_cycle_start,
  h.platform_cycle_end,
  DATEDIFF(x.excel_final_end, x.excel_final_start) AS excel_diff,
  DATEDIFF(LEAST(x.excel_final_end, h.platform_cycle_end), GREATEST(x.excel_final_start, h.platform_cycle_start)) AS candidate_diff,
  GREATEST(x.excel_final_start, h.platform_cycle_start) AS calc_start,
  LEAST(x.excel_final_end, h.platform_cycle_end) AS calc_end,
  DATEDIFF(LEAST(x.excel_final_end, h.platform_cycle_end), GREATEST(x.excel_final_start, h.platform_cycle_start)) + 1 AS candidate_days
FROM x
LEFT JOIN h
  ON x.imsi = h.imsi
 AND h.platform_cycle_start <= x.excel_final_end
 AND h.platform_cycle_end >= x.excel_final_start
ORDER BY h.platform_cycle_start;