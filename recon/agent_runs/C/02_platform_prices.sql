WITH wa_cards AS (
  SELECT DISTINCT CAST(imsi AS STRING) AS imsi
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE source_file IN (
    '01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx',
    '01-SIMO Data Purchase Invoice Details - APR 2026.xlsx',
    '01-SIMO Data Purchase Invoice Details - MAY 2026.xlsx'
  )
  UNION
  SELECT DISTINCT CAST(imsi AS STRING)
  FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
  WHERE source_file IN (
    '01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx',
    '01-SIMO Data Purchase Invoice Details - APR 2026.xlsx',
    '01-SIMO Data Purchase Invoice Details - MAY 2026.xlsx'
  )
),
cycle_prices AS (
  SELECT
    'cycle_history.package_price' AS evidence_field,
    CAST(h.package_price AS DOUBLE) AS price_value
  FROM simo_prod.ods.resource_res_vsim_cycle_history h
  JOIN wa_cards w ON w.imsi = CAST(h.imsi AS STRING)
  WHERE h.cycle_time >= TIMESTAMP '2026-02-01 00:00:00'
    AND h.cycle_time < TIMESTAMP '2026-07-01 00:00:00'
    AND h.package_price IS NOT NULL
),
product_prices AS (
  SELECT
    'product.monthly_rent' AS evidence_field,
    p.monthly_rent AS price_value
  FROM simo_prod.ods.resource_res_vsim_cycle_history h
  JOIN wa_cards w ON w.imsi = CAST(h.imsi AS STRING)
  JOIN simo_prod.ods.resource_res_vsim_product p
    ON CAST(p.product_id AS STRING) = CAST(h.product_id AS STRING)
  WHERE h.cycle_time >= TIMESTAMP '2026-02-01 00:00:00'
    AND h.cycle_time < TIMESTAMP '2026-07-01 00:00:00'
    AND p.monthly_rent IS NOT NULL
  UNION ALL
  SELECT
    'product.monthly_rent_withusd',
    p.monthly_rent_withusd
  FROM simo_prod.ods.resource_res_vsim_cycle_history h
  JOIN wa_cards w ON w.imsi = CAST(h.imsi AS STRING)
  JOIN simo_prod.ods.resource_res_vsim_product p
    ON CAST(p.product_id AS STRING) = CAST(h.product_id AS STRING)
  WHERE h.cycle_time >= TIMESTAMP '2026-02-01 00:00:00'
    AND h.cycle_time < TIMESTAMP '2026-07-01 00:00:00'
    AND p.monthly_rent_withusd IS NOT NULL
  UNION ALL
  SELECT
    'product.package_price',
    p.package_price
  FROM simo_prod.ods.resource_res_vsim_cycle_history h
  JOIN wa_cards w ON w.imsi = CAST(h.imsi AS STRING)
  JOIN simo_prod.ods.resource_res_vsim_product p
    ON CAST(p.product_id AS STRING) = CAST(h.product_id AS STRING)
  WHERE h.cycle_time >= TIMESTAMP '2026-02-01 00:00:00'
    AND h.cycle_time < TIMESTAMP '2026-07-01 00:00:00'
    AND p.package_price IS NOT NULL
  UNION ALL
  SELECT
    'product.package_price_withusd',
    p.package_price_withusd
  FROM simo_prod.ods.resource_res_vsim_cycle_history h
  JOIN wa_cards w ON w.imsi = CAST(h.imsi AS STRING)
  JOIN simo_prod.ods.resource_res_vsim_product p
    ON CAST(p.product_id AS STRING) = CAST(h.product_id AS STRING)
  WHERE h.cycle_time >= TIMESTAMP '2026-02-01 00:00:00'
    AND h.cycle_time < TIMESTAMP '2026-07-01 00:00:00'
    AND p.package_price_withusd IS NOT NULL
)
SELECT
  evidence_field,
  COUNT(*) AS evidence_rows,
  COUNT(DISTINCT price_value) AS price_count,
  CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(CAST(ROUND(price_value, 6) AS STRING)))) AS prices_seen
FROM (
  SELECT * FROM cycle_prices
  UNION ALL
  SELECT * FROM product_prices
) p
GROUP BY evidence_field
ORDER BY evidence_field;