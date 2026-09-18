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
    try_cast(nullif(trim(active_days), '') AS DECIMAL(38,10)) AS active_days,
    try_cast(nullif(trim(usage_days), '') AS DECIMAL(38,10)) AS usage_days,
    try_cast(nullif(trim(final_days), '') AS DECIMAL(38,10)) AS final_days,
    try_cast(nullif(trim(monthly_rate), '') AS DECIMAL(38,10)) AS monthly_rate,
    try_cast(nullif(trim(final_charge), '') AS DECIMAL(38,10)) AS detail_amount,
    trim(charge_type) AS charge_type
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
),
p AS (
  SELECT
    trim(source_file) AS source_file,
    trim(imsi) AS imsi,
    trim(iccid) AS iccid,
    trim(product_name) AS product_name,
    to_date(trim(cycle_start_date)) AS cycle_start,
    to_date(trim(cycle_end_date)) AS cycle_end,
    to_date(trim(final_start_date)) AS final_start,
    to_date(trim(final_end_date)) AS final_end,
    try_cast(nullif(trim(active_days), '') AS DECIMAL(38,10)) AS active_days,
    try_cast(nullif(trim(usage_days), '') AS DECIMAL(38,10)) AS usage_days,
    try_cast(nullif(trim(monthly_rate), '') AS DECIMAL(38,10)) AS monthly_rate,
    try_cast(nullif(trim(final_charge_for_usage_days), '') AS DECIMAL(38,10)) AS prorated_final_charge_for_usage_days,
    try_cast(nullif(trim(pending_charge), '') AS DECIMAL(38,10)) AS pending_charge
  FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
),
d_imsi AS (
  SELECT DISTINCT source_file, imsi
  FROM d
  WHERE imsi IS NOT NULL AND imsi <> ''
),
p_imsi AS (
  SELECT DISTINCT source_file, imsi
  FROM p
  WHERE imsi IS NOT NULL AND imsi <> ''
),
imsi_overlap AS (
  SELECT d.source_file, d.imsi
  FROM d_imsi d
  INNER JOIN p_imsi p
    ON d.source_file <=> p.source_file
   AND d.imsi <=> p.imsi
),
d_common AS (
  SELECT DISTINCT source_file, imsi, iccid, product_name, cycle_start, cycle_end, final_start, final_end
  FROM d
),
p_common AS (
  SELECT DISTINCT source_file, imsi, iccid, product_name, cycle_start, cycle_end, final_start, final_end
  FROM p
),
common_overlap AS (
  SELECT d.source_file, d.imsi, d.iccid, d.product_name, d.cycle_start, d.cycle_end, d.final_start, d.final_end
  FROM d_common d
  INNER JOIN p_common p
    ON d.source_file <=> p.source_file
   AND d.imsi <=> p.imsi
   AND d.iccid <=> p.iccid
   AND d.product_name <=> p.product_name
   AND d.cycle_start <=> p.cycle_start
   AND d.cycle_end <=> p.cycle_end
   AND d.final_start <=> p.final_start
   AND d.final_end <=> p.final_end
),
d_cycle AS (
  SELECT source_file, imsi, cycle_start, cycle_end, COUNT(*) AS detail_rows
  FROM d
  GROUP BY source_file, imsi, cycle_start, cycle_end
),
p_cycle AS (
  SELECT source_file, imsi, cycle_start, cycle_end, COUNT(*) AS prorated_rows
  FROM p
  GROUP BY source_file, imsi, cycle_start, cycle_end
),
cycle_overlap AS (
  SELECT d.source_file, d.imsi, d.cycle_start, d.cycle_end, d.detail_rows, p.prorated_rows
  FROM d_cycle d
  INNER JOIN p_cycle p
    ON d.source_file <=> p.source_file
   AND d.imsi <=> p.imsi
   AND d.cycle_start <=> p.cycle_start
   AND d.cycle_end <=> p.cycle_end
),
d_full AS (
  SELECT source_file, imsi, cycle_start, cycle_end, final_start, final_end, COUNT(*) AS detail_rows
  FROM d
  GROUP BY source_file, imsi, cycle_start, cycle_end, final_start, final_end
),
p_full AS (
  SELECT source_file, imsi, cycle_start, cycle_end, final_start, final_end, COUNT(*) AS prorated_rows
  FROM p
  GROUP BY source_file, imsi, cycle_start, cycle_end, final_start, final_end
),
full_overlap AS (
  SELECT d.source_file, d.imsi, d.cycle_start, d.cycle_end, d.final_start, d.final_end, d.detail_rows, p.prorated_rows
  FROM d_full d
  INNER JOIN p_full p
    ON d.source_file <=> p.source_file
   AND d.imsi <=> p.imsi
   AND d.cycle_start <=> p.cycle_start
   AND d.cycle_end <=> p.cycle_end
   AND d.final_start <=> p.final_start
   AND d.final_end <=> p.final_end
),
detail_cycle_dups AS (
  SELECT source_file, imsi, cycle_start, cycle_end, COUNT(*) AS detail_rows
  FROM d
  GROUP BY source_file, imsi, cycle_start, cycle_end
  HAVING COUNT(*) > 1
),
detail_full_dups AS (
  SELECT source_file, imsi, cycle_start, cycle_end, final_start, final_end, COUNT(*) AS detail_rows
  FROM d
  GROUP BY source_file, imsi, cycle_start, cycle_end, final_start, final_end
  HAVING COUNT(*) > 1
)
SELECT '1_IMSI_OVERLAP' AS metric,
       COUNT(*) AS overlap_key_count,
       COUNT(DISTINCT imsi) AS overlap_distinct_imsi,
       CAST(NULL AS BIGINT) AS detail_duplicate_key_count,
       CAST(NULL AS BIGINT) AS detail_duplicate_row_count,
       CAST(NULL AS BIGINT) AS detail_extra_row_count,
       CAST(NULL AS BIGINT) AS max_rows_per_detail_key
FROM imsi_overlap
UNION ALL
SELECT '2_COMMON_FIELDS_EXACT_OVERLAP',
       COUNT(*),
       COUNT(DISTINCT imsi),
       NULL, NULL, NULL, NULL
FROM common_overlap
UNION ALL
SELECT '3_SOURCE_IMSI_CYCLE_EXACT_OVERLAP',
       COUNT(*),
       COUNT(DISTINCT imsi),
       NULL, NULL, NULL, NULL
FROM cycle_overlap
UNION ALL
SELECT '4_SOURCE_IMSI_CYCLE_FINAL_EXACT_OVERLAP',
       COUNT(*),
       COUNT(DISTINCT imsi),
       NULL, NULL, NULL, NULL
FROM full_overlap
UNION ALL
SELECT '5_DETAIL_DUPLICATE_KEY_SOURCE_IMSI_CYCLE',
       NULL, NULL,
       COUNT(*),
       SUM(detail_rows),
       SUM(detail_rows - 1),
       MAX(detail_rows)
FROM detail_cycle_dups
UNION ALL
SELECT '6_DETAIL_DUPLICATE_KEY_SOURCE_IMSI_CYCLE_FINAL',
       NULL, NULL,
       COUNT(*),
       SUM(detail_rows),
       SUM(detail_rows - 1),
       MAX(detail_rows)
FROM detail_full_dups