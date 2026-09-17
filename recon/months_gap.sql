-- 各月天数未命中的卡：按 charge_type 拆
WITH cfg AS (
  SELECT '2025-10' AS mon, 2025 AS y, 10 AS m, '%772,765%' AS pat, DATE('2025-10-01') AS d1, DATE('2025-10-31') AS d2
  UNION ALL SELECT '2025-11',2025,11,'%773,793%',DATE('2025-11-01'),DATE('2025-11-30')
  UNION ALL SELECT '2025-12',2025,12,'%DEC 2025%',DATE('2025-12-01'),DATE('2025-12-31')
  UNION ALL SELECT '2026-01',2026,1,'%JAN 2025%',DATE('2026-01-01'),DATE('2026-01-31')
  UNION ALL SELECT '2026-02',2026,2,'%FEB 2026%',DATE('2026-02-01'),DATE('2026-02-28')
  UNION ALL SELECT '2026-03',2026,3,'%MAR 2026%',DATE('2026-03-01'),DATE('2026-03-31')
  UNION ALL SELECT '2026-04',2026,4,'%APR 2026%',DATE('2026-04-01'),DATE('2026-04-30')
  UNION ALL SELECT '2026-05',2026,5,'%MAY 2026%',DATE('2026-05-01'),DATE('2026-05-31')
  UNION ALL SELECT '2026-06',2026,6,'%JUNE 2026%',DATE('2026-06-01'),DATE('2026-06-30')
  UNION ALL SELECT '2026-07',2026,7,'%JULY 2026%',DATE('2026-07-01'),DATE('2026-07-31')
  UNION ALL SELECT '2026-08',2026,8,'%AUGUST 2026%',DATE('2026-08-01'),DATE('2026-08-31')
),
xl AS (
  SELECT c.mon, x.imsi, MAX(x.charge_type) AS xl_type,
         MAX(TRY_CAST(x.final_days AS DOUBLE)) AS xl_days,
         MAX(TRY_CAST(x.monthly_rate AS DOUBLE)) AS xl_rate,
         SUM(TRY_CAST(x.final_charge AS DOUBLE)) AS xl_charge
  FROM cfg c JOIN simo_prod.mysql_cdc_sync.wa_invoice_detail x ON x.source_file LIKE c.pat
  WHERE x.final_start_date LIKE '20%'
  GROUP BY c.mon, x.imsi, x.charge_type
),
cs AS (
  SELECT c.mon, hh.imsi,
         MIN(SPLIT(CAST(CAST(hh.next_cycle_time AS TIMESTAMP) - INTERVAL 5 HOURS AS STRING),' ')[0]) AS cycle_start
  FROM cfg c JOIN simo_prod.ods.resource_res_vsim_cycle_history hh
    ON SPLIT(CAST(CAST(hh.next_cycle_time AS TIMESTAMP) - INTERVAL 5 HOURS AS STRING),' ')[0]
       BETWEEN DATE_FORMAT(c.d1,'yyyy-MM-dd') AND DATE_FORMAT(c.d2,'yyyy-MM-dd')
  GROUP BY c.mon, hh.imsi
),
zf AS (
  SELECT c.mon, l.IMSI AS imsi, MIN(DATE(l.CREATE_DATE)) AS zf_d
  FROM cfg c JOIN simo_prod.ods.resource_res_vsim_status_log l
    ON l.NEXT_STATUS='\u4f5c\u5e9f'
   AND DATE(l.CREATE_DATE) BETWEEN DATE_FORMAT(c.d1,'yyyy-MM-dd') AND DATE_FORMAT(DATE_ADD(c.d2,30),'yyyy-MM-dd')
  WHERE DATE(l.CREATE_DATE) BETWEEN '2025-08-01' AND '2026-09-30'
  GROUP BY c.mon, l.IMSI
),
act AS (
  SELECT mon, imsi, SPLIT(CAST(CAST(act_date AS TIMESTAMP) - INTERVAL 5 HOURS AS STRING),' ')[0] AS act_d5
  FROM (
    SELECT c.mon, l.IMSI AS imsi, MAX(l.CREATE_DATE) AS act_date
    FROM cfg c JOIN simo_prod.ods.resource_res_vsim_status_log l
      ON l.NEXT_STATUS='\u6fc0\u6d3b'
     AND DATE(l.CREATE_DATE) BETWEEN DATE_FORMAT(DATE_SUB(c.d1,120),'yyyy-MM-dd') AND DATE_FORMAT(DATE_ADD(c.d1,40),'yyyy-MM-dd')
    WHERE DATE(l.CREATE_DATE) BETWEEN '2025-05-01' AND '2026-09-30'
    GROUP BY c.mon, l.IMSI
  ) t
),
sn AS (
  SELECT c.mon, s.imsi,
         MAX(SPLIT(s.Cycle_End_Time,' ')[0]) AS max_ce,
         MIN(CASE WHEN SPLIT(s.Cycle_Start_Time,' ')[0] >= DATE_FORMAT(DATE_ADD(c.d1,1),'yyyy-MM-dd')
                  THEN SPLIT(s.Cycle_Start_Time,' ')[0] END) AS min_cs_after_1st
  FROM cfg c JOIN simo_prod.tc_cdr.sim_status_for_sftp_bak s ON s.year=c.y AND s.month=c.m
  WHERE s.year = 2026 OR (s.year = 2025 AND s.month >= 9)
  GROUP BY c.mon, s.imsi
),
f AS (
  SELECT x.*, DAY(LAST_DAY(c.d1)) AS dim, c.d1 AS mstart, c.d2 AS mend,
    CASE
      WHEN x.xl_type='Partial Charge - Card Replaced Mid Cycle' THEN TO_DATE(cs.cycle_start)
      WHEN x.xl_type='Partial Charge - New Card Used as Replacement Mid Cycle' THEN DATE_ADD(TO_DATE(a.act_d5),1)
      ELSE c.d1 END AS final_start,
    CASE
      WHEN x.xl_type='Partial Charge - Card Replaced Mid Cycle' THEN COALESCE(DATE_SUB(zf.zf_d,1), c.d2)
      WHEN x.xl_type='Partial Charge - New Card Used as Replacement Mid Cycle' THEN COALESCE(DATE_SUB(TO_DATE(sn.max_ce),1), c.d2)
      WHEN x.xl_type='New Activation: Prorated-in Charge' THEN COALESCE(DATE_SUB(TO_DATE(sn.min_cs_after_1st),1), c.d2)
      ELSE c.d2 END AS final_end
  FROM xl x JOIN cfg c ON c.mon = x.mon
  LEFT JOIN cs ON cs.mon=x.mon AND cs.imsi=x.imsi
  LEFT JOIN zf ON zf.mon=x.mon AND zf.imsi=x.imsi
  LEFT JOIN act a ON a.mon=x.mon AND a.imsi=x.imsi
  LEFT JOIN sn ON sn.mon=x.mon AND sn.imsi=x.imsi
),
f2 AS (SELECT *, DATEDIFF(final_end, final_start)+1 AS plat_days FROM f)
SELECT mon, xl_type, COUNT(1) AS cards,
  SUM(CASE WHEN plat_days <> CAST(xl_days AS INT) THEN 1 ELSE 0 END) AS days_mismatch,
  ROUND(SUM(xl_charge),2) AS excel,
  ROUND(SUM(ROUND(xl_rate/dim*plat_days,4)),2) AS calc,
  ROUND(SUM(ROUND(xl_rate/dim*plat_days,4))-SUM(xl_charge),2) AS diff
FROM f2
GROUP BY mon, xl_type
HAVING ABS(SUM(ROUND(xl_rate/dim*plat_days,4))-SUM(xl_charge)) > 500
ORDER BY diff DESC
