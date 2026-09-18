SELECT table_catalog, table_schema, table_name, ordinal_position, column_name, data_type, is_nullable
FROM simo_prod.information_schema.columns
WHERE table_schema = 'mysql_cdc_sync'
  AND LOWER(table_name) LIKE 'wa%'
ORDER BY table_name, ordinal_position