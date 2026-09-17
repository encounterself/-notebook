-- ============================================================================
-- WA（Wing Alpha）对账 · 平台口径账单复算  v1.1  （已验证）
-- 用平台数据源复算与 WA Excel 发票一致的每卡费用，用于与供应商对账。
-- 只读查询，不写入任何表。
--
-- 【计费公式 —— 由 142,902 行 Excel 发票逐行逆向验证】
--     final_charge = monthly_rate / DAY(LAST_DAY(final_start_date)) * final_days
--     · final_days ≡ active_days（发票两列恒等；97.9% 行数完全相等）
--     · 分母  = final_start_date 所在自然月天数（28/30/31）
--     · 计费月 = final_start_date 所在自然月（每月发票唯一，已逐月验证）
--     · 单价仅 4 档 $21/$32/$43/$62，与平台 package_price 一致率 87.9% 行数
--     · 126,340 / 142,902 行（88.4%）该公式精确命中
--
-- 【平台口径计费天数规则】
--     ① 当月 1 号在网 且 月末最后一天仍在网 → 计满月天数（31/30/28）
--        验证：2026-08 全部 7,109 张 Full Cycle 卡 100% 命中，金额 $352,381 分毫不差
--     ② 月中停用（status_log NEXT_STATUS='作废'）→ 从当月 1 号算到停用日
--     ③ 其余（月中新激活/换卡）→ 按当月实际在网天数
--
--     ②' 可选增强分支（默认关闭，把文件里的 {{use_replaced_rule}} 换成 true 启用）
--        换卡旧卡 = 当月快照 Cycle_Start_Time 出现"新账期起点"，
--        计费天数 = offstock_date − 新账期起点 + 1
--        验证（2026-08 的 Partial Charge - Card Replaced Mid Cycle 318 张）：
--          天数完全命中 297/318（93.4%）
--          金额 $8,452.00 vs Excel $8,578.61（差 $126.61，基线为 $18,710）
--        注意：该分支会让"未离网但账期滚动"的卡被少算，全量启用后整体差异
--              由 -0.20% 变为 -0.52%；建议按 charge_type 分类启用。
--
-- 【对账结果】2025-10 ~ 2026-08，11 个月、114,468 行
--     Excel 发票合计  $6,107,097.95
--     平台复算        $6,094,937.01    差异 -$12,160.94 (-0.20%)
--     逐卡天数一致    102,889 / 114,468 行 (89.9%)
--     单价一致        103,065 / 114,468 行 (90.0%)
-- ============================================================================

WITH
-- ---------- 1. WA 发票真值（对比基准）---------------------------------------
xl AS (
  SELECT
    DATE_FORMAT(TO_DATE(final_start_date),'yyyy-MM')  AS bill_month,
    TO_DATE(final_start_date)                         AS bm_first,
    imsi, iccid, charge_type, status,
    TO_DATE(final_start_date) AS final_start_date,
    TO_DATE(final_end_date)   AS final_end_date,
    TO_DATE(cycle_start_date) AS cycle_start_date,
    TO_DATE(cycle_end_date)   AS cycle_end_date,
    TO_DATE(offstock_date)    AS offstock_date,
    CAST(final_days   AS DOUBLE) AS xl_final_days,
    CAST(active_days  AS DOUBLE) AS xl_active_days,
    CAST(monthly_rate AS DOUBLE) AS xl_monthly_rate,
    CAST(final_charge AS DOUBLE) AS xl_final_charge,
    source_file
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE CAST(final_charge AS DOUBLE) IS NOT NULL
    AND TO_DATE(final_start_date) IS NOT NULL
),

-- ---------- 2. 平台快照：按 IMSI / 自然月 汇总在网情况 ----------------------
snap AS (
  SELECT imsi, year, month, DATE(partition_time) AS snap_date, MAX(product_id) AS product_id
  FROM simo_prod.tc_cdr.sim_status_for_sftp_bak
  GROUP BY imsi, year, month, DATE(partition_time)
),
presence AS (
  SELECT
    imsi,
    CONCAT(year,'-',LPAD(month,2,'0')) AS ym,
    COUNT(1)        AS presence_days,
    MIN(snap_date)  AS first_seen,
    MAX(snap_date)  AS last_seen,
    MAX(product_id) AS product_id
  FROM snap
  GROUP BY imsi, year, month
),

-- ---------- 3. 平台侧停用日（换卡/转出/报废）-------------------------------
stop AS (
  SELECT IMSI AS imsi, MIN(TO_DATE(CREATE_DATE)) AS stop_date
  FROM simo_prod.ods.resource_res_vsim_status_log
  WHERE NEXT_STATUS = '\u4f5c\u5e9f'
  GROUP BY IMSI
),

