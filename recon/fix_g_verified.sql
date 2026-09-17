-- ============================================================================
-- 修正版规则实现（基于你的方案）· 7月+8月验证
--
-- 【G 整月卡 —— 已验证，两个月 $0.00】
--   新账期起点 = cycle_history 中 cycle_time 落在本月的记录存在与否
--     · 存在（本月内起了新账期）→ final_end = 月末
--     · 不存在（账期是上月带过来的）→ final_end = 月末
--   （两种情况都是月末；等价于「账期是否在本月内切换」不影响整月卡）
--
--   实测：2026-07 卡 7,240 张 $363,182.00 → $363,182.00  差异 $0.00
--         2026-08 卡 7,109 张 $352,381.00 → $352,381.00  差异 $0.00
--         天数命中 14,349 / 14,349 = 100%
-- ============================================================================
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
-- 本月内是否有新账期（cycle_history.cycle_time 落在本月）
inmonth_ct AS (
  SELECT c.mon, hh.imsi, COUNT(1) AS n_inmonth_cycle
  FROM cfg c JOIN simo_prod.ods.resource_res_vsim_cycle_history hh
    ON SPLIT(CAST(CAST(hh.cycle_time AS TIMESTAMP) - INTERVAL 5 HOURS AS STRING),' ')[0]
       BETWEEN DATE_FORMAT(c.d1,'yyyy-MM-dd') AND DATE_FORMAT(c.d2,'yyyy-MM-dd')
  GROUP BY c.mon, hh.imsi
),
-- 本月内是否有 next_cycle_time（用于换卡类截断）
inmonth_nct AS (
  SELECT c.mon, hh.imsi,
         MIN(SPLIT(CAST(CAST(hh.next_cycle_time AS TIMESTAMP) - INTERVAL 5 HOURS AS STRING),' ')[0]) AS nct_in_month
  FROM cfg c JOIN simo_prod.ods.resource_res_vsim_cycle_history hh
    ON SPLIT(CAST(CAST(hh.next_cycle_time AS TIMESTAMP) - INTERVAL 5 HOURS AS STRING),' ')[0]
       BETWEEN DATE_FORMAT(c.d1,'yyyy-MM-dd') AND DATE_FORMAT(c.d2,'yyyy-MM-dd')
  GROUP BY c.mon, hh.imsi
),
scored AS (
  SELECT x.*, i.n_inmonth_cycle, n.nct_in_month,
    DAY(LAST_DAY(TO_DATE(CONCAT(SUBSTR(x.mon,1,4),'-',SUBSTR(x.mon,6,2),'-01')))) AS dim,
    LAST_DAY(TO_DATE(CONCAT(SUBSTR(x.mon,1,4),'-',SUBSTR(x.mon,6,2),'-01'))) AS monthend,
    -- G 规则：final_end 一律月末
    LAST_DAY(TO_DATE(CONCAT(SUBSTR(x.mon,1,4),'-',SUBSTR(x.mon,6,2),'-01'))) AS final_end
  FROM xl x
  LEFT JOIN inmonth_ct  i ON i.mon = x.mon AND i.imsi = x.imsi
  LEFT JOIN inmonth_nct n ON n.mon = x.mon AND n.imsi = x.imsi
)
SELECT
  mon,
  CASE WHEN xl_type = 'Full Cycle Charge' THEN 'G_整月卡' ELSE xl_type END AS kind,
  COUNT(1) AS cards,
  SUM(CASE WHEN DATEDIFF(final_end, TO_DATE(CONCAT(SUBSTR(mon,1,4),'-',SUBSTR(mon,6,2),'-01'))) + 1 = CAST(xl_days AS INT)
           THEN 1 ELSE 0 END) AS days_match,
  ROUND(SUM(xl_charge),2) AS excel,
  ROUND(SUM(ROUND(xl_rate/dim*(DATEDIFF(final_end, TO_DATE(CONCAT(SUBSTR(mon,1,4),'-',SUBSTR(mon,6,2),'-01'))) + 1),4)),2) AS calc,
  ROUND(SUM(ROUND(xl_rate/dim*(DATEDIFF(final_end, TO_DATE(CONCAT(SUBSTR(mon,1,4),'-',SUBSTR(mon,6,2),'-01'))) + 1),4)) - SUM(xl_charge),2) AS diff
FROM scored GROUP BY mon, 2 ORDER BY mon, kind
