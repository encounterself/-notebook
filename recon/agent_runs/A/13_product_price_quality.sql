-- Batch A / read-only product-price quality checks.
-- Report every product_id with more than one observed package_price.
SELECT
  CAST(product_id AS STRING) AS product_id,
  COUNT(DISTINCT package_price) AS distinct_package_price_count,
  SORT_ARRAY(COLLECT_SET(package_price)) AS observed_package_prices,
  COUNT(*) AS product_rows,
  COUNT(DISTINCT product_name) AS distinct_product_name_count
FROM simo_prod.ods.resource_res_vsim_product
WHERE supplier_id = 2275
GROUP BY CAST(product_id AS STRING)
HAVING COUNT(DISTINCT package_price) > 1
ORDER BY product_id;