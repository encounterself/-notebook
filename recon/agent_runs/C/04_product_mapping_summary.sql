WITH cfg AS (
  SELECT '2026-03' AS billing_month, '01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx' AS source_file, DATE '2026-03-01' AS d1, DATE '2026-03-31' AS d2
  UNION ALL SELECT '2026-04', '01-SIMO Data Purchase Invoice Details - APR 2026.xlsx', DATE '2026-04-01', DATE '2026-04-30'
  UNION ALL SELECT '2026-05', '01-SIMO Data Purchase Invoice Details - MAY 2026.xlsx', DATE '2026-05-01', DATE '2026-05-31'
),
wa_products AS (
  SELECT DISTINCT
    c.billing_month,
    CAST(x.imsi AS STRING) AS imsi,
    LOWER(TRIM(CAST(x.product_name AS STRING))) AS excel_product_name
  FROM cfg c
  JOIN simo_prod.mysql_cdc_sync.wa_invoice_detail x ON x.source_file = c.source_file
),
platform_product_rows AS (
  SELECT
    w.billing_month,
    w.imsi,
    LOWER(TRIM(CAST(p.product_name AS STRING))) AS platform_product_name,
    CASE WHEN LOWER(CAST(p.product_name AS STRING)) RLIKE '\\(wa\\)' THEN 1 ELSE 0 END AS is_wa_named,
    CASE WHEN LOWER(CAST(p.product_name AS STRING)) RLIKE '\\(pi\\)' THEN 1 ELSE 0 END AS is_pi_named,
    CASE WHEN LOWER(TRIM(CAST(p.product_name AS STRING))) = w.excel_product_name THEN 1 ELSE 0 END AS exact_name_match
  FROM wa_products w
  JOIN simo_prod.ods.resource_res_vsim_cycle_history h
    ON CAST(h.imsi AS STRING) = w.imsi
  LEFT JOIN simo_prod.ods.resource_res_vsim_product p
    ON CAST(p.product_id AS STRING) = CAST(h.product_id AS STRING)
  WHERE h.cycle_time >= TIMESTAMP '2026-02-01 00:00:00'
    AND h.cycle_time < TIMESTAMP '2026-07-01 00:00:00'
),
card_flags AS (
  SELECT
    billing_month,
    imsi,
    MAX(is_wa_named) AS has_wa_named_product,
    MAX(is_pi_named) AS has_pi_named_product,
    MAX(exact_name_match) AS has_exact_name_match,
    COUNT(DISTINCT platform_product_name) AS platform_product_name_count
  FROM platform_product_rows
  GROUP BY billing_month, imsi
)
SELECT
  billing_month,
  COUNT(*) AS wa_cards_with_cycle_product_rows,
  SUM(CASE WHEN has_wa_named_product = 1 THEN 1 ELSE 0 END) AS cards_with_wa_named_product,
  SUM(CASE WHEN has_pi_named_product = 1 THEN 1 ELSE 0 END) AS cards_with_pi_named_product,
  SUM(CASE WHEN has_exact_name_match = 1 THEN 1 ELSE 0 END) AS cards_with_exact_excel_product_name,
  SUM(CASE WHEN has_wa_named_product = 0 AND has_pi_named_product = 0 THEN 1 ELSE 0 END) AS cards_with_unclassified_product_name,
  SUM(CASE WHEN platform_product_name_count > 1 THEN 1 ELSE 0 END) AS cards_with_multiple_platform_product_names
FROM card_flags
GROUP BY billing_month
ORDER BY billing_month;