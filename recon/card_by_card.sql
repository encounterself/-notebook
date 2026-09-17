-- ============================================================================
-- 8月逐卡对应 · 完整对账表
-- Excel 发票  vs  平台 notebook(card_billing_v2_aug) 输出
-- 每张卡一行，含差异金额与差异类型
-- ============================================================================
SELECT
  COALESCE(x.imsi, v.imsi)  AS imsi,
  x.xl_type                 AS excel_charge_type,
  x.xl_product              AS excel_product,
  x.xl_cycle_start, x.xl_cycle_end, x.xl_final_start, x.xl_final_end, x.xl_offstock,
  x.xl_final_days, x.xl_monthly_rate, x.xl_charge,
  v.plat_product, v.plat_price,
  v.plat_t1_days, v.plat_t1_fee,
  v.plat_t2_days, v.plat_t2_fee,
  ROUND(COALESCE(v.plat_t1_fee,0) - COALESCE(x.xl_charge,0), 2) AS diff_current,
  ROUND(COALESCE(v.plat_t2_fee,0), 2)                           AS diff_prepaid,
  CASE
    WHEN v.imsi IS NULL THEN 'A_平台缺卡'
    WHEN x.imsi IS NULL THEN 'B_Excel缺卡(平台多算)'
    WHEN x.xl_type = 'Partial Charge - Card Replaced Mid Cycle'
      THEN 'C_换卡旧卡_平台算满月'
    WHEN x.xl_type = 'Partial Charge - New Card Used as Replacement Mid Cycle'
      THEN 'D_换卡新卡'
    WHEN x.xl_type = 'New Activation: Prorated-in Charge'
      THEN 'E_新激活'
    WHEN ABS(COALESCE(v.plat_t1_fee,0) - COALESCE(x.xl_charge,0)) < 0.01
      THEN 'F_完全一致'
    WHEN v.plat_t1_days = 30 AND x.xl_final_days = 31
      THEN 'G_整月卡少算1天(COUNT-1)'
    ELSE 'H_其他'
  END AS diff_kind
FROM (
  SELECT imsi,
         MAX(charge_type) AS xl_type,
         MAX(TRIM(product_name)) AS xl_product,
         MAX(TO_DATE(cycle_start_date)) AS xl_cycle_start,
         MAX(TO_DATE(cycle_end_date))   AS xl_cycle_end,
         MAX(TO_DATE(final_start_date)) AS xl_final_start,
         MAX(TO_DATE(final_end_date))   AS xl_final_end,
         MAX(TO_DATE(offstock_date))    AS xl_offstock,
         MAX(TRY_CAST(final_days   AS DOUBLE)) AS xl_final_days,
         MAX(TRY_CAST(monthly_rate AS DOUBLE)) AS xl_monthly_rate,
         SUM(TRY_CAST(final_charge AS DOUBLE)) AS xl_charge
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE source_file LIKE '%AUGUST 2026%' GROUP BY imsi
) x
FULL OUTER JOIN (
  SELECT imsi,
         MAX(SIM_Product_Name) AS plat_product,
         MAX(Plan_Price)       AS plat_price,
         SUM(CASE WHEN types=1 THEN Billable_Days     ELSE 0 END) AS plat_t1_days,
         SUM(CASE WHEN types=1 THEN Billable_Fee_Final ELSE 0 END) AS plat_t1_fee,
         SUM(CASE WHEN types=2 THEN Billable_Days     ELSE 0 END) AS plat_t2_days,
         SUM(CASE WHEN types=2 THEN Billable_Fee_Final ELSE 0 END) AS plat_t2_fee
  FROM simo_prod.mysql_cdc_sync.card_billing_v2_aug GROUP BY imsi
) v ON x.imsi = v.imsi
