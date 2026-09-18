WITH x AS (
 SELECT CASE WHEN TRY_CAST(final_start_date AS DATE) BETWEEN DATE '2025-12-01' AND DATE '2025-12-31' THEN '2025-12' WHEN TRY_CAST(final_start_date AS DATE) BETWEEN DATE '2026-01-01' AND DATE '2026-01-31' THEN '2026-01' WHEN TRY_CAST(final_start_date AS DATE) BETWEEN DATE '2026-02-01' AND DATE '2026-02-28' THEN '2026-02' END AS billing_month,
        imsi, charge_type, TRY_CAST(cycle_start_date AS DATE) cs, TRY_CAST(cycle_end_date AS DATE) ce, TRY_CAST(final_days AS DOUBLE) days, TRY_CAST(monthly_rate AS DOUBLE) price, TRY_CAST(final_charge AS DOUBLE) amount, TRY_CAST(final_start_date AS DATE) fs, TRY_CAST(final_end_date AS DATE) fe
 FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
 WHERE TRY_CAST(final_start_date AS DATE) BETWEEN DATE '2025-12-01' AND DATE '2026-02-28'
), f AS (
 SELECT *, CASE
 WHEN LOWER(charge_type) LIKE '%full cycle%' OR LOWER(charge_type) LIKE '%backbilled%' THEN price
 WHEN LOWER(charge_type) LIKE '%new activation%' OR LOWER(charge_type) LIKE '%product transfer%' OR LOWER(charge_type) LIKE '%card replaced%' OR LOWER(charge_type) LIKE '%replacement%' THEN price*days/NULLIF(DATEDIFF(ce,cs)+1,0)
 WHEN LOWER(charge_type) LIKE '%prorated-out%' THEN -price*days/NULLIF(DATEDIFF(ce,cs)+1,0)
 WHEN LOWER(charge_type) LIKE '%credit%' THEN -price*((DATEDIFF(ce,cs)+1)-days)/NULLIF(DATEDIFF(ce,cs)+1,0)
 END expected
 FROM x WHERE billing_month IS NOT NULL
)
SELECT billing_month, charge_type, COUNT(*) rows, SUM(CASE WHEN expected IS NOT NULL AND ABS(amount-expected)>0.000001 THEN 1 ELSE 0 END) mismatch_rows, ROUND(SUM(amount-expected),6) diff_sum, MIN(amount-expected) min_diff, MAX(amount-expected) max_diff
FROM f GROUP BY billing_month, charge_type ORDER BY billing_month, charge_type