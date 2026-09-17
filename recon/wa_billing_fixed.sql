-- ============================================================================
-- WA 平台口径当月费用 · 修正版（平台字段自足，不依赖 Excel 的 offstock_date）
--
-- 修正 1：原逻辑 COUNT(1) - 1  → 改为「当月1号在网 且 月末最后一天在网 = 满月天数」
-- 修正 2：换卡费 → 用「当月新账期起点」锚定，不再算满整月
--         换卡旧卡：新账期起点 → 停用日
--         换卡新卡：新账期起点 → 月末
--         新账期起点 = 当月快照中 Cycle_Start_Time >= 当月2号 的最小值
--         停用日     = status_log 中 NEXT_STATUS='作废' 的 CREATE_DATE 减 1 天
-- ============================================================================
WITH presence AS (
  SELECT imsi,
         COUNT(DISTINCT DATE(partition_time)) AS presence_days,
         MIN(DATE(partition_time))            AS first_seen,
         MAX(DATE(partition_time))            AS last_seen
  FROM simo_prod.tc_cdr.sim_status_for_sftp_bak
  WHERE year = 2026 AND month = 8
  GROUP BY imsi
),
-- 当月新账期起点（修正 2 的锚点）
new_cycle AS (
  SELECT imsi, TO_DATE(MIN(SPLIT(Cycle_Start_Time,' ')[0])) AS new_cs
  FROM simo_prod.tc_cdr.sim_status_for_sftp_bak
  WHERE year = 2026 AND month = 8
    AND SPLIT(Cycle_Start_Time,' ')[0] BETWEEN '2026-08-02' AND '2026-08-31'
  GROUP BY imsi
),
-- 停用日（平台字段，替代 Excel 的 offstock_date）
stopped AS (
  SELECT IMSI AS imsi, DATE_SUB(MIN(TO_DATE(CREATE_DATE)), 1) AS stop_offstock
  FROM simo_prod.ods.resource_res_vsim_status_log
  WHERE NEXT_STATUS = '\u4f5c\u5e9f'
    AND CREATE_DATE >= '2026-08-01' AND CREATE_DATE < '2026-10-01'
  GROUP BY IMSI
),
sp AS (
  SELECT imsi, MAX(product_id) AS pid
  FROM simo_prod.tc_cdr.sim_status_for_sftp_bak
  WHERE year = 2026 AND month = 8 GROUP BY imsi
),
prod AS (
  SELECT product_id, TRIM(product_name) AS product_name,
         CAST(package_price AS DOUBLE) AS package_price
  FROM simo_prod.ods.resource_res_vsim_product WHERE supplier_id = 2275
),
xl AS (
  SELECT imsi, MAX(charge_type) AS charge_type,
         MAX(TO_DATE(offstock_date)) AS xl_offstock,
         MAX(TRY_CAST(final_days   AS DOUBLE)) AS xl_final_days,
         MAX(TRY_CAST(monthly_rate AS DOUBLE)) AS xl_monthly_rate,
         SUM(TRY_CAST(final_charge AS DOUBLE)) AS xl_final_charge
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE source_file LIKE '%AUGUST 2026%'
  GROUP BY imsi
),
calc AS (
  SELECT x.*,
         COALESCE(pr.package_price, x.xl_monthly_rate) AS plat_price,
         pr.product_name AS plat_product_name,
         p.presence_days, p.first_seen, p.last_seen,
         n.new_cs, s.stop_offstock,
         DAY(LAST_DAY(TO_DATE('2026-08-01'))) AS dim,
         -- 修正 1
         CASE WHEN p.first_seen = TO_DATE('2026-08-01')
                   AND p.last_seen = TO_DATE('2026-08-31')
              THEN DAY(LAST_DAY(TO_DATE('2026-08-01')))
              ELSE p.presence_days END AS d_fix1,
         -- 修正 2a 换卡旧卡
         CASE WHEN n.new_cs IS NOT NULL AND s.stop_offstock IS NOT NULL
                   AND s.stop_offstock >= n.new_cs
              THEN DATEDIFF(s.stop_offstock, n.new_cs) + 1 END AS d_fix2a,
         -- 修正 2b 换卡新卡
         CASE WHEN n.new_cs IS NOT NULL
              THEN DATEDIFF(TO_DATE('2026-08-31'), n.new_cs) + 1 END AS d_fix2b,
         -- 修正 2c 新激活
         CASE WHEN n.new_cs IS NOT NULL
              THEN DATEDIFF(DATE_SUB(n.new_cs,1), TO_DATE('2026-08-01')) + 1 END AS d_fix2c
  FROM xl x
  LEFT JOIN presence p ON p.imsi = x.imsi
  LEFT JOIN new_cycle n ON n.imsi = x.imsi
  LEFT JOIN stopped  s ON s.imsi = x.imsi
  LEFT JOIN sp         ON sp.imsi = x.imsi
  LEFT JOIN prod    pr ON pr.product_id = sp.pid
),
final AS (
  SELECT *,
         CASE
           WHEN charge_type = 'Partial Charge - Card Replaced Mid Cycle'                THEN d_fix2a
           WHEN charge_type = 'Partial Charge - New Card Used as Replacement Mid Cycle' THEN d_fix2b
           WHEN charge_type = 'New Activation: Prorated-in Charge'                      THEN d_fix2c
           ELSE d_fix1
         END AS plat_bill_days
  FROM calc
)
SELECT
  charge_type,
  COUNT(1)                                             AS cards,
  xl_final_days, xl_monthly_rate,
  new_cs, stop_offstock, xl_offstock,
  d_fix1, d_fix2a, d_fix2b, d_fix2c,
  plat_bill_days,
  xl_final_charge,
  ROUND(plat_price      / 31 * plat_bill_days, 4) AS plat_charge,
  ROUND(xl_monthly_rate / 31 * plat_bill_days, 4) AS plat_charge_xlrate,
  -- 平台停用日 vs Excel offstock 日 的对齐情况
  DATEDIFF(stop_offstock, xl_offstock)             AS stop_vs_xl_offstock_days
FROM final
