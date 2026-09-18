WITH
e AS (
  SELECT
    trim(source_file) AS source_file,
    trim(imsi) AS imsi,
    trim(charge_type) AS charge_type,
    to_date(trim(final_start_date)) AS final_start,
    to_date(trim(final_end_date)) AS final_end,
    try_cast(nullif(trim(final_days), '') AS DECIMAL(38,10)) AS excel_days,
    try_cast(nullif(trim(monthly_rate), '') AS DECIMAL(38,10)) AS excel_price,
    try_cast(nullif(trim(final_charge), '') AS DECIMAL(38,10)) AS excel_amount
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE (trim(source_file) LIKE '%MAR 2026%'
      OR trim(source_file) LIKE '%APR 2026%'
      OR trim(source_file) LIKE '%MAY 2026%')
),
prod AS (
  SELECT DISTINCT
    cast(product_id AS STRING) AS product_id,
    trim(product_name) AS platform_product_name,
    supplier_id,
    monthly_rent,
    package_price,
    time_zone
  FROM simo_prod.ods.resource_res_vsim_product
  WHERE supplier_id = 2275
),
s AS (
  SELECT
    trim(imsi) AS imsi,
    trim(product_id) AS product_id,
    trim(ICCID) AS iccid,
    to_date(trim(Cycle_Start_Time)) AS snapshot_cycle_start,
    to_date(trim(Cycle_End_Time)) AS snapshot_cycle_end,
    year,
    month,
    day,
    hour,
    trim(partition_time) AS partition_time,
    trim(SimStatus) AS sim_status,
    trim(DispatchStatus) AS dispatch_status
  FROM simo_prod.tc_cdr.sim_status_for_sftp_bak
  WHERE year = 2026 AND month IN (3,4,5)
)
SELECT
  e.source_file,
  e.charge_type,
  e.imsi,
  e.final_start,
  e.final_end,
  e.excel_days,
  e.excel_price,
  e.excel_amount,
  s.product_id AS platform_product_id,
  p.platform_product_name,
  p.monthly_rent AS platform_monthly_rent,
  p.package_price AS platform_package_price,
  p.time_zone AS platform_time_zone,
  s.iccid,
  s.snapshot_cycle_start,
  s.snapshot_cycle_end,
  s.year AS snapshot_year,
  s.month AS snapshot_month,
  s.day AS snapshot_day,
  s.hour AS snapshot_hour,
  s.partition_time,
  s.sim_status,
  s.dispatch_status
FROM e
INNER JOIN s ON e.imsi = s.imsi
INNER JOIN prod p ON s.product_id = p.product_id
WHERE s.snapshot_cycle_start <= e.final_end
  AND s.snapshot_cycle_end >= e.final_start
ORDER BY e.source_file, e.charge_type, e.imsi, s.partition_time DESC
LIMIT 100