-- Batch A / read-only platform scope summary for 2025-10 and 2025-11.
WITH snap_products AS (
  SELECT DISTINCT
    CONCAT(CAST(year AS STRING), '-', LPAD(CAST(month AS STRING), 2, '0')) AS billing_month,
    imsi,
    product_id
  FROM simo_prod.tc_cdr.sim_status_for_sftp_bak
  WHERE year = 2025 AND month IN (10, 11)
), product_map AS (
  SELECT DISTINCT CAST(product_id AS STRING) AS product_id, supplier_id, package_price
  FROM simo_prod.ods.resource_res_vsim_product
), card_map AS (
  SELECT
    s.billing_month,
    s.imsi,
    COUNT(DISTINCT s.product_id) AS distinct_product_id_count,
    COUNT(DISTINCT CASE WHEN p.supplier_id = 2275 THEN s.product_id END) AS wa_product_id_count,
    COUNT(DISTINCT CASE WHEN p.product_id IS NULL THEN s.product_id END) AS missing_product_id_count,
    COUNT(DISTINCT CASE WHEN p.supplier_id = 2275 THEN p.package_price END) AS distinct_wa_package_price_count
  FROM snap_products s
  LEFT JOIN product_map p ON p.product_id = s.product_id
  GROUP BY s.billing_month, s.imsi
)
SELECT
  billing_month,
  CASE
    WHEN wa_product_id_count > 0 AND missing_product_id_count = 0 THEN 'WA_PRODUCT_MATCH'
    WHEN missing_product_id_count > 0 THEN 'MISSING_MAPPING'
    ELSE 'NON_WA_OR_UNMAPPED'
  END AS platform_scope_status,
  COUNT(*) AS platform_cards,
  SUM(CASE WHEN distinct_wa_package_price_count = 1 THEN 1 ELSE 0 END) AS cards_with_unique_wa_price,
  SUM(CASE WHEN distinct_wa_package_price_count > 1 THEN 1 ELSE 0 END) AS cards_with_multiple_wa_prices,
  SUM(CASE WHEN missing_product_id_count > 0 THEN 1 ELSE 0 END) AS cards_with_missing_product_mapping
FROM card_map
GROUP BY billing_month,
  CASE
    WHEN wa_product_id_count > 0 AND missing_product_id_count = 0 THEN 'WA_PRODUCT_MATCH'
    WHEN missing_product_id_count > 0 THEN 'MISSING_MAPPING'
    ELSE 'NON_WA_OR_UNMAPPED'
  END
ORDER BY billing_month, platform_scope_status;