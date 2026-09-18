WITH cfg AS (
  SELECT '2026-03' AS billing_month, DATE '2026-03-01' AS d1, DATE '2026-03-31' AS d2
  UNION ALL SELECT '2026-04', DATE '2026-04-01', DATE '2026-04-30'
  UNION ALL SELECT '2026-05', DATE '2026-05-01', DATE '2026-05-31'
),
cycle_products AS (
  SELECT
    c.billing_month,
    CAST(h.imsi AS STRING) AS imsi,
    MAX(CASE WHEN LOWER(CAST(p.product_name AS STRING)) RLIKE '\\(wa\\)' THEN 1 ELSE 0 END) AS has_wa_named,
    MAX(CASE WHEN LOWER(CAST(p.product_name AS STRING)) RLIKE '\\(pi\\)' THEN 1 ELSE 0 END) AS has_pi_named,
    COUNT(DISTINCT CAST(p.product_name AS STRING)) AS product_name_count
  FROM cfg c
  JOIN simo_prod.ods.resource_res_vsim_cycle_history h
    ON h.cycle_time < CAST(c.d2 AS TIMESTAMP) + INTERVAL 1 DAY
   AND COALESCE(h.next_cycle_time, TIMESTAMP '9999-12-31 00:00:00') >= CAST(c.d1 AS TIMESTAMP)
  LEFT JOIN simo_prod.ods.resource_res_vsim_product p
    ON CAST(p.product_id AS STRING) = CAST(h.product_id AS STRING)
  WHERE NULLIF(TRIM(CAST(h.imsi AS STRING)), '') IS NOT NULL
  GROUP BY c.billing_month, CAST(h.imsi AS STRING)
)
SELECT
  billing_month,
  COUNT(*) AS platform_cycle_cards,
  SUM(CASE WHEN has_wa_named = 1 THEN 1 ELSE 0 END) AS platform_cards_with_wa_named,
  SUM(CASE WHEN has_pi_named = 1 THEN 1 ELSE 0 END) AS platform_cards_with_pi_named,
  SUM(CASE WHEN has_wa_named = 0 AND has_pi_named = 0 THEN 1 ELSE 0 END) AS platform_cards_unclassified,
  SUM(CASE WHEN product_name_count > 1 THEN 1 ELSE 0 END) AS platform_cards_multiple_product_names
FROM cycle_products
GROUP BY billing_month
ORDER BY billing_month;