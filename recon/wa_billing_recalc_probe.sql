-- ============================================================================
-- WA锛圵ing Alpha锛夊璐?路 骞冲彴鍙ｅ緞璐﹀崟澶嶇畻  v1.0
-- 鐩殑锛氱敤骞冲彴鏁版嵁婧愬绠椾笌 WA Excel 鍙戠エ涓€鑷寸殑姣忓崱璐圭敤锛岀敤浜庝笌渚涘簲鍟嗗璐︺€?--
-- 鏁版嵁婧?--   涓昏〃   simo_prod.tc_cdr.sim_status_for_sftp_bak   锛堟瘡灏忔椂鍗＄姸鎬佸揩鐓э級
--   鍗曚环   simo_prod.ods.resource_res_vsim_product     锛坧ackage_price锛?--   鐪熷€?  simo_prod.mysql_cdc_sync.wa_invoice_detail  锛圵A 鍙戠エ锛屼粎鐢ㄤ簬瀵规瘮/鍙栦骇鍝両D锛?--
-- 鈹€鈹€ 涓€銆佷粠 Excel 渚ч€嗗悜鍑虹殑璁¤垂鍏紡锛?42,902 琛岄€愯楠岃瘉锛夆攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
--    final_charge = monthly_rate / DAY(LAST_DAY(final_start_date)) * final_days
--    路 final_days 鈮?active_days锛堝彂绁ㄤ袱鍒楁亽绛夛紱97.9% 琛屾暟瀹屽叏鐩哥瓑锛?--    路 鍒嗘瘝 = final_start_date 鎵€鍦ㄨ嚜鐒舵湀澶╂暟锛?8/30/31锛夛紝宸查€愭湀楠岃瘉
--    路 璁¤垂鏈?= final_start_date 鎵€鍦ㄨ嚜鐒舵湀锛堝悇鏈堝彂绁ㄥ敮涓€锛屽凡閫愭湀楠岃瘉锛?--    路 134 绉?(浜у搧,鍗曚环) 缁勫悎涓?129 绉嶄笌骞冲彴 package_price 瀹屽叏涓€鑷?--    路 鍗曚环鍙湁 4 妗ｏ細$21 / $32 / $43 / $62
--
-- 鈹€鈹€ 浜屻€佸钩鍙板彛寰勮璐瑰ぉ鏁拌鍒欙紙宸叉妸鏁存湀鍗″仛鍒板垎姣笉宸級鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
--    鈶?褰撴湀 1 鍙峰湪缃?涓?鏈堟湯鏈€鍚庝竴澶╀粛鍦ㄧ綉  鈫?璁℃弧鏁存湀澶╂暟锛?8/30/31锛?--       楠岃瘉锛?026-08 鍏ㄩ儴 7,109 寮?Full Cycle 鍗?100% 鍛戒腑锛岄噾棰濆垎姣笉宸?--    鈶?鏈堜腑鎵嶅嚭鐜帮紙鏂版縺娲?鎹㈠崱鏂板崱锛夆啋 鎸夊綋鏈堝疄闄呭湪缃戝ぉ鏁?--    鈶?鏈堜腑鍋滅敤锛堟崲鍗℃棫鍗?杞?Simbank/鎶ュ簾锛夆啋 蹇呴』绠楀埌鍋滅敤鏃ワ紱
--       骞冲彴渚х敤涓嬮潰鐨?billing_end 鎺ㄥ
--
-- 鈹€鈹€ 涓夈€佸叏閲忓璐︾粨鏋滐紙2025-10 ~ 2026-08锛?1 涓湀锛?14,468 琛岋級鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
--    Excel 鍙戠エ鍚堣        $6,107,097.95
--    骞冲彴澶嶇畻锛堝钩鍙板崟浠凤級    $6,124,136.02   +$17,038.07  (+0.28%)
--    骞冲彴澶嶇畻锛圗xcel 鍗曚环锛? $6,298,390.81   +$191,292.86 (+3.13%)  鈫?涓嶈鐢?--    閫愬崱澶╂暟瀹屽叏涓€鑷?       102,651 / 114,468 琛?(89.7%)
--
-- 鈹€鈹€ 鍥涖€佸墿浣欏樊寮傛竻鍗曪紙鎸夐噾棰濓級鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
--    +$91,599  Prorated Out - Transferred to Wing's Simbank锛?,901 琛岋級
--              骞冲彴蹇収浠嶇湅鍒拌鍗″湪缃戯紝瀹為檯宸茶浆鍑?鈫?闇€鎸夎浆鍑烘棩鎴柇
--    +$74,819  New Activation: Prorated-in Charge锛?,545 琛岋級
--              骞冲彴渚ц繖浜涘崱鏁存湀閮藉湪缃戯紙31澶╋級锛學A 鍗村彧鏀堕儴鍒嗗ぉ鏁?--    +$25,323  Partial Charge - Card Replaced Mid Cycle锛?,016 琛岋級
--    +$ 9,637  Partial Charge - Product Transfer Mid Cycle锛?82 琛岋級
--    +$ 9,289  Partial Charge - New Card Used as Replacement Mid Cycle锛?26 琛岋級
--    -$28,148  Full Cycle Charge锛?02,321 琛岋級骞冲彴鐣ヤ綆
-- ============================================================================

