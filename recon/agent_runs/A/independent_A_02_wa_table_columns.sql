SELECT table_catalog, table_schema, table_name, ordinal_position, column_name, full_data_type, data_type, is_nullable
FROM simo_prod.information_schema.columns
WHERE table_schema = 'mysql_cdc_sync'
  AND LOWER(table_name) IN ('wa_invoice_credit','wa_invoice_detail','wa_invoice_prorated')
ORDER BY table_name, ordinal_position