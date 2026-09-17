-- 8月：完整逻辑（C/D/E 用规则，其余用满月/在网）
WITH cfg AS (
  SELECT '2026-08' AS mon, 2026 AS y, 8 AS m, '%AUGUST 2026%' AS pat,
         DATE('2026-08-01') AS d1, DATE('2026-08-31') AS d2
),
snap_f AS (
  SELECT c.mon, s.imsi, s.product_id, DATE(s.partition_time) AS d
  FROM cfg c JOIN simo_prod.tc_cdr.sim_status_for_sftp_bak s ON s.year=c.y AND s.month=c.m
  JOIN simo_prod.ods.resource_res_vsim_product p ON p.product_id = s.product_id
  WHERE p.supplier_id=2275 AND p.product_name NOT LIKE '%PI%' AND p.product_id <> '600111094'
    AND ((s.year=2025 AND s.month>=10) OR s.year=2026)
  GROUP BY c.mon, s.imsi, s.product_id, DATE(s.partition_time)
),
pres AS (
  SELECT mon, imsi, MAX(product_id) AS pid, MIN(d) AS fs, MAX(d) AS ls, COUNT(1) AS pd
  FROM snap_f GROUP BY mon, imsi
),
pr AS (SELECT product_id, CAST(package_price AS DOUBLE) AS price FROM simo_prod.ods.resource_res_vsim_product),
xl AS (
  SELECT imsi, MAX(charge_type) AS ct, SUM(TRY_CAST(final_charge AS DOUBLE)) AS chg
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE source_file LIKE '%AUGUST 2026%' AND final_start_date LIKE '20%' GROUP BY imsi
),
cs AS (
  SELECT hh.imsi, MIN(SPLIT(CAST(CAST(hh.next_cycle_time AS TIMESTAMP)-INTERVAL 5 HOURS AS STRING),' ')[0]) AS cstart
  FROM simo_prod.ods.resource_res_vsim_cycle_history hh
  JOIN cfg c ON 1=1
  WHERE SPLIT(CAST(CAST(hh.next_cycle_time AS TIMESTAMP)-INTERVAL 5 HOURS AS STRING),' ')[0] BETWEEN '2026-08-01' AND '2026-08-31'
  GROUP BY hh.imsi
),
zf AS (
  SELECT l.IMSI AS imsi, MIN(DATE(l.CREATE_DATE)) AS zfd
  FROM simo_prod.ods.resource_res_vsim_status_log l
  WHERE l.NEXT_STATUS='\u4f5c\u5e9f' AND DATE(l.CREATE_DATE) BETWEEN '2026-08-01' AND '2026-09-30'
  GROUP BY l.IMSI
),
act AS (
  SELECT imsi, SPLIT(CAST(CAST(MAX(CREATE_DATE) AS TIMESTAMP)-INTERVAL 5 HOURS AS STRING),' ')[0] AS actd
  FROM simo_prod.ods.resource_res_vsim_status_log
  WHERE NEXT_STATUS='\u6fc0\u6d3b' AND DATE(CREATE_DATE) BETWEEN '2026-04-01' AND '2026-09-10'
  GROUP BY imsi
),
sn AS (
  SELECT s.imsi, MAX(SPLIT(s.Cycle_End_Time,' ')[0]) AS mce,
         MIN(CASE WHEN SPLIT(s.Cycle_Start_Time,' ')[0] >= '2026-08-02' THEN SPLIT(s.Cycle_Start_Time,' ')[0] END) AS mcs2
  FROM simo_prod.tc_cdr.sim_status_for_sftp_bak s
  WHERE s.year=2026 AND s.month=8 GROUP BY s.imsi
),
f AS (
  SELECT p.imsi, p.fs, p.ls, p.pd, pr.price, x.ct, x.chg,
         cs.cstart, zf.zfd, a.actd, sn.mce, sn.mcs2, c.d1 AS mst, c.d2 AS mnd,
         DAY(LAST_DAY(c.d1)) AS dim
  FROM pres p JOIN cfg c ON c.mon = p.mon
  LEFT JOIN pr ON pr.product_id = p.pid
  LEFT JOIN xl x ON x.imsi = p.imsi
  LEFT JOIN cs ON cs.imsi = p.imsi
  LEFT JOIN zf ON zf.imsi = p.imsi
  LEFT JOIN act a ON a.imsi = p.imsi
  LEFT JOIN sn ON sn.imsi = p.imsi
),
f2 AS (
  SELECT *,
    CASE
      WHEN ct = 'Partial Charge - Card Replaced Mid Cycle'
        THEN COALESCE(DATEDIFF(DATE_SUB(zfd,1), TO_DATE(cstart)) + 1, dim)
      WHEN ct = 'Partial Charge - New Card Used as Replacement Mid Cycle'
        THEN COALESCE(DATEDIFF(DATE_SUB(TO_DATE(mce),1), DATE_ADD(TO_DATE(actd),1)) + 1, dim)
      WHEN ct = 'New Activation: Prorated-in Charge'
        THEN COALESCE(DATEDIFF(DATE_SUB(TO_DATE(mcs2),1), mst) + 1, dim)
      WHEN fs = mst AND ls = mnd THEN dim
      ELSE pd
    END AS plat_days
  FROM f
)
SELECT COUNT(1) AS cards,
  ROUND(SUM(ROUND(price/dim*plat_days,4)),2) AS plat_total,
  ROUND(SUM(COALESCE(chg,0)),2) AS xl_total,
  ROUND(SUM(ROUND(price/dim*plat_days,4)) - SUM(COALESCE(chg,0)),2) AS diff
FROM f2
