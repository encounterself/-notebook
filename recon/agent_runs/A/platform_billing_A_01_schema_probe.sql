-- Batch A platform billing schema probe.
-- Read-only only: information_schema metadata plus table identity.
WITH requested AS (
  SELECT 'simo_prod' AS table_catalog, 'tc_cdr' AS table_schema, 'sim_status_for_sftp_bak' AS table_name
  UNION ALL SELECT 'simo_prod', 'ods', 'resource_res_vsim_cycle_history'
  UNION ALL SELECT 'simo_prod', 'ods', 'resource_res_vsim_status_log'
  UNION ALL SELECT 'simo_prod', 'ods', 'resource_res_vsim_product'
  UNION ALL SELECT 'simo_prod', 'ods', 'resource_res_carrier'
),
cols AS (
  SELECT
    c.table_catalog,
    c.table_schema,
    c.table_name,
    c.ordinal_position,
    c.column_name,
    c.data_type,
    c.is_nullable,
    c.comment
  FROM simo_prod.information_schema.columns c
  INNER JOIN requested r
    ON c.table_catalog = r.table_catalog
   AND c.table_schema = r.table_schema
   AND c.table_name = r.table_name
),
table_counts AS (
  SELECT table_catalog, table_schema, table_name, COUNT(*) AS column_count
  FROM cols
  GROUP BY table_catalog, table_schema, table_name
)
SELECT
  c.table_catalog,
  c.table_schema,
  c.table_name,
  c.ordinal_position,
  c.column_name,
  c.data_type,
  c.is_nullable,
  c.comment,
  t.column_count
FROM cols c
INNER JOIN table_counts t
  ON c.table_catalog = t.table_catalog
 AND c.table_schema = t.table_schema
 AND c.table_name = t.table_name
ORDER BY c.table_schema, c.table_name, c.ordinal_position;