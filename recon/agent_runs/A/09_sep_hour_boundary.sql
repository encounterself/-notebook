-- Batch A / read-only September partition boundary probe.
SELECT
  '2025-09' AS snapshot_month,
  'hour_08_to_23_only' AS coverage_scope,
  COUNT(*) AS snapshot_rows,
  COUNT(DISTINCT imsi) AS distinct_imsi,
  COUNT(DISTINCT product_id) AS distinct_product_id,
  MIN(day) AS min_partition_day,
  MAX(day) AS max_partition_day,
  MIN(hour) AS min_partition_hour,
  MAX(hour) AS max_partition_hour
FROM simo_prod.tc_cdr.sim_status_for_sftp_bak
WHERE year = 2025 AND month = 9 AND hour >= 8;