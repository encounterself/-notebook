SELECT
  trim(charge_type) AS charge_type,
  length(trim(charge_type)) AS charge_type_length,
  hex(cast(trim(charge_type) AS BINARY)) AS charge_type_hex,
  CASE WHEN trim(charge_type) = 'Prorated Out - Transferred to Wing''s Simbank' THEN 1 ELSE 0 END AS literal_match
FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
WHERE trim(source_file) LIKE '%MAR 2026%'
  AND trim(charge_type) LIKE '%Simbank%'
GROUP BY trim(charge_type)