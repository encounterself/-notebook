-- Batch A / read-only platform lifecycle-event coverage probe.
SELECT
  'status_log' AS dataset,
  CAST(NULL AS STRING) AS raw_period,
  PRE_STATUS AS pre_status,
  NEXT_STATUS AS next_status,
  COUNT(*) AS row_count,
  COUNT(DISTINCT IMSI) AS distinct_imsi,
  MIN(CREATE_DATE) AS min_event_ts,
  MAX(CREATE_DATE) AS max_event_ts
FROM simo_prod.ods.resource_res_vsim_status_log
WHERE CREATE_DATE >= TIMESTAMP('2025-08-20 00:00:00')
  AND CREATE_DATE < TIMESTAMP('2025-12-15 00:00:00')
GROUP BY PRE_STATUS, NEXT_STATUS

UNION ALL

SELECT
  'cycle_history' AS dataset,
  DATE_FORMAT(next_cycle_time, 'yyyy-MM') AS raw_period,
  CAST(NULL AS STRING) AS pre_status,
  CAST(NULL AS STRING) AS next_status,
  COUNT(*) AS row_count,
  COUNT(DISTINCT imsi) AS distinct_imsi,
  MIN(next_cycle_time) AS min_event_ts,
  MAX(next_cycle_time) AS max_event_ts
FROM simo_prod.ods.resource_res_vsim_cycle_history
WHERE next_cycle_time >= TIMESTAMP('2025-08-20 00:00:00')
  AND next_cycle_time < TIMESTAMP('2025-12-15 00:00:00')
GROUP BY DATE_FORMAT(next_cycle_time, 'yyyy-MM')

UNION ALL

SELECT
  'cycle_history_minus_5h' AS dataset,
  DATE_FORMAT(next_cycle_time - INTERVAL 5 HOURS, 'yyyy-MM') AS raw_period,
  CAST(NULL AS STRING) AS pre_status,
  CAST(NULL AS STRING) AS next_status,
  COUNT(*) AS row_count,
  COUNT(DISTINCT imsi) AS distinct_imsi,
  MIN(next_cycle_time) AS min_event_ts,
  MAX(next_cycle_time) AS max_event_ts
FROM simo_prod.ods.resource_res_vsim_cycle_history
WHERE next_cycle_time >= TIMESTAMP('2025-08-20 00:00:00')
  AND next_cycle_time < TIMESTAMP('2025-12-15 00:00:00')
GROUP BY DATE_FORMAT(next_cycle_time - INTERVAL 5 HOURS, 'yyyy-MM')
ORDER BY dataset, raw_period, pre_status, next_status;