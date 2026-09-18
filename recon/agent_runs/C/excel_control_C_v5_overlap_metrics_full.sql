WITH
d AS (
  SELECT
    trim(source_file) AS source_file,
    trim(imsi) AS imsi,
    trim(iccid) AS iccid,
    trim(product_name) AS product_name,
    trim(data_allowance_gb) AS data_allowance_gb,
    to_date(trim(new_activation_date)) AS new_activation_date,
    to_date(trim(cycle_start_date)) AS cycle_start,
    to_date(trim(cycle_end_date)) AS cycle_end,
    to_date(trim(final_start_date)) AS final_start,
    to_date(trim(final_end_date)) AS final_end,
    try_cast(nullif(trim(active_days), '') AS DECIMAL(38,10)) AS active_days,
    try_cast(nullif(trim(usage_days), '') AS DECIMAL(38,10)) AS usage_days,
    try_cast(nullif(trim(monthly_rate), '') AS DECIMAL(38,10)) AS monthly_rate,
    try_cast(nullif(trim(final_days), '') AS DECIMAL(38,10)) AS final_days,
    try_cast(nullif(trim(final_charge), '') AS DECIMAL(38,10)) AS detail_amount
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
),
p AS (
  SELECT
    trim(source_file) AS source_file,
    trim(imsi) AS imsi,
    trim(iccid) AS iccid,
    trim(product_name) AS product_name,
    trim(data_allowance_gb) AS data_allowance_gb,
    to_date(trim(new_activation_date)) AS new_activation_date,
    to_date(trim(cycle_start_date)) AS cycle_start,
    to_date(trim(cycle_end_date)) AS cycle_end,
    to_date(trim(final_start_date)) AS final_start,
    to_date(trim(final_end_date)) AS final_end,
    try_cast(nullif(trim(active_days), '') AS DECIMAL(38,10)) AS active_days,
    try_cast(nullif(trim(usage_days), '') AS DECIMAL(38,10)) AS usage_days,
    try_cast(nullif(trim(monthly_rate), '') AS DECIMAL(38,10)) AS monthly_rate,
    try_cast(nullif(trim(final_charge_for_usage_days), '') AS DECIMAL(38,10)) AS prorated_amount,
    try_cast(nullif(trim(pending_charge), '') AS DECIMAL(38,10)) AS pending_charge
  FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
),
d_imsi AS (
  SELECT DISTINCT source_file, imsi FROM d WHERE imsi IS NOT NULL AND imsi <> ''
),
p_imsi AS (
  SELECT DISTINCT source_file, imsi FROM p WHERE imsi IS NOT NULL AND imsi <> ''
),
imsi_overlap AS (
  SELECT d.source_file, d.imsi
  FROM d_imsi d INNER JOIN p_imsi p
    ON d.source_file <=> p.source_file AND d.imsi <=> p.imsi
),
d_common_identity AS (
  SELECT DISTINCT source_file, imsi, iccid, product_name, data_allowance_gb, new_activation_date,
                  cycle_start, cycle_end, final_start, final_end
  FROM d
),
p_common_identity AS (
  SELECT DISTINCT source_file, imsi, iccid, product_name, data_allowance_gb, new_activation_date,
                  cycle_start, cycle_end, final_start, final_end
  FROM p
),
common_identity_overlap AS (
  SELECT d.source_file, d.imsi
  FROM d_common_identity d INNER JOIN p_common_identity p
    ON d.source_file <=> p.source_file
   AND d.imsi <=> p.imsi
   AND d.iccid <=> p.iccid
   AND d.product_name <=> p.product_name
   AND d.data_allowance_gb <=> p.data_allowance_gb
   AND d.new_activation_date <=> p.new_activation_date
   AND d.cycle_start <=> p.cycle_start
   AND d.cycle_end <=> p.cycle_end
   AND d.final_start <=> p.final_start
   AND d.final_end <=> p.final_end
),
d_common_attr AS (
  SELECT DISTINCT source_file, imsi, iccid, product_name, data_allowance_gb, new_activation_date,
                  cycle_start, cycle_end, final_start, final_end, active_days, usage_days, monthly_rate
  FROM d
),
p_common_attr AS (
  SELECT DISTINCT source_file, imsi, iccid, product_name, data_allowance_gb, new_activation_date,
                  cycle_start, cycle_end, final_start, final_end, active_days, usage_days, monthly_rate
  FROM p
),
common_attr_overlap AS (
  SELECT d.source_file, d.imsi
  FROM d_common_attr d INNER JOIN p_common_attr p
    ON d.source_file <=> p.source_file
   AND d.imsi <=> p.imsi
   AND d.iccid <=> p.iccid
   AND d.product_name <=> p.product_name
   AND d.data_allowance_gb <=> p.data_allowance_gb
   AND d.new_activation_date <=> p.new_activation_date
   AND d.cycle_start <=> p.cycle_start
   AND d.cycle_end <=> p.cycle_end
   AND d.final_start <=> p.final_start
   AND d.final_end <=> p.final_end
   AND d.active_days <=> p.active_days
   AND d.usage_days <=> p.usage_days
   AND d.monthly_rate <=> p.monthly_rate
),
d_cycle AS (
  SELECT source_file, imsi, cycle_start, cycle_end, COUNT(*) AS detail_rows
  FROM d GROUP BY source_file, imsi, cycle_start, cycle_end
),
p_cycle AS (
  SELECT source_file, imsi, cycle_start, cycle_end, COUNT(*) AS prorated_rows
  FROM p GROUP BY source_file, imsi, cycle_start, cycle_end
),
cycle_overlap AS (
  SELECT d.source_file, d.imsi
  FROM d_cycle d INNER JOIN p_cycle p
    ON d.source_file <=> p.source_file AND d.imsi <=> p.imsi
   AND d.cycle_start <=> p.cycle_start AND d.cycle_end <=> p.cycle_end
),
d_full AS (
  SELECT source_file, imsi, cycle_start, cycle_end, final_start, final_end, COUNT(*) AS detail_rows
  FROM d GROUP BY source_file, imsi, cycle_start, cycle_end, final_start, final_end
),
p_full AS (
  SELECT source_file, imsi, cycle_start, cycle_end, final_start, final_end, COUNT(*) AS prorated_rows
  FROM p GROUP BY source_file, imsi, cycle_start, cycle_end, final_start, final_end
),
full_overlap AS (
  SELECT d.source_file, d.imsi
  FROM d_full d INNER JOIN p_full p
    ON d.source_file <=> p.source_file AND d.imsi <=> p.imsi
   AND d.cycle_start <=> p.cycle_start AND d.cycle_end <=> p.cycle_end
   AND d.final_start <=> p.final_start AND d.final_end <=> p.final_end
),
detail_cycle_dups AS (
  SELECT source_file, imsi, cycle_start, cycle_end, COUNT(*) AS detail_rows
  FROM d GROUP BY source_file, imsi, cycle_start, cycle_end HAVING COUNT(*) > 1
),
detail_full_dups AS (
  SELECT source_file, imsi, cycle_start, cycle_end, final_start, final_end, COUNT(*) AS detail_rows
  FROM d GROUP BY source_file, imsi, cycle_start, cycle_end, final_start, final_end HAVING COUNT(*) > 1
)
SELECT '1_IMSI_OVERLAP_SOURCE_IMSI' AS metric, COUNT(*) AS overlap_key_count, COUNT(DISTINCT imsi) AS overlap_distinct_imsi,
       CAST(NULL AS BIGINT) AS detail_duplicate_key_count, CAST(NULL AS BIGINT) AS detail_duplicate_row_count,
       CAST(NULL AS BIGINT) AS detail_extra_row_count, CAST(NULL AS BIGINT) AS max_rows_per_detail_key
