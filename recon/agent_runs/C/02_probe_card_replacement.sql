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
  'dm.card_replacement_details' AS source_table,
  COUNT(*) AS matched_rows,
  COUNT(DISTINCT NULLIF(TRIM(r.old_imsi), '')) AS old_imsi_count,
  COUNT(DISTINCT NULLIF(TRIM(r.new_imsi), '')) AS new_imsi_count,
  MIN(CAST(r.dt AS STRING)) AS min_dt_raw,
  MAX(CAST(r.dt AS STRING)) AS max_dt_raw
FROM simo_prod.dm.card_replacement_details r
JOIN wa_cards w
  ON w.imsi = NULLIF(TRIM(r.old_imsi), '')
  OR w.imsi = NULLIF(TRIM(r.new_imsi), '');