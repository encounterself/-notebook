-- Batch A platform scope probe. Read-only only.
WITH target_products AS (
  SELECT
    TRIM(CAST(product_id AS STRING)) AS product_id,
    TRIM(CAST(product_name AS STRING)) AS product_name,
    CAST(supplier_id AS BIGINT) AS supplier_id,
    CAST(package_price AS DECIMAL(38,12)) AS package_price,
    CAST(package_price_withusd AS DECIMAL(38,12)) AS package_price_withusd,
    CAST(monthly_rent AS DECIMAL(38,12)) AS monthly_rent,
    CAST(monthly_rent_withusd AS DECIMAL(38,12)) AS monthly_rent_withusd,
    TRIM(CAST(time_zone AS STRING)) AS product_time_zone,
    TRIM(CAST(billing_cycle AS STRING)) AS billing_cycle,
    CAST(status AS INT) AS product_status,
    TRIM(CAST(product_name_in_supplier AS STRING)) AS product_name_in_supplier
  FROM simo_prod.ods.resource_res_vsim_product
  WHERE CAST(supplier_id AS BIGINT) = 2275
),
status_scope AS (
  SELECT
    CAST(s.year AS INT) AS partition_year,
    CAST(s.month AS INT) AS partition_month,
    TRIM(CAST(s.imsi AS STRING)) AS imsi,
    TRIM(CAST(s.product_id AS STRING)) AS product_id,
    TRIM(CAST(s.ICCID AS STRING)) AS iccid,
    TRIM(CAST(s.Cycle_Start_Time AS STRING)) AS cycle_start_raw,
    TRIM(CAST(s.Cycle_End_Time AS STRING)) AS cycle_end_raw,
    TRIM(CAST(s.DispatchStatus AS STRING)) AS dispatch_status,
    TRIM(CAST(s.SimStatus AS STRING)) AS sim_status,
    TRIM(CAST(s.partition_time AS STRING)) AS partition_time
  FROM simo_prod.tc_cdr.sim_status_for_sftp_bak s
  INNER JOIN target_products p
    ON TRIM(CAST(s.product_id AS STRING)) = p.product_id
  WHERE CAST(s.year AS INT) = 2025
    AND CAST(s.month AS INT) IN (9, 10, 11)
),
status_stats AS (
  SELECT
    'STATUS_PARTITION_PRODUCT' AS result_type,
    CAST(partition_year AS STRING) AS partition_year,
    CAST(partition_month AS STRING) AS partition_month,
    product_id,
    CAST(NULL AS STRING) AS product_name,
    COUNT(*) AS row_count,
    COUNT(DISTINCT imsi) AS imsi_count,
    COUNT(DISTINCT cycle_start_raw) AS cycle_start_count,
    COUNT(DISTINCT cycle_end_raw) AS cycle_end_count,
    COUNT(DISTINCT sim_status) AS sim_status_count,
    COUNT(DISTINCT dispatch_status) AS dispatch_status_count,
    MIN(partition_time) AS min_partition_time,
    MAX(partition_time) AS max_partition_time
  FROM status_scope
  GROUP BY partition_year, partition_month, product_id
),
product_rows AS (
  SELECT
    'TARGET_PRODUCT' AS result_type,
    CAST(NULL AS STRING) AS partition_year,
    CAST(NULL AS STRING) AS partition_month,
    product_id,
    product_name,
    1L AS row_count,
    CAST(NULL AS BIGINT) AS imsi_count,
    CAST(NULL AS BIGINT) AS cycle_start_count,
    CAST(NULL AS BIGINT) AS cycle_end_count,
    CAST(NULL AS BIGINT) AS sim_status_count,
    CAST(NULL AS BIGINT) AS dispatch_status_count,
    CAST(NULL AS STRING) AS min_partition_time,
    CAST(NULL AS STRING) AS max_partition_time
  FROM target_products
)
SELECT * FROM product_rows
UNION ALL
SELECT * FROM status_stats
ORDER BY result_type, partition_year, partition_month, product_id;