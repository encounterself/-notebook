-- 逐卡对应摘要：按 diff_kind 汇总
WITH x AS (
  SELECT imsi, MAX(charge_type) AS xl_type,
         MAX(TRY_CAST(final_days AS DOUBLE)) AS xl_days,
         SUM(TRY_CAST(final_charge AS DOUBLE)) AS xl_charge
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE source_file LIKE '%AUGUST 2026%' GROUP BY imsi
),
v AS (
  SELECT imsi,
         SUM(CASE WHEN types=1 THEN Billable_Days     ELSE 0 END) AS t1d,
         SUM(CASE WHEN types=1 THEN Billable_Fee_Final ELSE 0 END) AS t1f,
         SUM(CASE WHEN types=2 THEN Billable_Fee_Final ELSE 0 END) AS t2f,
         COUNT(1) AS vrows
  FROM simo_prod.mysql_cdc_sync.card_billing_v2_aug GROUP BY imsi
),
j AS (
  SELECT COALESCE(x.imsi,v.imsi) AS imsi, x.xl_type, x.xl_days, x.xl_charge,
         COALESCE(v.t1d,0) AS t1d, COALESCE(v.t1f,0) AS t1f, COALESCE(v.t2f,0) AS t2f,
         v.imsi IS NULL AS plat_missing, x.imsi IS NULL AS excel_missing,
         CASE
           WHEN v.imsi IS NULL THEN 'A_平台缺卡'
           WHEN x.imsi IS NULL THEN 'B_Excel缺卡(平台多算)'
           WHEN x.xl_type = 'Partial Charge - Card Replaced Mid Cycle' THEN 'C_换卡旧卡'
           WHEN x.xl_type = 'Partial Charge - New Card Used as Replacement Mid Cycle' THEN 'D_换卡新卡'
           WHEN x.xl_type = 'New Activation: Prorated-in Charge' THEN 'E_新激活'
           WHEN ABS(COALESCE(v.t1f,0) - COALESCE(x.xl_charge,0)) < 0.01 THEN 'F_完全一致'
           WHEN COALESCE(v.t1d,0) = 30 AND x.xl_days = 31 THEN 'G_整月卡少算1天'
           ELSE 'H_其他'
         END AS kind
  FROM x FULL OUTER JOIN v ON x.imsi = v.imsi
)
SELECT kind, COUNT(1) AS cards,
       ROUND(SUM(COALESCE(xl_charge,0)),2) AS excel_current,
       ROUND(SUM(t1f),2) AS plat_current,
       ROUND(SUM(t1f) - SUM(COALESCE(xl_charge,0)),2) AS diff_current,
       ROUND(SUM(t2f),2) AS plat_prepaid
FROM j GROUP BY kind ORDER BY diff_current
