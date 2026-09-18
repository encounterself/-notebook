-- Batch C independent live-only overlap diagnostics.
-- Read-only: SELECT/WITH only. No raw table UNION is used.
WITH
d AS (
  SELECT TRIM(source_file) AS source_file, NULLIF(TRIM(imsi), '') AS imsi,
         NULLIF(TRIM(cycle_start_date), '') AS cycle_start_date,
         NULLIF(TRIM(cycle_end_date), '') AS cycle_end_date,
         TRY_CAST(NULLIF(TRIM(final_charge), '') AS DECIMAL(28,8)) AS final_charge
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
),
p AS (
  SELECT TRIM(source_file) AS source_file, NULLIF(TRIM(imsi), '') AS imsi,
         NULLIF(TRIM(cycle_start_date), '') AS cycle_start_date,
         NULLIF(TRIM(cycle_end_date), '') AS cycle_end_date,
         TRY_CAST(NULLIF(TRIM(final_charge_for_usage_days), '') AS DECIMAL(28,8)) AS usage_amount,
         TRY_CAST(NULLIF(TRIM(pending_charge), '') AS DECIMAL(28,8)) AS pending_amount
  FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
),
c AS (
  SELECT TRIM(source_file) AS source_file, NULLIF(TRIM(imsi), '') AS imsi,
         NULLIF(TRIM(cycle_start), '') AS cycle_start_date,
         NULLIF(TRIM(cycle_end), '') AS cycle_end_date,
         TRY_CAST(NULLIF(TRIM(credit_owed), '') AS DECIMAL(28,8)) AS credit_owed,
         TRY_CAST(NULLIF(TRIM(final_price), '') AS DECIMAL(28,8)) AS final_price
  FROM simo_prod.mysql_cdc_sync.wa_invoice_credit
),
d_imsi AS (
  SELECT imsi, COUNT(*) AS detail_rows, SUM(final_charge) AS detail_amount
  FROM d WHERE imsi IS NOT NULL GROUP BY imsi
),
p_imsi AS (
  SELECT imsi, COUNT(*) AS prorated_rows, SUM(usage_amount) AS prorated_usage_amount, SUM(pending_amount) AS prorated_pending_amount
  FROM p WHERE imsi IS NOT NULL GROUP BY imsi
),
c_imsi AS (
  SELECT imsi, COUNT(*) AS credit_rows, SUM(credit_owed) AS credit_owed_amount, SUM(final_price) AS credit_final_price_amount
  FROM c WHERE imsi IS NOT NULL GROUP BY imsi
),
d_key AS (SELECT source_file, imsi, cycle_start_date, cycle_end_date FROM d WHERE imsi IS NOT NULL),
p_key AS (SELECT source_file, imsi, cycle_start_date, cycle_end_date FROM p WHERE imsi IS NOT NULL),
c_key AS (SELECT source_file, imsi, cycle_start_date, cycle_end_date FROM c WHERE imsi IS NOT NULL),
d_key_group AS (SELECT source_file, imsi, cycle_start_date, cycle_end_date, COUNT(*) AS key_rows FROM d_key GROUP BY source_file, imsi, cycle_start_date, cycle_end_date),
p_key_group AS (SELECT source_file, imsi, cycle_start_date, cycle_end_date, COUNT(*) AS key_rows FROM p_key GROUP BY source_file, imsi, cycle_start_date, cycle_end_date),
c_key_group AS (SELECT source_file, imsi, cycle_start_date, cycle_end_date, COUNT(*) AS key_rows FROM c_key GROUP BY source_file, imsi, cycle_start_date, cycle_end_date),
d_sources AS (SELECT DISTINCT source_file FROM d WHERE source_file IS NOT NULL),
p_sources AS (SELECT DISTINCT source_file FROM p WHERE source_file IS NOT NULL),
c_sources AS (SELECT DISTINCT source_file FROM c WHERE source_file IS NOT NULL),
d_keys AS (SELECT DISTINCT source_file, imsi, cycle_start_date, cycle_end_date FROM d_key),
p_keys AS (SELECT DISTINCT source_file, imsi, cycle_start_date, cycle_end_date FROM p_key),
c_keys AS (SELECT DISTINCT source_file, imsi, cycle_start_date, cycle_end_date FROM c_key)
SELECT
  (SELECT COUNT(*) FROM d) AS detail_row_count,
  (SELECT COUNT(DISTINCT imsi) FROM d WHERE imsi IS NOT NULL) AS detail_distinct_imsi_count,
  (SELECT SUM(final_charge) FROM d) AS detail_final_charge_sum,
  (SELECT COUNT(*) FROM p) AS prorated_row_count,
  (SELECT COUNT(DISTINCT imsi) FROM p WHERE imsi IS NOT NULL) AS prorated_distinct_imsi_count,
  (SELECT SUM(usage_amount) FROM p) AS prorated_usage_amount_sum,
  (SELECT SUM(pending_amount) FROM p) AS prorated_pending_amount_sum,
  (SELECT COUNT(*) FROM c) AS credit_row_count,
  (SELECT COUNT(DISTINCT imsi) FROM c WHERE imsi IS NOT NULL) AS credit_distinct_imsi_count,
  (SELECT SUM(credit_owed) FROM c) AS credit_owed_sum,
  (SELECT SUM(final_price) FROM c) AS credit_final_price_sum,
  (SELECT COUNT(*) FROM d_imsi JOIN p_imsi USING (imsi)) AS detail_prorated_overlap_imsi_count,
  (SELECT SUM(detail_amount) FROM d_imsi JOIN p_imsi USING (imsi)) AS detail_amount_on_detail_prorated_overlap,
  (SELECT SUM(prorated_usage_amount) FROM d_imsi JOIN p_imsi USING (imsi)) AS prorated_usage_on_detail_prorated_overlap,
  (SELECT SUM(prorated_pending_amount) FROM d_imsi JOIN p_imsi USING (imsi)) AS prorated_pending_on_detail_prorated_overlap,
  (SELECT COUNT(*) FROM d_imsi JOIN c_imsi USING (imsi)) AS detail_credit_overlap_imsi_count,
  (SELECT SUM(detail_amount) FROM d_imsi JOIN c_imsi USING (imsi)) AS detail_amount_on_detail_credit_overlap,
  (SELECT SUM(credit_owed_amount) FROM d_imsi JOIN c_imsi USING (imsi)) AS credit_owed_on_detail_credit_overlap,
  (SELECT SUM(credit_final_price_amount) FROM d_imsi JOIN c_imsi USING (imsi)) AS credit_final_price_on_detail_credit_overlap,
  (SELECT COUNT(*) FROM p_imsi JOIN c_imsi USING (imsi)) AS prorated_credit_overlap_imsi_count,
  (SELECT SUM(prorated_usage_amount) FROM p_imsi JOIN c_imsi USING (imsi)) AS prorated_usage_on_prorated_credit_overlap,
  (SELECT SUM(prorated_pending_amount) FROM p_imsi JOIN c_imsi USING (imsi)) AS prorated_pending_on_prorated_credit_overlap,
  (SELECT SUM(credit_owed_amount) FROM p_imsi JOIN c_imsi USING (imsi)) AS credit_owed_on_prorated_credit_overlap,
  (SELECT COUNT(*) FROM d_imsi JOIN p_imsi USING (imsi) JOIN c_imsi USING (imsi)) AS all_three_overlap_imsi_count,
  (SELECT COUNT(*) FROM d_sources JOIN p_sources USING (source_file)) AS detail_prorated_same_source_file_count,
  (SELECT COUNT(*) FROM d_sources JOIN c_sources USING (source_file)) AS detail_credit_same_source_file_count,
  (SELECT COUNT(*) FROM p_sources JOIN c_sources USING (source_file)) AS prorated_credit_same_source_file_count,
  (SELECT COUNT(*) FROM d_sources JOIN p_sources USING (source_file) JOIN c_sources USING (source_file)) AS all_three_same_source_file_count,
  (SELECT COUNT(*) FROM d_keys JOIN p_keys USING (source_file, imsi, cycle_start_date, cycle_end_date)) AS detail_prorated_same_candidate_key_count,
  (SELECT COUNT(*) FROM d_keys JOIN c_keys USING (source_file, imsi, cycle_start_date, cycle_end_date)) AS detail_credit_same_candidate_key_count,
  (SELECT COUNT(*) FROM p_keys JOIN c_keys USING (source_file, imsi, cycle_start_date, cycle_end_date)) AS prorated_credit_same_candidate_key_count,
  (SELECT COUNT(*) FROM d_keys JOIN p_keys USING (source_file, imsi, cycle_start_date, cycle_end_date) JOIN c_keys USING (source_file, imsi, cycle_start_date, cycle_end_date)) AS all_three_same_candidate_key_count,
  (SELECT COUNT(*) FROM d_key_group WHERE key_rows > 1) AS detail_duplicate_candidate_key_count,
  (SELECT COALESCE(SUM(key_rows - 1), 0) FROM d_key_group WHERE key_rows > 1) AS detail_duplicate_candidate_rows,
  (SELECT COUNT(*) FROM p_key_group WHERE key_rows > 1) AS prorated_duplicate_candidate_key_count,
  (SELECT COALESCE(SUM(key_rows - 1), 0) FROM p_key_group WHERE key_rows > 1) AS prorated_duplicate_candidate_rows,
  (SELECT COUNT(*) FROM c_key_group WHERE key_rows > 1) AS credit_duplicate_candidate_key_count,
  (SELECT COALESCE(SUM(key_rows - 1), 0) FROM c_key_group WHERE key_rows > 1) AS credit_duplicate_candidate_rows;
