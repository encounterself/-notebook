WITH cfg AS (
  SELECT '2026-03' AS billing_month, '01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx' AS source_file, DATE '2026-03-01' AS d1, LAST_DAY(DATE '2026-03-01') AS d2
  UNION ALL SELECT '2026-04', '01-SIMO Data Purchase Invoice Details - APR 2026.xlsx', DATE '2026-04-01', LAST_DAY(DATE '2026-04-01')
  UNION ALL SELECT '2026-05', '01-SIMO Data Purchase Invoice Details - MAY 2026.xlsx', DATE '2026-05-01', LAST_DAY(DATE '2026-05-01')
), x AS (
  SELECT c.billing_month, c.d1, c.d2,
    CAST(w.imsi AS STRING) AS imsi,
    CAST(w.charge_type AS STRING) AS charge_type,
    TRY_CAST(w.final_start_date AS DATE) AS final_start_d,
    TRY_CAST(w.final_end_date AS DATE) AS final_end_d,
    TRY_CAST(w.final_days AS DOUBLE) AS excel_final_days,
    TRY_CAST(w.monthly_rate AS DOUBLE) AS excel_monthly_rate,
    TRY_CAST(w.final_charge AS DOUBLE) AS excel_final_charge,
    DAY(c.d2) AS month_days
  FROM cfg c JOIN simo_prod.mysql_cdc_sync.wa_invoice_detail w ON w.source_file = c.source_file
), f AS (
  SELECT *,
    CASE WHEN final_start_d IS NOT NULL AND final_end_d IS NOT NULL THEN CAST(DATEDIFF(final_end_d, final_start_d) + 1 AS DOUBLE) END AS date_span_days,
    CASE WHEN excel_monthly_rate IS NOT NULL THEN ROUND(excel_monthly_rate, 6) END AS full_month_formula_amount,
    CASE WHEN excel_monthly_rate IS NOT NULL AND excel_final_days IS NOT NULL THEN ROUND(excel_monthly_rate * excel_final_days / month_days, 6) END AS prorated_formula_amount,
    CASE WHEN excel_monthly_rate IS NOT NULL AND excel_final_days IS NOT NULL THEN ROUND(-excel_monthly_rate * excel_final_days / month_days, 6) END AS signed_prorated_formula_amount
  FROM x
), scored AS (
  SELECT *,
    CASE WHEN excel_final_days IS NOT NULL AND date_span_days IS NOT NULL AND excel_final_days = date_span_days THEN 1 ELSE 0 END AS day_exact,
    CASE WHEN excel_final_charge IS NOT NULL AND full_month_formula_amount IS NOT NULL AND ABS(excel_final_charge - full_month_formula_amount) <= 0.01 THEN 1 ELSE 0 END AS full_month_amount_exact,
    CASE WHEN excel_final_charge IS NOT NULL AND prorated_formula_amount IS NOT NULL AND ABS(excel_final_charge - prorated_formula_amount) <= 0.01 THEN 1 ELSE 0 END AS prorated_amount_exact,
    CASE WHEN excel_final_charge IS NOT NULL AND signed_prorated_formula_amount IS NOT NULL AND ABS(excel_final_charge - signed_prorated_formula_amount) <= 0.01 THEN 1 ELSE 0 END AS signed_prorated_amount_exact,
    CASE WHEN charge_type IN ('Full Cycle Charge', 'Full Cycle Charge - Backbilled for FEB Invoice') THEN full_month_formula_amount
         WHEN charge_type LIKE 'Credit%' THEN signed_prorated_formula_amount
         ELSE prorated_formula_amount END AS type_formula_amount
  FROM f
)
SELECT billing_month, imsi, charge_type, final_start_d, final_end_d, excel_final_days,
  date_span_days, excel_monthly_rate, excel_final_charge,
  full_month_formula_amount, prorated_formula_amount, signed_prorated_formula_amount,
  type_formula_amount,
  CASE WHEN excel_final_days IS NULL OR date_span_days IS NULL THEN 'MISSING_DATE_DATA'
       WHEN excel_final_days <> date_span_days AND excel_final_charge IS NOT NULL AND type_formula_amount IS NOT NULL AND ABS(excel_final_charge - type_formula_amount) > 0.01 THEN 'DATE_AND_AMOUNT_FORMULA_RESIDUAL'
       WHEN excel_final_days <> date_span_days THEN 'DATE_SPAN_RESIDUAL'
       WHEN excel_final_charge IS NULL OR type_formula_amount IS NULL THEN 'MISSING_AMOUNT_DATA'
       WHEN ABS(excel_final_charge - type_formula_amount) > 0.01 THEN 'AMOUNT_FORMULA_RESIDUAL'
       ELSE 'NO_RESIDUAL' END AS excel_formula_residual_reason,
  CASE WHEN excel_final_charge IS NOT NULL AND type_formula_amount IS NOT NULL THEN ROUND(excel_final_charge - type_formula_amount, 6) END AS excel_formula_amount_diff
FROM scored
WHERE excel_final_days IS NULL
   OR date_span_days IS NULL
   OR excel_final_days <> date_span_days
   OR excel_final_charge IS NULL
   OR type_formula_amount IS NULL
   OR ABS(excel_final_charge - type_formula_amount) > 0.01
ORDER BY billing_month, charge_type, excel_formula_residual_reason, imsi