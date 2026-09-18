SELECT tc.table_catalog, tc.table_schema, tc.table_name, tc.constraint_name, tc.constraint_type,
       kcu.column_name, kcu.ordinal_position
FROM simo_prod.information_schema.table_constraints tc
LEFT JOIN simo_prod.information_schema.key_column_usage kcu
  ON tc.constraint_catalog = kcu.constraint_catalog
 AND tc.constraint_schema = kcu.constraint_schema
 AND tc.constraint_name = kcu.constraint_name
 AND tc.table_name = kcu.table_name
WHERE tc.table_schema = 'mysql_cdc_sync'
  AND LOWER(tc.table_name) LIKE 'wa%'
ORDER BY tc.table_name, tc.constraint_name, kcu.ordinal_position