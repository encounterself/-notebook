-- ============================================================================
-- 四类规则全量验证 · 平台自足 · 7月 + 8月
--   G 整月卡   : final_end = 月末                        final_start = 月初
--   C 换卡旧卡 : final_end = 作废日-1                    final_start = cycle_start
--   D 换卡新卡 : final_end = 月末                        final_start = cycle_start
--   E 新激活   : final_end = 新账期起点-1                final_start = 月初
-- ============================================================================
WITH cfg AS (
  SELECT '2026-07' AS mon, '%JULY 2026%' AS pat, DATE('2026-07-01') AS d1, DATE('2026-07-31') AS d2
  UNION ALL SELECT '2026-08', '%AUGUST 2026%', DATE('2026-08-01'), DATE('2026-08-31')
),
xl AS (
  SELECT c.mon, x.imsi, MAX(x.charge_type) AS xl_type,
         MAX(TRY_CAST(x.final_days AS DOUBLE))   AS xl_days,
         MAX(TRY_CAST(x.monthly_rate AS DOUBLE)) AS xl_rate,
         SUM(TRY_CAST(x.final_charge AS DOUBLE)) AS xl_charge
  FROM cfg c JOIN simo_prod.mysql_cdc_sync.wa_invoice_detail x ON x.source_file LIKE c.pat
  GROUP BY c.mon, x.imsi, x.charge_type
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
         MIN(SPLIT(CAST(CAST(hh.next_cycle_time AS TIMESTAMP) - INTERVAL 5 HOURS AS STRING),' ')[0]) AS cycle_start,
         COUNT(1) AS n_hist
  FROM cfg c JOIN simo_prod.ods.resource_res_vsim_cycle_history hh
    ON SPLIT(CAST(CAST(hh.next_cycle_time AS TIMESTAMP) - INTERVAL 5 HOURS AS STRING),' ')[0]
       BETWEEN DATE_FORMAT(c.d1,'yyyy-MM-dd') AND DATE_FORMAT(c.d2,'yyyy-MM-dd')
  GROUP BY c.mon, hh.imsi
),
inmonth_ct AS (
  SELECT c.mon, s.imsi, COUNT(1) AS n
  FROM cfg c JOIN simo_prod.tc_cdr.sim_status_for_sftp_bak s
    ON s.year = CAST(SUBSTR(c.mon,1,4) AS INT) AND s.month = CAST(SUBSTR(c.mon,6,2) AS INT)
   AND SPLIT(s.Cycle_Start_Time,' ')[0] BETWEEN DATE_FORMAT(c.d1,'yyyy-MM-dd') AND DATE_FORMAT(c.d2,'yyyy-MM-dd')
  GROUP BY c.mon, s.imsi
),
calc AS (
  SELECT x.*, z.zf_d, cs.cycle_start,
    DAY(LAST_DAY(TO_DATE(CONCAT(SUBSTR(x.mon,1,4),'-',SUBSTR(x.mon,6,2),'-01')))) AS dim,
    TO_DATE(CONCAT(SUBSTR(x.mon,1,4),'-',SUBSTR(x.mon,6,2),'-01')) AS month_start,
    LAST_DAY(TO_DATE(CONCAT(SUBSTR(x.mon,1,4),'-',SUBSTR(x.mon,6,2),'-01'))) AS month_end,
    DATE_SUB(z.zf_d, 1) AS zf_minus1
  FROM xl x
  LEFT JOIN zf z  ON z.mon = x.mon AND z.imsi = x.imsi
  LEFT JOIN cs    ON cs.mon = x.mon AND cs.imsi = x.imsi
),
f2 AS (
  SELECT *,
    CASE
      WHEN xl_type = 'Partial Charge - Card Replaced Mid Cycle'
        THEN COALESCE(zf_minus1, month_end)                                    -- C
      WHEN xl_type = 'Partial Charge - New Card Used as Replacement Mid Cycle'
        THEN month_end                                                          -- D
      WHEN xl_type = 'New Activation: Prorated-in Charge'
        THEN DATE_SUB(TO_DATE(cycle_start), 1)                                  -- E
      ELSE month_end                                                            -- G
    END AS final_end,
    CASE
      WHEN xl_type IN ('Partial Charge - Card Replaced Mid Cycle',
                       'Partial Charge - New Card Used as Replacement Mid Cycle')
        THEN TO_DATE(cycle_start)
      ELSE month_start
    END AS final_start
  FROM calc
),
f3 AS (
  SELECT *, DATEDIFF(final_end, final_start) + 1 AS plat_days FROM f2
)
SELECT mon,
  CASE WHEN xl_type = 'Full Cycle Charge' THEN 'G_整月卡'
       WHEN xl_type = 'Partial Charge - Card Replaced Mid Cycle' THEN 'C_换卡旧卡'
       WHEN xl_type = 'Partial Charge - New Card Used as Replacement Mid Cycle' THEN 'D_换卡新卡'
       WHEN xl_type = 'New Activation: Prorated-in Charge' THEN 'E_新激活'
       ELSE xl_type END AS kind,
  COUNT(1) AS cards,
  SUM(CASE WHEN plat_days = CAST(xl_days AS INT) THEN 1 ELSE 0 END) AS days_match,
  ROUND(SUM(xl_charge),2) AS excel,
  ROUND(SUM(ROUND(xl_rate/dim*plat_days,4)),2) AS calc,
  ROUND(SUM(ROUND(xl_rate/dim*plat_days,4)) - SUM(xl_charge),2) AS diff
FROM f3 GROUP BY mon, 2 ORDER BY mon, kind
