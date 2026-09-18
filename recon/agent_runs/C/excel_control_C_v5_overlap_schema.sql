SELECT
  table_name,
  ordinal_position,
  column_name,
  data_type
FROM simo_prod.information_schema.columns
WHERE table_schema = 'mysql_cdc_sync'
  AND table_name IN ('wa_invoice_detail', 'wa_invoice_prorated')
ORDER BY table_name, ordinal_position