-- Batch A / read-only September snapshot facts.
-- Excludes only the inaccessible raw file partition year=2025/month=9/day=16/hour=6.
SELECT
  '2025-09' AS snapshot_month,
  'readable_excluding_2025-09-16_06' AS coverage_scope,
  COUNT(*) AS snapshot_rows,
  COUNT(DISTINCT imsi) AS distinct_imsi,
  COUNT(DISTINCT product_id) AS distinct_product_id,
  MIN(day) AS min_partition_day,
  MAX(day) AS max_partition_day,
  MIN(partition_time) AS min_partition_time_raw,
  MAX(partition_time) AS max_partition_time_raw
FROM simo_prod.tc_cdr.sim_status_for_sftp_bak
WHERE year = 2025 AND month = 9
  AND NOT (day = 16 AND hour = 6);