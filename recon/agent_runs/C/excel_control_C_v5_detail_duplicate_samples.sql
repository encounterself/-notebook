WITH
d AS (
  SELECT
    trim(source_file) AS source_file,
    trim(imsi) AS imsi,
    trim(iccid) AS iccid,
    trim(product_name) AS product_name,
    to_date(trim(cycle_start_date)) AS cycle_start,
    to_date(trim(cycle_end_date)) AS cycle_end,
    to_date(trim(final_start_date)) AS final_start,
    to_date(trim(final_end_date)) AS final_end,
    try_cast(nullif(trim(final_days), '') AS DECIMAL(38,10)) AS final_days,
    try_cast(nullif(trim(monthly_rate), '') AS DECIMAL(38,10)) AS monthly_rate,
    try_cast(nullif(trim(final_charge), '') AS DECIMAL(38,10)) AS detail_amount,
    trim(charge_type) AS charge_type,
    trim(status) AS status,
    trim(new_card_imsi_replacement) AS new_card_imsi_replacement,
    trim(old_card_imsi_replaced) AS old_card_imsi_replaced
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
),
dup_profile AS (
  SELECT
    source_file,
    imsi,
    cycle_start,
    cycle_end,
    COUNT(*) AS rows_on_cycle_key,
    COUNT(DISTINCT concat_ws('|', coalesce(cast(final_start AS STRING), '#'), coalesce(cast(final_end AS STRING), '#'))) AS final_window_variants
  FROM d
  GROUP BY source_file, imsi, cycle_start, cycle_end
  HAVING COUNT(*) > 1
),
sample AS (
  SELECT
    d.*,
    k.rows_on_cycle_key,
    k.final_window_variants,
    ROW_NUMBER() OVER (
      PARTITION BY d.source_file, d.imsi, d.cycle_start, d.cycle_end
      ORDER BY d.final_start, d.final_end, d.detail_amount
    ) AS row_on_duplicate_key
  FROM d
  INNER JOIN dup_profile k
    ON d.source_file <=> k.source_file
   AND d.imsi <=> k.imsi
   AND d.cycle_start <=> k.cycle_start
   AND d.cycle_end <=> k.cycle_end
)
SELECT
  source_file,
  imsi,
  iccid,
  product_name,
  cycle_start,
  cycle_end,
  final_start,
  final_end,
  final_days,
  monthly_rate,
  detail_amount,
  charge_type,
  status,
  new_card_imsi_replacement,
  old_card_imsi_replaced,
  rows_on_cycle_key,
  final_window_variants,
  row_on_duplicate_key,
  'KEEP_BOTH_ROWS_FULL_KEY_DIFFERS' AS retention_decision
FROM sample
WHERE row_on_duplicate_key <= 2
ORDER BY source_file, imsi, cycle_start, cycle_end, row_on_duplicate_key
LIMIT 20