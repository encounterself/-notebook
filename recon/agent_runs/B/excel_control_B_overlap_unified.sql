/* READ-ONLY KEY DEFINITIONS
   Normalization: string fields = nullif(trim(field),''); date fields = to_date(try_cast(nullif(trim(field),'') AS TIMESTAMP)); amount fields = try_cast(... AS DECIMAL(38,12)).
   COMMON_EXACT_KEY = source_file + imsi + iccid + product_name + cycle_start_date + cycle_end_date + final_start_date + final_end_date.
   SOURCE_IMSI_CYCLE_KEY = source_file + imsi + cycle_start_date + cycle_end_date.
   SOURCE_IMSI_CYCLE_FINAL_KEY = source_file + imsi + cycle_start_date + cycle_end_date + final_start_date + final_end_date.
   No raw three-table UNION; detail and prorated are normalized and compared in separate branches.
*/
WITH
D AS (
  SELECT
    nullif(trim(source_file),'') source_file_n, nullif(trim(imsi),'') imsi_n, nullif(trim(iccid),'') iccid_n, nullif(trim(product_name),'') product_name_n,
    to_date(try_cast(nullif(trim(cycle_start_date),'') AS TIMESTAMP)) cycle_start_n, to_date(try_cast(nullif(trim(cycle_end_date),'') AS TIMESTAMP)) cycle_end_n,
    to_date(try_cast(nullif(trim(final_start_date),'') AS TIMESTAMP)) final_start_n, to_date(try_cast(nullif(trim(final_end_date),'') AS TIMESTAMP)) final_end_n
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
),
P AS (
  SELECT
    nullif(trim(source_file),'') source_file_n, nullif(trim(imsi),'') imsi_n, nullif(trim(iccid),'') iccid_n, nullif(trim(product_name),'') product_name_n,
    to_date(try_cast(nullif(trim(cycle_start_date),'') AS TIMESTAMP)) cycle_start_n, to_date(try_cast(nullif(trim(cycle_end_date),'') AS TIMESTAMP)) cycle_end_n,
    to_date(try_cast(nullif(trim(final_start_date),'') AS TIMESTAMP)) final_start_n, to_date(try_cast(nullif(trim(final_end_date),'') AS TIMESTAMP)) final_end_n
  FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
),
K AS (
  SELECT *,
    concat_ws('|',coalesce(source_file_n,'<NULL>'),coalesce(imsi_n,'<NULL>'),coalesce(iccid_n,'<NULL>'),coalesce(product_name_n,'<NULL>'),coalesce(date_format(cycle_start_n,'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(cycle_end_n,'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(final_start_n,'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(final_end_n,'yyyy-MM-dd'),'<NULL>')) common_exact_key,
    concat_ws('|',coalesce(source_file_n,'<NULL>'),coalesce(imsi_n,'<NULL>'),coalesce(date_format(cycle_start_n,'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(cycle_end_n,'yyyy-MM-dd'),'<NULL>')) source_imsi_cycle_key,
    concat_ws('|',coalesce(source_file_n,'<NULL>'),coalesce(imsi_n,'<NULL>'),coalesce(date_format(cycle_start_n,'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(cycle_end_n,'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(final_start_n,'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(final_end_n,'yyyy-MM-dd'),'<NULL>')) source_imsi_cycle_final_key
  FROM D
),
L AS (
  SELECT *,
    concat_ws('|',coalesce(source_file_n,'<NULL>'),coalesce(imsi_n,'<NULL>'),coalesce(iccid_n,'<NULL>'),coalesce(product_name_n,'<NULL>'),coalesce(date_format(cycle_start_n,'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(cycle_end_n,'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(final_start_n,'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(final_end_n,'yyyy-MM-dd'),'<NULL>')) common_exact_key,
    concat_ws('|',coalesce(source_file_n,'<NULL>'),coalesce(imsi_n,'<NULL>'),coalesce(date_format(cycle_start_n,'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(cycle_end_n,'yyyy-MM-dd'),'<NULL>')) source_imsi_cycle_key,
    concat_ws('|',coalesce(source_file_n,'<NULL>'),coalesce(imsi_n,'<NULL>'),coalesce(date_format(cycle_start_n,'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(cycle_end_n,'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(final_start_n,'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(final_end_n,'yyyy-MM-dd'),'<NULL>')) source_imsi_cycle_final_key
  FROM P
)
SELECT 'IMSI_OVERLAP' metric_id, count(DISTINCT K.imsi_n) matched_distinct_keys, count(*) matched_row_pairs,
  'trim(imsi); null imsi excluded' key_definition, 'IMSI-only diagnostic; no billing join' semantic_decision
FROM K INNER JOIN L ON K.imsi_n=L.imsi_n WHERE K.imsi_n IS NOT NULL
UNION ALL
SELECT 'COMMON_EXACT_OVERLAP', count(DISTINCT K.common_exact_key), count(*),
  'source_file + imsi + iccid + product_name + cycle_start + cycle_end + final_start + final_end; strings trim; dates to_date; null marker <NULL>', 'common-field exact diagnostic; product_name is not a formal billing JOIN key'
FROM K INNER JOIN L ON K.common_exact_key=L.common_exact_key
UNION ALL
SELECT 'SOURCE_IMSI_CYCLE_OVERLAP', count(DISTINCT K.source_imsi_cycle_key), count(*),
  'source_file + imsi + cycle_start + cycle_end; strings trim; dates to_date; null marker <NULL>', 'requested cycle diagnostic key'
FROM K INNER JOIN L ON K.source_imsi_cycle_key=L.source_imsi_cycle_key
UNION ALL
SELECT 'SOURCE_IMSI_CYCLE_FINAL_OVERLAP', count(DISTINCT K.source_imsi_cycle_final_key), count(*),
  'source_file + imsi + cycle_start + cycle_end + final_start + final_end; strings trim; dates to_date; null marker <NULL>', 'requested full common date diagnostic key'
FROM K INNER JOIN L ON K.source_imsi_cycle_final_key=L.source_imsi_cycle_final_key
ORDER BY metric_id