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
)
SELECT
  CAST(l.PRE_STATUS AS STRING) AS pre_status,
  CAST(l.NEXT_STATUS AS STRING) AS next_status,
  COUNT(*) AS row_count,
  COUNT(DISTINCT CAST(l.IMSI AS STRING)) AS imsi_count,
  MIN(l.CREATE_DATE) AS min_create_date,
  MAX(l.CREATE_DATE) AS max_create_date
FROM simo_prod.ods.resource_res_vsim_status_log l
JOIN wa_cards w ON w.imsi = CAST(l.IMSI AS STRING)
WHERE l.CREATE_DATE >= TIMESTAMP '2026-02-01 00:00:00'
  AND l.CREATE_DATE < TIMESTAMP '2026-07-15 00:00:00'
GROUP BY CAST(l.PRE_STATUS AS STRING), CAST(l.NEXT_STATUS AS STRING)
ORDER BY row_count DESC, pre_status, next_status;