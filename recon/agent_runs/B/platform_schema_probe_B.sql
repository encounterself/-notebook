SELECT table_schema, table_name, column_name, data_type, ordinal_position
FROM simo_prod.information_schema.columns
WHERE (table_schema='tc_cdr' AND table_name='sim_status_for_sftp_bak')
   OR (table_schema='ods' AND table_name IN ('resource_res_vsim_cycle_history','resource_res_vsim_status_log','resource_res_vsim_product','resource_res_carrier'))
ORDER BY table_schema, table_name, ordinal_position