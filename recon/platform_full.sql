-- ============================================================================
-- 平台全量口径 · 11 个月（2025-10 ~ 2026-08）· 可靠实现
--   pres 聚合：先过滤产品（排除 PI/Unassigned）再聚合
--   C/D/E 用四类规则；G 与平台独有卡按「整月在网→满月，否则在网天数」
-- ============================================================================
WITH cfg AS (
  SELECT '2025-10' AS mon, 2025 AS y, 10 AS m, '%772,765%' AS pat, DATE('2025-10-01') AS d1, DATE('2025-10-31') AS d2
  UNION ALL SELECT '2025-11', 2025, 11, '%773,793%', DATE('2025-11-01'), DATE('2025-11-30')
  UNION ALL SELECT '2025-12', 2025, 12, '%DEC 2025%', DATE('2025-12-01'), DATE('2025-12-31')
  UNION ALL SELECT '2026-01', 2026,  1, '%JAN 2025%', DATE('2026-01-01'), DATE('2026-01-31')
  UNION ALL SELECT '2026-02', 2026,  2, '%FEB 2026%', DATE('2026-02-01'), DATE('2026-02-28')
  UNION ALL SELECT '2026-03', 2026,  3, '%MAR 2026%', DATE('2026-03-01'), DATE('2026-03-31')
  UNION ALL SELECT '2026-04', 2026,  4, '%APR 2026%', DATE('2026-04-01'), DATE('2026-04-30')
  UNION ALL SELECT '2026-05', 2026,  5, '%MAY 2026%', DATE('2026-05-01'), DATE('2026-05-31')
  UNION ALL SELECT '2026-06', 2026,  6, '%JUNE 2026%', DATE('2026-06-01'), DATE('2026-06-30')
  UNION ALL SELECT '2026-07', 2026,  7, '%JULY 2026%', DATE('2026-07-01'), DATE('2026-07-31')
  UNION ALL SELECT '2026-08', 2026,  8, '%AUGUST 2026%', DATE('2026-08-01'), DATE('2026-08-31')
),
-- ① 先过滤，再聚合
snap_f AS (
  SELECT c.mon, s.imsi, s.product_id, DATE(s.partition_time) AS d
  FROM cfg c JOIN simo_prod.tc_cdr.sim_status_for_sftp_bak s ON s.year=c.y AND s.month=c.m
  JOIN simo_prod.ods.resource_res_vsim_product p ON p.product_id = s.product_id
  WHERE p.supplier_id = 2275 AND p.product_name NOT LIKE '%PI%'
    AND p.product_id <> '600111094'
    AND ((s.year = 2025 AND s.month >= 10) OR s.year = 2026)
  GROUP BY c.mon, s.imsi, s.product_id, DATE(s.partition_time)
),
pres AS (
  SELECT mon, imsi, MAX(product_id) AS pid,
         MIN(d) AS first_seen, MAX(d) AS last_seen, COUNT(1) AS pres_days
  FROM snap_f GROUP BY mon, imsi
),
pr AS (SELECT product_id, CAST(package_price AS DOUBLE) AS price
       FROM simo_prod.ods.resource_res_vsim_product),
