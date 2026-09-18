SELECT imsi, charge_type, cycle_start_date, cycle_end_date, final_start_date, final_end_date, final_days, monthly_rate, final_charge,
       TRY_CAST(final_charge AS DOUBLE) + TRY_CAST(monthly_rate AS DOUBLE) * TRY_CAST(final_days AS DOUBLE) / NULLIF(DATEDIFF(TRY_CAST(cycle_end_date AS DATE),TRY_CAST(cycle_start_date AS DATE))+1,0) AS signed_formula_residual,
       TRY_CAST(final_charge AS DOUBLE) + TRY_CAST(monthly_rate AS DOUBLE) * (DATEDIFF(TRY_CAST(cycle_end_date AS DATE),TRY_CAST(cycle_start_date AS DATE))+1-TRY_CAST(final_days AS DOUBLE)) / NULLIF(DATEDIFF(TRY_CAST(cycle_end_date AS DATE),TRY_CAST(cycle_start_date AS DATE))+1,0) AS complement_formula_residual
FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
WHERE TRY_CAST(final_start_date AS DATE) BETWEEN DATE '2026-01-01' AND DATE '2026-01-31'
  AND charge_type = 'Prorated-Out Credit (Offstocked for Replacement)'
ORDER BY ABS(TRY_CAST(final_charge AS DOUBLE)) DESC
LIMIT 10