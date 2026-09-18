-- Batch A / official Excel baseline by user-specified source_file CASE.
-- Read-only. source_file mapping is authoritative; final_start_date is diagnostic only.
WITH mapped_detail AS (
  SELECT
    x.source_file AS excel_source_file,
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
      ELSE x.source_file
    END AS official_excel_billing_month,
    TRY_CAST(x.final_start_date AS DATE) AS final_start_date,
    x.imsi,
    TRY_CAST(x.final_charge AS DOUBLE) AS final_charge,
    TRY_CAST(x.monthly_rate AS DOUBLE) AS monthly_rate,
    x.charge_type,
    x.product_name
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail x
), source_file_agg AS (
  SELECT
    'SOURCE_FILE' AS result_grain,
    official_excel_billing_month,
    excel_source_file,
    COUNT(*) AS record_count,
    COUNT(DISTINCT imsi) AS imsi_count,
    ROUND(SUM(final_charge), 4) AS total_final_charge,
    ROUND(SUM(monthly_rate), 4) AS total_monthly_rate_sum,
    COUNT(DISTINCT charge_type) AS charge_type_count,
    COUNT(DISTINCT product_name) AS product_count,
    COUNT(DISTINCT DATE_FORMAT(final_start_date, 'yyyy-MM')) AS final_start_month_count,
    CONCAT_WS(',', SORT_ARRAY(COLLECT_SET(DATE_FORMAT(final_start_date, 'yyyy-MM')))) AS final_start_month_values,
    SUM(CASE WHEN official_excel_billing_month IN ('2025-09','2025-10 (v1)','2025-10 (v2)')
                   AND DATE_FORMAT(final_start_date, 'yyyy-MM') NOT IN ('2025-09','2025-10')
             THEN 1 ELSE 0 END) AS final_start_source_month_conflict_rows,
    CASE WHEN official_excel_billing_month IN ('2025-09','2025-10 (v1)','2025-10 (v2)') THEN 'BATCH_A_SOURCE' ELSE 'OUTSIDE_BATCH_A' END AS batch_a_scope
  FROM mapped_detail
  GROUP BY official_excel_billing_month, excel_source_file
), official_month_agg AS (
  SELECT
    'OFFICIAL_MONTH' AS result_grain,
    official_excel_billing_month,
    CAST(NULL AS STRING) AS excel_source_file,
    SUM(record_count) AS record_count,
    SUM(imsi_count) AS imsi_count,
    ROUND(SUM(total_final_charge), 4) AS total_final_charge,
    ROUND(SUM(total_monthly_rate_sum), 4) AS total_monthly_rate_sum,
    SUM(charge_type_count) AS charge_type_count,
    SUM(product_count) AS product_count,
    CAST(NULL AS BIGINT) AS final_start_month_count,
    CAST(NULL AS STRING) AS final_start_month_values,
    SUM(final_start_source_month_conflict_rows) AS final_start_source_month_conflict_rows,
    CASE WHEN official_excel_billing_month IN ('2025-09','2025-10 (v1)','2025-10 (v2)') THEN 'BATCH_A_SOURCE' ELSE 'OUTSIDE_BATCH_A' END AS batch_a_scope
  FROM source_file_agg
  GROUP BY official_excel_billing_month
)
SELECT * FROM source_file_agg
UNION ALL
SELECT * FROM official_month_agg
ORDER BY result_grain, official_excel_billing_month, excel_source_file