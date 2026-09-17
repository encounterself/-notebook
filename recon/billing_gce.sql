-- ============================================================================
-- WA 当月费用复算 · 已落地规则（G + C + E）· 平台侧自足 · 7月 + 8月验证
--
-- 【G 整月卡】final_start = 月初，final_end = 月末          → $0.00 ✅
-- 【C 换卡旧卡】final_start = cycle_history.next_cycle_time（落本月内）
--               final_end   = MIN(status_log 作废日) − 1    → −$97 / −$133
-- 【E 新激活】final_start = 月初，final_end = 新账期起点 − 1  → −$21
-- 【D 换卡新卡】未打通，暂不计入
-- ============================================================================
WITH cfg AS (
  SELECT '2026-07' AS mon, '%JULY 2026%' AS pat, 2026 AS y, 7 AS m,
         DATE('2026-07-01') AS d1, DATE('2026-07-31') AS d2
  UNION ALL SELECT '2026-08', '%AUGUST 2026%', 2026, 8, DATE('2026-08-01'), DATE('2026-08-31')
),

-- Excel 真值（仅用于对账，规则本身不依赖）
xl AS (
  SELECT c.mon, x.imsi, MAX(x.charge_type) AS xl_type,
         MAX(TRY_CAST(x.final_days AS DOUBLE))   AS xl_days,
         MAX(TRY_CAST(x.monthly_rate AS DOUBLE)) AS xl_rate,
         SUM(TRY_CAST(x.final_charge AS DOUBLE)) AS xl_charge
  FROM cfg c JOIN simo_prod.mysql_cdc_sync.wa_invoice_detail x ON x.source_file LIKE c.pat
  WHERE x.charge_type IN ('Full Cycle Charge',
                          'Partial Charge - Card Replaced Mid Cycle',
                          'New Activation: Prorated-in Charge')
  GROUP BY c.mon, x.imsi, x.charge_type
),

-- C：账期起点（cycle_history 中 next_cycle_time 落在本月内的最早日期）
cs AS (
  SELECT c.mon, hh.imsi,
         MIN(SPLIT(CAST(CAST(hh.next_cycle_time AS TIMESTAMP) - INTERVAL 5 HOURS AS STRING),' ')[0]) AS cycle_start
  FROM cfg c JOIN simo_prod.ods.resource_res_vsim_cycle_history hh
    ON SPLIT(CAST(CAST(hh.next_cycle_time AS TIMESTAMP) - INTERVAL 5 HOURS AS STRING),' ')[0]
       BETWEEN DATE_FORMAT(c.d1,'yyyy-MM-dd') AND DATE_FORMAT(c.d2,'yyyy-MM-dd')
  GROUP BY c.mon, hh.imsi
),

-- C：作废日
zf AS (
  SELECT c.mon, l.IMSI AS imsi, MIN(DATE(l.CREATE_DATE)) AS zf_d
  FROM cfg c JOIN simo_prod.ods.resource_res_vsim_status_log l
    ON l.NEXT_STATUS = '\u4f5c\u5e9f'
   AND DATE(l.CREATE_DATE) >= DATE_FORMAT(c.d1,'yyyy-MM-dd')
   AND DATE(l.CREATE_DATE) <= DATE_FORMAT(DATE_ADD(c.d2,30),'yyyy-MM-dd')
  GROUP BY c.mon, l.IMSI
),

-- E：新账期起点（同 cs，但语义是用 next_cycle_time 作为新周期起点）
nct AS (
  SELECT c.mon, s.imsi,
         MIN(SPLIT(s.Cycle_Start_Time,' ')[0]) AS min_cs_in_month
  FROM cfg c JOIN simo_prod.tc_cdr.sim_status_for_sftp_bak s ON s.year=c.y AND s.month=c.m
  WHERE SPLIT(s.Cycle_Start_Time,' ')[0] >= DATE_FORMAT(DATE_ADD(c.d1,1),'yyyy-MM-dd')
  GROUP BY c.mon, s.imsi
),

calc AS (
  SELECT x.*, z.zf_d, cs.cycle_start, n.min_cs_in_month,
         DAY(LAST_DAY(c.d1)) AS dim,
         c.d1 AS mstart, c.d2 AS mend
  FROM xl x JOIN cfg c ON c.mon = x.mon
  LEFT JOIN zf z ON z.mon = x.mon AND z.imsi = x.imsi
  LEFT JOIN cs   ON cs.mon = x.mon AND cs.imsi = x.imsi
  LEFT JOIN nct n ON n.mon = x.mon AND n.imsi = x.imsi
),

f AS (
  SELECT *,
    CASE
      WHEN xl_type = 'Partial Charge - Card Replaced Mid Cycle'
        THEN TO_DATE(cycle_start)
      ELSE mstart
    END AS final_start,
    CASE
      WHEN xl_type = 'Partial Charge - Card Replaced Mid Cycle'
        THEN COALESCE(DATE_SUB(zf_d, 1), mend)
      WHEN xl_type = 'New Activation: Prorated-in Charge'
        THEN COALESCE(DATE_SUB(TO_DATE(min_cs_in_month), 1), mend)
      ELSE mend
    END AS final_end
  FROM calc
),

f2 AS (
  SELECT *, DATEDIFF(final_end, final_start) + 1 AS plat_days FROM f
)

SELECT mon,
  CASE WHEN xl_type = 'Full Cycle Charge' THEN 'G_整月卡'
       WHEN xl_type = 'Partial Charge - Card Replaced Mid Cycle' THEN 'C_换卡旧卡'
       WHEN xl_type = 'New Activation: Prorated-in Charge' THEN 'E_新激活'
       ELSE xl_type END AS kind,
  COUNT(1) AS cards,
  SUM(CASE WHEN plat_days = CAST(xl_days AS INT) THEN 1 ELSE 0 END) AS days_match,
  ROUND(SUM(xl_charge),2) AS excel,
  ROUND(SUM(ROUND(xl_rate/dim*plat_days,4)),2) AS calc,
  ROUND(SUM(ROUND(xl_rate/dim*plat_days,4)) - SUM(xl_charge),2) AS diff
FROM f2 GROUP BY mon, 2 ORDER BY mon, kind
