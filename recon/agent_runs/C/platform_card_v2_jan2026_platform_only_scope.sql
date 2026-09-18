WITH target_products AS (
  SELECT cast(product_id AS STRING) AS platform_product_id,
         trim(product_name) AS platform_product_name,
         cast(monthly_rent AS DECIMAL(38,10)) AS platform_monthly_rent,
         cast(package_price AS DECIMAL(38,10)) AS platform_package_price,
         trim(time_zone) AS platform_time_zone
  FROM simo_prod.ods.resource_res_vsim_product
  WHERE supplier_id = 2275
),
jan_snapshot AS (
  SELECT
    '2026-01' AS reconciliation_billing_month,
    trim(s.imsi) AS imsi,
    trim(s.product_id) AS platform_product_id,
    trim(s.ICCID) AS platform_iccid,
    to_date(trim(s.Cycle_Start_Time)) AS platform_cycle_start,
    to_date(trim(s.Cycle_End_Time)) AS platform_cycle_end,
    max(to_timestamp(trim(s.partition_time))) AS last_snapshot_ts
  FROM simo_prod.tc_cdr.sim_status_for_sftp_bak s
  INNER JOIN target_products p
    ON trim(s.product_id) = p.platform_product_id
  WHERE s.year = 2026 AND s.month = 1
    AND trim(s.imsi) IS NOT NULL AND trim(s.imsi) <> ''
  GROUP BY trim(s.imsi), trim(s.product_id), trim(s.ICCID),
           to_date(trim(s.Cycle_Start_Time)), to_date(trim(s.Cycle_End_Time))
)
SELECT
  reconciliation_billing_month,
  'PLATFORM_ONLY' AS source_match_status,
  'NO_OFFICIAL_JAN_2026_DETAIL_SOURCE_FILE' AS difference_reason,
  count(*) AS row_count,
  count(DISTINCT imsi) AS distinct_imsi_count,
  count(DISTINCT platform_product_id) AS distinct_product_count,
  min(platform_cycle_start) AS min_platform_cycle_start,
  max(platform_cycle_end) AS max_platform_cycle_end
FROM jan_snapshot
GROUP BY reconciliation_billing_month