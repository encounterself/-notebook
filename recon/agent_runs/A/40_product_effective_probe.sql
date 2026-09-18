-- Batch A / read-only product price effective-field probe.
SELECT
  supplier_id,
  COUNT(*) AS product_rows,
  COUNT(DISTINCT product_id) AS distinct_product_id,
  COUNT(DISTINCT package_price) AS distinct_package_price,
  COUNT(CASE WHEN create_time IS NOT NULL THEN 1 END) AS rows_with_create_time,
  COUNT(CASE WHEN modify_time IS NOT NULL THEN 1 END) AS rows_with_modify_time,
  MIN(TRY_CAST(create_time AS TIMESTAMP)) AS min_create_time,
  MAX(TRY_CAST(create_time AS TIMESTAMP)) AS max_create_time,
  MIN(TRY_CAST(modify_time AS TIMESTAMP)) AS min_modify_time,
  MAX(TRY_CAST(modify_time AS TIMESTAMP)) AS max_modify_time
FROM simo_prod.ods.resource_res_vsim_product
WHERE supplier_id = 2275
GROUP BY supplier_id;