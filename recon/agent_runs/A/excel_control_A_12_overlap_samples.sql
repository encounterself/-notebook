WITH detail_canonical AS (
  SELECT
    NULLIF(TRIM(CAST(imsi AS STRING)), '') AS imsi_std,
    NULLIF(TRIM(CAST(source_file AS STRING)), '') AS source_file_std,
    NULLIF(TRIM(CAST(product_name AS STRING)), '') AS product_name_std,
    TO_DATE(cycle_start_date) AS cycle_start_std,
    TO_DATE(cycle_end_date) AS cycle_end_std,
    TO_DATE(final_start_date) AS final_start_std,
    TO_DATE(final_end_date) AS final_end_std,
    NULLIF(TRIM(CAST(charge_type AS STRING)), '') AS charge_type_std,
    TRY_CAST(monthly_rate AS DECIMAL(38,12)) AS monthly_rate_std,
    TRY_CAST(final_days AS DECIMAL(38,12)) AS final_days_std,
    TRY_CAST(final_charge AS DECIMAL(38,12)) AS detail_amount_std
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
),
prorated_canonical AS (
  SELECT
    NULLIF(TRIM(CAST(imsi AS STRING)), '') AS imsi_std,
    NULLIF(TRIM(CAST(source_file AS STRING)), '') AS source_file_std,
    NULLIF(TRIM(CAST(product_name AS STRING)), '') AS product_name_std,
    TO_DATE(cycle_start_date) AS cycle_start_std,
    TO_DATE(cycle_end_date) AS cycle_end_std,
    TO_DATE(final_start_date) AS final_start_std,
    TO_DATE(final_end_date) AS final_end_std,
    TRY_CAST(monthly_rate AS DECIMAL(38,12)) AS monthly_rate_std,
    TRY_CAST(usage_days AS DECIMAL(38,12)) AS usage_days_std,
    TRY_CAST(final_charge_for_usage_days AS DECIMAL(38,12)) AS prorated_amount_std,
    TRY_CAST(pending_charge AS DECIMAL(38,12)) AS pending_amount_std
  FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
),
detail_ranked AS (
  SELECT *, ROW_NUMBER() OVER (
    PARTITION BY imsi_std
    ORDER BY source_file_std, cycle_start_std, cycle_end_std, final_start_std, final_end_std, detail_amount_std
  ) AS rn
  FROM detail_canonical
  WHERE imsi_std IS NOT NULL
),
prorated_ranked AS (
  SELECT *, ROW_NUMBER() OVER (
    PARTITION BY imsi_std
    ORDER BY source_file_std, cycle_start_std, cycle_end_std, final_start_std, final_end_std, prorated_amount_std
  ) AS rn
  FROM prorated_canonical
  WHERE imsi_std IS NOT NULL
),
shared_imsis AS (
  SELECT DISTINCT d.imsi_std
  FROM detail_ranked d
  JOIN prorated_ranked p ON d.imsi_std = p.imsi_std
),
sampled AS (
  SELECT
    ROW_NUMBER() OVER (ORDER BY s.imsi_std) AS sample_no,
    'IMSI_ONLY_OVERLAP_SAMPLE' AS sample_type,
    'imsi' AS sample_key_fields,
    'source_file|imsi|cycle_start|cycle_end' AS base_key_fields,
    'source_file|imsi|cycle_start|cycle_end|final_start|final_end' AS full_lifecycle_key_fields,
    'source_file|imsi|product_name|cycle_start|cycle_end|final_start|final_end|monthly_rate' AS common_fields_key_fields,
    d.imsi_std AS imsi,
    d.source_file_std AS detail_source_file,
    p.source_file_std AS prorated_source_file,
    d.product_name_std AS detail_product_name,
    p.product_name_std AS prorated_product_name,
    d.cycle_start_std AS detail_cycle_start,
    p.cycle_start_std AS prorated_cycle_start,
    d.cycle_end_std AS detail_cycle_end,
    p.cycle_end_std AS prorated_cycle_end,
    d.final_start_std AS detail_final_start,
    p.final_start_std AS prorated_final_start,
    d.final_end_std AS detail_final_end,
    p.final_end_std AS prorated_final_end,
    d.charge_type_std AS detail_charge_type,
    d.final_days_std AS detail_final_days,
    p.usage_days_std AS prorated_usage_days,
    d.monthly_rate_std AS detail_monthly_rate,
    p.monthly_rate_std AS prorated_monthly_rate,
    d.detail_amount_std AS detail_final_charge,
    p.prorated_amount_std AS prorated_final_charge_for_usage_days,
    p.pending_amount_std AS prorated_pending_charge,
    CASE WHEN d.source_file_std <=> p.source_file_std THEN 'EQUAL' ELSE 'DIFFERENT' END AS source_file_equal,
    CASE WHEN d.cycle_start_std <=> p.cycle_start_std AND d.cycle_end_std <=> p.cycle_end_std THEN 'EQUAL' ELSE 'DIFFERENT' END AS cycle_window_equal,
    CASE WHEN d.final_start_std <=> p.final_start_std AND d.final_end_std <=> p.final_end_std THEN 'EQUAL' ELSE 'DIFFERENT' END AS final_window_equal,
    CASE WHEN d.product_name_std <=> p.product_name_std THEN 'EQUAL' ELSE 'DIFFERENT' END AS product_equal,
    CASE WHEN d.monthly_rate_std <=> p.monthly_rate_std THEN 'EQUAL' ELSE 'DIFFERENT' END AS monthly_rate_equal,
    ROUND(d.detail_amount_std - p.prorated_amount_std, 6) AS detail_minus_prorated_amount,
    ROUND(d.detail_amount_std - (p.prorated_amount_std + p.pending_amount_std), 6) AS detail_minus_prorated_plus_pending,
    CASE
      WHEN d.source_file_std <=> p.source_file_std
       AND d.cycle_start_std <=> p.cycle_start_std
       AND d.cycle_end_std <=> p.cycle_end_std
      THEN 'SAME_SOURCE_AND_CYCLE_KEY'
      ELSE 'IMSI_ONLY_OVERLAP_DIFFERENT_RECORD_CONTEXT'
    END AS record_context_classification,
    'detail.final_charge and prorated.final_charge_for_usage_days are different amount semantics; pending_charge is prorated auxiliary amount. Do not union or deduplicate by IMSI alone.' AS amount_semantics_note
  FROM shared_imsis s
  JOIN detail_ranked d ON s.imsi_std = d.imsi_std AND d.rn = 1
  JOIN prorated_ranked p ON s.imsi_std = p.imsi_std AND p.rn = 1
)
SELECT *
FROM sampled
WHERE sample_no <= 20
ORDER BY sample_no
