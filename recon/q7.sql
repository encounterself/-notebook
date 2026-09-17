SELECT MIN(CONCAT(year,'-',LPAD(month,2,'0'))) AS min_ym, MAX(CONCAT(year,'-',LPAD(month,2,'0'))) AS max_ym
FROM simo_prod.tc_cdr.sim_status_for_sftp_bak
