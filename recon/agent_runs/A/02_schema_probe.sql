-- Batch A / read-only schema probe.
SELECT
  table_schema,
  table_name,
  ordinal_position,
  column_name,
  data_type
FROM simo_prod.information_schema.columns
WHERE (table_schema, table_name) IN (
  ('mysql_cdc_sync', 'wa_invoice_detail'),
  ('mysql_cdc_sync', 'wa_invoice_credit'),
  ('mysql_cdc_sync', 'wa_invoice_prorated'),
  ('tc_cdr', 'sim_status_for_sftp_bak'),
  ('ods', 'resource_res_vsim_cycle_history'),
  ('ods', 'resource_res_vsim_status_log'),
  ('ods', 'resource_res_vsim_product'),
  ('ods', 'resource_res_carrier')
)
ORDER BY table_schema, table_name, ordinal_position;