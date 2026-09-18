SELECT
  table_schema,
  table_name,
  ordinal_position,
  column_name,
  data_type,
  is_nullable
FROM simo_prod.information_schema.columns
WHERE
  (table_schema = 'mysql_cdc_sync' AND table_name IN ('wa_invoice_detail', 'wa_invoice_credit', 'wa_invoice_prorated'))
  OR (table_schema = 'tc_cdr' AND table_name IN ('sim_status_for_sftp_bak'))
  OR (table_schema = 'ods' AND table_name IN ('resource_res_vsim_cycle_history', 'resource_res_vsim_status_log', 'resource_res_vsim_product', 'resource_res_carrier'))
ORDER BY table_schema, table_name, ordinal_position;