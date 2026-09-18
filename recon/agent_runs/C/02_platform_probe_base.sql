WITH wa_cards AS (
  SELECT DISTINCT CAST(imsi AS STRING) AS imsi
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE source_file IN (
    '01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx',
    '01-SIMO Data Purchase Invoice Details - APR 2026.xlsx',
    '01-SIMO Data Purchase Invoice Details - MAY 2026.xlsx'
  )
  AND NULLIF(TRIM(imsi), '') IS NOT NULL
  UNION
  SELECT DISTINCT CAST(imsi AS STRING) AS imsi
  FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
  WHERE source_file IN (
    '01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx',
    '01-SIMO Data Purchase Invoice Details - APR 2026.xlsx',
    '01-SIMO Data Purchase Invoice Details - MAY 2026.xlsx'
  )
  AND NULLIF(TRIM(imsi), '') IS NOT NULL
),
cycle_rows AS (
  SELECT h.*
  FROM simo_prod.ods.resource_res_vsim_cycle_history h
  JOIN wa_cards w ON w.imsi = CAST(h.imsi AS STRING)
  WHERE h.cycle_time >= TIMESTAMP '2026-02-01 00:00:00'
    AND h.cycle_time < TIMESTAMP '2026-07-01 00:00:00'
),
product_rows AS (
  SELECT DISTINCT
    c.imsi,
    CAST(h.product_id AS STRING) AS product_id,
    p.product_name,
    CAST(p.carrier_id AS STRING) AS carrier_id,
    p.monthly_rent,
    p.monthly_rent_withusd,
    p.package_price,
    p.package_price_withusd,
    p.billing_type,
    p.product_category
  FROM cycle_rows h
  JOIN wa_cards c ON c.imsi = CAST(h.imsi AS STRING)
  LEFT JOIN simo_prod.ods.resource_res_vsim_product p
    ON CAST(p.product_id AS STRING) = CAST(h.product_id AS STRING)
),
carrier_rows AS (
  SELECT DISTINCT
    pr.imsi,
    pr.product_id,
    pr.product_name,
    pr.carrier_id,
    cr.CARRIER_NAME AS carrier_name,
    cr.simple_carrier_name
  FROM product_rows pr
  LEFT JOIN simo_prod.ods.resource_res_carrier cr
    ON CAST(cr.ID AS STRING) = pr.carrier_id
)
SELECT
  'wa_card_keys' AS source_table,
  COUNT(*) AS row_count,
  COUNT(DISTINCT imsi) AS distinct_key_count,
  COUNT(DISTINCT imsi) AS matched_wa_count,
  CAST(NULL AS STRING) AS min_event_raw,
  CAST(NULL AS STRING) AS max_event_raw
FROM wa_cards
UNION ALL
SELECT
  'tc_cdr.sim_status_for_sftp_bak',
  COUNT(*),
  COUNT(DISTINCT CAST(s.imsi AS STRING)),
  COUNT(DISTINCT CASE WHEN w.imsi IS NOT NULL THEN CAST(s.imsi AS STRING) END),
  MIN(CAST(s.partition_time AS STRING)),
  MAX(CAST(s.partition_time AS STRING))
FROM simo_prod.tc_cdr.sim_status_for_sftp_bak s
LEFT JOIN wa_cards w ON w.imsi = CAST(s.imsi AS STRING)
WHERE s.year = 2026 AND s.month BETWEEN 2 AND 6
UNION ALL
SELECT
  'ods.resource_res_vsim_cycle_history',
  COUNT(*),
  COUNT(DISTINCT CAST(h.imsi AS STRING)),
  COUNT(DISTINCT CASE WHEN w.imsi IS NOT NULL THEN CAST(h.imsi AS STRING) END),
  CAST(MIN(h.cycle_time) AS STRING),
  CAST(MAX(h.next_cycle_time) AS STRING)
FROM simo_prod.ods.resource_res_vsim_cycle_history h
LEFT JOIN wa_cards w ON w.imsi = CAST(h.imsi AS STRING)
WHERE h.cycle_time >= TIMESTAMP '2026-02-01 00:00:00'
  AND h.cycle_time < TIMESTAMP '2026-07-01 00:00:00'
UNION ALL
SELECT
  'ods.resource_res_vsim_status_log',
  COUNT(*),
  COUNT(DISTINCT CAST(l.IMSI AS STRING)),
  COUNT(DISTINCT CASE WHEN w.imsi IS NOT NULL THEN CAST(l.IMSI AS STRING) END),
  CAST(MIN(l.CREATE_DATE) AS STRING),
  CAST(MAX(l.CREATE_DATE) AS STRING)
FROM simo_prod.ods.resource_res_vsim_status_log l
LEFT JOIN wa_cards w ON w.imsi = CAST(l.IMSI AS STRING)
WHERE l.CREATE_DATE >= TIMESTAMP '2026-02-01 00:00:00'
  AND l.CREATE_DATE < TIMESTAMP '2026-07-15 00:00:00'
UNION ALL
SELECT
  'ods.resource_res_vsim_product_via_cycle',
  COUNT(*),
  COUNT(DISTINCT product_id),
  COUNT(DISTINCT CASE WHEN product_name IS NOT NULL THEN imsi END),
  CAST(NULL AS STRING),
  CAST(NULL AS STRING)
FROM product_rows
UNION ALL
SELECT
  'ods.resource_res_carrier_via_product',
  COUNT(*),
  COUNT(DISTINCT carrier_id),
  COUNT(DISTINCT CASE WHEN carrier_name IS NOT NULL THEN imsi END),
  CAST(NULL AS STRING),
  CAST(NULL AS STRING)
FROM carrier_rows
ORDER BY source_table;