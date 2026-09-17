SELECT source_file, sheet_name, COUNT(1) AS n, COUNT(DISTINCT imsi) AS imsis,
       MIN(final_start_date) AS min_sd, MAX(final_start_date) AS max_sd,
       ROUND(SUM(TRY_CAST(original_charge AS DOUBLE)),2) AS sum_orig,
       ROUND(SUM(TRY_CAST(pending_charge AS DOUBLE)),2) AS sum_pending
FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
GROUP BY source_file, sheet_name
ORDER BY source_file
