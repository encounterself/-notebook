SELECT table_schema, table_name, ordinal_position, column_name, data_type, is_nullable
FROM simo_prod.information_schema.columns
WHERE
  (table_schema = 'dm' AND table_name IN ('card_replacement_details','change_card_data','change_card_data_details','change_card_data_details01','change_card_data_details02','change_card_data_details03','imsi_dispatch_details'))
  OR (table_schema = 'ods' AND table_name IN ('change_card_reason_relation','core_dse_applylog'))
ORDER BY table_schema, table_name, ordinal_position;