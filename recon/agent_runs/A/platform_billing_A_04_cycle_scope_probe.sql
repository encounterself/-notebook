-- Batch A cycle scope probe. Read-only only.
WITH target_products AS (
  SELECT DISTINCT TRIM(CAST(product_id AS STRING)) AS product_id
  FROM simo_prod.ods.resource_res_vsim_product
  WHERE CAST(supplier_id AS BIGINT) = 2275
),
cycle_scope AS (
  SELECT
    TRIM(CAST(h.imsi AS STRING)) AS imsi,
    TRIM(CAST(h.product_id AS STRING)) AS product_id,
    CAST(h.cycle_time AS TIMESTAMP) AS cycle_start_ts,
    CAST(h.next_cycle_time AS TIMESTAMP) AS cycle_end_ts,
    CAST(h.package_price AS DECIMAL(38,12)) AS cycle_package_price,
    TRIM(CAST(h.time_zone AS STRING)) AS cycle_time_zone,
    CAST(h.create_time AS TIMESTAMP) AS create_ts
  FROM simo_prod.ods.resource_res_vsim_cycle_history h
  INNER JOIN target_products p
    ON TRIM(CAST(h.product_id AS STRING)) = p.product_id
  WHERE CAST(h.cycle_time AS TIMESTAMP) < TIMESTAMP '2025-12-01 00:00:00'
    AND CAST(h.next_cycle_time AS TIMESTAMP) > TIMESTAMP '2025-09-01 00:00:00'
),
cycle_stats AS (
  SELECT
    'CYCLE_PRODUCT_MONTH' AS result_type,
    DATE_FORMAT(cycle_start_ts, 'yyyy-MM') AS observed_cycle_month,
    product_id,
    COUNT(*) AS row_count,
    COUNT(DISTINCT imsi) AS imsi_count,
    MIN(cycle_start_ts) AS min_cycle_start_ts,
    MAX(cycle_end_ts) AS max_cycle_end_ts,
    MIN(cycle_package_price) AS min_cycle_package_price,
    MAX(cycle_package_price) AS max_cycle_package_price,
    COUNT(DISTINCT cycle_package_price) AS distinct_cycle_package_price_count,
    COUNT(DISTINCT cycle_time_zone) AS distinct_time_zone_count,
    CAST(NULL AS STRING) AS imsi,
    CAST(NULL AS TIMESTAMP) AS cycle_start_ts,
    CAST(NULL AS TIMESTAMP) AS cycle_end_ts,
    CAST(NULL AS DECIMAL(38,12)) AS cycle_package_price
  FROM cycle_scope
  GROUP BY DATE_FORMAT(cycle_start_ts, 'yyyy-MM'), product_id
),
cycle_samples AS (
  SELECT
    'CYCLE_SAMPLE' AS result_type,
    DATE_FORMAT(cycle_start_ts, 'yyyy-MM') AS observed_cycle_month,
    product_id,
    CAST(NULL AS BIGINT) AS row_count,
    CAST(NULL AS BIGINT) AS imsi_count,
    CAST(NULL AS TIMESTAMP) AS min_cycle_start_ts,
    CAST(NULL AS TIMESTAMP) AS max_cycle_end_ts,
    CAST(NULL AS DECIMAL(38,12)) AS min_cycle_package_price,
    CAST(NULL AS DECIMAL(38,12)) AS max_cycle_package_price,
    CAST(NULL AS BIGINT) AS distinct_cycle_package_price_count,
    CAST(NULL AS BIGINT) AS distinct_time_zone_count,
    imsi,
    cycle_start_ts,
    cycle_end_ts,
    cycle_package_price
  FROM cycle_scope
  ORDER BY cycle_start_ts, product_id, imsi
  LIMIT 200
)
SELECT * FROM cycle_stats
UNION ALL
SELECT * FROM cycle_samples
ORDER BY result_type, observed_cycle_month, product_id, imsi;