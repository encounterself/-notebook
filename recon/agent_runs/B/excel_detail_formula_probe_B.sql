WITH d AS (
  SELECT
    TRIM(CAST(imsi AS STRING)) AS imsi,
    TRIM(CAST(source_file AS STRING)) AS source_file,
    charge_type,
    TRY_CAST(final_start_date AS DATE) AS final_start_date,
    TRY_CAST(final_end_date AS DATE) AS final_end_date,
    TRY_CAST(final_days AS DECIMAL(38,12)) AS excel_days,
    TRY_CAST(monthly_rate AS DECIMAL(38,12)) AS excel_price,
    TRY_CAST(final_charge AS DECIMAL(38,12)) AS excel_amount
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE source_file LIKE '%DEC 2025%' OR source_file LIKE '%JAN 2026%' OR source_file LIKE '%FEB 2026%'
), x AS (
  SELECT *,
    DATEDIFF(final_end_date,final_start_date) AS diff_exclusive,
    DATEDIFF(final_end_date,final_start_date)+1 AS diff_inclusive,
    DAY(LAST_DAY(final_start_date)) AS calendar_days,
    CASE WHEN final_start_date IS NOT NULL AND final_end_date IS NOT NULL AND excel_days IS NOT NULL AND excel_price IS NOT NULL
      THEN ROUND(CAST(excel_price AS DOUBLE)*CAST(excel_days AS DOUBLE)/DAY(LAST_DAY(final_start_date)),10) END AS amount_by_days_calendar
  FROM d
)
SELECT source_file, charge_type, COUNT(*) AS row_count, COUNT(DISTINCT imsi) AS imsi_count,
  SUM(excel_amount) AS total_excel_amount, SUM(excel_days) AS total_excel_days, SUM(excel_price) AS total_excel_price,
  SUM(CASE WHEN excel_days=diff_exclusive THEN 1 ELSE 0 END) AS days_match_exclusive,
  SUM(CASE WHEN excel_days=diff_inclusive THEN 1 ELSE 0 END) AS days_match_inclusive,
  SUM(CASE WHEN excel_amount IS NOT NULL AND amount_by_days_calendar IS NOT NULL AND ABS(CAST(excel_amount AS DOUBLE)-amount_by_days_calendar)<=0.000001 THEN 1 ELSE 0 END) AS amount_match_price_days_calendar,
  SUM(CASE WHEN excel_amount IS NOT NULL AND excel_price IS NOT NULL AND ABS(CAST(excel_amount AS DOUBLE)-CAST(excel_price AS DOUBLE))<=0.000001 THEN 1 ELSE 0 END) AS amount_match_full_price,
  MIN(final_start_date) AS min_start, MAX(final_start_date) AS max_start, MIN(final_end_date) AS min_end, MAX(final_end_date) AS max_end
FROM x
GROUP BY source_file, charge_type
ORDER BY source_file, charge_type;