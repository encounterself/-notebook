SELECT id, carrier_name FROM simo_prod.ods.resource_res_carrier
WHERE UPPER(carrier_name) LIKE '%WING%' OR UPPER(carrier_name) LIKE '%ALPHA%'
ORDER BY id
