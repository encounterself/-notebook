SELECT table_schema, table_name, ordinal_position, column_name, data_type
FROM simo_prod.information_schema.columns
WHERE table_schema IN ('mysql_cdc_sync','tc_cdr','ods')
  AND table_name IN ('wa_invoice_detail','wa_invoice_credit','wa_invoice_prorated','sim_status_for_sftp_bak','resource_res_vsim_cycle_history','resource_res_vsim_status_log','resource_res_vsim_product','resource_res_carrier')
ORDER BY table_schema, table_name, ordinal_position