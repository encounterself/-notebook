-- ============================================================================
-- 换卡旧卡（C）完整规则 · 平台自足 · 7月+8月验证
--   cycle_start = cycle_history 中 next_cycle_time 落在本月内的最早日期
--   final_end   = 作废日 - 1        （作废日 = status_log MIN(DATE(CREATE_DATE)) 且 >= 月初）
--   final_days  = DATEDIFF(final_end, cycle_start) + 1
--   charge      = final_days / 自然月天数 × 月单价
-- ============================================================================
WITH cfg AS (
  SELECT '2026-07' AS mon, '%JULY 2026%' AS pat, DATE('2026-07-01') AS d1, DATE('2026-07-31') AS d2
  UNION ALL SELECT '2026-08', '%AUGUST 2026%', DATE('2026-08-01'), DATE('2026-08-31')
),
xl AS (
  SELECT c.mon, x.imsi,
         MAX(TRY_CAST(x.final_days AS DOUBLE))   AS xl_days,
         MAX(TRY_CAST(x.monthly_rate AS DOUBLE)) AS xl_rate,
         SUM(TRY_CAST(x.final_charge AS DOUBLE)) AS xl_charge
  FROM cfg c JOIN simo_prod.mysql_cdc_sync.wa_invoice_detail x ON x.source_file LIKE c.pat
  WHERE x.charge_type = 'Partial Charge - Card Replaced Mid Cycle'
  GROUP BY c.mon, x.imsi
),
zf AS (
  SELECT c.mon, l.IMSI AS imsi, MIN(DATE(l.CREATE_DATE)) AS zf_d
  FROM cfg c JOIN simo_prod.ods.resource_res_vsim_status_log l
    ON l.NEXT_STATUS = '\u4f5c\u5e9f'
   AND DATE(l.CREATE_DATE) >= DATE_FORMAT(c.d1,'yyyy-MM-dd')
   AND DATE(l.CREATE_DATE) <= DATE_FORMAT(DATE_ADD(c.d2,30),'yyyy-MM-dd')
  GROUP BY c.mon, l.IMSI
),
cs AS (
  SELECT c.mon, hh.imsi,
         MIN(SPLIT(CAST(CAST(hh.next_cycle_time AS TIMESTAMP) - INTERVAL 5 HOURS AS STRING),' ')[0]) AS cycle_start
  FROM cfg c JOIN simo_prod.ods.resource_res_vsim_cycle_history hh
    ON SPLIT(CAST(CAST(hh.next_cycle_time AS TIMESTAMP) - INTERVAL 5 HOURS AS STRING),' ')[0]
       BETWEEN DATE_FORMAT(c.d1,'yyyy-MM-dd') AND DATE_FORMAT(c.d2,'yyyy-MM-dd')
  GROUP BY c.mon, hh.imsi
),
calc AS (
  SELECT x.*, z.zf_d, s.cycle_start,
    DAY(LAST_DAY(TO_DATE(CONCAT(SUBSTR(x.mon,1,4),'-',SUBSTR(x.mon,6,2),'-01')))) AS dim,
    DATE_SUB(z.zf_d, 1) AS final_end
  FROM xl x
  LEFT JOIN zf z ON z.mon = x.mon AND z.imsi = x.imsi
  LEFT JOIN cs s ON s.mon = x.mon AND s.imsi = x.imsi
),
f2 AS (
  SELECT *, DATEDIFF(final_end, TO_DATE(cycle_start)) + 1 AS plat_days FROM calc
)
SELECT mon, COUNT(1) AS cards,
  SUM(CASE WHEN cycle_start IS NULL THEN 1 ELSE 0 END) AS no_cycle_start,
  SUM(CASE WHEN zf_d IS NULL THEN 1 ELSE 0 END) AS no_zf,
  SUM(CASE WHEN plat_days = CAST(xl_days AS INT) THEN 1 ELSE 0 END) AS days_match,
  ROUND(SUM(xl_charge),2) AS excel,
  ROUND(SUM(ROUND(xl_rate/dim*plat_days,4)),2) AS calc,
  ROUND(SUM(ROUND(xl_rate/dim*plat_days,4)) - SUM(xl_charge),2) AS diff,
  ROUND(AVG(xl_days),1) AS avg_xl, ROUND(AVG(plat_days),1) AS avg_plat
FROM f2 GROUP BY mon ORDER BY mon
