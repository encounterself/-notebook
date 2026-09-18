/* READ-ONLY detail duplicate verification.
   Normalization: string fields = nullif(trim(field),''); dates = to_date(try_cast(nullif(trim(field),'') AS TIMESTAMP)); amounts/days/prices = DECIMAL(38,12).
   The duplicate counts are calculated independently for each explicit detail key; no deduplication is applied.
*/
WITH D AS (
  SELECT nullif(trim(source_file),'') source_file_n, nullif(trim(imsi),'') imsi_n, nullif(trim(iccid),'') iccid_n, nullif(trim(product_name),'') product_name_n,
    to_date(try_cast(nullif(trim(cycle_start_date),'') AS TIMESTAMP)) cycle_start_n, to_date(try_cast(nullif(trim(cycle_end_date),'') AS TIMESTAMP)) cycle_end_n,
    to_date(try_cast(nullif(trim(final_start_date),'') AS TIMESTAMP)) final_start_n, to_date(try_cast(nullif(trim(final_end_date),'') AS TIMESTAMP)) final_end_n,
    try_cast(nullif(trim(final_days),'') AS DECIMAL(38,12)) detail_days_n, try_cast(nullif(trim(monthly_rate),'') AS DECIMAL(38,12)) detail_price_n, try_cast(nullif(trim(final_charge),'') AS DECIMAL(38,12)) detail_amount_n
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
),
K AS (
  SELECT 'D_SOURCE_IMSI_CYCLE_FINAL' key_id, 'source_file + imsi + cycle_start + cycle_end + final_start + final_end' key_definition,
    concat_ws('|',coalesce(source_file_n,'<NULL>'),coalesce(imsi_n,'<NULL>'),coalesce(date_format(cycle_start_n,'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(cycle_end_n,'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(final_start_n,'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(final_end_n,'yyyy-MM-dd'),'<NULL>')) row_key, D.* FROM D
  UNION ALL
  SELECT 'D_COMMON_EXACT','source_file + imsi + iccid + product_name + cycle_start + cycle_end + final_start + final_end',
    concat_ws('|',coalesce(source_file_n,'<NULL>'),coalesce(imsi_n,'<NULL>'),coalesce(iccid_n,'<NULL>'),coalesce(product_name_n,'<NULL>'),coalesce(date_format(cycle_start_n,'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(cycle_end_n,'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(final_start_n,'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(final_end_n,'yyyy-MM-dd'),'<NULL>')), D.* FROM D
  UNION ALL
  SELECT 'D_SOURCE_IMSI_CYCLE','source_file + imsi + cycle_start + cycle_end',
    concat_ws('|',coalesce(source_file_n,'<NULL>'),coalesce(imsi_n,'<NULL>'),coalesce(date_format(cycle_start_n,'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(cycle_end_n,'yyyy-MM-dd'),'<NULL>')), D.* FROM D
  UNION ALL
  SELECT 'D_IMSI_ICCID_FINAL','imsi + iccid + final_start + final_end',
    concat_ws('|',coalesce(imsi_n,'<NULL>'),coalesce(iccid_n,'<NULL>'),coalesce(date_format(final_start_n,'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(final_end_n,'yyyy-MM-dd'),'<NULL>')), D.* FROM D
),
G AS (
  SELECT key_id,key_definition,row_key,count(*) duplicate_row_count,count(DISTINCT detail_amount_n) amount_variants,count(DISTINCT detail_days_n) days_variants,count(DISTINCT detail_price_n) price_variants,count(DISTINCT product_name_n) product_variants
  FROM K GROUP BY key_id,key_definition,row_key HAVING count(*) > 1
),
S AS (
  SELECT G.*, row_number() OVER (PARTITION BY key_id ORDER BY row_key) sample_rank FROM G
),
SUMMARY AS (
  SELECT 'DUPLICATE_KEY_SUMMARY' control_section,key_id,key_definition,CAST(NULL AS STRING) row_key,CAST(NULL AS STRING) source_file,CAST(NULL AS STRING) imsi,CAST(NULL AS STRING) iccid,CAST(NULL AS STRING) product_name,
    CAST(NULL AS DATE) cycle_start,CAST(NULL AS DATE) cycle_end,CAST(NULL AS DATE) final_start,CAST(NULL AS DATE) final_end,CAST(NULL AS DECIMAL(38,12)) detail_days,CAST(NULL AS DECIMAL(38,12)) detail_price,CAST(NULL AS DECIMAL(38,12)) detail_amount,
    count(*) duplicate_key_count,sum(duplicate_row_count) duplicate_row_count,sum(duplicate_row_count-1) excess_rows,sum(CASE WHEN amount_variants=1 AND days_variants=1 AND price_variants=1 AND product_variants=1 THEN 1 ELSE 0 END) uniform_value_key_count,
    CAST(NULL AS BIGINT) amount_variants,CAST(NULL AS BIGINT) days_variants,CAST(NULL AS BIGINT) price_variants,CAST(NULL AS BIGINT) product_variants,
    CASE WHEN sum(CASE WHEN amount_variants=1 AND days_variants=1 AND price_variants=1 AND product_variants=1 THEN 1 ELSE 0 END)=count(*) THEN 'all duplicate keys have identical sampled business values; retain source rows until a proven row id authorizes dedup' ELSE 'at least one duplicate key has differing business values; do not dedup' END assessment
  FROM G GROUP BY key_id,key_definition
),
SAMPLE AS (
  SELECT 'DETAIL_DUPLICATE_SAMPLE' control_section,s.key_id,s.key_definition,k.row_key,k.source_file_n source_file,k.imsi_n imsi,k.iccid_n iccid,k.product_name_n product_name,k.cycle_start_n cycle_start,k.cycle_end_n cycle_end,k.final_start_n final_start,k.final_end_n final_end,k.detail_days_n detail_days,k.detail_price_n detail_price,k.detail_amount_n detail_amount,
    CAST(NULL AS BIGINT) duplicate_key_count, s.duplicate_row_count, s.duplicate_row_count-1 excess_rows, CAST(NULL AS BIGINT) uniform_value_key_count, s.amount_variants,s.days_variants,s.price_variants,s.product_variants,
    CASE WHEN s.amount_variants=1 AND s.days_variants=1 AND s.price_variants=1 AND s.product_variants=1 THEN 'same normalized key and same business values; source rows retained for audit' ELSE 'same normalized key but differing business values; unsafe to dedup' END assessment
  FROM S s INNER JOIN K k ON s.key_id=k.key_id AND s.row_key=k.row_key WHERE s.sample_rank <= 20
)
SELECT * FROM SUMMARY
UNION ALL
SELECT * FROM SAMPLE
ORDER BY control_section,key_id,row_key,source_file,imsi