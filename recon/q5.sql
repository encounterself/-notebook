SELECT 'WA_detail' AS src, COUNT(DISTINCT imsi) AS imsis FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
UNION ALL SELECT 'WA_prorated', COUNT(DISTINCT imsi) FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
UNION ALL SELECT 'WA_credit', COUNT(DISTINCT imsi) FROM simo_prod.mysql_cdc_sync.wa_invoice_credit
