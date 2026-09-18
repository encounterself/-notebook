/* READ-ONLY IMSI overlap samples. The pair key is only normalized IMSI for this diagnostic sample.
   Exact-key flags use the same definitions as excel_control_B_overlap_unified.sql.
   Normalization: trim strings; to_date(try_cast(trim(timestamp) AS TIMESTAMP)); amounts DECIMAL(38,12).
*/
WITH
D AS (
  SELECT nullif(trim(source_file),'') source_file_n, nullif(trim(imsi),'') imsi_n, nullif(trim(iccid),'') iccid_n, nullif(trim(product_name),'') product_name_n,
    to_date(try_cast(nullif(trim(cycle_start_date),'') AS TIMESTAMP)) cycle_start_n, to_date(try_cast(nullif(trim(cycle_end_date),'') AS TIMESTAMP)) cycle_end_n,
    to_date(try_cast(nullif(trim(final_start_date),'') AS TIMESTAMP)) final_start_n, to_date(try_cast(nullif(trim(final_end_date),'') AS TIMESTAMP)) final_end_n,
    try_cast(nullif(trim(final_days),'') AS DECIMAL(38,12)) detail_days_n, try_cast(nullif(trim(monthly_rate),'') AS DECIMAL(38,12)) detail_price_n, try_cast(nullif(trim(final_charge),'') AS DECIMAL(38,12)) detail_amount_n,
    concat_ws('|',coalesce(nullif(trim(source_file),''),'<NULL>'),coalesce(nullif(trim(imsi),''),'<NULL>'),coalesce(nullif(trim(iccid),''),'<NULL>'),coalesce(nullif(trim(product_name),''),'<NULL>'),coalesce(date_format(to_date(try_cast(nullif(trim(cycle_start_date),'') AS TIMESTAMP)),'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(to_date(try_cast(nullif(trim(cycle_end_date),'') AS TIMESTAMP)),'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(to_date(try_cast(nullif(trim(final_start_date),'') AS TIMESTAMP)),'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(to_date(try_cast(nullif(trim(final_end_date),'') AS TIMESTAMP)),'yyyy-MM-dd'),'<NULL>')) common_exact_key,
    concat_ws('|',coalesce(nullif(trim(source_file),''),'<NULL>'),coalesce(nullif(trim(imsi),''),'<NULL>'),coalesce(date_format(to_date(try_cast(nullif(trim(cycle_start_date),'') AS TIMESTAMP)),'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(to_date(try_cast(nullif(trim(cycle_end_date),'') AS TIMESTAMP)),'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(to_date(try_cast(nullif(trim(final_start_date),'') AS TIMESTAMP)),'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(to_date(try_cast(nullif(trim(final_end_date),'') AS TIMESTAMP)),'yyyy-MM-dd'),'<NULL>')) source_imsi_cycle_final_key,
    concat_ws('|',coalesce(nullif(trim(source_file),''),'<NULL>'),coalesce(nullif(trim(imsi),''),'<NULL>'),coalesce(date_format(to_date(try_cast(nullif(trim(cycle_start_date),'') AS TIMESTAMP)),'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(to_date(try_cast(nullif(trim(cycle_end_date),'') AS TIMESTAMP)),'yyyy-MM-dd'),'<NULL>')) source_imsi_cycle_key
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
),
P AS (
  SELECT nullif(trim(source_file),'') source_file_n, nullif(trim(imsi),'') imsi_n, nullif(trim(iccid),'') iccid_n, nullif(trim(product_name),'') product_name_n,
    to_date(try_cast(nullif(trim(cycle_start_date),'') AS TIMESTAMP)) cycle_start_n, to_date(try_cast(nullif(trim(cycle_end_date),'') AS TIMESTAMP)) cycle_end_n,
    to_date(try_cast(nullif(trim(final_start_date),'') AS TIMESTAMP)) final_start_n, to_date(try_cast(nullif(trim(final_end_date),'') AS TIMESTAMP)) final_end_n,
    try_cast(nullif(trim(usage_days),'') AS DECIMAL(38,12)) prorated_days_n, try_cast(nullif(trim(monthly_rate),'') AS DECIMAL(38,12)) prorated_price_n, try_cast(nullif(trim(final_charge_for_usage_days),'') AS DECIMAL(38,12)) prorated_amount_n, try_cast(nullif(trim(pending_charge),'') AS DECIMAL(38,12)) pending_amount_n,
    concat_ws('|',coalesce(nullif(trim(source_file),''),'<NULL>'),coalesce(nullif(trim(imsi),''),'<NULL>'),coalesce(nullif(trim(iccid),''),'<NULL>'),coalesce(nullif(trim(product_name),''),'<NULL>'),coalesce(date_format(to_date(try_cast(nullif(trim(cycle_start_date),'') AS TIMESTAMP)),'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(to_date(try_cast(nullif(trim(cycle_end_date),'') AS TIMESTAMP)),'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(to_date(try_cast(nullif(trim(final_start_date),'') AS TIMESTAMP)),'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(to_date(try_cast(nullif(trim(final_end_date),'') AS TIMESTAMP)),'yyyy-MM-dd'),'<NULL>')) common_exact_key,
    concat_ws('|',coalesce(nullif(trim(source_file),''),'<NULL>'),coalesce(nullif(trim(imsi),''),'<NULL>'),coalesce(date_format(to_date(try_cast(nullif(trim(cycle_start_date),'') AS TIMESTAMP)),'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(to_date(try_cast(nullif(trim(cycle_end_date),'') AS TIMESTAMP)),'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(to_date(try_cast(nullif(trim(final_start_date),'') AS TIMESTAMP)),'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(to_date(try_cast(nullif(trim(final_end_date),'') AS TIMESTAMP)),'yyyy-MM-dd'),'<NULL>')) source_imsi_cycle_final_key,
    concat_ws('|',coalesce(nullif(trim(source_file),''),'<NULL>'),coalesce(nullif(trim(imsi),''),'<NULL>'),coalesce(date_format(to_date(try_cast(nullif(trim(cycle_start_date),'') AS TIMESTAMP)),'yyyy-MM-dd'),'<NULL>'),coalesce(date_format(to_date(try_cast(nullif(trim(cycle_end_date),'') AS TIMESTAMP)),'yyyy-MM-dd'),'<NULL>')) source_imsi_cycle_key
  FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
),
PAIRS AS (
  SELECT d.imsi_n,
    d.source_file_n detail_source_file, p.source_file_n prorated_source_file,
    d.iccid_n detail_iccid, p.iccid_n prorated_iccid, d.product_name_n detail_product_name, p.product_name_n prorated_product_name,
    d.cycle_start_n detail_cycle_start, p.cycle_start_n prorated_cycle_start, d.cycle_end_n detail_cycle_end, p.cycle_end_n prorated_cycle_end,
    d.final_start_n detail_final_start, p.final_start_n prorated_final_start, d.final_end_n detail_final_end, p.final_end_n prorated_final_end,
    d.detail_days_n, p.prorated_days_n, d.detail_price_n, p.prorated_price_n, d.detail_amount_n, p.prorated_amount_n, p.pending_amount_n,
    CASE WHEN d.source_file_n <=> p.source_file_n THEN 1 ELSE 0 END same_source_file,
    CASE WHEN d.source_imsi_cycle_key = p.source_imsi_cycle_key THEN 1 ELSE 0 END same_source_imsi_cycle_key,
    CASE WHEN d.source_imsi_cycle_final_key = p.source_imsi_cycle_final_key THEN 1 ELSE 0 END same_source_imsi_cycle_final_key,
    CASE WHEN d.common_exact_key = p.common_exact_key THEN 1 ELSE 0 END same_common_exact_key
  FROM D d INNER JOIN P p ON d.imsi_n=p.imsi_n
),
R AS (
  SELECT *, row_number() OVER (PARTITION BY imsi_n ORDER BY same_common_exact_key DESC, same_source_imsi_cycle_final_key DESC, same_source_imsi_cycle_key DESC, same_source_file DESC, detail_source_file, prorated_source_file, detail_cycle_start, prorated_cycle_start) rn
  FROM PAIRS
)
SELECT 'IMSI_OVERLAP_SAMPLE' sample_type, imsi_n imsi, detail_source_file, prorated_source_file,
  detail_iccid, prorated_iccid, detail_product_name, prorated_product_name,
  detail_cycle_start, detail_cycle_end, prorated_cycle_start, prorated_cycle_end,
  detail_final_start, detail_final_end, prorated_final_start, prorated_final_end,
  detail_days_n detail_days, prorated_days_n prorated_usage_days, detail_price_n detail_price, prorated_price_n prorated_price,
  detail_amount_n detail_amount, prorated_amount_n prorated_final_charge_for_usage_days, pending_amount_n pending_charge,
  same_source_file, same_source_imsi_cycle_key, same_source_imsi_cycle_final_key, same_common_exact_key,
  CASE WHEN same_common_exact_key=1 THEN 'SAME_COMMON_EXACT_KEY: same normalized row identity; prorated amount remains auxiliary, not an added invoice row'
       WHEN same_source_imsi_cycle_final_key=1 THEN 'SAME_SOURCE_IMSI_CYCLE_FINAL_KEY: same source/card/cycle/final window; inspect as auxiliary versus duplicate'
       WHEN same_source_imsi_cycle_key=1 THEN 'SAME_SOURCE_IMSI_CYCLE_KEY: same source/card/cycle but different final window'
       WHEN same_source_file=1 THEN 'SAME_SOURCE_IMSI_ONLY: same file/card but different cycle/date'
       ELSE 'IMSI_ONLY: different source/cycle/date; not proven duplicate' END difference_classification
FROM R WHERE rn=1 ORDER BY imsi_n