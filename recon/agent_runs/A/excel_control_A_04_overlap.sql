WITH detail_imsi AS (
  SELECT imsi, COUNT(*) AS row_count, ROUND(SUM(TRY_CAST(final_charge AS DOUBLE)), 6) AS amount_sum
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  GROUP BY imsi
), credit_imsi AS (
  SELECT imsi, COUNT(*) AS row_count, ROUND(SUM(TRY_CAST(credit_owed AS DOUBLE)), 6) AS amount_sum
  FROM simo_prod.mysql_cdc_sync.wa_invoice_credit
  GROUP BY imsi
), prorated_imsi AS (
  SELECT imsi, COUNT(*) AS row_count, ROUND(SUM(TRY_CAST(final_charge_for_usage_days AS DOUBLE)), 6) AS amount_sum
  FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
  GROUP BY imsi
), imsi_overlap AS (
  SELECT 'IMSI_OVERLAP' AS check_kind, 'detail_vs_credit' AS table_pair,
    COUNT(*) AS shared_key_count,
    ROUND(SUM(d.amount_sum), 6) AS left_amount_sum,
    ROUND(SUM(c.amount_sum), 6) AS right_amount_sum,
    SUM(d.row_count) AS left_row_count,
    SUM(c.row_count) AS right_row_count,
    CAST(NULL AS STRING) AS shared_values
  FROM detail_imsi d JOIN credit_imsi c ON d.imsi <=> c.imsi
  WHERE d.imsi IS NOT NULL
  UNION ALL
  SELECT 'IMSI_OVERLAP','detail_vs_prorated',COUNT(*),ROUND(SUM(d.amount_sum),6),ROUND(SUM(p.amount_sum),6),SUM(d.row_count),SUM(p.row_count),CAST(NULL AS STRING)
  FROM detail_imsi d JOIN prorated_imsi p ON d.imsi <=> p.imsi
  WHERE d.imsi IS NOT NULL
  UNION ALL
  SELECT 'IMSI_OVERLAP','credit_vs_prorated',COUNT(*),ROUND(SUM(c.amount_sum),6),ROUND(SUM(p.amount_sum),6),SUM(c.row_count),SUM(p.row_count),CAST(NULL AS STRING)
  FROM credit_imsi c JOIN prorated_imsi p ON c.imsi <=> p.imsi
  WHERE c.imsi IS NOT NULL
), detail_sources AS (SELECT DISTINCT source_file FROM simo_prod.mysql_cdc_sync.wa_invoice_detail),
credit_sources AS (SELECT DISTINCT source_file FROM simo_prod.mysql_cdc_sync.wa_invoice_credit),
prorated_sources AS (SELECT DISTINCT source_file FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated),
source_overlap AS (
  SELECT 'SOURCE_FILE_OVERLAP','detail_vs_credit',COUNT(*),CAST(NULL AS DOUBLE),CAST(NULL AS DOUBLE),CAST(NULL AS BIGINT),CAST(NULL AS BIGINT),CONCAT_WS(' || ',SORT_ARRAY(COLLECT_SET(CAST(d.source_file AS STRING))))
  FROM detail_sources d JOIN credit_sources c ON d.source_file <=> c.source_file
  WHERE d.source_file IS NOT NULL
  UNION ALL
  SELECT 'SOURCE_FILE_OVERLAP','detail_vs_prorated',COUNT(*),CAST(NULL AS DOUBLE),CAST(NULL AS DOUBLE),CAST(NULL AS BIGINT),CAST(NULL AS BIGINT),CONCAT_WS(' || ',SORT_ARRAY(COLLECT_SET(CAST(d.source_file AS STRING))))
  FROM detail_sources d JOIN prorated_sources p ON d.source_file <=> p.source_file
  WHERE d.source_file IS NOT NULL
  UNION ALL
  SELECT 'SOURCE_FILE_OVERLAP','credit_vs_prorated',COUNT(*),CAST(NULL AS DOUBLE),CAST(NULL AS DOUBLE),CAST(NULL AS BIGINT),CAST(NULL AS BIGINT),CONCAT_WS(' || ',SORT_ARRAY(COLLECT_SET(CAST(c.source_file AS STRING))))
  FROM credit_sources c JOIN prorated_sources p ON c.source_file <=> p.source_file
  WHERE c.source_file IS NOT NULL
), detail_row_keys AS (
  SELECT
    CONCAT_WS('||',COALESCE(CAST(imsi AS STRING),''),COALESCE(CAST(source_file AS STRING),''),COALESCE(CAST(final_start_date AS STRING),''),COALESCE(CAST(final_end_date AS STRING),''),COALESCE(CAST(charge_type AS STRING),''),COALESCE(CAST(final_charge AS STRING),'')) AS row_key,
    ROUND(SUM(TRY_CAST(final_charge AS DOUBLE)),6) AS amount_sum, COUNT(*) AS row_count
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  GROUP BY imsi, source_file, final_start_date, final_end_date, charge_type, final_charge
), credit_row_keys AS (
  SELECT
    CONCAT_WS('||',COALESCE(CAST(imsi AS STRING),''),COALESCE(CAST(source_file AS STRING),''),COALESCE(CAST(date_line_went_down AS STRING),''),COALESCE(CAST(cycle_end AS STRING),''),COALESCE(CAST(credit_owed AS STRING),'')) AS row_key,
    ROUND(SUM(TRY_CAST(credit_owed AS DOUBLE)),6) AS amount_sum, COUNT(*) AS row_count
  FROM simo_prod.mysql_cdc_sync.wa_invoice_credit
  GROUP BY imsi, source_file, date_line_went_down, cycle_end, credit_owed
), prorated_row_keys AS (
  SELECT
    CONCAT_WS('||',COALESCE(CAST(imsi AS STRING),''),COALESCE(CAST(source_file AS STRING),''),COALESCE(CAST(final_start_date AS STRING),''),COALESCE(CAST(final_end_date AS STRING),''),COALESCE(CAST(final_charge_for_usage_days AS STRING),'')) AS row_key,
    ROUND(SUM(TRY_CAST(final_charge_for_usage_days AS DOUBLE)),6) AS amount_sum, COUNT(*) AS row_count
  FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
  GROUP BY imsi, source_file, final_start_date, final_end_date, final_charge_for_usage_days
), row_key_overlap AS (
  SELECT 'CANDIDATE_ROW_KEY_OVERLAP','detail_vs_credit',COUNT(*),ROUND(SUM(d.amount_sum),6),ROUND(SUM(c.amount_sum),6),SUM(d.row_count),SUM(c.row_count),CAST(NULL AS STRING)
  FROM detail_row_keys d JOIN credit_row_keys c ON d.row_key=c.row_key
  UNION ALL
  SELECT 'CANDIDATE_ROW_KEY_OVERLAP','detail_vs_prorated',COUNT(*),ROUND(SUM(d.amount_sum),6),ROUND(SUM(p.amount_sum),6),SUM(d.row_count),SUM(p.row_count),CAST(NULL AS STRING)
  FROM detail_row_keys d JOIN prorated_row_keys p ON d.row_key=p.row_key
  UNION ALL
  SELECT 'CANDIDATE_ROW_KEY_OVERLAP','credit_vs_prorated',COUNT(*),ROUND(SUM(c.amount_sum),6),ROUND(SUM(p.amount_sum),6),SUM(c.row_count),SUM(p.row_count),CAST(NULL AS STRING)
  FROM credit_row_keys c JOIN prorated_row_keys p ON c.row_key=p.row_key
)
SELECT * FROM imsi_overlap
UNION ALL SELECT * FROM source_overlap
UNION ALL SELECT * FROM row_key_overlap
ORDER BY check_kind, table_pair