/* Batch B read-only platform date/product probe. */
WITH status_stats AS (
  SELECT 'simo_prod.tc_cdr.sim_status_for_sftp_bak' AS source_table, COUNT(*) AS row_count,
    MIN(TRY_CAST(TRIM(Cycle_Start_Time) AS TIMESTAMP)) AS min_cycle_start,
    MAX(TRY_CAST(TRIM(Cycle_End_Time) AS TIMESTAMP)) AS max_cycle_end,
    MIN(TRY_CAST(TRIM(partition_time) AS TIMESTAMP)) AS min_partition_time,
    MAX(TRY_CAST(TRIM(partition_time) AS TIMESTAMP)) AS max_partition_time,
    CAST(NULL AS TIMESTAMP) AS min_event_time, CAST(NULL AS TIMESTAMP) AS max_event_time
  FROM simo_prod.tc_cdr.sim_status_for_sftp_bak
), cycle_stats AS (
  SELECT 'simo_prod.ods.resource_res_vsim_cycle_history' AS source_table, COUNT(*) AS row_count,
    MIN(cycle_time) AS min_cycle_start, MAX(next_cycle_time) AS max_cycle_end,
    CAST(NULL AS TIMESTAMP) AS min_partition_time, CAST(NULL AS TIMESTAMP) AS max_partition_time,
    MIN(create_time) AS min_event_time, MAX(create_time) AS max_event_time
  FROM simo_prod.ods.resource_res_vsim_cycle_history
), log_stats AS (
  SELECT 'simo_prod.ods.resource_res_vsim_status_log' AS source_table, COUNT(*) AS row_count,
    CAST(NULL AS TIMESTAMP) AS min_cycle_start, CAST(NULL AS TIMESTAMP) AS max_cycle_end,
    MIN(TRY_CAST(partition_date AS TIMESTAMP)) AS min_partition_time,
    MAX(TRY_CAST(partition_date AS TIMESTAMP)) AS max_partition_time,
    MIN(CREATE_DATE) AS min_event_time, MAX(CREATE_DATE) AS max_event_time
  FROM simo_prod.ods.resource_res_vsim_status_log
), product_stats AS (
  SELECT 'simo_prod.ods.resource_res_vsim_product[supplier_id=2275]' AS source_table, COUNT(*) AS row_count,
    CAST(NULL AS TIMESTAMP) AS min_cycle_start, CAST(NULL AS TIMESTAMP) AS max_cycle_end,
    MIN(TRY_CAST(create_time AS TIMESTAMP)) AS min_partition_time,
    MAX(TRY_CAST(modify_time AS TIMESTAMP)) AS max_partition_time,
    CAST(NULL AS TIMESTAMP) AS min_event_time, CAST(NULL AS TIMESTAMP) AS max_event_time
  FROM simo_prod.ods.resource_res_vsim_product WHERE supplier_id=2275
)
SELECT * FROM status_stats UNION ALL SELECT * FROM cycle_stats UNION ALL SELECT * FROM log_stats UNION ALL SELECT * FROM product_stats;

WITH product_candidates AS (
  SELECT CAST(product_id AS STRING) AS platform_product_id, CAST(supplier_id AS BIGINT) AS supplier_id,
    product_name, monthly_rent, monthly_rent_withusd, package_price, package_price_withusd,
    price_include_tax, price_include_tax_withusd, billing_cycle, status, COUNT(*) AS product_row_count,
    MIN(TRY_CAST(create_time AS TIMESTAMP)) AS min_create_time, MAX(TRY_CAST(modify_time AS TIMESTAMP)) AS max_modify_time
  FROM simo_prod.ods.resource_res_vsim_product WHERE supplier_id=2275
  GROUP BY CAST(product_id AS STRING), CAST(supplier_id AS BIGINT), product_name, monthly_rent,
    monthly_rent_withusd, package_price, package_price_withusd, price_include_tax, price_include_tax_withusd,
    billing_cycle, status
)
SELECT * FROM product_candidates ORDER BY platform_product_id, product_name, monthly_rent, package_price;