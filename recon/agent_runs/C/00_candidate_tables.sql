SELECT table_schema, table_name, table_type
FROM simo_prod.information_schema.tables
WHERE LOWER(table_name) RLIKE 'replace|change_card|core|sim_status|dispatch'
  AND table_schema IN ('ods', 'tc_cdr', 'dm', 'mysql_cdc_sync')
ORDER BY table_schema, table_name;