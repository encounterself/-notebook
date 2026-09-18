WITH cfg AS (
  SELECT '2026-03' AS billing_month, DATE '2026-03-01' AS d1, DATE '2026-03-31' AS d2
  UNION ALL SELECT '2026-04', DATE '2026-04-01', DATE '2026-04-30'
  UNION ALL SELECT '2026-05', DATE '2026-05-01', DATE '2026-05-31'
), target_cycle AS (
  SELECT c.billing_month, CAST(h.imsi AS STRING) AS imsi, CAST(h.product_id AS STRING) AS product_id,
    h.cycle_time, h.next_cycle_time, h.package_price
  FROM cfg c
  JOIN simo_prod.ods.resource_res_vsim_cycle_history h
    ON h.cycle_time < CAST(c.d2 AS TIMESTAMP) + INTERVAL 1 DAY
   AND COALESCE(h.next_cycle_time, TIMESTAMP '9999-12-31 00:00:00') >= CAST(c.d1 AS TIMESTAMP)
  WHERE NULLIF(TRIM(CAST(h.imsi AS STRING)), '') IS NOT NULL
), product_dim AS (
  SELECT CAST(product_id AS STRING) AS product_id, product_category, owner, service, status,
    product_name, package_price, monthly_rent, billing_cycle, billing_type,
    TRY_CAST(create_time AS TIMESTAMP) AS create_time_ts,
    TRY_CAST(modify_time AS TIMESTAMP) AS modify_time_ts
  FROM simo_prod.ods.resource_res_vsim_product
)
SELECT
  'PRODUCT_DIM' AS probe_type,
  CAST(NULL AS STRING) AS billing_month,
  CAST(NULL AS STRING) AS product_category,
  CAST(NULL AS STRING) AS owner,
  COUNT(*) AS row_count,
  COUNT(DISTINCT product_id) AS product_id_count,
  CAST(NULL AS BIGINT) AS imsi_count,
  CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(product_category AS STRING)))) AS categories,
  CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(owner AS STRING)))) AS owners,
  CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(billing_cycle AS STRING)))) AS billing_cycles,
  CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(billing_type AS STRING)))) AS billing_types,
  CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(package_price AS STRING)))) AS package_prices,
  CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(product_name AS STRING)))) AS product_names
FROM product_dim
UNION ALL
SELECT
  'TARGET_CYCLE_SCOPE' AS probe_type,
  t.billing_month,
  CAST(p.product_category AS STRING) AS product_category,
  CAST(p.owner AS STRING) AS owner,
  COUNT(*) AS row_count,
  COUNT(DISTINCT t.product_id) AS product_id_count,
  COUNT(DISTINCT t.imsi) AS imsi_count,
  CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(p.product_category AS STRING)))) AS categories,
  CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(p.owner AS STRING)))) AS owners,
  CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(p.billing_cycle AS STRING)))) AS billing_cycles,
  CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(p.billing_type AS STRING)))) AS billing_types,
  CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(p.package_price AS STRING)))) AS package_prices,
  CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(p.product_name AS STRING)))) AS product_names
FROM target_cycle t
LEFT JOIN product_dim p ON p.product_id = t.product_id
GROUP BY t.billing_month, CAST(p.product_category AS STRING), CAST(p.owner AS STRING)
ORDER BY probe_type, billing_month, product_category, owner