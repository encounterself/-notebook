-- ============================================================================
-- 四类规则 · 7月+8月同时验证（G / C / D / E）
-- 输出：每类每月「Excel vs 平台修正后」的天数与金额对比
-- ============================================================================
WITH cfg AS (
  SELECT '2026-07' AS mon, 2026 AS y, 7 AS m, DATE('2026-07-01') AS d1, DATE('2026-07-31') AS d2,
         '%JULY 2026%' AS pat
  UNION ALL
  SELECT '2026-08', 2026, 8, DATE('2026-08-01'), DATE('2026-08-31'), '%AUGUST 2026%'
),
-- Excel 真值
xl AS (
  SELECT c.mon, x.imsi, MAX(x.charge_type) AS xl_type,
         MAX(TRY_CAST(x.final_days AS DOUBLE)) AS xl_days,
         MAX(TRY_CAST(x.monthly_rate AS DOUBLE)) AS xl_rate,
         SUM(TRY_CAST(x.final_charge AS DOUBLE)) AS xl_charge,
         MAX(TO_DATE(x.offstock_date)) AS xl_offstock
  FROM cfg c
  JOIN simo_prod.mysql_cdc_sync.wa_invoice_detail x ON x.source_file LIKE c.pat
  GROUP BY c.mon, x.imsi
),
-- 平台快照：在网区间 + 当月新账期起点
pres AS (
  SELECT c.mon, s.imsi,
         MIN(DATE(s.partition_time)) AS first_seen,
         MAX(DATE(s.partition_time)) AS last_seen,
         COUNT(DISTINCT DATE(s.partition_time)) AS pres_days,
         MIN(CASE WHEN DATE(s.partition_time) >= c.d1 THEN DATE(s.partition_time) END) AS first_in_month,
         MAX(CASE WHEN SPLIT(s.Cycle_Start_Time,' ')[0] BETWEEN DATE_FORMAT(c.d1,'yyyy-MM-dd')
                                                          AND DATE_FORMAT(c.d2,'yyyy-MM-dd')
                  THEN SPLIT(s.Cycle_Start_Time,' ')[0] END) AS max_cs_in_month
  FROM cfg c
  JOIN simo_prod.tc_cdr.sim_status_for_sftp_bak s
    ON s.year = c.y AND s.month = c.m
  GROUP BY c.mon, s.imsi
),
-- 新账期起点（当月 2 号及以后的最小值）
newcs AS (
  SELECT c.mon, s.imsi, TO_DATE(MIN(SPLIT(s.Cycle_Start_Time,' ')[0])) AS new_cs
  FROM cfg c
  JOIN simo_prod.tc_cdr.sim_status_for_sftp_bak s ON s.year = c.y AND s.month = c.m
  WHERE SPLIT(s.Cycle_Start_Time,' ')[0] >= DATE_FORMAT(DATE_ADD(c.d1, 1),'yyyy-MM-dd')
    AND SPLIT(s.Cycle_Start_Time,' ')[0] <= DATE_FORMAT(c.d2,'yyyy-MM-dd')
  GROUP BY c.mon, s.imsi
),
-- 当月账期起点（用于换卡旧卡锚点）
anchor AS (
  SELECT c.mon, s.imsi, TO_DATE(MIN(SPLIT(s.Cycle_Start_Time,' ')[0])) AS month_anchor
  FROM cfg c
  JOIN simo_prod.tc_cdr.sim_status_for_sftp_bak s ON s.year = c.y AND s.month = c.m
  WHERE SPLIT(s.Cycle_Start_Time,' ')[0] >= DATE_FORMAT(c.d1,'yyyy-MM-dd')
    AND SPLIT(s.Cycle_Start_Time,' ')[0] <= DATE_FORMAT(c.d2,'yyyy-MM-dd')
  GROUP BY c.mon, s.imsi
),
-- 停用日（作废 - 1 天）
stop AS (
  SELECT c.mon, l.IMSI AS imsi, DATE_SUB(MIN(TO_DATE(l.CREATE_DATE)), 1) AS stop_offstock
  FROM cfg c
  JOIN simo_prod.ods.resource_res_vsim_status_log l
    ON l.NEXT_STATUS = '\u4f5c\u5e9f'
   AND DATE(l.CREATE_DATE) >= DATE_FORMAT(c.d1,'yyyy-MM-dd')
   AND DATE(l.CREATE_DATE) <= DATE_FORMAT(DATE_ADD(c.d2, 30),'yyyy-MM-dd')
  GROUP BY c.mon, l.IMSI
),
joined AS (
  SELECT x.*, p.first_seen, p.last_seen, p.pres_days, p.first_in_month, p.max_cs_in_month,
         n.new_cs, a.month_anchor, s.stop_offstock, c.d1 AS bm_first, c.d2 AS bm_last,
         DAY(LAST_DAY(c.d1)) AS dim
  FROM xl x
  JOIN cfg c ON c.mon = x.mon
  LEFT JOIN pres  p ON p.mon = x.mon AND p.imsi = x.imsi
  LEFT JOIN newcs n ON n.mon = x.mon AND n.imsi = x.imsi
  LEFT JOIN anchor a ON a.mon = x.mon AND a.imsi = x.imsi
  LEFT JOIN stop  s ON s.mon = x.mon AND s.imsi = x.imsi
),
scored AS (
  SELECT *,
    CASE
      -- C 换卡旧卡：当月账期起点 → 停用日
      WHEN xl_type = 'Partial Charge - Card Replaced Mid Cycle'
           AND month_anchor IS NOT NULL AND stop_offstock IS NOT NULL AND stop_offstock >= month_anchor
        THEN DATEDIFF(stop_offstock, month_anchor) + 1
      -- D 换卡新卡：新账期起点 → 月末
      WHEN xl_type = 'Partial Charge - New Card Used as Replacement Mid Cycle'
           AND new_cs IS NOT NULL
        THEN DATEDIFF(bm_last, new_cs) + 1
      -- E 新激活：月初 → 新账期起点前一天
      WHEN xl_type = 'New Activation: Prorated-in Charge' AND new_cs IS NOT NULL
        THEN DATEDIFF(DATE_SUB(new_cs,1), bm_first) + 1
      -- G 整月卡：满月天数
      WHEN first_seen = bm_first AND last_seen = bm_last
        THEN dim
      ELSE COALESCE(pres_days, 0)
    END AS plat_days
  FROM joined
)
SELECT mon,
  CASE WHEN xl_type LIKE '%Replaced Mid Cycle%' THEN 'C_换卡旧卡'
       WHEN xl_type LIKE '%New Card Used as Replacement%' THEN 'D_换卡新卡'
       WHEN xl_type LIKE 'New Activation%' THEN 'E_新激活'
       ELSE 'G_整月卡/其他' END AS kind,
  COUNT(1) AS cards,
  SUM(CASE WHEN plat_days = CAST(xl_days AS INT) THEN 1 ELSE 0 END) AS days_match,
  ROUND(SUM(xl_charge),2) AS excel,
  ROUND(SUM(ROUND(xl_rate/dim*plat_days,4)),2) AS fixed,
  ROUND(SUM(ROUND(xl_rate/dim*plat_days,4)) - SUM(xl_charge),2) AS diff,
  ROUND(AVG(xl_days),1) AS avg_xl_days, ROUND(AVG(plat_days),1) AS avg_plat_days
FROM scored
GROUP BY mon, 2
ORDER BY mon, kind
