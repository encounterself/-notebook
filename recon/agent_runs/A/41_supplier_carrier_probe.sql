-- Batch A / read-only Wing Alpha supplier and carrier mapping probe.
SELECT
  p.supplier_id,
  p.carrier_id,
  c.CARRIER_NAME AS carrier_name,
  c.simple_carrier_name,
  COUNT(DISTINCT p.product_id) AS product_count,
  COUNT(DISTINCT p.package_price) AS package_price_count
FROM simo_prod.ods.resource_res_vsim_product p
LEFT JOIN simo_prod.ods.resource_res_carrier c
  ON c.ID = p.carrier_id
WHERE p.supplier_id = 2275
GROUP BY p.supplier_id, p.carrier_id, c.CARRIER_NAME, c.simple_carrier_name
ORDER BY p.carrier_id;