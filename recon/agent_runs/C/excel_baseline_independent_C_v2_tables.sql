SELECT table_catalog, table_schema, table_name, table_type
FROM simo_prod.information_schema.tables
WHERE table_schema = 'mysql_cdc_sync'
  AND LOWER(table_name) LIKE 'wa%'
ORDER BY table_name