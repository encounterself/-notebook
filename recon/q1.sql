WITH b AS (
  SELECT source_file, imsi, charge_type,
    TO_DATE(final_start_date) AS sd, TO_DATE(final_end_date) AS ed,
    TRY_CAST(final_days AS DOUBLE) AS fd,
    TRY_CAST(monthly_rate AS DOUBLE) AS rate,
    TRY_CAST(final_charge AS DOUBLE) AS chg,
    DAY(LAST_DAY(TO_DATE(final_start_date))) AS dim_sd,
    DAY(LAST_DAY(TO_DATE(final_end_date))) AS dim_ed
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE TRY_CAST(final_charge AS DOUBLE) IS NOT NULL
),
est AS (
  SELECT *,
    ROUND(rate/dim_sd*fd,2) AS est_cal,
    ROUND(chg/nullif(fd,0)*dim_sd,4) AS implied_rate_cal,
    ROUND(chg/nullif(fd,0)*dim_ed,4) AS implied_rate_ed
  FROM b
)
SELECT
  CASE
    WHEN ABS(chg-est_cal) <= 0.02 THEN 'A_calendar'
    WHEN ABS(chg-ROUND(implied_rate_cal/30*fd,4)) <= 0.02 THEN 'A_cal30'
    WHEN ABS(chg-ROUND(implied_rate_cal/31*fd,4)) <= 0.02 THEN 'A_cal31'
    WHEN chg < 0 THEN 'NEG'
    WHEN chg = 0 THEN 'ZERO'
    ELSE 'UNEXPLAINED'
  END AS formula_class,
  COUNT(1) AS n,
  ROUND(SUM(chg),2) AS sum_excel,
  ROUND(SUM(est_cal),2) AS sum_cal,
  ROUND(SUM(CASE WHEN ABS(chg-est_cal) <= 0.02 THEN 0 ELSE chg-est_cal END),2) AS unexplained_delta
FROM est
GROUP BY 1
ORDER BY n DESC
