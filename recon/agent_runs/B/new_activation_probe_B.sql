WITH d AS (
  SELECT
    TRIM(CAST(imsi AS STRING)) AS imsi,
    source_file, charge_type,
    TRY_CAST(new_activation_date AS DATE) AS excel_new_activation_date,
    TRY_CAST(final_start_date AS DATE) AS excel_final_start_date,
    TRY_CAST(final_end_date AS DATE) AS excel_final_end_date,
    TRY_CAST(final_days AS DECIMAL(38,12)) AS excel_days,
    TRY_CAST(monthly_rate AS DECIMAL(38,12)) AS excel_price,
    TRY_CAST(final_charge AS DECIMAL(38,12)) AS excel_amount
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE (source_file LIKE '%DEC 2025%' OR source_file LIKE '%FEB 2026%')
    AND charge_type='New Activation: Prorated-in Charge'
), ev AS (
  SELECT TRIM(CAST(IMSI AS STRING)) AS imsi, CREATE_DATE AS activation_event_time,
    TRIM(CAST(PRE_STATUS AS STRING)) AS pre_status, TRIM(CAST(NEXT_STATUS AS STRING)) AS next_status,
    TRIM(CAST(DESC_LOG AS STRING)) AS desc_log, TRIM(CAST(DESCRIPTION AS STRING)) AS description
  FROM simo_prod.ods.resource_res_vsim_status_log
  WHERE CREATE_DATE >= CAST('2025-11-01' AS TIMESTAMP) AND CREATE_DATE < CAST('2026-04-01' AS TIMESTAMP)
    AND TRIM(CAST(NEXT_STATUS AS STRING))='激活'
    AND (CAST(DESC_LOG AS STRING) LIKE '%激活%' OR CAST(DESCRIPTION AS STRING) LIKE '%激活%')
), joined AS (
  SELECT d.*, e.activation_event_time, e.pre_status, e.next_status, e.desc_log, e.description,
    DATEDIFF(TRY_CAST(d.excel_final_start_date AS DATE),TRY_CAST(e.activation_event_time AS DATE)) AS event_to_excel_start_days,
    ROW_NUMBER() OVER (PARTITION BY d.imsi,d.source_file,d.excel_final_start_date,d.excel_final_end_date,d.excel_amount ORDER BY ABS(DATEDIFF(TRY_CAST(e.activation_event_time AS DATE),d.excel_final_start_date)), e.activation_event_time) AS rn
  FROM d LEFT JOIN ev e ON d.imsi=e.imsi
)
SELECT * FROM joined WHERE rn=1 ORDER BY source_file, imsi LIMIT 300;