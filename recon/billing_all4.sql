-- ============================================================================
-- WA 当月费用复算 · 全部四类规则（G + C + D + E）· 平台侧自足 · 7月 + 8月
-- ============================================================================
WITH cfg AS (
  SELECT '2026-07' AS mon, '%JULY 2026%' AS pat, 2026 AS y, 7 AS m,
         DATE('2026-07-01') AS d1, DATE('2026-07-31') AS d2
  UNION ALL SELECT '2026-08', '%AUGUST 2026%', 2026, 8, DATE('2026-08-01'), DATE('2026-08-31')
),

-- Excel 真值（仅对账用，规则不依赖）
xl AS (
  SELECT c.mon, x.imsi, MAX(x.charge_type) AS xl_type,
         MAX(TRY_CAST(x.final_days AS DOUBLE))   AS xl_days,
         MAX(TRY_CAST(x.usage_days AS DOUBLE))   AS xl_usage,
         MAX(TRY_CAST(x.monthly_rate AS DOUBLE)) AS xl_rate,
         SUM(TRY_CAST(x.final_charge AS DOUBLE)) AS xl_charge
  FROM cfg c JOIN simo_prod.mysql_cdc_sync.wa_invoice_detail x ON x.source_file LIKE c.pat
  WHERE x.charge_type IN ('Full Cycle Charge',
                          'Partial Charge - Card Replaced Mid Cycle',
                          'Partial Charge - New Card Used as Replacement Mid Cycle',
                          'New Activation: Prorated-in Charge')
  GROUP BY c.mon, x.imsi, x.charge_type
),

-- 【C】账期起点：cycle_history 中 next_cycle_time 落在本月内的最早日期
cs AS (
  SELECT c.mon, hh.imsi,
         MIN(SPLIT(CAST(CAST(hh.next_cycle_time AS TIMESTAMP) - INTERVAL 5 HOURS AS STRING),' ')[0]) AS cycle_start
  FROM cfg c JOIN simo_prod.ods.resource_res_vsim_cycle_history hh
    ON SPLIT(CAST(CAST(hh.next_cycle_time AS TIMESTAMP) - INTERVAL 5 HOURS AS STRING),' ')[0]
       BETWEEN DATE_FORMAT(c.d1,'yyyy-MM-dd') AND DATE_FORMAT(c.d2,'yyyy-MM-dd')
  GROUP BY c.mon, hh.imsi
),

-- 【C】作废日
zf AS (
  SELECT c.mon, l.IMSI AS imsi, MIN(DATE(l.CREATE_DATE)) AS zf_d
  FROM cfg c JOIN simo_prod.ods.resource_res_vsim_status_log l
    ON l.NEXT_STATUS = '\u4f5c\u5e9f'
   AND DATE(l.CREATE_DATE) >= DATE_FORMAT(c.d1,'yyyy-MM-dd')
   AND DATE(l.CREATE_DATE) <= DATE_FORMAT(DATE_ADD(c.d2,30),'yyyy-MM-dd')
  GROUP BY c.mon, l.IMSI
),

-- 【D】激活日（减 5 小时后取日期）
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

-- 【D/E】当月快照的账期极值
sn AS (
  SELECT c.mon, s.imsi,
         MAX(SPLIT(s.Cycle_End_Time,' ')[0])   AS max_ce,
         MIN(SPLIT(s.Cycle_Start_Time,' ')[0]) AS min_cs,
         MIN(CASE WHEN SPLIT(s.Cycle_Start_Time,' ')[0] >= DATE_FORMAT(DATE_ADD(c.d1,1),'yyyy-MM-dd')
                  THEN SPLIT(s.Cycle_Start_Time,' ')[0] END) AS min_cs_after_1st
  FROM cfg c JOIN simo_prod.tc_cdr.sim_status_for_sftp_bak s ON s.year=c.y AND s.month=c.m
  GROUP BY c.mon, s.imsi
),

calc AS (
  SELECT x.*, z.zf_d, cs.cycle_start, a.act_d5, s.max_ce, s.min_cs, s.min_cs_after_1st,
         DAY(LAST_DAY(c.d1)) AS dim, c.d1 AS mstart, c.d2 AS mend
  FROM xl x JOIN cfg c ON c.mon = x.mon
  LEFT JOIN zf z  ON z.mon = x.mon AND z.imsi = x.imsi
  LEFT JOIN cs    ON cs.mon = x.mon AND cs.imsi = x.imsi
  LEFT JOIN act a ON a.mon = x.mon AND a.imsi = x.imsi
  LEFT JOIN sn  s ON s.mon = x.mon AND s.imsi = x.imsi
),

f AS (
  SELECT *,
    CASE
      WHEN xl_type = 'Partial Charge - Card Replaced Mid Cycle'
        THEN TO_DATE(cycle_start)
      WHEN xl_type = 'Partial Charge - New Card Used as Replacement Mid Cycle'
        THEN DATE_ADD(TO_DATE(act_d5), 1)
      ELSE mstart
    END AS final_start,
    CASE
      WHEN xl_type = 'Partial Charge - Card Replaced Mid Cycle'
        THEN COALESCE(DATE_SUB(zf_d, 1), mend)
      WHEN xl_type = 'Partial Charge - New Card Used as Replacement Mid Cycle'
        THEN COALESCE(DATE_SUB(TO_DATE(max_ce), 1), mend)
      WHEN xl_type = 'New Activation: Prorated-in Charge'
        THEN COALESCE(DATE_SUB(TO_DATE(min_cs_after_1st), 1), mend)
      ELSE mend
    END AS final_end
  FROM calc
),

f2 AS (SELECT *, DATEDIFF(final_end, final_start) + 1 AS plat_days FROM f)

SELECT mon,
  CASE WHEN xl_type = 'Full Cycle Charge' THEN 'G_整月卡'
       WHEN xl_type = 'Partial Charge - Card Replaced Mid Cycle' THEN 'C_换卡旧卡'
       WHEN xl_type = 'Partial Charge - New Card Used as Replacement Mid Cycle' THEN 'D_换卡新卡'
       WHEN xl_type = 'New Activation: Prorated-in Charge' THEN 'E_新激活'
       ELSE xl_type END AS kind,
  COUNT(1) AS cards,
  SUM(CASE WHEN plat_days = CAST(xl_days AS INT) THEN 1 ELSE 0 END) AS days_match,
  SUM(CASE WHEN plat_days <> CAST(xl_days AS INT)
            AND CAST(xl_days AS INT) = CAST(xl_usage AS INT) THEN 1 ELSE 0 END) AS unmatched_is_usage,
  ROUND(SUM(xl_charge),2) AS excel,
  ROUND(SUM(ROUND(xl_rate/dim*plat_days,4)),2) AS calc,
  ROUND(SUM(ROUND(xl_rate/dim*plat_days,4)) - SUM(xl_charge),2) AS diff
FROM f2 GROUP BY mon, 2 ORDER BY mon, kind
