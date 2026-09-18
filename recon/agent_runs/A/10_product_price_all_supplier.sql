-- Batch A / read-only product-price evidence.
-- Keep one row per product_id and observed package_price; do not collapse prices.
SELECT
  CAST(product_id AS STRING) AS product_id,
  package_price,
  COUNT(*) AS product_rows,
  COUNT(DISTINCT product_name) AS distinct_product_name_count,
  MIN(create_time) AS min_create_time_raw,
  MAX(modify_time) AS max_modify_time_raw
FROM simo_prod.ods.resource_res_vsim_product
WHERE supplier_id = 2275
GROUP BY CAST(product_id AS STRING), package_price
ORDER BY product_id, package_price;