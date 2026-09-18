-- Batch A status snapshot probe for readable target partitions. Read-only only.
WITH target_products AS (
  SELECT DISTINCT TRIM(CAST(product_id AS STRING)) AS product_id
  FROM simo_prod.ods.resource_res_vsim_product
  WHERE CAST(supplier_id AS BIGINT) = 2275
)
SELECT
  CAST(s.year AS INT) AS partition_year,
  CAST(s.month AS INT) AS partition_month,
  TRIM(CAST(s.product_id AS STRING)) AS product_id,
  COUNT(*) AS row_count,
  COUNT(DISTINCT TRIM(CAST(s.imsi AS STRING))) AS imsi_count,
  MIN(TRY_TO_TIMESTAMP(TRIM(CAST(s.Cycle_Start_Time AS STRING)))) AS min_cycle_start_ts,
  MAX(TRY_TO_TIMESTAMP(TRIM(CAST(s.Cycle_End_Time AS STRING)))) AS max_cycle_end_ts,
  COUNT(DISTINCT TRIM(CAST(s.SimStatus AS STRING))) AS sim_status_count,
  COUNT(DISTINCT TRIM(CAST(s.DispatchStatus AS STRING))) AS dispatch_status_count
FROM simo_prod.tc_cdr.sim_status_for_sftp_bak s
INNER JOIN target_products p
  ON TRIM(CAST(s.product_id AS STRING)) = p.product_id
WHERE CAST(s.year AS INT) = 2025
  AND CAST(s.month AS INT) IN (10, 11)
GROUP BY CAST(s.year AS INT), CAST(s.month AS INT), TRIM(CAST(s.product_id AS STRING))
ORDER BY partition_month, product_id;