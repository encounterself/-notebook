-- D 换卡新卡（7月）：Excel 真值 vs 平台各候选字段
WITH xl AS (
  SELECT imsi, MAX(TRY_CAST(final_days AS DOUBLE)) AS xl_days,
         MAX(TRY_CAST(monthly_rate AS DOUBLE)) AS xl_rate,
         SUM(TRY_CAST(final_charge AS DOUBLE)) AS xl_charge,
         MAX(TO_DATE(final_start_date)) AS fsd, MAX(TO_DATE(final_end_date)) AS fed,
         MAX(TO_DATE(cycle_start_date)) AS csd, MAX(TO_DATE(cycle_end_date)) AS ced,
         MAX(TO_DATE(new_activation_date)) AS nad, MAX(TO_DATE(offstock_date)) AS ofs,
         MAX(status) AS st
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE source_file LIKE '%JULY 2026%'
    AND charge_type = 'Partial Charge - New Card Used as Replacement Mid Cycle'
  GROUP BY imsi
),
-- 平台：cycle_history 全部记录（含本月与下月）
h AS (
  SELECT imsi,
         SPLIT(CAST(CAST(cycle_time AS TIMESTAMP) - INTERVAL 5 HOURS AS STRING),' ')[0] AS ct,
         SPLIT(CAST(CAST(next_cycle_time AS TIMESTAMP) - INTERVAL 5 HOURS AS STRING),' ')[0] AS nct
  FROM simo_prod.ods.resource_res_vsim_cycle_history
),
-- 平台：7月快照的账期
sn AS (
  SELECT imsi, MIN(SPLIT(Cycle_Start_Time,' ')[0]) AS min_cs,
         MAX(SPLIT(Cycle_Start_Time,' ')[0]) AS max_cs,
         MIN(SPLIT(Cycle_End_Time,' ')[0]) AS min_ce,
         MAX(SPLIT(Cycle_End_Time,' ')[0]) AS max_ce,
         COUNT(DISTINCT DATE(partition_time)) AS pres_days,
         MIN(DATE(partition_time)) AS first_seen, MAX(DATE(partition_time)) AS last_seen
  FROM simo_prod.tc_cdr.sim_status_for_sftp_bak
  WHERE year = 2026 AND month = 7 GROUP BY imsi
)
SELECT x.imsi, x.xl_days, x.fsd, x.fed, x.csd, x.ced, x.nad, x.ofs, x.st,
       s.min_cs, s.max_cs, s.min_ce, s.max_ce, s.pres_days, s.first_seen, s.last_seen
FROM xl x LEFT JOIN sn s ON s.imsi = x.imsi
ORDER BY x.xl_days LIMIT 20