xl AS (
  SELECT c.mon, x.imsi, MAX(x.charge_type) AS xl_type,
         SUM(TRY_CAST(x.final_charge AS DOUBLE)) AS xl_charge
  FROM cfg c JOIN simo_prod.mysql_cdc_sync.wa_invoice_detail x ON x.source_file LIKE c.pat
  WHERE x.final_start_date LIKE '20%'
  GROUP BY c.mon, x.imsi
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
    ON l.NEXT_STATUS = '\u4f5c\u5e9f'
   AND DATE(l.CREATE_DATE) BETWEEN DATE_FORMAT(c.d1,'yyyy-MM-dd') AND DATE_FORMAT(DATE_ADD(c.d2,30),'yyyy-MM-dd')
  WHERE DATE(l.CREATE_DATE) BETWEEN '2025-08-01' AND '2026-09-30'
  GROUP BY c.mon, l.IMSI
),
act AS (
  SELECT mon, imsi, SPLIT(CAST(CAST(act_date AS TIMESTAMP) - INTERVAL 5 HOURS AS STRING),' ')[0] AS act_d5
  FROM (
    SELECT c.mon, l.IMSI AS imsi, MAX(l.CREATE_DATE) AS act_date
    FROM cfg c JOIN simo_prod.ods.resource_res_vsim_status_log l
      ON l.NEXT_STATUS = '\u6fc0\u6d3b'
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
  WHERE ((s.year = 2025 AND s.month >= 10) OR s.year = 2026)
  GROUP BY c.mon, s.imsi
),
calc AS (
  SELECT p.mon, p.imsi, p.first_seen, p.last_seen, p.pres_days,
         x.xl_type, x.xl_charge, pr.price AS package_price,
         z.zf_d, cs.cycle_start, a.act_d5, sn.max_ce, sn.min_cs_after_1st,
         DAY(LAST_DAY(c.d1)) AS dim, c.d1 AS mstart, c.d2 AS mend
  FROM pres p JOIN cfg c ON c.mon = p.mon
  LEFT JOIN xl x ON x.mon = p.mon AND x.imsi = p.imsi
  LEFT JOIN pr ON pr.product_id = p.pid
  LEFT JOIN zf z  ON z.mon = p.mon AND z.imsi = p.imsi
  LEFT JOIN cs    ON cs.mon = p.mon AND cs.imsi = p.imsi
  LEFT JOIN act a ON a.mon = p.mon AND a.imsi = p.imsi
  LEFT JOIN sn    ON sn.mon = p.mon AND sn.imsi = p.imsi
),
f AS (
  SELECT *,
    CASE
      WHEN xl_type = 'Partial Charge - Card Replaced Mid Cycle'
        THEN COALESCE(DATEDIFF(COALESCE(DATE_SUB(zf_d,1), mend), TO_DATE(cycle_start)) + 1, dim)
      WHEN xl_type = 'Partial Charge - New Card Used as Replacement Mid Cycle'
        THEN COALESCE(DATEDIFF(COALESCE(DATE_SUB(TO_DATE(max_ce),1), mend), DATE_ADD(TO_DATE(act_d5),1)) + 1, dim)
      WHEN xl_type = 'New Activation: Prorated-in Charge'
        THEN COALESCE(DATEDIFF(COALESCE(DATE_SUB(TO_DATE(min_cs_after_1st),1), mend), mstart) + 1, dim)
      ELSE NULL
    END AS rule_days
  FROM calc
),
f2 AS (
  SELECT *,
    COALESCE(rule_days,
             CASE WHEN first_seen = mstart AND last_seen = mend THEN dim ELSE pres_days END) AS plat_days
  FROM f
)
SELECT mon, COUNT(1) AS plat_cards,
       SUM(CASE WHEN xl_charge IS NOT NULL THEN 1 ELSE 0 END) AS in_xl,
       SUM(CASE WHEN xl_charge IS NULL THEN 1 ELSE 0 END)     AS plat_only,
       ROUND(SUM(ROUND(package_price/dim*plat_days,4)),2)     AS plat_total,
       ROUND(SUM(COALESCE(xl_charge,0)),2)                    AS xl_total,
       ROUND(SUM(ROUND(package_price/dim*plat_days,4)) - SUM(COALESCE(xl_charge,0)),2) AS diff,
       ROUND(100.0*(SUM(ROUND(package_price/dim*plat_days,4)) - SUM(COALESCE(xl_charge,0)))
             /NULLIF(SUM(COALESCE(xl_charge,0)),0),2) AS diff_pct
FROM f2 GROUP BY mon ORDER BY mon
