WITH
e AS (
  SELECT DISTINCT trim(imsi) AS imsi,
         to_date(trim(final_start_date)) AS final_start,
         to_date(trim(final_end_date)) AS final_end
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE trim(source_file) LIKE '%MAR 2026%'
     OR trim(source_file) LIKE '%APR 2026%'
     OR trim(source_file) LIKE '%MAY 2026%'
),
prod AS (
  SELECT DISTINCT cast(product_id AS STRING) AS product_id
  FROM simo_prod.ods.resource_res_vsim_product
  WHERE supplier_id = 2275
),
h AS (
  SELECT
    trim(h.imsi) AS imsi,
    cast(h.product_id AS STRING) AS product_id,
    to_date(h.cycle_time) AS cycle_start,
    to_date(h.next_cycle_time) AS next_cycle_start,
    to_date(h.next_cycle_time) - INTERVAL 1 DAY AS inclusive_cycle_end,
    h.package_price,
    h.time_zone,
    h.cycle_time,
    h.next_cycle_time
  FROM simo_prod.ods.resource_res_vsim_cycle_history h
  INNER JOIN prod p ON cast(h.product_id AS STRING) = p.product_id
  WHERE h.cycle_time < TIMESTAMP '2026-06-01'
    AND h.next_cycle_time >= TIMESTAMP '2026-03-01'
)
SELECT
  h.product_id,
  h.imsi,
  h.cycle_start,
  h.next_cycle_start,
  h.inclusive_cycle_end,
  h.package_price,
  h.time_zone,
  COUNT(*) AS history_rows,
  MIN(e.final_start) AS min_excel_final_start,
  MAX(e.final_end) AS max_excel_final_end
FROM h
INNER JOIN e
  ON h.imsi=e.imsi
 AND h.cycle_start <= e.final_end
 AND h.inclusive_cycle_end >= e.final_start
GROUP BY h.product_id,h.imsi,h.cycle_start,h.next_cycle_start,h.inclusive_cycle_end,h.package_price,h.time_zone
ORDER BY h.imsi, h.cycle_start
LIMIT 100