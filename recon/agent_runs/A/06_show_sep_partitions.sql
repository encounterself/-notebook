-- Batch A / read-only metadata probe for the inaccessible September snapshot.
SHOW PARTITIONS simo_prod.tc_cdr.sim_status_for_sftp_bak PARTITION (year=2025, month=9);