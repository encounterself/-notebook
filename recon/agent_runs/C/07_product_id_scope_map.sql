SELECT
  CAST(product_id AS STRING) AS platform_product_id,
  CAST(product_category AS STRING) AS product_category,
  CAST(owner AS STRING) AS owner,
  CAST(product_name AS STRING) AS platform_product_name,
  package_price AS platform_package_price,
  monthly_rent AS platform_monthly_rent,
  billing_cycle,
  billing_type,
  create_time,
  modify_time
FROM simo_prod.ods.resource_res_vsim_product
WHERE LOWER(CAST(product_name AS STRING)) LIKE '%(wa)%'
   OR LOWER(CAST(product_name AS STRING)) LIKE '%(pi)%'
ORDER BY platform_product_id