-- Batch A / read-only platform snapshot coverage probe.
SELECT
  CONCAT(CAST(year AS STRING), '-', LPAD(CAST(month AS STRING), 2, '0')) AS snapshot_month,
  COUNT(*) AS snapshot_rows,
  COUNT(DISTINCT imsi) AS distinct_imsi,
  COUNT(DISTINCT product_id) AS distinct_product_id,
  MIN(day) AS min_partition_day,
  MAX(day) AS max_partition_day,
  MIN(partition_time) AS min_partition_time_raw,
  MAX(partition_time) AS max_partition_time_raw
FROM simo_prod.tc_cdr.sim_status_for_sftp_bak
WHERE year = 2025 AND month IN (9, 10, 11)
GROUP BY year, month
ORDER BY year, month;