WITH
-- ---------- 1. Excel 渚э細璁¤垂鏈堛€佺湡鍊笺€佷骇鍝両D -------------------------------
xl AS (
  SELECT
    DATE_FORMAT(TO_DATE(final_start_date),'yyyy-MM')    AS bill_month,
    TO_DATE(final_start_date)                           AS bm_first,
    imsi, iccid, charge_type, status,
    TO_DATE(final_start_date)  AS final_start_date,
    TO_DATE(final_end_date)    AS final_end_date,
    TO_DATE(cycle_start_date)  AS cycle_start_date,
    TO_DATE(cycle_end_date)    AS cycle_end_date,
    TO_DATE(offstock_date)     AS offstock_date,
    CAST(final_days  AS DOUBLE) AS xl_final_days,
    CAST(active_days AS DOUBLE) AS xl_active_days,
    CAST(monthly_rate AS DOUBLE) AS xl_monthly_rate,
    CAST(final_charge AS DOUBLE) AS xl_final_charge,
    CASE WHEN TRIM(product_name) LIKE '%|%'      -- 浠?2025-09 鏂囦欢甯?"浜у搧ID|" 鍓嶇紑
         THEN TRIM(SPLIT(TRIM(product_name),'[|]')[0]) END AS product_id_xl,
    source_file
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE CAST(final_charge AS DOUBLE) IS NOT NULL
    AND TO_DATE(final_start_date) IS NOT NULL
),

-- ---------- 2. 骞冲彴渚э細姣?IMSI 姣忚嚜鐒舵湀鐨勫湪缃戝ぉ鏁?---------------------------
snap_days AS (
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
  FROM snap_days
  GROUP BY imsi, year, month
),

-- ---------- 3. 骞冲彴渚э細鍋滅敤鏃ワ紙鎹㈠崱/杞嚭/鎶ュ簾锛?-----------------------------
-- status_log 涓?NEXT_STATUS='浣滃簾'锛圽u4f5c\u5e9f锛変唬琛ㄥ崱琚仠鐢?鏇挎崲
stop AS (
  SELECT IMSI AS imsi, MIN(TO_DATE(CREATE_DATE)) AS stop_date
  FROM simo_prod.ods.resource_res_vsim_status_log
  WHERE NEXT_STATUS = '\u4f5c\u5e9f'
  GROUP BY IMSI
),

-- ---------- 4. 骞冲彴渚э細浜у搧鍗曚环锛堜粎 Wing Alpha = supplier_id 2275锛?--------
prod AS (
  SELECT product_id, TRIM(product_name) AS product_name,
         CAST(package_price AS DOUBLE) AS package_price
  FROM simo_prod.ods.resource_res_vsim_product
  WHERE supplier_id = 2275
),

-- ---------- 5. 骞冲彴鍙ｅ緞璁¤垂澶╂暟 --------------------------------------------
calc AS (
  SELECT
    x.*,
    m.presence_days, m.first_seen, m.last_seen,
    m.product_id                    AS snap_product_id,
    pr.product_name                 AS plat_product_name,
    pr.package_price                AS plat_package_price,
    s.stop_date,
    DAY(LAST_DAY(x.bm_first))       AS days_in_month,
    -- 鍋滅敤鏃ュ繀椤昏惤鍦ㄦ湰鏈堝唴鎵嶇敤浜庢埅鏂?    CASE WHEN s.stop_date BETWEEN x.bm_first AND LAST_DAY(x.bm_first)
         THEN s.stop_date END       AS stop_in_month,
    CASE
      -- 瑙勫垯鈶狅細鏁存湀閮藉湪缃?鈫?婊℃湀
      WHEN m.first_seen = x.bm_first AND m.last_seen = LAST_DAY(x.bm_first)
        THEN DAY(LAST_DAY(x.bm_first))
      WHEN m.presence_days IS NULL THEN 0
      ELSE m.presence_days
    END                             AS days_presence
  FROM xl x
  LEFT JOIN presence m ON m.imsi = x.imsi AND m.ym = x.bill_month
  LEFT JOIN stop     s ON s.imsi = x.imsi
  LEFT JOIN prod    pr ON pr.product_id = m.product_id
)

SELECT bill_month, charge_type, COUNT(1) AS n, ROUND(SUM(plat_charge),2) AS plat_sum, ROUND(SUM(xl_final_charge),2) AS xl_sum FROM calc GROUP BY bill_month, charge_type ORDER BY bill_month, charge_type
