WITH e AS (
  SELECT
    trim(source_file) AS source_file,
    trim(imsi) AS imsi,
    trim(charge_type) AS charge_type,
    to_date(trim(cycle_start_date)) AS cycle_start,
    to_date(trim(cycle_end_date)) AS cycle_end,
    to_date(trim(final_start_date)) AS final_start,
    to_date(trim(final_end_date)) AS final_end,
    try_cast(nullif(trim(final_days), '') AS DECIMAL(38,10)) AS excel_days,
    try_cast(nullif(trim(monthly_rate), '') AS DECIMAL(38,10)) AS excel_price,
    try_cast(nullif(trim(final_charge), '') AS DECIMAL(38,10)) AS excel_amount,
    datediff(to_date(trim(final_end_date)), to_date(trim(final_start_date))) + 1 AS date_days,
    day(last_day(to_date(trim(final_start_date)))) AS start_month_days,
    day(last_day(to_date(trim(final_end_date)))) AS end_month_days,
    datediff(to_date(trim(cycle_end_date)), to_date(trim(cycle_start_date))) + 1 AS cycle_days
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE trim(source_file) LIKE '%MAR 2026%'
     OR trim(source_file) LIKE '%APR 2026%'
     OR trim(source_file) LIKE '%MAY 2026%'
),
x AS (
  SELECT *,
    excel_amount - excel_price * excel_days / nullif(start_month_days, 0) AS err_start_month,
    excel_amount - excel_price * excel_days / nullif(end_month_days, 0) AS err_end_month,
    excel_amount - excel_price * excel_days / nullif(cycle_days, 0) AS err_cycle
  FROM e
  WHERE excel_amount IS NOT NULL AND excel_price IS NOT NULL AND excel_days IS NOT NULL
)
SELECT
  source_file,
  charge_type,
  COUNT(*) AS rows,
  SUM(CASE WHEN abs(err_start_month) < 0.0001 THEN 1 ELSE 0 END) AS start_month_formula_hits,
  SUM(CASE WHEN abs(err_end_month) < 0.0001 THEN 1 ELSE 0 END) AS end_month_formula_hits,
  SUM(CASE WHEN abs(err_cycle) < 0.0001 THEN 1 ELSE 0 END) AS cycle_formula_hits,
  SUM(CASE WHEN abs(excel_days - date_days) < 0.0001 THEN 1 ELSE 0 END) AS date_days_hits,
  SUM(CASE WHEN abs(excel_days - cycle_days) < 0.0001 THEN 1 ELSE 0 END) AS cycle_days_hits,
  SUM(abs(err_start_month)) AS abs_err_start_month,
  SUM(abs(err_end_month)) AS abs_err_end_month,
  SUM(abs(err_cycle)) AS abs_err_cycle,
  MIN(start_month_days) AS min_start_month_days,
  MAX(start_month_days) AS max_start_month_days,
  MIN(end_month_days) AS min_end_month_days,
  MAX(end_month_days) AS max_end_month_days,
  MIN(cycle_days) AS min_cycle_days,
  MAX(cycle_days) AS max_cycle_days
FROM x
GROUP BY source_file, charge_type
ORDER BY source_file, charge_type