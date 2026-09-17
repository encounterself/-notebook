-- 最终规则：新账期起点 = 当月在【本月内】出现的最小 Cycle_Start_Time
-- 若不存在（该卡当月账期是上月带过来的）→ final_end = 月末
WITH cfg AS (
  SELECT '2026-07' AS mon, 2026 AS y, 7 AS m, DATE('2026-07-01') AS d1, DATE('2026-07-31') AS d2,
         '%JULY 2026%' AS pat
  UNION ALL SELECT '2026-08', 2026, 8, DATE('2026-08-01'), DATE('2026-08-31'), '%AUGUST 2026%'
),
xl AS (
  SELECT c.mon, x.imsi, MAX(x.charge_type) AS xl_type,
         MAX(TRY_CAST(x.final_days AS DOUBLE)) AS xl_days,
         MAX(TRY_CAST(x.monthly_rate AS DOUBLE)) AS xl_rate,
         SUM(TRY_CAST(x.final_charge AS DOUBLE)) AS xl_charge
  FROM cfg c JOIN simo_prod.mysql_cdc_sync.wa_invoice_detail x ON x.source_file LIKE c.pat
  GROUP BY c.mon, x.imsi
),
newcs AS (
  SELECT c.mon, s.imsi, MIN(SPLIT(s.Cycle_Start_Time,' ')[0]) AS in_month_cs
  FROM cfg c JOIN simo_prod.tc_cdr.sim_status_for_sftp_bak s ON s.year=c.y AND s.month=c.m
  WHERE SPLIT(s.Cycle_Start_Time,' ')[0] >= DATE_FORMAT(c.d1,'yyyy-MM-dd')
    AND SPLIT(s.Cycle_Start_Time,' ')[0] <= DATE_FORMAT(c.d2,'yyyy-MM-dd')
  GROUP BY c.mon, s.imsi
),
scored AS (
  SELECT x.*, n.in_month_cs,
    DAY(LAST_DAY(TO_DATE(CONCAT(SUBSTR(x.mon,1,4),'-',SUBSTR(x.mon,6,2),'-01')))) AS dim,
    CASE WHEN n.in_month_cs IS NOT NULL THEN DATE_SUB(TO_DATE(n.in_month_cs), 1)
         ELSE LAST_DAY(TO_DATE(CONCAT(SUBSTR(x.mon,1,4),'-',SUBSTR(x.mon,6,2),'-01'))) END AS final_end,
    CASE WHEN n.in_month_cs IS NOT NULL THEN 'in_month_cs' ELSE 'fallback_monthend' END AS src
  FROM xl x LEFT JOIN newcs n ON n.mon = x.mon AND n.imsi = x.imsi
)
SELECT mon, xl_type, src, COUNT(1) AS cards,
  SUM(CASE WHEN DATEDIFF(final_end, TO_DATE(CONCAT(SUBSTR(mon,1,4),'-',SUBSTR(mon,6,2),'-01'))) + 1 = CAST(xl_days AS INT)
           THEN 1 ELSE 0 END) AS days_match,
  ROUND(SUM(xl_charge),2) AS excel,
  ROUND(SUM(ROUND(xl_rate/dim*(DATEDIFF(final_end, TO_DATE(CONCAT(SUBSTR(mon,1,4),'-',SUBSTR(mon,6,2),'-01'))) + 1),4)),2) AS calc,
  ROUND(SUM(ROUND(xl_rate/dim*(DATEDIFF(final_end, TO_DATE(CONCAT(SUBSTR(mon,1,4),'-',SUBSTR(mon,6,2),'-01'))) + 1),4)) - SUM(xl_charge),2) AS diff,
  ROUND(AVG(xl_days),1) AS avg_xl,
  ROUND(AVG(DATEDIFF(final_end, TO_DATE(CONCAT(SUBSTR(mon,1,4),'-',SUBSTR(mon,6,2),'-01'))) + 1),1) AS avg_calc
FROM scored GROUP BY mon, xl_type, src ORDER BY mon, xl_type, src