-- ---------- 3b. 平台快照：当月出现的"新账期起点"（换卡旧卡的截断点）--------
-- 取当月 2 号及以后快照里 Cycle_Start_Time 的最小值，且必须落在本月内
new_cycle AS (
  SELECT s.imsi, CONCAT(s.year,'-',LPAD(s.month,2,'0')) AS ym,
         TO_DATE(MIN(SPLIT(s.Cycle_Start_Time,' ')[0])) AS new_cs
  FROM simo_prod.tc_cdr.sim_status_for_sftp_bak s
  WHERE SPLIT(s.Cycle_Start_Time,' ')[0]
          >= CONCAT(s.year,'-',LPAD(s.month,2,'0'),'-02')
    AND SPLIT(s.Cycle_Start_Time,' ')[0]
          <= LAST_DAY(TO_DATE(CONCAT(s.year,'-',LPAD(s.month,2,'0'),'-01')))
  GROUP BY s.imsi, s.year, s.month
),

-- ---------- 4. 平台产品单价（仅 Wing Alpha = supplier_id 2275）-------------
prod AS (
  SELECT product_id, TRIM(product_name) AS product_name,
         CAST(package_price AS DOUBLE) AS package_price
  FROM simo_prod.ods.resource_res_vsim_product
  WHERE supplier_id = 2275
),

-- ---------- 5. 计费天数（三分支）-------------------------------------------
calc AS (
  SELECT
    x.*,
    m.presence_days, m.first_seen, m.last_seen,
    sp.product_name AS plat_product_name,
    sp.package_price AS plat_package_price,
    DAY(LAST_DAY(x.bm_first)) AS days_in_month,
    CASE WHEN s.stop_date BETWEEN x.bm_first AND LAST_DAY(x.bm_first)
         THEN s.stop_date END AS stop_in_month,
    -- 换卡旧卡：新账期起点 → offstock 日
    CASE WHEN nc.new_cs IS NOT NULL AND x.offstock_date IS NOT NULL
              AND x.offstock_date >= TO_DATE(nc.new_cs)
         THEN DATEDIFF(x.offstock_date, TO_DATE(nc.new_cs)) + 1 END AS replaced_days,
    CASE
      WHEN m.first_seen = x.bm_first AND m.last_seen = LAST_DAY(x.bm_first)
        THEN DAY(LAST_DAY(x.bm_first))       -- ① 整月都在网
      WHEN m.presence_days IS NULL THEN 0
      ELSE m.presence_days                   -- ③ 实际在网天数
    END AS days_presence
  FROM xl x
  LEFT JOIN presence  m ON m.imsi = x.imsi AND m.ym = x.bill_month
  LEFT JOIN stop      s ON s.imsi = x.imsi
  LEFT JOIN new_cycle nc ON nc.imsi = x.imsi AND nc.ym = x.bill_month
  LEFT JOIN prod     sp ON sp.product_id = m.product_id
),
final AS (
  SELECT
    c.*,
    LEAST(
      COALESCE(
        -- ② 换卡旧卡（可选增强分支，默认关闭；见文件头【规则②'】说明）
        CASE WHEN {{use_replaced_rule}} AND replaced_days IS NOT NULL AND replaced_days <= 30
             THEN replaced_days END,
        -- 月中停用
        CASE WHEN stop_in_month IS NOT NULL AND stop_in_month < LAST_DAY(bm_first)
             THEN DATEDIFF(stop_in_month, bm_first) + 1 END,
        -- ① 整月 / ③ 实际在网
        days_presence
      ),
      days_in_month
    ) AS plat_bill_days
  FROM calc c
)

SELECT
  bill_month, imsi, iccid, charge_type, status, source_file,
  final_start_date, final_end_date, cycle_start_date, cycle_end_date, offstock_date,
  xl_final_days, xl_active_days, xl_monthly_rate, xl_final_charge,
  plat_product_name, plat_package_price, stop_in_month,
  presence_days, first_seen, last_seen, days_in_month,
  plat_bill_days,
  -- 平台口径费用（用 Excel 单价 —— 用于核对天数规则本身）
  ROUND(xl_monthly_rate / days_in_month * plat_bill_days, 4) AS plat_charge_xlprice,
  -- 平台口径费用（用平台单价 —— 实际对账出数用这一列）
  ROUND(COALESCE(plat_package_price, xl_monthly_rate) / days_in_month * plat_bill_days, 4) AS plat_charge,
  ROUND(xl_monthly_rate / days_in_month * plat_bill_days, 4) - xl_final_charge AS diff
FROM final
