-- 区分信号：该卡在【本月内】是否还有一条 history（cycle_time 落在本月）
-- 有 → 进了新账期 → final_end = 该新账期起点 - 1
-- 无 → 账期是上月带过来的 → final_end = 月末
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
-- 本月内的 history 记录（cycle_time 落在本月）
inmonth AS (
  SELECT c.mon, hh.imsi,
         MIN(SPLIT(CAST(CAST(hh.cycle_time AS TIMESTAMP) - INTERVAL 5 HOURS AS STRING),' ')[0]) AS ct_in_month
  FROM cfg c JOIN simo_prod.ods.resource_res_vsim_cycle_history hh
    ON SPLIT(CAST(CAST(hh.cycle_time AS TIMESTAMP) - INTERVAL 5 HOURS AS STRING),' ')[0]
       BETWEEN DATE_FORMAT(c.d1,'yyyy-MM-dd') AND DATE_FORMAT(c.d2,'yyyy-MM-dd')
  GROUP BY c.mon, hh.imsi
),
scored AS (
  SELECT x.*, m.ct_in_month,
    DAY(LAST_DAY(TO_DATE(CONCAT(SUBSTR(x.mon,1,4),'-',SUBSTR(x.mon,6,2),'-01')))) AS dim,
    -- 方向反转：有本月内新账期 → 月末；无 → 用 next_cycle_time 截断
    CASE WHEN m.ct_in_month IS NOT NULL
         THEN LAST_DAY(TO_DATE(CONCAT(SUBSTR(x.mon,1,4),'-',SUBSTR(x.mon,6,2),'-01')))
         ELSE LAST_DAY(TO_DATE(CONCAT(SUBSTR(x.mon,1,4),'-',SUBSTR(x.mon,6,2),'-01'))) END AS final_end,
    CASE WHEN m.ct_in_month IS NOT NULL THEN 'has_inmonth_cycle' ELSE 'no_inmonth_cycle' END AS src
  FROM xl x LEFT JOIN inmonth m ON m.mon = x.mon AND m.imsi = x.imsi
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
