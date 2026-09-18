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
  'ods.core_dse_applylog' AS source_table,
  COUNT(*) AS matched_rows,
  COUNT(DISTINCT COALESCE(NULLIF(TRIM(a.vsimImsi), ''), NULLIF(TRIM(a.oldImsi), ''))) AS imsi_count,
  COUNT(DISTINCT CAST(a.action AS STRING)) AS action_count,
  CONCAT_WS(' || ', SORT_ARRAY(COLLECT_SET(COALESCE(CAST(a.action AS STRING), '<NULL>')))) AS actions,
  MIN(CAST(a.applyTime_dt AS STRING)) AS min_apply_raw,
  MAX(CAST(a.applyTime_dt AS STRING)) AS max_apply_raw
FROM simo_prod.ods.core_dse_applylog a
JOIN wa_cards w
  ON w.imsi = NULLIF(TRIM(a.vsimImsi), '')
  OR w.imsi = NULLIF(TRIM(a.oldImsi), '');