WITH product_dim AS (
  SELECT
    CAST(product_id AS STRING) AS platform_product_id,
    CAST(supplier_id AS BIGINT) AS supplier_id,
    product_name,
    monthly_rent,
    package_price,
    CASE
      WHEN UPPER(COALESCE(product_name,'')) LIKE '%(PI)%' THEN 'EXCLUDED_PI'
      WHEN UPPER(COALESCE(product_name,'')) LIKE '%UNASSIGNED%' THEN 'EXCLUDED_UNASSIGNED'
      WHEN UPPER(COALESCE(product_name,'')) LIKE '%TEST%' OR COALESCE(product_name,'') LIKE '%测试%' THEN 'EXCLUDED_TEST'
      WHEN UPPER(COALESCE(product_name,'')) LIKE '%(WA)%' OR UPPER(COALESCE(product_name,'')) LIKE '% WA%' THEN 'WA_CANDIDATE'
      ELSE 'SUPPLIER_2275_NAME_UNCONFIRMED'
    END AS product_population_status
  FROM simo_prod.ods.resource_res_vsim_product
  WHERE supplier_id=2275
), target_snapshot AS (
  SELECT
    CASE WHEN year=2025 AND month=12 THEN '2025-12'
         WHEN year=2026 AND month=1 THEN '2026-01'
         WHEN year=2026 AND month=2 THEN '2026-02' END AS platform_month,
    TRIM(CAST(s.imsi AS STRING)) AS imsi,
    CAST(s.product_id AS STRING) AS platform_product_id,
    TRY_CAST(TRIM(s.Cycle_Start_Time) AS TIMESTAMP) AS cycle_start_time,
    TRY_CAST(TRIM(s.Cycle_End_Time) AS TIMESTAMP) AS cycle_end_time,
    TRIM(s.SimStatus) AS sim_status,
    TRIM(s.DispatchStatus) AS dispatch_status,
    TRY_CAST(TRIM(s.partition_time) AS TIMESTAMP) AS partition_time,
    p.supplier_id,
    p.product_name,
    p.monthly_rent,
    p.package_price,
    p.product_population_status
  FROM simo_prod.tc_cdr.sim_status_for_sftp_bak s
  LEFT JOIN product_dim p ON CAST(s.product_id AS STRING)=p.platform_product_id
  WHERE (s.year=2025 AND s.month=12) OR (s.year=2026 AND s.month IN (1,2))
)
SELECT
  platform_month,
  product_population_status,
  supplier_id,
  platform_product_id,
  product_name,
  COUNT(*) AS snapshot_row_count,
  COUNT(DISTINCT imsi) AS imsi_count,
  MIN(cycle_start_time) AS min_cycle_start_time,
  MAX(cycle_end_time) AS max_cycle_end_time,
  MIN(partition_time) AS min_partition_time,
  MAX(partition_time) AS max_partition_time,
  COUNT(DISTINCT sim_status) AS sim_status_count,
  COUNT(DISTINCT dispatch_status) AS dispatch_status_count
FROM target_snapshot
GROUP BY platform_month, product_population_status, supplier_id, platform_product_id, product_name
ORDER BY platform_month, product_population_status, platform_product_id;