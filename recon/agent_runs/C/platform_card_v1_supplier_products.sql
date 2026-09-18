SELECT
  p.supplier_id,
  p.product_id,
  p.product_name,
  p.product_name_in_supplier,
  p.carrier_id,
  c.CARRIER_NAME,
  p.billing_cycle,
  p.time_zone,
  p.monthly_rent,
  p.monthly_rent_withusd,
  p.package_price,
  p.package_price_withusd,
  p.billing_type,
  p.status,
  p.create_time,
  p.modify_time
FROM simo_prod.ods.resource_res_vsim_product p
LEFT JOIN simo_prod.ods.resource_res_carrier c
  ON p.carrier_id = c.ID
WHERE p.supplier_id = 2275
ORDER BY p.product_id