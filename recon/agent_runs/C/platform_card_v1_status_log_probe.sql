WITH e AS (
  SELECT DISTINCT trim(imsi) AS imsi
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE trim(source_file) LIKE '%MAR 2026%'
     OR trim(source_file) LIKE '%APR 2026%'
     OR trim(source_file) LIKE '%MAY 2026%'
),
l AS (
  SELECT
    trim(l.IMSI) AS imsi,
    trim(l.PRE_STATUS) AS pre_status,
    trim(l.NEXT_STATUS) AS next_status,
    trim(l.DESC_LOG) AS desc_log,
    trim(l.DESCRIPTION) AS description,
    to_date(l.CREATE_DATE) AS create_date,
    to_date(trim(l.partition_date)) AS partition_date,
    trim(l.EXT1) AS ext1
  FROM simo_prod.ods.resource_res_vsim_status_log l
  INNER JOIN e ON trim(l.IMSI)=e.imsi
  WHERE to_date(trim(l.partition_date)) >= DATE '2026-02-01'
    AND to_date(trim(l.partition_date)) < DATE '2026-06-01'
)
SELECT
  pre_status,
  next_status,
  desc_log,
  COUNT(*) AS log_rows,
  COUNT(DISTINCT imsi) AS imsi_count,
  MIN(create_date) AS min_create_date,
  MAX(create_date) AS max_create_date
FROM l
GROUP BY pre_status,next_status,desc_log
ORDER BY log_rows DESC
LIMIT 100