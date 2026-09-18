-- Batch A / read-only early platform scope, Wing Alpha supplier gate, and exclusion reasons.
-- September is explicitly represented as unavailable because its raw snapshot partitions are unreadable;
-- it is not scanned here and is not converted into fabricated PLATFORM_ONLY rows.
WITH cfg AS (
  SELECT '2025-09' AS billing_month, 2025 AS y, 9 AS m, FALSE AS readable_snapshot
  UNION ALL SELECT '2025-10', 2025, 10, TRUE
  UNION ALL SELECT '2025-11', 2025, 11, TRUE
), scope_cfg AS (
  SELECT * FROM cfg WHERE readable_snapshot
), invoice_cards AS (
  SELECT
    c.billing_month,
    x.imsi,
    COUNT(*) AS excel_line_count,
    ROUND(SUM(TRY_CAST(x.final_charge AS DOUBLE)), 4) AS excel_amount
  FROM cfg c
  JOIN simo_prod.mysql_cdc_sync.wa_invoice_detail x
    ON TRY_CAST(x.final_start_date AS DATE)
       BETWEEN DATE(CONCAT(c.billing_month, '-01'))
           AND LAST_DAY(DATE(CONCAT(c.billing_month, '-01')))
  GROUP BY c.billing_month, x.imsi
), product_dim AS (
  SELECT DISTINCT
    CAST(product_id AS STRING) AS product_id,
    product_name,
    supplier_id,
    package_price,
    create_time,
    modify_time
  FROM simo_prod.ods.resource_res_vsim_product
), target_snapshot AS (
  SELECT DISTINCT
    c.billing_month,
    s.imsi,
    CAST(s.product_id AS STRING) AS product_id,
    CAST(s.partition_time AS DATE) AS presence_d
  FROM scope_cfg c
  JOIN simo_prod.tc_cdr.sim_status_for_sftp_bak s
    ON s.year = c.y AND s.month = c.m
), classified_card_product AS (
  SELECT
    t.billing_month, t.imsi, t.product_id, t.presence_d,
    p.product_name, p.supplier_id, p.package_price,
    CASE
      WHEN p.product_id IS NULL THEN 'MISSING_PRODUCT_MAPPING'
      WHEN p.supplier_id = 2275 THEN 'WING_ALPHA_SCOPE'
      ELSE 'NON_WA_SUPPLIER_EXCLUDED'
    END AS scope_class
  FROM target_snapshot t
  LEFT JOIN product_dim p ON p.product_id = t.product_id
), wa_snapshot AS (
  SELECT * FROM classified_card_product WHERE scope_class = 'WING_ALPHA_SCOPE'
), wa_scope_summary AS (
  SELECT
    billing_month,
    'PLATFORM_SCOPE' AS result_kind,
    COUNT(*) AS scoped_snapshot_rows,
    COUNT(DISTINCT imsi) AS scoped_card_count,
    COUNT(DISTINCT product_id) AS scoped_product_id_count,
    COUNT(DISTINCT package_price) AS scoped_price_count,
    CAST(NULL AS BIGINT) AS excluded_card_count,
    CAST(NULL AS BIGINT) AS platform_only_card_count,
    'Early scope: target month partition INNER JOIN product_id with supplier_id=2275.' AS source_or_exclusion_reason
  FROM wa_snapshot
  GROUP BY billing_month
), exclusion_summary AS (
  SELECT
    billing_month,
    CASE WHEN scope_class = 'NON_WA_SUPPLIER_EXCLUDED'
         THEN 'EXCLUDED_NON_WA_SUPPLIER'
         ELSE 'EXCLUDED_MISSING_PRODUCT_MAPPING' END AS result_kind,
    CAST(NULL AS BIGINT) AS scoped_snapshot_rows,
    CAST(NULL AS BIGINT) AS scoped_card_count,
    CAST(NULL AS BIGINT) AS scoped_product_id_count,
    CAST(NULL AS BIGINT) AS scoped_price_count,
    COUNT(DISTINCT imsi) AS excluded_card_count,
    CAST(NULL AS BIGINT) AS platform_only_card_count,
    CASE WHEN scope_class = 'NON_WA_SUPPLIER_EXCLUDED'
         THEN 'Target-month snapshot card/product was excluded because mapped supplier_id <> 2275; not PLATFORM_ONLY.'
         ELSE 'Target-month snapshot card/product was excluded because product_id has no current product mapping; not PLATFORM_ONLY.' END AS source_or_exclusion_reason
  FROM classified_card_product
  WHERE scope_class IN ('NON_WA_SUPPLIER_EXCLUDED', 'MISSING_PRODUCT_MAPPING')
  GROUP BY billing_month, scope_class
), wa_cards AS (
  SELECT billing_month, imsi, COUNT(*) AS wa_snapshot_rows
  FROM wa_snapshot
  GROUP BY billing_month, imsi
), platform_only_summary AS (
  SELECT
    w.billing_month,
    'PLATFORM_ONLY' AS result_kind,
    CAST(NULL AS BIGINT) AS scoped_snapshot_rows,
    CAST(NULL AS BIGINT) AS scoped_card_count,
    CAST(NULL AS BIGINT) AS scoped_product_id_count,
    CAST(NULL AS BIGINT) AS scoped_price_count,
    CAST(NULL AS BIGINT) AS excluded_card_count,
    COUNT(*) AS platform_only_card_count,
    'WA supplier_id=2275 card in target-month partition with no matching Excel detail imsi; source is scoped sim_status_for_sftp_bak, not a union of full snapshots/logs/history.' AS source_or_exclusion_reason
  FROM wa_cards w
  LEFT JOIN invoice_cards i
    ON i.billing_month = w.billing_month AND i.imsi = w.imsi
  WHERE i.imsi IS NULL
  GROUP BY w.billing_month
), missing_snapshot AS (
  SELECT
    billing_month,
    'PLATFORM_SCOPE_UNAVAILABLE' AS result_kind,
    CAST(NULL AS BIGINT) AS scoped_snapshot_rows,
    CAST(NULL AS BIGINT) AS scoped_card_count,
    CAST(NULL AS BIGINT) AS scoped_product_id_count,
    CAST(NULL AS BIGINT) AS scoped_price_count,
    CAST(NULL AS BIGINT) AS excluded_card_count,
    CAST(NULL AS BIGINT) AS platform_only_card_count,
    'MISSING_DATA: September raw snapshot partitions returned AccessDeniedException; no PLATFORM_ONLY classification is materialized.' AS source_or_exclusion_reason
  FROM cfg
  WHERE NOT readable_snapshot
)
SELECT * FROM wa_scope_summary
UNION ALL SELECT * FROM exclusion_summary
UNION ALL SELECT * FROM platform_only_summary
UNION ALL SELECT * FROM missing_snapshot
ORDER BY billing_month, result_kind