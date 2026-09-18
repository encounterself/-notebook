WITH
prod AS (
  SELECT DISTINCT
    cast(product_id AS STRING) AS product_id,
    supplier_id,
    trim(product_name) AS product_name,
    monthly_rent,
    package_price,
    time_zone
  FROM simo_prod.ods.resource_res_vsim_product
  WHERE supplier_id = 2275
),
snap AS (
  SELECT
    year,
    month,
    day,
    hour,
    trim(imsi) AS imsi,
    trim(product_id) AS product_id,
    to_date(trim(Cycle_Start_Time)) AS cycle_start,
    to_date(trim(Cycle_End_Time)) AS cycle_end,
    trim(ICCID) AS iccid,
    trim(SimStatus) AS sim_status,
    trim(DispatchStatus) AS dispatch_status,
    trim(partition_time) AS partition_time
  FROM simo_prod.tc_cdr.sim_status_for_sftp_bak
  WHERE year = 2026 AND month IN (3,4,5)
)
SELECT
  s.year,
  s.month,
  max(s.day) AS max_partition_day,
  max(s.hour) AS max_partition_hour,
  max(s.partition_time) AS max_partition_time,
  count(*) AS snapshot_rows,
  count(DISTINCT s.imsi) AS snapshot_imsi_count,
  count(DISTINCT s.product_id) AS snapshot_product_count,
  count(DISTINCT CASE WHEN p.product_id IS NOT NULL THEN s.imsi END) AS supplier_2275_imsi_count,
  count(DISTINCT CASE WHEN p.product_id IS NOT NULL THEN s.product_id END) AS supplier_2275_product_count,
  count(DISTINCT CASE WHEN p.product_id IS NULL THEN s.product_id END) AS non_supplier_product_count,
  min(s.cycle_start) AS min_cycle_start,
  max(s.cycle_start) AS max_cycle_start,
  min(s.cycle_end) AS min_cycle_end,
  max(s.cycle_end) AS max_cycle_end
FROM snap s
LEFT JOIN prod p ON s.product_id = p.product_id
GROUP BY s.year, s.month
ORDER BY s.year, s.month