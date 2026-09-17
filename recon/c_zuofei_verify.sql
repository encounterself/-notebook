-- 最终验证：换卡类 final_end = DATE(作废时间戳 - 5小时)
-- final_days = DATEDIFF(final_end, 月初) + 1
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
  WHERE x.charge_type IN ('Partial Charge - Card Replaced Mid Cycle',
                          'Partial Charge - New Card Used as Replacement Mid Cycle')
  GROUP BY c.mon, x.imsi
),
zf AS (
  SELECT c.mon, l.IMSI AS imsi,
         MIN(SPLIT(CAST(CAST(l.CREATE_DATE AS TIMESTAMP) - INTERVAL 5 HOURS AS STRING),' ')[0]) AS zuofei_d
  FROM cfg c JOIN simo_prod.ods.resource_res_vsim_status_log l
    ON l.NEXT_STATUS = '\u4f5c\u5e9f'
   AND DATE(l.CREATE_DATE) >= DATE_FORMAT(c.d1,'yyyy-MM-dd')
   AND DATE(l.CREATE_DATE) <= DATE_FORMAT(DATE_ADD(c.d2,30),'yyyy-MM-dd')
  GROUP BY c.mon, l.IMSI
),
scored AS (
  SELECT x.*, z.zuofei_d,
    DAY(LAST_DAY(TO_DATE(CONCAT(SUBSTR(x.mon,1,4),'-',SUBSTR(x.mon,6,2),'-01')))) AS dim,
    COALESCE(TO_DATE(z.zuofei_d),
             LAST_DAY(TO_DATE(CONCAT(SUBSTR(x.mon,1,4),'-',SUBSTR(x.mon,6,2),'-01')))) AS final_end
  FROM xl x LEFT JOIN zf z ON z.mon = x.mon AND z.imsi = x.imsi
)
SELECT mon, xl_type, COUNT(1) AS cards,
  SUM(CASE WHEN zuofei_d IS NULL THEN 1 ELSE 0 END) AS no_zuofei,
  SUM(CASE WHEN DATEDIFF(final_end, TO_DATE(CONCAT(SUBSTR(mon,1,4),'-',SUBSTR(mon,6,2),'-01'))) + 1 = CAST(xl_days AS INT)
           THEN 1 ELSE 0 END) AS days_match,
  ROUND(SUM(xl_charge),2) AS excel,
  ROUND(SUM(ROUND(xl_rate/dim*(DATEDIFF(final_end, TO_DATE(CONCAT(SUBSTR(mon,1,4),'-',SUBSTR(mon,6,2),'-01'))) + 1),4)),2) AS calc,
  ROUND(SUM(ROUND(xl_rate/dim*(DATEDIFF(final_end, TO_DATE(CONCAT(SUBSTR(mon,1,4),'-',SUBSTR(mon,6,2),'-01'))) + 1),4)) - SUM(xl_charge),2) AS diff,
  ROUND(AVG(xl_days),1) AS avg_xl,
  ROUND(AVG(DATEDIFF(final_end, TO_DATE(CONCAT(SUBSTR(mon,1,4),'-',SUBSTR(mon,6,2),'-01'))) + 1),1) AS avg_calc
FROM scored GROUP BY mon, xl_type ORDER BY mon, xl_type
