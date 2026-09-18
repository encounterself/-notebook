WITH
d AS (
  SELECT
    trim(source_file) AS source_file,
    trim(imsi) AS imsi,
    trim(iccid) AS detail_iccid,
    trim(product_name) AS detail_product_name,
    to_date(trim(cycle_start_date)) AS detail_cycle_start,
    to_date(trim(cycle_end_date)) AS detail_cycle_end,
    to_date(trim(final_start_date)) AS detail_final_start,
    to_date(trim(final_end_date)) AS detail_final_end,
    try_cast(nullif(trim(final_charge), '') AS DECIMAL(38,10)) AS detail_amount,
    trim(charge_type) AS detail_charge_type,
    ROW_NUMBER() OVER (
      PARTITION BY trim(source_file), trim(imsi)
      ORDER BY
        to_date(trim(cycle_start_date)),
        to_date(trim(cycle_end_date)),
        to_date(trim(final_start_date)),
        to_date(trim(final_end_date)),
        try_cast(nullif(trim(final_charge), '') AS DECIMAL(38,10))
    ) AS source_imsi_row
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE trim(imsi) IS NOT NULL AND trim(imsi) <> ''
),
p AS (
  SELECT
    trim(source_file) AS source_file,
    trim(imsi) AS imsi,
    trim(iccid) AS prorated_iccid,
    trim(product_name) AS prorated_product_name,
    to_date(trim(cycle_start_date)) AS prorated_cycle_start,
    to_date(trim(cycle_end_date)) AS prorated_cycle_end,
    to_date(trim(final_start_date)) AS prorated_final_start,
    to_date(trim(final_end_date)) AS prorated_final_end,
    try_cast(nullif(trim(final_charge_for_usage_days), '') AS DECIMAL(38,10)) AS prorated_final_charge_for_usage_days,
    try_cast(nullif(trim(pending_charge), '') AS DECIMAL(38,10)) AS pending_charge,
    ROW_NUMBER() OVER (
      PARTITION BY trim(source_file), trim(imsi)
      ORDER BY
        to_date(trim(cycle_start_date)),
        to_date(trim(cycle_end_date)),
        to_date(trim(final_start_date)),
        to_date(trim(final_end_date)),
        try_cast(nullif(trim(final_charge_for_usage_days), '') AS DECIMAL(38,10))
    ) AS source_imsi_row
  FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
  WHERE trim(imsi) IS NOT NULL AND trim(imsi) <> ''
),
overlap AS (
  SELECT
    d.source_file,
    d.imsi,
    d.detail_iccid,
    p.prorated_iccid,
    d.detail_product_name,
    p.prorated_product_name,
    d.detail_cycle_start,
    p.prorated_cycle_start,
    d.detail_cycle_end,
    p.prorated_cycle_end,
    d.detail_final_start,
    p.prorated_final_start,
    d.detail_final_end,
    p.prorated_final_end,
    d.detail_amount,
    p.prorated_final_charge_for_usage_days,
    p.pending_charge,
    d.detail_charge_type,
    CASE
      WHEN d.detail_iccid <=> p.prorated_iccid
       AND d.detail_product_name <=> p.prorated_product_name
       AND d.detail_cycle_start <=> p.prorated_cycle_start
       AND d.detail_cycle_end <=> p.prorated_cycle_end
       AND d.detail_final_start <=> p.prorated_final_start
       AND d.detail_final_end <=> p.prorated_final_end
      THEN 1 ELSE 0
    END AS common_fields_exact_match,
    CASE
      WHEN d.detail_cycle_start <=> p.prorated_cycle_start
       AND d.detail_cycle_end <=> p.prorated_cycle_end
      THEN 1 ELSE 0
    END AS cycle_exact_match,
    CASE
      WHEN d.detail_cycle_start <=> p.prorated_cycle_start
       AND d.detail_cycle_end <=> p.prorated_cycle_end
       AND d.detail_final_start <=> p.prorated_final_start
       AND d.detail_final_end <=> p.prorated_final_end
      THEN 1 ELSE 0
    END AS full_key_exact_match
  FROM d
  INNER JOIN p
    ON d.source_file <=> p.source_file
   AND d.imsi <=> p.imsi
   AND d.source_imsi_row = 1
   AND p.source_imsi_row = 1
),
ranked AS (
  SELECT
    *,
    CASE
      WHEN full_key_exact_match = 1
        THEN 'SAME_FULL_KEY_DIFFERENT_AMOUNT_SEMANTICS'
      WHEN cycle_exact_match = 1
        THEN 'SAME_CYCLE_KEY_DIFFERENT_FINAL_WINDOW'
      ELSE 'SAME_IMSI_DIFFERENT_RECORD'
    END AS overlap_interpretation,
    ROW_NUMBER() OVER (ORDER BY source_file, imsi) AS sample_no
  FROM overlap
)
SELECT
  sample_no,
  source_file,
  imsi,
  detail_iccid,
  prorated_iccid,
  detail_product_name,
  prorated_product_name,
  detail_cycle_start,
  prorated_cycle_start,
  detail_cycle_end,
  prorated_cycle_end,
  detail_final_start,
  prorated_final_start,
  detail_final_end,
  prorated_final_end,
  detail_amount,
  prorated_final_charge_for_usage_days,
  pending_charge,
  detail_charge_type,
  common_fields_exact_match,
  cycle_exact_match,
  full_key_exact_match,
  overlap_interpretation
FROM ranked
WHERE sample_no <= 20
ORDER BY sample_no