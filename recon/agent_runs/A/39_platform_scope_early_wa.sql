-- Batch A / read-only early Wing Alpha monthly platform scope.
WITH cfg AS (
  SELECT '2025-10' AS billing_month, 2025 AS y, 10 AS m
  UNION ALL SELECT '2025-11', 2025, 11
), wa_products AS (
  SELECT DISTINCT CAST(product_id AS STRING) AS product_id, product_name, package_price, supplier_id, create_time, modify_time
  FROM simo_prod.ods.resource_res_vsim_product
  WHERE supplier_id = 2275
), wa_snapshot AS (
  SELECT c.billing_month, s.imsi, CAST(s.product_id AS STRING) AS product_id,
         p.product_name, p.package_price, p.create_time, p.modify_time
  FROM cfg c
  JOIN simo_prod.tc_cdr.sim_status_for_sftp_bak s
    ON s.year = c.y AND s.month = c.m
  JOIN wa_products p
    ON p.product_id = CAST(s.product_id AS STRING)
)
SELECT billing_month, COUNT(*) AS snapshot_rows, COUNT(DISTINCT imsi) AS distinct_imsi,
       COUNT(DISTINCT product_id) AS distinct_product_id,
       COUNT(DISTINCT package_price) AS distinct_package_price,
       COUNT(DISTINCT product_name) AS distinct_product_name
FROM wa_snapshot
GROUP BY billing_month
ORDER BY billing_month;