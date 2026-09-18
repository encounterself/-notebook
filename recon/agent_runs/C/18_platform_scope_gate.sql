-- C batch v3 hard-gate platform scope, read-only.
-- Target card set is anchored to sim_status_for_sftp_bak month partitions and supplier_id=2275.
-- cycle_history/status_log are not used to create platform-only keys.
WITH cfg AS (
  SELECT '2026-03' AS billing_month, 2026 AS y, 3 AS m, '01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx' AS source_file
  UNION ALL SELECT '2026-04', 2026, 4, '01-SIMO Data Purchase Invoice Details - APR 2026.xlsx'
  UNION ALL SELECT '2026-05', 2026, 5, '01-SIMO Data Purchase Invoice Details - MAY 2026.xlsx'
), invoice_cards AS (
  SELECT c.billing_month, CAST(x.imsi AS STRING) AS imsi
  FROM cfg c
  JOIN simo_prod.mysql_cdc_sync.wa_invoice_detail x ON x.source_file = c.source_file
  GROUP BY c.billing_month, CAST(x.imsi AS STRING)
), product_dim AS (
  SELECT DISTINCT CAST(product_id AS STRING) AS product_id, CAST(product_name AS STRING) AS product_name,
    CAST(supplier_id AS BIGINT) AS supplier_id, package_price
  FROM simo_prod.ods.resource_res_vsim_product
), target_card_product AS (
  SELECT DISTINCT c.billing_month, CAST(s.imsi AS STRING) AS imsi, CAST(s.product_id AS STRING) AS product_id
  FROM cfg c
  JOIN simo_prod.tc_cdr.sim_status_for_sftp_bak s ON s.year = c.y AND s.month = c.m
  WHERE NULLIF(TRIM(CAST(s.imsi AS STRING)), '') IS NOT NULL
), classified AS (
  SELECT t.billing_month, t.imsi, t.product_id, p.product_name, p.supplier_id, p.package_price,
    CASE WHEN p.product_id IS NULL THEN 'MISSING_PRODUCT_MAPPING'
         WHEN p.supplier_id = 2275 THEN 'WING_ALPHA_SCOPE'
         ELSE 'NON_WA_SUPPLIER_EXCLUDED' END AS scope_class
  FROM target_card_product t LEFT JOIN product_dim p ON p.product_id = t.product_id
), wa_card_product AS (
  SELECT * FROM classified WHERE scope_class = 'WING_ALPHA_SCOPE'
), wa_cards AS (
  SELECT billing_month, imsi, COUNT(*) AS scoped_product_count
  FROM wa_card_product GROUP BY billing_month, imsi
), scope_summary AS (
  SELECT billing_month, 'PLATFORM_SCOPE' AS result_kind,
    COUNT(*) AS scoped_card_product_rows, COUNT(DISTINCT imsi) AS scoped_card_count,
    COUNT(DISTINCT product_id) AS scoped_product_id_count, COUNT(DISTINCT package_price) AS scoped_price_count,
    CAST(NULL AS BIGINT) AS platform_only_card_count, CAST(NULL AS BIGINT) AS excluded_card_count,
    'Target-month sim_status_for_sftp_bak partition INNER JOIN resource_res_vsim_product on product_id and supplier_id=2275.' AS reason
  FROM wa_card_product GROUP BY billing_month
), platform_only AS (
  SELECT w.billing_month, COUNT(*) AS platform_only_card_count
  FROM wa_cards w LEFT JOIN invoice_cards i ON i.billing_month=w.billing_month AND i.imsi=w.imsi
  WHERE i.imsi IS NULL GROUP BY w.billing_month
), platform_only_summary AS (
  SELECT billing_month, 'PLATFORM_ONLY' AS result_kind,
    CAST(NULL AS BIGINT), CAST(NULL AS BIGINT), CAST(NULL AS BIGINT), CAST(NULL AS BIGINT),
    platform_only_card_count, CAST(NULL AS BIGINT),
    'Source: target-month supplier_id=2275 snapshot card absent from Excel detail imsi; cycle_history/status_log are not allowed to add this category.'
  FROM platform_only
), exclusion_summary AS (
  SELECT billing_month,
    CASE WHEN scope_class='NON_WA_SUPPLIER_EXCLUDED' THEN 'EXCLUDED_NON_WA_SUPPLIER' ELSE 'EXCLUDED_MISSING_PRODUCT_MAPPING' END AS result_kind,
    CAST(NULL AS BIGINT), CAST(NULL AS BIGINT), CAST(NULL AS BIGINT), CAST(NULL AS BIGINT), CAST(NULL AS BIGINT),
    COUNT(DISTINCT imsi),
    CASE WHEN scope_class='NON_WA_SUPPLIER_EXCLUDED' THEN 'Target-month product mapped but supplier_id<>2275; excluded before platform card aggregation, not PLATFORM_ONLY.'
         ELSE 'Target-month product_id absent from product dimension; excluded before platform card aggregation, not PLATFORM_ONLY.' END
  FROM classified
  WHERE scope_class IN ('NON_WA_SUPPLIER_EXCLUDED','MISSING_PRODUCT_MAPPING')
  GROUP BY billing_month, scope_class
)
SELECT * FROM scope_summary
UNION ALL SELECT * FROM platform_only_summary
UNION ALL SELECT * FROM exclusion_summary
ORDER BY billing_month, result_kind