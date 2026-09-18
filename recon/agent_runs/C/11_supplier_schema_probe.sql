SELECT table_catalog, table_schema, table_name, column_name, data_type
FROM simo_prod.information_schema.columns
WHERE table_schema IN ('tc_cdr', 'ods', 'mysql_cdc_sync')
  AND LOWER(column_name) LIKE '%supplier%'
ORDER BY table_schema, table_name, ordinal_position