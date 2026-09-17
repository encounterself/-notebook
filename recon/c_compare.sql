-- C 的两种算法对比（换卡旧卡）
-- 算法1：收满月（G 规则）
-- 算法2：收满月，但若 status_log 有作废记录则截断到 作废日-1
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
  WHERE x.charge_type = 'Partial Charge - Card Replaced Mid Cycle'
  GROUP BY c.mon, x.imsi
),
stop AS (
  SELECT c.mon, l.IMSI AS imsi, DATE_SUB(MAX(DATE(l.CREATE_DATE)), 1) AS cut
  FROM cfg c JOIN simo_prod.ods.resource_res_vsim_status_log l
    ON l.NEXT_STATUS = '\u4f5c\u5e9f'
   AND DATE(l.CREATE_DATE) BETWEEN DATE_FORMAT(c.d1,'yyyy-MM-dd') AND DATE_FORMAT(DATE_ADD(c.d2,30),'yyyy-MM-dd')
  GROUP BY c.mon, l.IMSI
),
scored AS (
  SELECT x.*, s.cut,
    DAY(LAST_DAY(TO_DATE(CONCAT(SUBSTR(x.mon,1,4),'-',SUBSTR(x.mon,6,2),'-01')))) AS dim,
    LAST_DAY(TO_DATE(CONCAT(SUBSTR(x.mon,1,4),'-',SUBSTR(x.mon,6,2),'-01'))) AS monthend,
    LEAST(COALESCE(s.cut, LAST_DAY(TO_DATE(CONCAT(SUBSTR(x.mon,1,4),'-',SUBSTR(x.mon,6,2),'-01')))),
          LAST_DAY(TO_DATE(CONCAT(SUBSTR(x.mon,1,4),'-',SUBSTR(x.mon,6,2),'-01')))) AS cut_end
  FROM xl x LEFT JOIN stop s ON s.mon = x.mon AND s.imsi = x.imsi
)
SELECT mon, COUNT(1) AS cards,
  SUM(CASE WHEN s.cut IS NOT NULL THEN 1 ELSE 0 END) AS has_stop_record,
  ROUND(SUM(xl_charge),2) AS excel,
  -- 算法1：收满月
  ROUND(SUM(ROUND(xl_rate/dim*dim,4)),2) AS alg1_fullmonth,
  ROUND(SUM(ROUND(xl_rate/dim*dim,4)) - SUM(xl_charge),2) AS alg1_diff,
  -- 算法2：截断到 stop
  ROUND(SUM(ROUND(xl_rate/dim*(DATEDIFF(cut_end, TO_DATE(CONCAT(SUBSTR(mon,1,4),'-',SUBSTR(mon,6,2),'-01'))) + 1),4)),2) AS alg2_truncated,
  ROUND(SUM(ROUND(xl_rate/dim*(DATEDIFF(cut_end, TO_DATE(CONCAT(SUBSTR(mon,1,4),'-',SUBSTR(mon,6,2),'-01'))) + 1),4)) - SUM(xl_charge),2) AS alg2_diff,
  SUM(CASE WHEN DATEDIFF(cut_end, TO_DATE(CONCAT(SUBSTR(mon,1,4),'-',SUBSTR(mon,6,2),'-01'))) + 1 = CAST(xl_days AS INT)
           THEN 1 ELSE 0 END) AS alg2_days_match,
  ROUND(AVG(xl_days),1) AS avg_xl_days
FROM scored s GROUP BY mon ORDER BY mon
