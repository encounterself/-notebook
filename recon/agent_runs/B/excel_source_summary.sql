WITH detail_source_map AS (
  SELECT CAST(x.source_file AS STRING) AS source_file,
         CAST(x.sheet_name AS STRING) AS sheet_name,
         CAST(x.imsi AS STRING) AS imsi,
         CAST(x.product_name AS STRING) AS product_name,
         CAST(x.charge_type AS STRING) AS charge_type,
         TRY_CAST(x.final_start_date AS DATE) AS final_start_date,
         TRY_CAST(x.final_end_date AS DATE) AS final_end_date,
         TRY_CAST(x.final_days AS DOUBLE) AS invoice_days,
         TRY_CAST(x.monthly_rate AS DOUBLE) AS invoice_unit_price,
         TRY_CAST(x.final_charge AS DOUBLE) AS invoice_amount,
         CASE
           WHEN x.source_file LIKE '%JAN 2025%' THEN '2025-01'
           WHEN x.source_file LIKE '%SEP 2025%' THEN '2025-09'
           WHEN x.source_file LIKE '%OCT 2025%' AND x.source_file LIKE '%773,793.84%' THEN '2025-10 (v2)'
           WHEN x.source_file LIKE '%OCT 2025%' AND x.source_file LIKE '%772,765.00%' THEN '2025-10 (v1)'
           WHEN x.source_file LIKE '%DEC 2025%' THEN '2025-12'
           WHEN x.source_file LIKE '%FEB 2026%' THEN '2026-02'
           WHEN x.source_file LIKE '%MAR 2026%' THEN '2026-03'
           WHEN x.source_file LIKE '%APR 2026%' THEN '2026-04'
           WHEN x.source_file LIKE '%MAY 2026%' THEN '2026-05'
           WHEN x.source_file LIKE '%JUNE 2026%' THEN '2026-06'
           WHEN x.source_file LIKE '%JULY 2026%' THEN '2026-07'
           WHEN x.source_file LIKE '%AUGUST 2026%' THEN '2026-08'
           ELSE CAST(x.source_file AS STRING) END AS official_excel_billing_month
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail x
), detail_file AS (
  SELECT official_excel_billing_month, source_file,
         COUNT(*) AS record_count, COUNT(DISTINCT imsi) AS imsi_count,
         ROUND(SUM(invoice_amount), 6) AS total_final_charge,
         ROUND(SUM(invoice_unit_price), 6) AS total_monthly_rate_sum,
         COUNT(DISTINCT charge_type) AS charge_type_count,
         COUNT(DISTINCT product_name) AS product_count,
         MIN(final_start_date) AS min_final_start_date, MAX(final_start_date) AS max_final_start_date,
         SUM(CASE WHEN final_start_date IS NULL THEN 1 ELSE 0 END) AS missing_final_start_rows,
         SUM(CASE WHEN final_start_date IS NOT NULL AND DATE_FORMAT(final_start_date, 'yyyy-MM') <> official_excel_billing_month THEN 1 ELSE 0 END) AS final_start_source_conflict_rows,
         CASE WHEN SUM(CASE WHEN final_start_date IS NULL THEN 1 ELSE 0 END) > 0 THEN 'MISSING_FINAL_START_DATE'
              WHEN SUM(CASE WHEN final_start_date IS NOT NULL AND DATE_FORMAT(final_start_date, 'yyyy-MM') <> official_excel_billing_month THEN 1 ELSE 0 END) > 0 THEN 'SOURCE_FILE_FINAL_START_CONFLICT'
              ELSE 'SOURCE_FILE_MAPPING_MATCHES_FINAL_START' END AS source_match_status
  FROM detail_source_map
  GROUP BY official_excel_billing_month, source_file
), detail_month AS (
  SELECT official_excel_billing_month, COUNT(*) AS record_count, COUNT(DISTINCT imsi) AS imsi_count,
         ROUND(SUM(invoice_amount), 6) AS total_final_charge,
         ROUND(SUM(invoice_unit_price), 6) AS total_monthly_rate_sum,
         COUNT(DISTINCT charge_type) AS charge_type_count, COUNT(DISTINCT product_name) AS product_count,
         SUM(CASE WHEN final_start_date IS NULL THEN 1 ELSE 0 END) AS missing_final_start_rows,
         SUM(CASE WHEN final_start_date IS NOT NULL AND DATE_FORMAT(final_start_date, 'yyyy-MM') <> official_excel_billing_month THEN 1 ELSE 0 END) AS final_start_source_conflict_rows
  FROM detail_source_map GROUP BY official_excel_billing_month
), detail_formula AS (
  SELECT official_excel_billing_month,
         SUM(CASE
           WHEN LOWER(charge_type) LIKE '%full cycle%' OR LOWER(charge_type) LIKE '%backbilled%' THEN CASE WHEN ABS(invoice_amount - invoice_unit_price) > 0.000001 THEN 1 ELSE 0 END
           WHEN LOWER(charge_type) LIKE '%prorated-out%' THEN CASE WHEN ABS(invoice_amount + invoice_unit_price * invoice_days / NULLIF(DATEDIFF(final_end_date, final_start_date) + 1, 0)) > 0.000001 THEN 1 ELSE 0 END
           WHEN LOWER(charge_type) LIKE '%credit%' THEN CASE WHEN ABS(invoice_amount + invoice_unit_price * ((DATEDIFF(final_end_date, final_start_date) + 1) - invoice_days) / NULLIF(DATEDIFF(final_end_date, final_start_date) + 1, 0)) > 0.000001 THEN 1 ELSE 0 END
           WHEN LOWER(charge_type) LIKE '%new activation%' OR LOWER(charge_type) LIKE '%product transfer%' OR LOWER(charge_type) LIKE '%card replaced%' OR LOWER(charge_type) LIKE '%replacement%' THEN CASE WHEN ABS(invoice_amount - invoice_unit_price * invoice_days / NULLIF(DATEDIFF(final_end_date, final_start_date) + 1, 0)) > 0.000001 THEN 1 ELSE 0 END
           ELSE 0 END) AS formula_mismatch_rows,
         SUM(CASE WHEN final_start_date IS NOT NULL AND final_end_date IS NOT NULL AND invoice_days IS NOT NULL AND invoice_days <> DATEDIFF(final_end_date, final_start_date) + 1 THEN 1 ELSE 0 END) AS final_date_span_mismatch_rows
  FROM detail_source_map GROUP BY official_excel_billing_month
), prorated AS (
  SELECT CASE WHEN source_file LIKE '%JAN 2025%' THEN '2025-01' WHEN source_file LIKE '%DEC 2025%' THEN '2025-12' WHEN source_file LIKE '%FEB 2026%' THEN '2026-02' WHEN source_file LIKE '%MAR 2026%' THEN '2026-03' ELSE source_file END AS auxiliary_source_month,
         COUNT(*) AS record_count, COUNT(DISTINCT CAST(imsi AS STRING)) AS imsi_count,
         ROUND(SUM(TRY_CAST(final_charge_for_usage_days AS DOUBLE)), 6) AS total_final_charge,
         ROUND(SUM(TRY_CAST(pending_charge AS DOUBLE)), 6) AS total_pending_charge,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(CAST(source_file AS STRING)))) AS source_files
  FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated GROUP BY CASE WHEN source_file LIKE '%JAN 2025%' THEN '2025-01' WHEN source_file LIKE '%DEC 2025%' THEN '2025-12' WHEN source_file LIKE '%FEB 2026%' THEN '2026-02' WHEN source_file LIKE '%MAR 2026%' THEN '2026-03' ELSE source_file END
), credit AS (
  SELECT COUNT(*) AS record_count, COUNT(DISTINCT CAST(imsi AS STRING)) AS imsi_count,
         ROUND(SUM(TRY_CAST(credit_owed AS DOUBLE)), 6) AS total_credit_owed,
         CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(CAST(source_file AS STRING)))) AS source_files
  FROM simo_prod.mysql_cdc_sync.wa_invoice_credit
)
SELECT 'OFFICIAL_DETAIL_FILE' AS record_kind, f.official_excel_billing_month AS official_excel_billing_month, f.source_file,
       f.record_count, f.imsi_count, f.total_final_charge, f.total_monthly_rate_sum, f.charge_type_count, f.product_count,
       f.min_final_start_date, f.max_final_start_date, f.missing_final_start_rows, f.final_start_source_conflict_rows, f.source_match_status,
       CASE WHEN f.official_excel_billing_month IN ('2025-12','2026-01','2026-02') THEN 1 ELSE 0 END AS in_B_batch,
       'Official Excel baseline: direct detail grouped by source_file; no union with credit/prorated' AS evidence_note
