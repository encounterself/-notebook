WITH wa_cards AS (
  SELECT DISTINCT
    CAST(imsi AS STRING) AS imsi
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE source_file IN (
    '01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx',
    '01-SIMO Data Purchase Invoice Details - APR 2026.xlsx',
    '01-SIMO Data Purchase Invoice Details - MAY 2026.xlsx'
  )
  AND NULLIF(TRIM(imsi), '') IS NOT NULL
  UNION
  SELECT DISTINCT
    CAST(imsi AS STRING) AS imsi
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
    h.product_id,
    p.product_name,
    p.carrier_id,
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
probe AS (
  SELECT
    'wa_card_keys' AS source_table,
    COUNT(*) AS row_count,
    COUNT(DISTINCT imsi) AS distinct_imsi,
    COUNT(DISTINCT imsi) AS matched_wa_imsi,
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
    COUNT(DISTINCT CAST(product_id AS STRING)),
    COUNT(DISTINCT CASE WHEN product_name IS NOT NULL THEN imsi END),
    CAST(NULL AS STRING),
    CAST(NULL AS STRING)
  FROM product_rows

  UNION ALL

  SELECT
    'ods.resource_res_carrier_via_product',
    COUNT(*),
    COUNT(DISTINCT CAST(carrier_id AS STRING)),
    COUNT(DISTINCT CASE WHEN carrier_name IS NOT NULL THEN imsi END),
    CAST(NULL AS STRING),
    CAST(NULL AS STRING)
  FROM (
    SELECT DISTINCT
      pr.imsi,
      pr.carrier_id,
      cr.CARRIER_NAME AS carrier_name
    FROM product_rows pr
    LEFT JOIN simo_prod.ods.resource_res_carrier cr
      ON cr.ID = pr.carrier_id
  ) carrier_rows

  UNION ALL

  SELECT
    'dm.card_replacement_details',
    COUNT(*),
    COUNT(DISTINCT COALESCE(NULLIF(TRIM(r.old_imsi), ''), NULLIF(TRIM(r.new_imsi), ''))),
    COUNT(DISTINCT CASE WHEN w_old.imsi IS NOT NULL OR w_new.imsi IS NOT NULL THEN COALESCE(NULLIF(TRIM(r.old_imsi), ''), NULLIF(TRIM(r.new_imsi), '')) END),
    MIN(CAST(r.dt AS STRING)),
    MAX(CAST(r.dt AS STRING))
  FROM simo_prod.dm.card_replacement_details r
  LEFT JOIN wa_cards w_old ON w_old.imsi = NULLIF(TRIM(r.old_imsi), '')
  LEFT JOIN wa_cards w_new ON w_new.imsi = NULLIF(TRIM(r.new_imsi), '')
  WHERE w_old.imsi IS NOT NULL OR w_new.imsi IS NOT NULL

  UNION ALL

  SELECT
    'dm.change_card_data',
    COUNT(*),
    COUNT(DISTINCT CAST(d.imsi AS STRING)),
    COUNT(DISTINCT CASE WHEN w.imsi IS NOT NULL THEN CAST(d.imsi AS STRING) END),
    CAST(MIN(TRY_CAST(d.createtime / 1000 AS TIMESTAMP)) AS STRING),
    CAST(MAX(TRY_CAST(d.createtime / 1000 AS TIMESTAMP)) AS STRING)
  FROM simo_prod.dm.change_card_data d
  LEFT JOIN wa_cards w ON w.imsi = CAST(d.imsi AS STRING)
  WHERE w.imsi IS NOT NULL

  UNION ALL

  SELECT
    'ods.core_dse_applylog',
    COUNT(*),
    COUNT(DISTINCT COALESCE(NULLIF(TRIM(a.vsimImsi), ''), NULLIF(TRIM(a.oldImsi), ''))),
    COUNT(DISTINCT CASE WHEN w1.imsi IS NOT NULL OR w2.imsi IS NOT NULL THEN COALESCE(NULLIF(TRIM(a.vsimImsi), ''), NULLIF(TRIM(a.oldImsi), '')) END),
    MIN(CAST(a.applyTime_dt AS STRING)),
    MAX(CAST(a.applyTime_dt AS STRING))
  FROM simo_prod.ods.core_dse_applylog a
  LEFT JOIN wa_cards w1 ON w1.imsi = NULLIF(TRIM(a.vsimImsi), '')
  LEFT JOIN wa_cards w2 ON w2.imsi = NULLIF(TRIM(a.oldImsi), '')
  WHERE w1.imsi IS NOT NULL OR w2.imsi IS NOT NULL
)
SELECT source_table, row_count, distinct_imsi, matched_wa_imsi, min_event_raw, max_event_raw
FROM probe
ORDER BY source_table;