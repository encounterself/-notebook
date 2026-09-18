-- Batch A / read-only product-price evidence probe.
-- Keep one row per product_id and observed package_price; do not collapse prices.
WITH used_products AS (
  SELECT DISTINCT product_id
  FROM simo_prod.tc_cdr.sim_status_for_sftp_bak
  WHERE year = 2025 AND month IN (9, 10, 11)
)
SELECT
  CAST(p.product_id AS STRING) AS product_id,
  p.package_price,
  COUNT(*) AS product_rows,
  COUNT(DISTINCT p.product_name) AS distinct_product_name_count,
  MIN(p.create_time) AS min_create_time_raw,
  MAX(p.modify_time) AS max_modify_time_raw
FROM simo_prod.ods.resource_res_vsim_product p
JOIN used_products u ON u.product_id = p.product_id
WHERE p.supplier_id = 2275
GROUP BY CAST(p.product_id AS STRING), p.package_price
ORDER BY product_id, package_price;