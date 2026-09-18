SELECT CAST(product_id AS STRING) AS platform_product_id, CAST(supplier_id AS BIGINT) AS supplier_id,
  product_name, monthly_rent, monthly_rent_withusd, package_price, package_price_withusd,
  price_include_tax, price_include_tax_withusd, billing_cycle, status, COUNT(*) AS product_row_count,
  MIN(TRY_CAST(create_time AS TIMESTAMP)) AS min_create_time, MAX(TRY_CAST(modify_time AS TIMESTAMP)) AS max_modify_time
FROM simo_prod.ods.resource_res_vsim_product
WHERE supplier_id=2275
GROUP BY CAST(product_id AS STRING), CAST(supplier_id AS BIGINT), product_name, monthly_rent,
  monthly_rent_withusd, package_price, package_price_withusd, price_include_tax, price_include_tax_withusd,
  billing_cycle, status
ORDER BY platform_product_id, product_name, monthly_rent, package_price;