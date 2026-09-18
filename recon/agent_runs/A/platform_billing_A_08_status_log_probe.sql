WITH target_products AS (
  SELECT DISTINCT TRIM(CAST(product_id AS STRING)) AS product_id
  FROM simo_prod.ods.resource_res_vsim_product
  WHERE CAST(supplier_id AS BIGINT) = 2275
),
platform_imsi AS (
  SELECT DISTINCT TRIM(CAST(h.imsi AS STRING)) AS imsi
  FROM simo_prod.ods.resource_res_vsim_cycle_history h
  INNER JOIN target_products p
    ON TRIM(CAST(h.product_id AS STRING)) = p.product_id
  WHERE CAST(h.cycle_time AS TIMESTAMP) < TIMESTAMP '2025-12-01 00:00:00'
    AND CAST(h.next_cycle_time AS TIMESTAMP) > TIMESTAMP '2025-09-01 00:00:00'
),
status_log_scope AS (
  SELECT
    TRIM(CAST(l.IMSI AS STRING)) AS imsi,
    COUNT(*) AS row_count,
    COUNT(DISTINCT TRIM(CAST(l.PRE_STATUS AS STRING))) AS pre_status_count,
    COUNT(DISTINCT TRIM(CAST(l.NEXT_STATUS AS STRING))) AS next_status_count,
    MIN(CAST(l.CREATE_DATE AS TIMESTAMP)) AS min_create_date,
    MAX(CAST(l.CREATE_DATE AS TIMESTAMP)) AS max_create_date
  FROM simo_prod.ods.resource_res_vsim_status_log l
  INNER JOIN platform_imsi i
    ON TRIM(CAST(l.IMSI AS STRING)) = i.imsi
  WHERE TRY_TO_DATE(TRIM(CAST(l.partition_date AS STRING))) >= DATE '2025-09-01'
    AND TRY_TO_DATE(TRIM(CAST(l.partition_date AS STRING))) < DATE '2025-12-01'
  GROUP BY TRIM(CAST(l.IMSI AS STRING))
)
SELECT
  (SELECT COUNT(*) FROM platform_imsi) AS platform_imsi_count,
  COUNT(*) AS status_log_imsi_count,
  COALESCE(SUM(row_count),0) AS status_log_row_count,
  MIN(min_create_date) AS min_create_date,
  MAX(max_create_date) AS max_create_date
FROM status_log_scope;