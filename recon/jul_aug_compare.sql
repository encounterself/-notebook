-- 7月 vs 8月 逐卡差异桶并排
WITH j7x AS (
  SELECT imsi, MAX(charge_type) AS xl_type, MAX(TRY_CAST(final_days AS DOUBLE)) AS xl_days,
         SUM(TRY_CAST(final_charge AS DOUBLE)) AS xl_charge
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE source_file LIKE '%JULY 2026%' GROUP BY imsi
),
j7v AS (
  SELECT IMSI AS imsi, SUM(CASE WHEN types=1 THEN Billable_Days ELSE 0 END) AS t1d,
         SUM(CASE WHEN types=1 THEN Billable_Fee_Final ELSE 0 END) AS t1f,
         SUM(CASE WHEN types=2 THEN Billable_Fee_Final ELSE 0 END) AS t2f
  FROM simo_prod.mysql_cdc_sync.card_billing_v2_jul_test GROUP BY IMSI
),
j7 AS (
  SELECT '2026-07' AS mon, COALESCE(x.imsi,v.imsi) AS imsi, x.xl_type, x.xl_days, x.xl_charge,
         COALESCE(v.t1d,0) AS t1d, COALESCE(v.t1f,0) AS t1f, COALESCE(v.t2f,0) AS t2f,
         v.imsi IS NULL AS plat_missing, x.imsi IS NULL AS excel_missing
  FROM j7x x FULL OUTER JOIN j7v v ON x.imsi = v.imsi
),
j8x AS (
  SELECT imsi, MAX(charge_type) AS xl_type, MAX(TRY_CAST(final_days AS DOUBLE)) AS xl_days,
         SUM(TRY_CAST(final_charge AS DOUBLE)) AS xl_charge
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE source_file LIKE '%AUGUST 2026%' GROUP BY imsi
),
j8v AS (
  SELECT imsi, SUM(CASE WHEN types=1 THEN Billable_Days ELSE 0 END) AS t1d,
         SUM(CASE WHEN types=1 THEN Billable_Fee_Final ELSE 0 END) AS t1f,
         SUM(CASE WHEN types=2 THEN Billable_Fee_Final ELSE 0 END) AS t2f
  FROM simo_prod.mysql_cdc_sync.card_billing_v2_aug GROUP BY imsi
),
j8 AS (
  SELECT '2026-08' AS mon, COALESCE(x.imsi,v.imsi) AS imsi, x.xl_type, x.xl_days, x.xl_charge,
         COALESCE(v.t1d,0) AS t1d, COALESCE(v.t1f,0) AS t1f, COALESCE(v.t2f,0) AS t2f,
         v.imsi IS NULL AS plat_missing, x.imsi IS NULL AS excel_missing
  FROM j8x x FULL OUTER JOIN j8v v ON x.imsi = v.imsi
),
allm AS (SELECT * FROM j7 UNION ALL SELECT * FROM j8),
bucketed AS (
  SELECT mon, xl_charge, t1f, t2f,
    CASE
      WHEN plat_missing THEN 'A_平台缺卡'
      WHEN excel_missing THEN 'B_Excel缺卡'
      WHEN xl_type = 'Partial Charge - Card Replaced Mid Cycle' THEN 'C_换卡旧卡'
      WHEN xl_type = 'Partial Charge - New Card Used as Replacement Mid Cycle' THEN 'D_换卡新卡'
      WHEN xl_type = 'New Activation: Prorated-in Charge' THEN 'E_新激活'
      WHEN ABS(COALESCE(t1f,0) - COALESCE(xl_charge,0)) < 0.01 THEN 'F_完全一致'
      WHEN t1d = 30 AND xl_days = 31 THEN 'G_整月卡少算1天'
      ELSE 'H_其他'
    END AS kind
  FROM allm
)
SELECT kind,
  SUM(CASE WHEN mon='2026-07' THEN 1 ELSE 0 END) AS jul_cards,
  ROUND(SUM(CASE WHEN mon='2026-07' THEN COALESCE(t1f,0)-COALESCE(xl_charge,0) ELSE 0 END),2) AS jul_diff,
  SUM(CASE WHEN mon='2026-08' THEN 1 ELSE 0 END) AS aug_cards,
  ROUND(SUM(CASE WHEN mon='2026-08' THEN COALESCE(t1f,0)-COALESCE(xl_charge,0) ELSE 0 END),2) AS aug_diff
FROM bucketed GROUP BY kind
UNION ALL
SELECT '=== 合计 ===',
  SUM(CASE WHEN mon='2026-07' THEN 1 ELSE 0 END),
  ROUND(SUM(CASE WHEN mon='2026-07' THEN COALESCE(t1f,0)-COALESCE(xl_charge,0) ELSE 0 END),2),
  SUM(CASE WHEN mon='2026-08' THEN 1 ELSE 0 END),
  ROUND(SUM(CASE WHEN mon='2026-08' THEN COALESCE(t1f,0)-COALESCE(xl_charge,0) ELSE 0 END),2)
FROM bucketed
ORDER BY kind
