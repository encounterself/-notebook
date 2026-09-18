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
  TRIM(CAST(product_name_in_supplier AS STRING)) AS product_name_in_supplier,
  CAST(create_time AS STRING) AS product_create_time,
  CAST(modify_time AS STRING) AS product_modify_time
FROM simo_prod.ods.resource_res_vsim_product
WHERE CAST(supplier_id AS BIGINT) = 2275
ORDER BY product_id;