FROM imsi_overlap
UNION ALL
SELECT '2_COMMON_IDENTITY_EXACT_OVERLAP', COUNT(*), COUNT(DISTINCT imsi), NULL, NULL, NULL, NULL FROM common_identity_overlap
UNION ALL
SELECT '2B_COMMON_IDENTITY_PLUS_SAME_NAMED_ATTRIBUTES_DIAGNOSTIC', COUNT(*), COUNT(DISTINCT imsi), NULL, NULL, NULL, NULL FROM common_attr_overlap
UNION ALL
SELECT '3_SOURCE_IMSI_CYCLE_EXACT_OVERLAP', COUNT(*), COUNT(DISTINCT imsi), NULL, NULL, NULL, NULL FROM cycle_overlap
UNION ALL
SELECT '4_SOURCE_IMSI_CYCLE_FINAL_EXACT_OVERLAP', COUNT(*), COUNT(DISTINCT imsi), NULL, NULL, NULL, NULL FROM full_overlap
UNION ALL
SELECT '5_DETAIL_DUPLICATE_KEY_SOURCE_IMSI_CYCLE', NULL, NULL, COUNT(*), SUM(detail_rows), SUM(detail_rows - 1), MAX(detail_rows) FROM detail_cycle_dups
UNION ALL
SELECT '6_DETAIL_DUPLICATE_KEY_SOURCE_IMSI_CYCLE_FINAL', NULL, NULL, COUNT(*), SUM(detail_rows), SUM(detail_rows - 1), MAX(detail_rows) FROM detail_full_dups