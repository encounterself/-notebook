SELECT 'wa_invoice_detail' AS object_name,
       COUNT(*) AS row_count,
       MIN(TRY_CAST(final_start_date AS DATE)) AS min_relevant_date,
       MAX(TRY_CAST(final_start_date AS DATE)) AS max_relevant_date,
       CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(CAST(source_file AS STRING)))) AS source_files
FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
WHERE TRY_CAST(final_start_date AS DATE) BETWEEN DATE '2025-12-01' AND DATE '2026-02-28'
UNION ALL
SELECT 'wa_invoice_credit', COUNT(*), MIN(TRY_CAST(cycle_start AS DATE)), MAX(TRY_CAST(cycle_end AS DATE)), CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(CAST(source_file AS STRING))))
FROM simo_prod.mysql_cdc_sync.wa_invoice_credit
UNION ALL
SELECT 'wa_invoice_prorated', COUNT(*), MIN(TRY_CAST(final_start_date AS DATE)), MAX(TRY_CAST(final_start_date AS DATE)), CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(CAST(source_file AS STRING))))
FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
UNION ALL
SELECT 'status_snapshot_2025_12_31', COUNT(*), MIN(CAST(partition_time AS DATE)), MAX(CAST(partition_time AS DATE)), CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(CAST(year AS STRING) || '-' || CAST(month AS STRING) || '-' || CAST(day AS STRING))))
FROM simo_prod.tc_cdr.sim_status_for_sftp_bak
WHERE year = 2025 AND month = 12 AND day = 31
UNION ALL
SELECT 'status_snapshot_2026_01_31', COUNT(*), MIN(CAST(partition_time AS DATE)), MAX(CAST(partition_time AS DATE)), CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(CAST(year AS STRING) || '-' || CAST(month AS STRING) || '-' || CAST(day AS STRING))))
FROM simo_prod.tc_cdr.sim_status_for_sftp_bak
WHERE year = 2026 AND month = 1 AND day = 31
UNION ALL
SELECT 'status_snapshot_2026_02_28', COUNT(*), MIN(CAST(partition_time AS DATE)), MAX(CAST(partition_time AS DATE)), CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(CAST(year AS STRING) || '-' || CAST(month AS STRING) || '-' || CAST(day AS STRING))))
FROM simo_prod.tc_cdr.sim_status_for_sftp_bak
WHERE year = 2026 AND month = 2 AND day = 28
UNION ALL
SELECT 'product_dim_supplier_2275', COUNT(*), CAST(NULL AS DATE), CAST(NULL AS DATE), CONCAT_WS(' | ', SORT_ARRAY(COLLECT_SET(CAST(product_name AS STRING))))
FROM simo_prod.ods.resource_res_vsim_product
WHERE supplier_id = 2275