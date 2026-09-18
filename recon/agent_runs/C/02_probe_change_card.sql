WITH wa_cards AS (
  SELECT DISTINCT CAST(imsi AS STRING) AS imsi
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE source_file IN (
    '01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx',
    '01-SIMO Data Purchase Invoice Details - APR 2026.xlsx',
    '01-SIMO Data Purchase Invoice Details - MAY 2026.xlsx'
  )
)
SELECT
  'dm.change_card_data' AS source_table,
  COUNT(*) AS matched_rows,
  COUNT(DISTINCT CAST(d.imsi AS STRING)) AS imsi_count,
  MIN(CAST(d.dt AS STRING)) AS min_dt_raw,
  MAX(CAST(d.dt AS STRING)) AS max_dt_raw,
  COUNT(DISTINCT CAST(d.releaseReason AS STRING)) AS release_reason_count,
  CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(COALESCE(CAST(d.releaseReason AS STRING), '<NULL>')))) AS release_reasons
FROM simo_prod.dm.change_card_data d
JOIN wa_cards w ON w.imsi = CAST(d.imsi AS STRING);