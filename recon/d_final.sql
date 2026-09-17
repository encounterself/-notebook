-- ============================================================================
-- D 换卡新卡 · 平台侧完整规则验证
--   final_start = 激活日 + 1        （status_log NEXT_STATUS='激活' 的 CREATE_DATE，减5h）
--   final_end   = max(Cycle_End) − 1（当月快照中 Cycle_End_Time 的最大日期）
--   final_days  = DATEDIFF(final_end, final_start) + 1
-- ============================================================================
WITH cfg AS (
  SELECT '2026-07' AS mon, '%JULY 2026%' AS pat, 2026 AS y, 7 AS m, DATE('2026-07-01') AS d1
  UNION ALL SELECT '2026-08', '%AUGUST 2026%', 2026, 8, DATE('2026-08-01')
),
xl AS (
  SELECT c.mon, x.imsi,
         MAX(TRY_CAST(x.final_days AS DOUBLE))   AS xl_days,
         MAX(TRY_CAST(x.active_days AS DOUBLE))  AS xl_active,
         MAX(TRY_CAST(x.usage_days AS DOUBLE))   AS xl_usage,
         MAX(TRY_CAST(x.monthly_rate AS DOUBLE)) AS xl_rate,
         SUM(TRY_CAST(x.final_charge AS DOUBLE)) AS xl_charge,
         MAX(TO_DATE(x.final_start_date))        AS xl_fsd,
         MAX(TO_DATE(x.final_end_date))          AS xl_fed
  FROM cfg c JOIN simo_prod.mysql_cdc_sync.wa_invoice_detail x ON x.source_file LIKE c.pat
  WHERE x.charge_type = 'Partial Charge - New Card Used as Replacement Mid Cycle'
  GROUP BY c.mon, x.imsi
),
-- 激活日（减 5 小时后取日期）
act AS (
  SELECT mon, imsi, SPLIT(CAST(CAST(act_date AS TIMESTAMP) - INTERVAL 5 HOURS AS STRING),' ')[0] AS act_d5
  FROM (
    SELECT c.mon, l.IMSI AS imsi, MAX(l.CREATE_DATE) AS act_date
    FROM cfg c JOIN simo_prod.ods.resource_res_vsim_status_log l
      ON l.NEXT_STATUS = '\u6fc0\u6d3b'
     AND DATE(l.CREATE_DATE) >= DATE_FORMAT(DATE_SUB(c.d1, 120),'yyyy-MM-dd')
     AND DATE(l.CREATE_DATE) <= DATE_FORMAT(DATE_ADD(c.d1, 40),'yyyy-MM-dd')
    GROUP BY c.mon, l.IMSI
  ) t
),
-- 当月快照最大 Cycle_End / 最大 Cycle_Start
mce AS (
  SELECT c.mon, s.imsi,
         MAX(SPLIT(s.Cycle_End_Time,' ')[0])   AS max_ce,
         MAX(SPLIT(s.Cycle_Start_Time,' ')[0]) AS max_cs
  FROM cfg c JOIN simo_prod.tc_cdr.sim_status_for_sftp_bak s ON s.year=c.y AND s.month=c.m
  GROUP BY c.mon, s.imsi
),
calc AS (
  SELECT x.*, a.act_d5, m.max_ce, m.max_cs, DAY(LAST_DAY(c.d1)) AS dim,
         DATE_ADD(TO_DATE(a.act_d5), 1)      AS start_act,
         DATE_SUB(TO_DATE(m.max_ce), 1)      AS end_mce,
         DATE_SUB(TO_DATE(m.max_cs), 1)      AS end_mcs
  FROM xl x JOIN cfg c ON c.mon = x.mon
  LEFT JOIN act a ON a.mon = x.mon AND a.imsi = x.imsi
  LEFT JOIN mce m ON m.mon = x.mon AND m.imsi = x.imsi
),
f AS (
  SELECT *,
    DATEDIFF(end_mce, start_act) + 1 AS days_mce,
    DATEDIFF(end_mcs, start_act) + 1 AS days_mcs
  FROM calc
)
SELECT mon, COUNT(1) AS cards,
  SUM(CASE WHEN start_act = xl_fsd THEN 1 ELSE 0 END) AS start_match,
  SUM(CASE WHEN end_mce = xl_fed THEN 1 ELSE 0 END)   AS end_mce_match,
  SUM(CASE WHEN end_mcs = xl_fed THEN 1 ELSE 0 END)   AS end_mcs_match,
  SUM(CASE WHEN days_mce = CAST(xl_days AS INT) THEN 1 ELSE 0 END) AS days_mce_match,
  SUM(CASE WHEN days_mcs = CAST(xl_days AS INT) THEN 1 ELSE 0 END) AS days_mcs_match,
  SUM(CASE WHEN days_mce <> CAST(xl_days AS INT)
            AND CAST(xl_days AS INT) = CAST(xl_usage AS INT) THEN 1 ELSE 0 END) AS unmatched_is_usage,
  ROUND(SUM(xl_charge),2) AS excel,
  ROUND(SUM(ROUND(xl_rate/dim*days_mce,4)),2) AS calc_mce,
  ROUND(SUM(ROUND(xl_rate/dim*days_mce,4)) - SUM(xl_charge),2) AS diff_mce,
  ROUND(SUM(ROUND(xl_rate/dim*days_mcs,4)),2) AS calc_mcs,
  ROUND(SUM(ROUND(xl_rate/dim*days_mcs,4)) - SUM(xl_charge),2) AS diff_mcs,
  ROUND(AVG(xl_days),1) AS avg_xl, ROUND(AVG(days_mce),1) AS avg_mce, ROUND(AVG(days_mcs),1) AS avg_mcs
FROM f GROUP BY mon ORDER BY mon