FROM detail_file f
UNION ALL
SELECT 'OFFICIAL_DETAIL_MONTH', m.official_excel_billing_month, CAST(NULL AS STRING), m.record_count, m.imsi_count, m.total_final_charge, m.total_monthly_rate_sum, m.charge_type_count, m.product_count,
       CAST(NULL AS DATE), CAST(NULL AS DATE), m.missing_final_start_rows, m.final_start_source_conflict_rows,
       CASE WHEN m.missing_final_start_rows > 0 THEN 'MISSING_FINAL_START_DATE' WHEN m.final_start_source_conflict_rows > 0 THEN 'SOURCE_FILE_FINAL_START_CONFLICT' ELSE 'SOURCE_FILE_MAPPING_MONTH_TOTAL' END,
       CASE WHEN m.official_excel_billing_month IN ('2025-12','2026-01','2026-02') THEN 1 ELSE 0 END,
       'total_final_charge is the official amount; total_monthly_rate_sum is diagnostic only'
FROM detail_month m
UNION ALL
SELECT 'PRORATED_INDEPENDENT', p.auxiliary_source_month, p.source_files, p.record_count, p.imsi_count, p.total_final_charge, p.total_pending_charge, CAST(NULL AS BIGINT), CAST(NULL AS BIGINT), CAST(NULL AS DATE), CAST(NULL AS DATE), CAST(NULL AS BIGINT), CAST(NULL AS BIGINT), 'AUXILIARY_NOT_OFFICIAL_DETAIL', 0, 'Independent auxiliary source; never added to official detail amount'
FROM prorated p
UNION ALL
SELECT 'CREDIT_INDEPENDENT', CAST(NULL AS STRING), c.source_files, c.record_count, c.imsi_count, c.total_credit_owed, CAST(NULL AS DOUBLE), CAST(NULL AS BIGINT), CAST(NULL AS BIGINT), CAST(NULL AS DATE), CAST(NULL AS DATE), CAST(NULL AS BIGINT), CAST(NULL AS BIGINT), 'NO_OFFICIAL_BILLING_MONTH_KEY', 0, 'Independent credit source; negative/positive credit kept separately and never added to official detail amount'
FROM credit c
UNION ALL
SELECT 'FORMULA_CHECK', q.official_excel_billing_month, CAST(NULL AS STRING), CAST(NULL AS BIGINT), CAST(NULL AS BIGINT), CAST(NULL AS DOUBLE), CAST(NULL AS DOUBLE), CAST(NULL AS BIGINT), CAST(NULL AS BIGINT), CAST(NULL AS DATE), CAST(NULL AS DATE), q.formula_mismatch_rows, q.final_date_span_mismatch_rows, 'DETAIL_SELF_FIELD_CHECK', CASE WHEN q.official_excel_billing_month IN ('2025-12','2026-01','2026-02') THEN 1 ELSE 0 END, 'Formula/date checks use detail fields only; no amount back-solving'
FROM detail_formula q
ORDER BY record_kind, official_excel_billing_month, source_file