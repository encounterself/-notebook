WITH detail_imsis AS (
  SELECT DISTINCT TRIM(CAST(imsi AS STRING)) AS imsi
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE source_file LIKE '%DEC 2025%' OR source_file LIKE '%JAN 2026%' OR source_file LIKE '%FEB 2026%'
)
SELECT
  TRIM(CAST(l.PRE_STATUS AS STRING)) AS pre_status,
  TRIM(CAST(l.NEXT_STATUS AS STRING)) AS next_status,
  TRIM(CAST(l.DESC_LOG AS STRING)) AS desc_log,
  TRIM(CAST(l.DESCRIPTION AS STRING)) AS description,
  COUNT(*) AS event_count,
  COUNT(DISTINCT TRIM(CAST(l.IMSI AS STRING))) AS imsi_count,
  MIN(l.CREATE_DATE) AS min_create_date,
  MAX(l.CREATE_DATE) AS max_create_date,
  MIN(TRY_CAST(l.partition_date AS TIMESTAMP)) AS min_partition_date,
  MAX(TRY_CAST(l.partition_date AS TIMESTAMP)) AS max_partition_date
FROM simo_prod.ods.resource_res_vsim_status_log l
JOIN detail_imsis d ON TRIM(CAST(l.IMSI AS STRING))=d.imsi
WHERE l.CREATE_DATE >= CAST('2025-11-01' AS TIMESTAMP)
  AND l.CREATE_DATE < CAST('2026-04-01' AS TIMESTAMP)
GROUP BY TRIM(CAST(l.PRE_STATUS AS STRING)), TRIM(CAST(l.NEXT_STATUS AS STRING)),
  TRIM(CAST(l.DESC_LOG AS STRING)), TRIM(CAST(l.DESCRIPTION AS STRING))
ORDER BY event_count DESC, pre_status, next_status;