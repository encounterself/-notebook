WITH requested_labels AS (
  SELECT '2026-01' AS invoice_batch_label
  UNION ALL SELECT '2026-03'
  UNION ALL SELECT '2026-04'
  UNION ALL SELECT '2026-05'
),
detail_labeled AS (
  SELECT
    CASE
      WHEN trim(source_file) LIKE '%JAN 2025%' THEN '2025-01'
      WHEN trim(source_file) LIKE '%SEP 2025%' THEN '2025-09'
      WHEN trim(source_file) LIKE '%OCT 2025%' AND trim(source_file) LIKE '%773,793.84%' THEN '2025-10 (v2)'
      WHEN trim(source_file) LIKE '%OCT 2025%' AND trim(source_file) LIKE '%772,765.00%' THEN '2025-10 (v1)'
      WHEN trim(source_file) LIKE '%DEC 2025%' THEN '2025-12'
      WHEN trim(source_file) LIKE '%FEB 2026%' THEN '2026-02'
      WHEN trim(source_file) LIKE '%MAR 2026%' THEN '2026-03'
      WHEN trim(source_file) LIKE '%APR 2026%' THEN '2026-04'
      WHEN trim(source_file) LIKE '%MAY 2026%' THEN '2026-05'
      WHEN trim(source_file) LIKE '%JUNE 2026%' THEN '2026-06'
      WHEN trim(source_file) LIKE '%JULY 2026%' THEN '2026-07'
      WHEN trim(source_file) LIKE '%AUGUST 2026%' THEN '2026-08'
      ELSE trim(source_file)
    END AS invoice_batch_label,
    trim(source_file) AS source_file,
    trim(imsi) AS imsi,
    try_cast(nullif(trim(final_charge), '') AS DECIMAL(38,10)) AS final_charge
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
),
agg AS (
  SELECT invoice_batch_label, count(*) AS row_count,
         count(DISTINCT imsi) AS distinct_imsi_count,
         coalesce(sum(final_charge), CAST(0 AS DECIMAL(38,10))) AS total_final_charge,
         count(DISTINCT source_file) AS source_file_count
  FROM detail_labeled
  GROUP BY invoice_batch_label
)
SELECT
  r.invoice_batch_label,
  coalesce(a.row_count, 0) AS excel_row_count,
  coalesce(a.distinct_imsi_count, 0) AS excel_imsi_count,
  coalesce(a.total_final_charge, CAST(0 AS DECIMAL(38,10))) AS excel_total_final_charge,
  coalesce(a.source_file_count, 0) AS source_file_count,
  CASE WHEN a.invoice_batch_label IS NULL THEN 'NO_OFFICIAL_DETAIL_SOURCE_FILE' ELSE 'DETAIL_SOURCE_PRESENT' END AS source_status
FROM requested_labels r
LEFT JOIN agg a ON a.invoice_batch_label = r.invoice_batch_label
ORDER BY r.invoice_batch_label