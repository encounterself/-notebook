SELECT CAST(charge_type AS STRING) AS charge_type, COUNT(*) AS row_count, COUNT(DISTINCT CAST(imsi AS STRING)) AS imsi_count
FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
WHERE source_file = '01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx'
GROUP BY CAST(charge_type AS STRING)
ORDER BY charge_type