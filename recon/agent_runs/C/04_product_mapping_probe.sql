WITH cfg AS (
  SELECT '2026-03' AS billing_month, '01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx' AS source_file
  UNION ALL SELECT '2026-04', '01-SIMO Data Purchase Invoice Details - APR 2026.xlsx'
  UNION ALL SELECT '2026-05', '01-SIMO Data Purchase Invoice Details - MAY 2026.xlsx'
),
excel_products AS (
  SELECT
    c.billing_month,
    CAST(x.product_name AS STRING) AS product_name,
    COUNT(*) AS row_count,
    COUNT(DISTINCT CAST(x.imsi AS STRING)) AS imsi_count,
    COUNT(DISTINCT TRY_CAST(x.monthly_rate AS DOUBLE)) AS rate_count,
    CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(TRY_CAST(x.monthly_rate AS DOUBLE) AS STRING)))) AS rates_seen
  FROM cfg c
  JOIN simo_prod.mysql_cdc_sync.wa_invoice_detail x ON x.source_file = c.source_file
  GROUP BY c.billing_month, CAST(x.product_name AS STRING)
),
wa_cards AS (
  SELECT DISTINCT c.billing_month, CAST(x.imsi AS STRING) AS imsi
  FROM cfg c
  JOIN simo_prod.mysql_cdc_sync.wa_invoice_detail x ON x.source_file = c.source_file
),
platform_products AS (
  SELECT DISTINCT
    w.billing_month,
    CAST(h.imsi AS STRING) AS imsi,
    CAST(h.product_id AS STRING) AS product_id,
    CAST(p.product_name AS STRING) AS platform_product_name,
    ROUND(p.package_price, 6) AS package_price,
    ROUND(p.monthly_rent, 6) AS monthly_rent,
    CAST(p.product_category AS STRING) AS product_category,
    CAST(p.billing_type AS STRING) AS billing_type,
    CAST(p.carrier_id AS STRING) AS carrier_id,
    CAST(cr.CARRIER_NAME AS STRING) AS carrier_name,
    CAST(cr.simple_carrier_name AS STRING) AS simple_carrier_name
  FROM wa_cards w
  JOIN simo_prod.ods.resource_res_vsim_cycle_history h
    ON CAST(h.imsi AS STRING) = w.imsi
  LEFT JOIN simo_prod.ods.resource_res_vsim_product p
    ON CAST(p.product_id AS STRING) = CAST(h.product_id AS STRING)
  LEFT JOIN simo_prod.ods.resource_res_carrier cr
    ON CAST(cr.ID AS STRING) = CAST(p.carrier_id AS STRING)
  WHERE h.cycle_time >= TIMESTAMP '2026-02-01 00:00:00'
    AND h.cycle_time < TIMESTAMP '2026-07-01 00:00:00'
)
SELECT
  'EXCEL_PRODUCT' AS evidence_side,
  billing_month,
  product_name AS name_or_product,
  CAST(NULL AS STRING) AS product_id,
  CAST(NULL AS STRING) AS carrier_name,
  CAST(NULL AS STRING) AS simple_carrier_name,
  rate_count AS price_or_row_count,
  rates_seen AS price_values
FROM excel_products
UNION ALL
SELECT
  'PLATFORM_PRODUCT',
  billing_month,
  platform_product_name,
  product_id,
  carrier_name,
  simple_carrier_name,
  COUNT(DISTINCT imsi) AS price_or_row_count,
  CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(COALESCE(CAST(package_price AS STRING), '<NULL>') || '@monthly=' || COALESCE(CAST(monthly_rent AS STRING), '<NULL>')))) AS price_values
FROM platform_products
GROUP BY billing_month, platform_product_name, product_id, carrier_name, simple_carrier_name
ORDER BY evidence_side, billing_month, name_or_product, product_id;