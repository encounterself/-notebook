-- WA SIM 12-batch generic reconciliation SQL candidate
-- STATUS: CANDIDATE / NOT FINAL / NOT EXECUTED
-- READ-ONLY ONLY: SELECT/WITH. No DDL/DML.
-- Excel sources are separate:
--   simo_prod.mysql_cdc_sync.wa_invoice_detail   (main)
--   simo_prod.mysql_cdc_sync.wa_invoice_prorated (auxiliary)
--   simo_prod.mysql_cdc_sync.wa_invoice_credit   (auxiliary)
-- PENDING_MAP: platform field names/grain must pass DESCRIBE before execution.

WITH
cfg AS (
  SELECT CAST(2275 AS BIGINT) AS supplier_id,
         CAST(0.01 AS DECIMAL(18,6)) AS amount_tolerance
),
file_labels AS (
  SELECT source_file,
    CASE
      WHEN source_file LIKE '%JAN 2025%' THEN '2025-01'
      WHEN source_file LIKE '%SEP 2025%' THEN '2025-09'
      WHEN source_file LIKE '%OCT 2025%' AND source_file LIKE '%773,793.84%' THEN '2025-10 (v2)'
      WHEN source_file LIKE '%OCT 2025%' AND source_file LIKE '%772,765.00%' THEN '2025-10 (v1)'
      WHEN source_file LIKE '%DEC 2025%' THEN '2025-12'
      WHEN source_file LIKE '%FEB 2026%' THEN '2026-02'
      WHEN source_file LIKE '%MAR 2026%' THEN '2026-03'
      WHEN source_file LIKE '%APR 2026%' THEN '2026-04'
      WHEN source_file LIKE '%MAY 2026%' THEN '2026-05'
      WHEN source_file LIKE '%JUNE 2026%' THEN '2026-06'
      WHEN source_file LIKE '%JULY 2026%' THEN '2026-07'
      WHEN source_file LIKE '%AUGUST 2026%' THEN '2026-08'
      ELSE source_file
    END AS invoice_batch_label
  FROM (
    SELECT source_file FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
    UNION SELECT source_file FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
    UNION SELECT source_file FROM simo_prod.mysql_cdc_sync.wa_invoice_credit
  )
),
excel_detail AS (
  SELECT d.*, f.invoice_batch_label,
         DATE_FORMAT(TRY_CAST(d.final_start_date AS DATE),'yyyy-MM') AS observed_start_month
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail d
  JOIN file_labels f ON f.source_file=d.source_file
  WHERE f.invoice_batch_label IN
   ('2025-01','2025-09','2025-10 (v1)','2025-10 (v2)','2025-12',
    '2026-02','2026-03','2026-04','2026-05','2026-06','2026-07','2026-08')
),
excel_units AS (
  SELECT
    SHA2(CONCAT_WS('|',COALESCE(source_file,''),COALESCE(imsi,''),
      COALESCE(CAST(final_start_date AS STRING),''),COALESCE(CAST(final_end_date AS STRING),''),
      COALESCE(CAST(product_id AS STRING),''),COALESCE(CAST(monthly_rate AS STRING),'')),256) AS excel_unit_id,
    source_file, invoice_batch_label, observed_start_month,
    CAST(imsi AS STRING) AS excel_imsi,
    CAST(NULLIF(TRIM(CAST(product_id AS STRING)),'') AS STRING) AS excel_product_id,
    TRY_CAST(final_start_date AS DATE) AS excel_start_date,
    TRY_CAST(final_end_date AS DATE) AS excel_end_date,
    TRY_CAST(monthly_rate AS DECIMAL(18,6)) AS excel_rate,
    MAX(TRY_CAST(days AS INT)) AS excel_days,
    SUM(TRY_CAST(final_charge AS DECIMAL(18,6))) AS excel_amount,
    COUNT(*) AS excel_detail_row_count,
    CONCAT_WS(',',SORT_ARRAY(COLLECT_SET(CAST(charge_type AS STRING)))) AS excel_charge_type_set,
    CASE WHEN COUNT(*)=COUNT(imsi) AND COUNT(*)=COUNT(final_start_date)
           AND COUNT(*)=COUNT(final_end_date) AND COUNT(*)=COUNT(final_charge)
         THEN 'COMPLETE' ELSE 'MISSING_DATA' END AS excel_evidence_status
  FROM excel_detail
  GROUP BY source_file,invoice_batch_label,observed_start_month,imsi,product_id,
           final_start_date,final_end_date,monthly_rate
),
excel_auxiliary AS (
  SELECT f.invoice_batch_label,CAST(p.imsi AS STRING) AS imsi,
         TRY_CAST(p.final_charge_for_usage_days AS DECIMAL(18,6)) AS prorated_usage_amount,
         TRY_CAST(p.pending_charge AS DECIMAL(18,6)) AS prorated_pending_amount,
         CAST(NULL AS DECIMAL(18,6)) AS credit_amount
  FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated p
  JOIN file_labels f ON f.source_file=p.source_file
  UNION ALL
  SELECT f.invoice_batch_label,CAST(c.imsi AS STRING),
         CAST(NULL AS DECIMAL(18,6)),CAST(NULL AS DECIMAL(18,6)),
         TRY_CAST(c.credit_owed AS DECIMAL(18,6))
  FROM simo_prod.mysql_cdc_sync.wa_invoice_credit c
  JOIN file_labels f ON f.source_file=c.source_file
),
/* PENDING_MAP: verify every platform column below with DESCRIBE. */
platform_card_map AS (
  SELECT CAST(s.imsi AS STRING) AS platform_imsi,
         CAST(s.card_key AS STRING) AS platform_card_key,
         TRY_CAST(s.effective_start_date AS DATE) AS key_start_date,
         TRY_CAST(s.effective_end_date AS DATE) AS key_end_date,
         CAST(s.supplier_id AS BIGINT) AS supplier_id
  FROM simo_prod.tc_cdr.sim_status_for_sftp_bak s
  WHERE CAST(s.supplier_id AS BIGINT)=(SELECT supplier_id FROM cfg)
),
platform_product AS (
  SELECT CAST(p.product_id AS STRING) AS platform_product_id,
         CAST(p.supplier_id AS BIGINT) AS supplier_id,
         TRY_CAST(p.monthly_rate AS DECIMAL(18,6)) AS product_rate
  FROM simo_prod.ods.resource_res_vsim_product p
  WHERE CAST(p.supplier_id AS BIGINT)=(SELECT supplier_id FROM cfg)
),
platform_cycle AS (
  SELECT CAST(h.imsi AS STRING) AS platform_imsi,
         TRY_CAST(h.cycle_start_date AS DATE) AS platform_start_date,
         TRY_CAST(h.cycle_end_date AS DATE) AS platform_end_date,
         CAST(h.product_id AS STRING) AS platform_product_id,
         TRY_CAST(h.monthly_rate AS DECIMAL(18,6)) AS platform_rate,
         TRY_CAST(h.days AS INT) AS platform_days,
         TRY_CAST(h.calculated_amount AS DECIMAL(18,6)) AS platform_amount,
         CAST(h.charge_type AS STRING) AS platform_charge_type,
         CAST(h.supplier_id AS BIGINT) AS supplier_id
  FROM simo_prod.ods.resource_res_vsim_cycle_history h
  WHERE CAST(h.supplier_id AS BIGINT)=(SELECT supplier_id FROM cfg)
),
platform_units AS (
  SELECT SHA2(CONCAT_WS('|',COALESCE(h.platform_imsi,''),COALESCE(k.platform_card_key,''),
      COALESCE(CAST(h.platform_start_date AS STRING),''),COALESCE(CAST(h.platform_end_date AS STRING),''),
      COALESCE(h.platform_product_id,''),COALESCE(CAST(COALESCE(h.platform_rate,p.product_rate) AS STRING),'')),256) AS platform_unit_id,
    h.platform_imsi,k.platform_card_key,h.platform_start_date,h.platform_end_date,
    DATE_FORMAT(h.platform_start_date,'yyyy-MM') AS platform_observed_start_month,
    h.platform_product_id,COALESCE(h.platform_rate,p.product_rate) AS platform_rate,
    MAX(h.platform_days) AS platform_days,SUM(h.platform_amount) AS platform_amount,
    CONCAT_WS(',',SORT_ARRAY(COLLECT_SET(h.platform_charge_type))) AS platform_charge_type_set,
    CASE WHEN h.platform_product_id IS NULL OR p.platform_product_id IS NULL
         THEN 'MISSING_MAPPING' ELSE 'PRODUCT_PRICE_MAPPING_PENDING' END AS platform_mapping_status,
    CASE WHEN COUNT(*)=COUNT(h.platform_imsi) AND COUNT(*)=COUNT(h.platform_start_date)
              AND COUNT(*)=COUNT(h.platform_end_date) AND COUNT(*)=COUNT(h.platform_amount)
         THEN 'COMPLETE' ELSE 'MISSING_DATA' END AS platform_evidence_status,
    'simo_prod.ods.resource_res_vsim_cycle_history' AS platform_evidence_source
  FROM platform_cycle h
  LEFT JOIN platform_product p ON p.platform_product_id=h.platform_product_id
                              AND p.supplier_id=h.supplier_id
  LEFT JOIN platform_card_map k ON k.platform_imsi=h.platform_imsi
                                AND k.supplier_id=h.supplier_id
                                AND (k.key_start_date IS NULL OR h.platform_start_date IS NULL
                                  OR h.platform_start_date BETWEEN k.key_start_date
                                  AND COALESCE(k.key_end_date,h.platform_start_date))
  GROUP BY h.platform_imsi,k.platform_card_key,h.platform_start_date,h.platform_end_date,
           h.platform_product_id,COALESCE(h.platform_rate,p.product_rate),h.platform_charge_type,
           p.platform_product_id,h.platform_amount,h.platform_days,h.platform_charge_type
),
platform_window_proof AS (
  SELECT platform_imsi,platform_start_date,platform_end_date,
         COUNT(DISTINCT platform_product_id) AS product_count,
         COUNT(DISTINCT platform_rate) AS rate_count,
         MAX(platform_product_id) AS unique_product_id,MAX(platform_rate) AS unique_rate
  FROM platform_units
  GROUP BY platform_imsi,platform_start_date,platform_end_date
),
candidate_pairs AS (
  SELECT e.excel_unit_id,p.platform_unit_id,
         'PROVEN_BY_PLATFORM_IMSI_WINDOW_UNIQUE_PRODUCT_RATE' AS mapping_evidence,
         ROW_NUMBER() OVER(PARTITION BY e.excel_unit_id ORDER BY p.platform_unit_id) AS e_rn,
         ROW_NUMBER() OVER(PARTITION BY p.platform_unit_id ORDER BY e.excel_unit_id) AS p_rn
  FROM excel_units e
  JOIN platform_units p ON p.platform_imsi=e.excel_imsi
    AND p.platform_start_date=e.excel_start_date AND p.platform_end_date=e.excel_end_date
  JOIN platform_window_proof w ON w.platform_imsi=p.platform_imsi
    AND w.platform_start_date=p.platform_start_date AND w.platform_end_date=p.platform_end_date
    AND w.product_count=1 AND w.rate_count=1
  WHERE p.platform_product_id=w.unique_product_id
    AND (e.excel_product_id IS NULL OR e.excel_product_id=p.platform_product_id)
    AND e.excel_rate IS NOT NULL AND p.platform_rate IS NOT NULL
    AND ABS(e.excel_rate-p.platform_rate)<=(SELECT amount_tolerance FROM cfg)
),
matched AS (
  SELECT e.*,p.platform_card_key,p.platform_start_date,p.platform_end_date,
         p.platform_product_id,p.platform_rate,p.platform_days,p.platform_amount,
         p.platform_observed_start_month,p.platform_charge_type_set,
         p.platform_evidence_status,p.platform_evidence_source,
         CASE WHEN ABS(p.platform_amount-e.excel_amount)<=(SELECT amount_tolerance FROM cfg)
              THEN 'MATCHED' ELSE 'AMOUNT_DIFF' END AS numeric_match_status,
         CASE WHEN e.excel_evidence_status<>'COMPLETE' OR p.platform_evidence_status<>'COMPLETE'
              THEN 'MISSING_DATA'
              WHEN e.excel_days IS NULL OR p.platform_days IS NULL THEN 'MISSING_DATA'
              WHEN e.excel_days<>p.platform_days THEN 'UNRESOLVED'
              WHEN ABS(p.platform_amount-e.excel_amount)>(SELECT amount_tolerance FROM cfg)
              THEN 'UNRESOLVED' ELSE 'MATCHED' END AS formal_match_status,
         c.mapping_evidence
  FROM candidate_pairs c
  JOIN excel_units e ON e.excel_unit_id=c.excel_unit_id
  JOIN platform_units p ON p.platform_unit_id=c.platform_unit_id
  WHERE c.e_rn=1 AND c.p_rn=1
),
all_recon AS (
  SELECT 'PAIRED' AS direction,m.* FROM matched m
  UNION ALL
  SELECT 'WA_TO_PLATFORM_MISSING',e.*,CAST(NULL AS STRING),CAST(NULL AS DATE),CAST(NULL AS DATE),
         CAST(NULL AS STRING),CAST(NULL AS DECIMAL(18,6)),CAST(NULL AS INT),CAST(NULL AS DECIMAL(18,6)),
         CAST(NULL AS STRING),CAST(NULL AS STRING),CAST(NULL AS STRING),CAST(NULL AS STRING),
         CAST(NULL AS STRING),'WA_ONLY',
         CASE WHEN e.excel_evidence_status<>'COMPLETE' THEN 'MISSING_DATA'
              WHEN EXISTS(SELECT 1 FROM platform_units p WHERE p.platform_imsi=e.excel_imsi
                    AND p.platform_start_date=e.excel_start_date AND p.platform_end_date=e.excel_end_date)
              THEN 'MISSING_MAPPING'
              WHEN EXISTS(SELECT 1 FROM platform_units p WHERE p.platform_imsi=e.excel_imsi)
              THEN 'UNRESOLVED' ELSE 'WA_ONLY' END,
         CAST(NULL AS STRING)
  FROM excel_units e
  WHERE NOT EXISTS(SELECT 1 FROM matched m WHERE m.excel_unit_id=e.excel_unit_id)
  UNION ALL
  SELECT 'PLATFORM_TO_WA_MISSING',
         CAST(NULL AS STRING),CAST(NULL AS STRING),CAST(NULL AS STRING),CAST(NULL AS STRING),
         CAST(NULL AS STRING),CAST(NULL AS STRING),CAST(NULL AS STRING),p.platform_imsi,
         CAST(NULL AS STRING),p.platform_card_key,CAST(NULL AS DATE),CAST(NULL AS DATE),
         p.platform_start_date,p.platform_end_date,CAST(NULL AS STRING),p.platform_product_id,
         CAST(NULL AS DECIMAL(18,6)),p.platform_rate,CAST(NULL AS INT),p.platform_days,
         CAST(NULL AS DECIMAL(18,6)),p.platform_amount,p.platform_observed_start_month,
         CAST(NULL AS STRING),p.platform_charge_type_set,CAST(NULL AS STRING),CAST(NULL AS STRING),
         CAST(NULL AS BIGINT),CAST(NULL AS STRING),p.platform_evidence_status,CAST(NULL AS STRING),
         CASE WHEN p.platform_amount IS NULL THEN 'MISSING_DATA' ELSE 'PLATFORM_ONLY' END,
         CASE WHEN p.platform_evidence_status<>'COMPLETE' THEN 'MISSING_DATA'
              WHEN EXISTS(SELECT 1 FROM excel_units e WHERE e.excel_imsi=p.platform_imsi
                    AND e.excel_start_date=p.platform_start_date AND e.excel_end_date=p.platform_end_date)
              THEN 'MISSING_MAPPING'
              WHEN EXISTS(SELECT 1 FROM excel_units e WHERE e.excel_imsi=p.platform_imsi)
              THEN 'UNRESOLVED' ELSE 'PLATFORM_ONLY' END,
         CAST(NULL AS STRING)
  FROM platform_units p
  WHERE NOT EXISTS(SELECT 1 FROM matched m WHERE m.platform_unit_id=p.platform_unit_id)
),
reasoned AS (
  SELECT r.*,
    CASE WHEN r.formal_match_status='PLATFORM_ONLY' THEN 'PLATFORM_EXTRA_CARD_CANDIDATE'
         WHEN r.formal_match_status='WA_ONLY' THEN 'WA_CARD_WITHOUT_PLATFORM_MATCH'
         WHEN r.formal_match_status IN ('MISSING_DATA','MISSING_MAPPING') THEN r.formal_match_status
         WHEN r.excel_days<>r.platform_days THEN 'DAYS'
         WHEN ABS(r.excel_rate-r.platform_rate)>(SELECT amount_tolerance FROM cfg) THEN 'RATE'
         WHEN LOWER(COALESCE(r.excel_charge_type_set,'')||'|'||COALESCE(r.platform_charge_type_set,'')) LIKE '%backbill%' THEN 'BACKBILL'
         WHEN LOWER(COALESCE(r.excel_charge_type_set,'')||'|'||COALESCE(r.platform_charge_type_set,'')) LIKE '%credit%' THEN 'CREDIT'
         WHEN LOWER(COALESCE(r.excel_charge_type_set,'')||'|'||COALESCE(r.platform_charge_type_set,'')) LIKE '%replacement%' THEN 'REPLACEMENT'
         WHEN LOWER(COALESCE(r.excel_charge_type_set,'')||'|'||COALESCE(r.platform_charge_type_set,'')) LIKE '%transfer%' THEN 'TRANSFER'
         WHEN r.platform_amount IS NOT NULL AND r.excel_amount IS NOT NULL
              AND ABS(r.platform_amount-r.excel_amount)>(SELECT amount_tolerance FROM cfg) THEN 'OTHER_AMOUNT_DIFF'
         ELSE 'NONE' END AS reason_code,
    CASE WHEN r.platform_amount IS NOT NULL AND r.excel_amount IS NOT NULL
         THEN r.platform_amount-r.excel_amount END AS same_card_amount_diff
  FROM all_recon r
),
platform_month AS (
  SELECT platform_observed_start_month,
         SUM(platform_amount) AS platform_calculated_amount_known,
         CASE WHEN SUM(CASE WHEN platform_amount IS NULL THEN 1 ELSE 0 END)=0
              THEN SUM(platform_amount) END AS platform_total
  FROM platform_units GROUP BY platform_observed_start_month
),
monthly AS (
  SELECT COALESCE(r.invoice_batch_label,'PLATFORM_ONLY__'||r.platform_observed_start_month) AS invoice_batch_label,
         COALESCE(r.observed_start_month,r.platform_observed_start_month) AS observed_start_month,
         SUM(CASE WHEN r.excel_amount IS NOT NULL THEN r.excel_amount ELSE 0 END) AS excel_total,
         SUM(CASE WHEN r.platform_amount IS NOT NULL THEN r.platform_amount ELSE 0 END) AS platform_calculated_amount_known,
         MAX(pm.platform_total) AS platform_total,
         SUM(CASE WHEN r.formal_match_status='PLATFORM_ONLY' THEN COALESCE(r.platform_amount,0) ELSE 0 END) AS platform_only_amount,
         SUM(CASE WHEN r.direction='PAIRED' THEN COALESCE(r.same_card_amount_diff,0) ELSE 0 END) AS same_card_net_diff,
         SUM(CASE WHEN r.formal_match_status='WA_ONLY' THEN COALESCE(r.excel_amount,0) ELSE 0 END) AS wa_only_amount,
         SUM(CASE WHEN r.formal_match_status='MATCHED' THEN 1 ELSE 0 END) AS matched_count,
         SUM(CASE WHEN r.formal_match_status='WA_ONLY' THEN 1 ELSE 0 END) AS wa_only_count,
         SUM(CASE WHEN r.formal_match_status='PLATFORM_ONLY' THEN 1 ELSE 0 END) AS platform_only_count,
         SUM(CASE WHEN r.formal_match_status='UNRESOLVED' THEN 1 ELSE 0 END) AS unresolved_count,
         SUM(CASE WHEN r.formal_match_status='MISSING_DATA' THEN 1 ELSE 0 END) AS missing_data_count,
         SUM(CASE WHEN r.formal_match_status='MISSING_MAPPING' THEN 1 ELSE 0 END) AS missing_mapping_count
  FROM reasoned r LEFT JOIN platform_month pm
    ON pm.platform_observed_start_month=COALESCE(r.observed_start_month,r.platform_observed_start_month)
  GROUP BY COALESCE(r.invoice_batch_label,'PLATFORM_ONLY__'||r.platform_observed_start_month),
           COALESCE(r.observed_start_month,r.platform_observed_start_month)
)
SELECT 'MONTHLY_WATERFALL' AS result_type,m.*,
       m.platform_total-m.excel_total AS bridge_lhs,
       m.platform_only_amount+m.same_card_net_diff-m.wa_only_amount AS bridge_rhs,
       (m.platform_total-m.excel_total)
        -(m.platform_only_amount+m.same_card_net_diff-m.wa_only_amount) AS bridge_residual
FROM monthly m
UNION ALL
SELECT 'CARD_LEAK_CANDIDATE',
       r.invoice_batch_label,COALESCE(r.observed_start_month,r.platform_observed_start_month),
       r.excel_amount,r.platform_amount,r.platform_calculated_amount_known,
       r.platform_only_amount,r.same_card_net_diff,r.wa_only_amount,
       r.matched_count,r.wa_only_count,r.platform_only_count,r.unresolved_count,
       r.missing_data_count,r.missing_mapping_count,
       CAST(NULL AS DECIMAL(18,6)),CAST(NULL AS DECIMAL(18,6)),CAST(NULL AS DECIMAL(18,6))
FROM reasoned r
WHERE r.formal_match_status<>'MATCHED';
