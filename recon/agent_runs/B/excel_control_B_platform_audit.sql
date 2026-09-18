WITH
D AS (
  SELECT 'simo_prod.mysql_cdc_sync.wa_invoice_detail' source_table, source_file,
    CASE WHEN source_file LIKE '%JAN 2025%' THEN '2025-01' WHEN source_file LIKE '%SEP 2025%' THEN '2025-09'
      WHEN source_file LIKE '%OCT 2025%' AND source_file LIKE '%773,793.84%' THEN '2025-10 (v2)'
      WHEN source_file LIKE '%OCT 2025%' AND source_file LIKE '%772,765.00%' THEN '2025-10 (v1)'
      WHEN source_file LIKE '%DEC 2025%' THEN '2025-12' WHEN source_file LIKE '%FEB 2026%' THEN '2026-02'
      WHEN source_file LIKE '%MAR 2026%' THEN '2026-03' WHEN source_file LIKE '%APR 2026%' THEN '2026-04'
      WHEN source_file LIKE '%MAY 2026%' THEN '2026-05' WHEN source_file LIKE '%JUNE 2026%' THEN '2026-06'
      WHEN source_file LIKE '%JULY 2026%' THEN '2026-07' WHEN source_file LIKE '%AUGUST 2026%' THEN '2026-08' ELSE source_file END invoice_batch_label,
    imsi, charge_type, try_cast(nullif(trim(final_days),'') AS DOUBLE) excel_days, try_cast(nullif(trim(monthly_rate),'') AS DOUBLE) excel_price,
    try_cast(nullif(trim(final_charge),'') AS DOUBLE) excel_amount, CAST(NULL AS DOUBLE) aux_amount, product_name,
    try_cast(nullif(trim(final_start_date),'') AS DATE) observed_start_dt, try_cast(nullif(trim(final_end_date),'') AS DATE) observed_end_dt,
    date_format(try_cast(nullif(trim(final_start_date),'') AS DATE),'yyyy-MM') observed_start_month,
    CAST(NULL AS STRING) observed_cycle_start_month, CAST(NULL AS STRING) observed_cycle_end_month,
    concat_ws('|',coalesce(imsi,''),coalesce(iccid,''),coalesce(final_start_date,''),coalesce(final_end_date,'')) row_key
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
),
P AS (
  SELECT 'simo_prod.mysql_cdc_sync.wa_invoice_prorated' source_table, source_file,
    CASE WHEN source_file LIKE '%JAN 2025%' THEN '2025-01' WHEN source_file LIKE '%SEP 2025%' THEN '2025-09'
      WHEN source_file LIKE '%OCT 2025%' AND source_file LIKE '%773,793.84%' THEN '2025-10 (v2)'
      WHEN source_file LIKE '%OCT 2025%' AND source_file LIKE '%772,765.00%' THEN '2025-10 (v1)'
      WHEN source_file LIKE '%DEC 2025%' THEN '2025-12' WHEN source_file LIKE '%FEB 2026%' THEN '2026-02'
      WHEN source_file LIKE '%MAR 2026%' THEN '2026-03' WHEN source_file LIKE '%APR 2026%' THEN '2026-04'
      WHEN source_file LIKE '%MAY 2026%' THEN '2026-05' WHEN source_file LIKE '%JUNE 2026%' THEN '2026-06'
      WHEN source_file LIKE '%JULY 2026%' THEN '2026-07' WHEN source_file LIKE '%AUGUST 2026%' THEN '2026-08' ELSE source_file END invoice_batch_label,
    imsi, CAST(NULL AS STRING) charge_type, try_cast(nullif(trim(usage_days),'') AS DOUBLE) excel_days, try_cast(nullif(trim(monthly_rate),'') AS DOUBLE) excel_price,
    try_cast(nullif(trim(final_charge_for_usage_days),'') AS DOUBLE) excel_amount, try_cast(nullif(trim(pending_charge),'') AS DOUBLE) aux_amount, product_name,
    try_cast(nullif(trim(final_start_date),'') AS DATE) observed_start_dt, try_cast(nullif(trim(final_end_date),'') AS DATE) observed_end_dt,
    date_format(try_cast(nullif(trim(final_start_date),'') AS DATE),'yyyy-MM') observed_start_month,
    CAST(NULL AS STRING) observed_cycle_start_month, CAST(NULL AS STRING) observed_cycle_end_month,
    concat_ws('|',coalesce(imsi,''),coalesce(iccid,''),coalesce(final_start_date,''),coalesce(final_end_date,'')) row_key
  FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
),
C AS (
  SELECT 'simo_prod.mysql_cdc_sync.wa_invoice_credit' source_table, source_file,
    CASE WHEN source_file LIKE '%JAN 2025%' THEN '2025-01' WHEN source_file LIKE '%SEP 2025%' THEN '2025-09'
      WHEN source_file LIKE '%OCT 2025%' AND source_file LIKE '%773,793.84%' THEN '2025-10 (v2)'
      WHEN source_file LIKE '%OCT 2025%' AND source_file LIKE '%772,765.00%' THEN '2025-10 (v1)'
      WHEN source_file LIKE '%DEC 2025%' THEN '2025-12' WHEN source_file LIKE '%FEB 2026%' THEN '2026-02'
      WHEN source_file LIKE '%MAR 2026%' THEN '2026-03' WHEN source_file LIKE '%APR 2026%' THEN '2026-04'
      WHEN source_file LIKE '%MAY 2026%' THEN '2026-05' WHEN source_file LIKE '%JUNE 2026%' THEN '2026-06'
      WHEN source_file LIKE '%JULY 2026%' THEN '2026-07' WHEN source_file LIKE '%AUGUST 2026%' THEN '2026-08' ELSE source_file END invoice_batch_label,
    imsi, CAST(NULL AS STRING) charge_type, CAST(NULL AS DOUBLE) excel_days, try_cast(nullif(trim(price),'') AS DOUBLE) excel_price,
    try_cast(nullif(trim(credit_owed),'') AS DOUBLE) excel_amount, CAST(NULL AS DOUBLE) aux_amount, prod product_name,
    CAST(NULL AS DATE) observed_start_dt, CAST(NULL AS DATE) observed_end_dt, CAST(NULL AS STRING) observed_start_month,
    date_format(try_cast(nullif(trim(cycle_start),'') AS DATE),'yyyy-MM') observed_cycle_start_month,
    date_format(try_cast(nullif(trim(cycle_end),'') AS DATE),'yyyy-MM') observed_cycle_end_month,
    concat_ws('|',coalesce(imsi,''),coalesce(iccid,''),coalesce(cycle_start,''),coalesce(cycle_end,'')) row_key
  FROM simo_prod.mysql_cdc_sync.wa_invoice_credit
),
S AS (
  SELECT 'SOURCE_FILE' control_section, source_table, source_file, invoice_batch_label,
    concat_ws(',',sort_array(collect_set(observed_start_month))) observed_start_month,
    concat_ws(',',sort_array(collect_set(observed_cycle_start_month))) observed_cycle_start_month,
    concat_ws(',',sort_array(collect_set(observed_cycle_end_month))) observed_cycle_end_month,
    count(*) row_count, count(DISTINCT imsi) imsi_count, sum(excel_amount) total_excel_amount, sum(aux_amount) total_aux_amount, sum(excel_price) total_price,
    count(DISTINCT charge_type) charge_type_count, count(DISTINCT product_name) product_count, min(observed_start_dt) min_start_date, max(observed_start_dt) max_start_date,
    min(observed_end_dt) min_end_date, max(observed_end_dt) max_end_date,
    CASE WHEN source_file LIKE '%773,793.84%' THEN 773793.84 WHEN source_file LIKE '%772,765.00%' THEN 772765.00 WHEN source_file LIKE '%585.45%' THEN 585.45 END filename_amount,
    CASE WHEN source_file LIKE '%773,793.84%' THEN sum(excel_amount)-773793.84 WHEN source_file LIKE '%772,765.00%' THEN sum(excel_amount)-772765.00 WHEN source_file LIKE '%585.45%' THEN sum(excel_amount)-585.45 END filename_amount_diff,
    'detail/prorated/credit source statistics are kept separate' note
  FROM D GROUP BY source_table, source_file, invoice_batch_label
  UNION ALL
  SELECT 'SOURCE_FILE', source_table, source_file, invoice_batch_label,
    concat_ws(',',sort_array(collect_set(observed_start_month))), concat_ws(',',sort_array(collect_set(observed_cycle_start_month))), concat_ws(',',sort_array(collect_set(observed_cycle_end_month))),
    count(*), count(DISTINCT imsi), sum(excel_amount), sum(aux_amount), sum(excel_price), count(DISTINCT charge_type), count(DISTINCT product_name), min(observed_start_dt), max(observed_start_dt), min(observed_end_dt), max(observed_end_dt),
    CASE WHEN source_file LIKE '%773,793.84%' THEN 773793.84 WHEN source_file LIKE '%772,765.00%' THEN 772765.00 WHEN source_file LIKE '%585.45%' THEN 585.45 END,
    CASE WHEN source_file LIKE '%773,793.84%' THEN sum(excel_amount)-773793.84 WHEN source_file LIKE '%772,765.00%' THEN sum(excel_amount)-772765.00 WHEN source_file LIKE '%585.45%' THEN sum(excel_amount)-585.45 END,
    'detail/prorated/credit source statistics are kept separate' FROM P GROUP BY source_table, source_file, invoice_batch_label
  UNION ALL
  SELECT 'SOURCE_FILE', source_table, source_file, invoice_batch_label,
    concat_ws(',',sort_array(collect_set(observed_start_month))), concat_ws(',',sort_array(collect_set(observed_cycle_start_month))), concat_ws(',',sort_array(collect_set(observed_cycle_end_month))),
    count(*), count(DISTINCT imsi), sum(excel_amount), sum(aux_amount), sum(excel_price), count(DISTINCT charge_type), count(DISTINCT product_name), min(observed_start_dt), max(observed_start_dt), min(observed_end_dt), max(observed_end_dt),
    CASE WHEN source_file LIKE '%773,793.84%' THEN 773793.84 WHEN source_file LIKE '%772,765.00%' THEN 772765.00 WHEN source_file LIKE '%585.45%' THEN 585.45 END,
    CASE WHEN source_file LIKE '%773,793.84%' THEN sum(excel_amount)-773793.84 WHEN source_file LIKE '%772,765.00%' THEN sum(excel_amount)-772765.00 WHEN source_file LIKE '%585.45%' THEN sum(excel_amount)-585.45 END,
    'detail/prorated/credit source statistics are kept separate' FROM C GROUP BY source_table, source_file, invoice_batch_label
),
M AS (
  SELECT 'INVOICE_BATCH' control_section, source_table, source_file, invoice_batch_label, CAST(NULL AS STRING) observed_start_month,
    concat_ws(',',sort_array(collect_set(observed_cycle_start_month))) observed_cycle_start_month, concat_ws(',',sort_array(collect_set(observed_cycle_end_month))) observed_cycle_end_month,
    count(*) row_count, count(DISTINCT imsi) imsi_count, sum(excel_amount) total_excel_amount, sum(aux_amount) total_aux_amount, sum(excel_price) total_price,
    count(DISTINCT charge_type) charge_type_count, count(DISTINCT product_name) product_count, min(observed_start_dt) min_start_date, max(observed_start_dt) max_start_date,
    min(observed_end_dt) min_end_date, max(observed_end_dt) max_end_date, CAST(NULL AS DOUBLE) filename_amount, CAST(NULL AS DOUBLE) filename_amount_diff,
    'invoice_batch_label basis; each source table remains separate' note FROM D GROUP BY source_table, source_file, invoice_batch_label
  UNION ALL
  SELECT 'INVOICE_BATCH', source_table, source_file, invoice_batch_label, CAST(NULL AS STRING), concat_ws(',',sort_array(collect_set(observed_cycle_start_month))), concat_ws(',',sort_array(collect_set(observed_cycle_end_month))), count(*), count(DISTINCT imsi), sum(excel_amount), sum(aux_amount), sum(excel_price), count(DISTINCT charge_type), count(DISTINCT product_name), min(observed_start_dt), max(observed_start_dt), min(observed_end_dt), max(observed_end_dt), NULL, NULL, 'invoice_batch_label basis; each source table remains separate' FROM P GROUP BY source_table, source_file, invoice_batch_label
  UNION ALL
  SELECT 'INVOICE_BATCH', source_table, source_file, invoice_batch_label, CAST(NULL AS STRING), concat_ws(',',sort_array(collect_set(observed_cycle_start_month))), concat_ws(',',sort_array(collect_set(observed_cycle_end_month))), count(*), count(DISTINCT imsi), sum(excel_amount), sum(aux_amount), sum(excel_price), count(DISTINCT charge_type), count(DISTINCT product_name), min(observed_start_dt), max(observed_start_dt), min(observed_end_dt), max(observed_end_dt), NULL, NULL, 'invoice_batch_label basis; each source table remains separate' FROM C GROUP BY source_table, source_file, invoice_batch_label
  UNION ALL
  SELECT 'OBSERVED_START_MONTH', source_table, source_file, CAST(NULL AS STRING), observed_start_month, CAST(NULL AS STRING), CAST(NULL AS STRING), count(*), count(DISTINCT imsi), sum(excel_amount), sum(aux_amount), sum(excel_price), count(DISTINCT charge_type), count(DISTINCT product_name), min(observed_start_dt), max(observed_start_dt), min(observed_end_dt), max(observed_end_dt), NULL, NULL, 'detail final_start_date basis; source table remains separate' FROM D WHERE observed_start_month IS NOT NULL GROUP BY source_table, source_file, observed_start_month
  UNION ALL
  SELECT 'OBSERVED_START_MONTH', source_table, source_file, CAST(NULL AS STRING), observed_start_month, CAST(NULL AS STRING), CAST(NULL AS STRING), count(*), count(DISTINCT imsi), sum(excel_amount), sum(aux_amount), sum(excel_price), count(DISTINCT charge_type), count(DISTINCT product_name), min(observed_start_dt), max(observed_start_dt), min(observed_end_dt), max(observed_end_dt), NULL, NULL, 'prorated final_start_date basis; source table remains separate' FROM P WHERE observed_start_month IS NOT NULL GROUP BY source_table, source_file, observed_start_month
  UNION ALL
  SELECT 'CREDIT_CYCLE_MONTH', source_table, source_file, invoice_batch_label, CAST(NULL AS STRING), observed_cycle_start_month, observed_cycle_end_month, count(*), count(DISTINCT imsi), sum(excel_amount), sum(aux_amount), sum(excel_price), count(DISTINCT charge_type), count(DISTINCT product_name), NULL, NULL, NULL, NULL, NULL, NULL, 'credit cycle_start/cycle_end basis; no fabricated final_start_month' FROM C GROUP BY source_table, source_file, invoice_batch_label, observed_cycle_start_month, observed_cycle_end_month
),
DI AS (SELECT DISTINCT imsi FROM D WHERE imsi IS NOT NULL), PI AS (SELECT DISTINCT imsi FROM P WHERE imsi IS NOT NULL), CI AS (SELECT DISTINCT imsi FROM C WHERE imsi IS NOT NULL),
DK AS (SELECT DISTINCT row_key FROM D), PK AS (SELECT DISTINCT row_key FROM P), CK AS (SELECT DISTINCT row_key FROM C),
O AS (
  SELECT 'OVERLAP' control_section, 'detail_vs_prorated' source_table, CAST(NULL AS STRING) source_file, CAST(NULL AS STRING) invoice_batch_label, CAST(NULL AS STRING) observed_start_month, CAST(NULL AS STRING) observed_cycle_start_month, CAST(NULL AS STRING) observed_cycle_end_month,
    CAST(NULL AS BIGINT) row_count, CAST(NULL AS BIGINT) imsi_count, CAST(NULL AS DOUBLE) total_excel_amount, CAST(NULL AS DOUBLE) total_aux_amount, CAST(NULL AS DOUBLE) total_price, CAST(NULL AS BIGINT) charge_type_count, CAST(NULL AS BIGINT) product_count, CAST(NULL AS DATE) min_start_date, CAST(NULL AS DATE) max_start_date, CAST(NULL AS DATE) min_end_date, CAST(NULL AS DATE) max_end_date, CAST(NULL AS DOUBLE) filename_amount, CAST(NULL AS DOUBLE) filename_amount_diff,
    (SELECT count(*) FROM DI JOIN PI ON DI.imsi=PI.imsi) imsi_overlap_count, (SELECT count(*) FROM DK JOIN PK ON DK.row_key=PK.row_key) row_key_overlap_count, 'pairwise overlap only; no amount addition' note
  UNION ALL SELECT 'OVERLAP','detail_vs_credit',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,(SELECT count(*) FROM DI JOIN CI ON DI.imsi=CI.imsi),(SELECT count(*) FROM DK JOIN CK ON DK.row_key=CK.row_key),'pairwise overlap only; credit remains separate'
  UNION ALL SELECT 'OVERLAP','prorated_vs_credit',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,(SELECT count(*) FROM PI JOIN CI ON PI.imsi=CI.imsi),(SELECT count(*) FROM PK JOIN CK ON PK.row_key=CK.row_key),'pairwise overlap only; no amount addition'
),
X AS (
  SELECT 'BATCH_VS_OBSERVED_CONFLICT' control_section, source_table, source_file, invoice_batch_label, observed_start_month, observed_cycle_start_month, observed_cycle_end_month, count(*) row_count, count(DISTINCT imsi) imsi_count, sum(excel_amount) total_excel_amount, sum(aux_amount) total_aux_amount, sum(excel_price) total_price, count(DISTINCT charge_type) charge_type_count, count(DISTINCT product_name) product_count, min(observed_start_dt) min_start_date, max(observed_start_dt) max_start_date, min(observed_end_dt) min_end_date, max(observed_end_dt) max_end_date, NULL, NULL, 'known label month compared to observed_start_month; label not rewritten' note FROM D WHERE observed_start_month IS NOT NULL AND observed_start_month <> substr(invoice_batch_label,1,7) GROUP BY source_table, source_file, invoice_batch_label, observed_start_month, observed_cycle_start_month, observed_cycle_end_month
  UNION ALL
  SELECT 'BATCH_VS_OBSERVED_CONFLICT', source_table, source_file, invoice_batch_label, observed_start_month, observed_cycle_start_month, observed_cycle_end_month, count(*), count(DISTINCT imsi), sum(excel_amount), sum(aux_amount), sum(excel_price), count(DISTINCT charge_type), count(DISTINCT product_name), min(observed_start_dt), max(observed_start_dt), min(observed_end_dt), max(observed_end_dt), NULL, NULL, 'known label month compared to observed_start_month; label not rewritten' FROM P WHERE observed_start_month IS NOT NULL AND observed_start_month <> substr(invoice_batch_label,1,7) GROUP BY source_table, source_file, invoice_batch_label, observed_start_month, observed_cycle_start_month, observed_cycle_end_month
)
SELECT control_section, source_table, source_file, invoice_batch_label, observed_start_month, observed_cycle_start_month, observed_cycle_end_month, row_count, imsi_count, total_excel_amount, total_aux_amount, total_price, charge_type_count, product_count, min_start_date, max_start_date, min_end_date, max_end_date, filename_amount, filename_amount_diff, CAST(NULL AS BIGINT) imsi_overlap_count, CAST(NULL AS BIGINT) row_key_overlap_count, note FROM S
UNION ALL SELECT control_section, source_table, source_file, invoice_batch_label, observed_start_month, observed_cycle_start_month, observed_cycle_end_month, row_count, imsi_count, total_excel_amount, total_aux_amount, total_price, charge_type_count, product_count, min_start_date, max_start_date, min_end_date, max_end_date, filename_amount, filename_amount_diff, NULL, NULL, note FROM M
UNION ALL SELECT control_section, source_table, source_file, invoice_batch_label, observed_start_month, observed_cycle_start_month, observed_cycle_end_month, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, imsi_overlap_count, row_key_overlap_count, note FROM O
UNION ALL SELECT control_section, source_table, source_file, invoice_batch_label, observed_start_month, observed_cycle_start_month, observed_cycle_end_month, row_count, imsi_count, total_excel_amount, total_aux_amount, total_price, charge_type_count, product_count, min_start_date, max_start_date, min_end_date, max_end_date, NULL, NULL, NULL, NULL, note FROM X
ORDER BY control_section, source_table, source_file, invoice_batch_label, observed_start_month, observed_cycle_start_month, observed_cycle_end_month