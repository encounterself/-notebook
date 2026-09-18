WITH product_dim AS (
  SELECT CAST(product_id AS STRING) AS platform_product_id, CAST(supplier_id AS BIGINT) AS supplier_id, product_name,
    monthly_rent, package_price
  FROM simo_prod.ods.resource_res_vsim_product
), snapshot_target AS (
  SELECT CASE WHEN year=2025 AND month=12 THEN '2025-12' WHEN year=2026 AND month=1 THEN '2026-01' WHEN year=2026 AND month=2 THEN '2026-02' END AS platform_month,
    TRIM(CAST(s.imsi AS STRING)) AS imsi, CAST(s.product_id AS STRING) AS platform_product_id,
    TRY_CAST(TRIM(s.Cycle_Start_Time) AS TIMESTAMP) AS cycle_start_time,
    TRY_CAST(TRIM(s.Cycle_End_Time) AS TIMESTAMP) AS cycle_end_time,
    p.supplier_id, p.product_name, p.monthly_rent, p.package_price
  FROM simo_prod.tc_cdr.sim_status_for_sftp_bak s
  LEFT JOIN product_dim p ON CAST(s.product_id AS STRING)=p.platform_product_id
  WHERE (s.year=2025 AND s.month=12) OR (s.year=2026 AND s.month IN (1,2))
), cycle_target AS (
  SELECT TRIM(CAST(c.imsi AS STRING)) AS imsi, CAST(c.product_id AS STRING) AS platform_product_id,
    c.cycle_time, c.next_cycle_time, c.package_price,
    p.supplier_id, p.product_name, p.monthly_rent, p.package_price AS product_package_price
  FROM simo_prod.ods.resource_res_vsim_cycle_history c
  LEFT JOIN product_dim p ON CAST(c.product_id AS STRING)=p.platform_product_id
  WHERE c.cycle_time < CAST('2026-03-01' AS TIMESTAMP)
    AND c.next_cycle_time >= CAST('2025-12-01' AS TIMESTAMP)
)
SELECT 'snapshot_product_mapping' AS check_name, platform_month, platform_product_id,
  supplier_id, product_name, COUNT(*) AS row_count, COUNT(DISTINCT imsi) AS imsi_count,
  MIN(cycle_start_time) AS min_start, MAX(cycle_end_time) AS max_end,
  CAST(NULL AS DOUBLE) AS source_package_price, CAST(NULL AS DOUBLE) AS product_monthly_rent
FROM snapshot_target
GROUP BY platform_month, platform_product_id, supplier_id, product_name
UNION ALL
SELECT 'cycle_product_mapping' AS check_name, CAST(NULL AS STRING) AS platform_month, platform_product_id,
  supplier_id, product_name, COUNT(*) AS row_count, COUNT(DISTINCT imsi) AS imsi_count,
  MIN(cycle_time) AS min_start, MAX(next_cycle_time) AS max_end,
  MIN(package_price) AS source_package_price, MIN(monthly_rent) AS product_monthly_rent
FROM cycle_target
GROUP BY platform_product_id, supplier_id, product_name
ORDER BY check_name, platform_month, platform_product_id;