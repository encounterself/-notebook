SELECT billing_state, types,
       COUNT(1) AS rows_cnt, COUNT(DISTINCT IMSI) AS cards,
       ROUND(SUM(Billable_Fee_Final),2) AS total,
       ROUND(AVG(NULLIF(Billable_Days,0)),2) AS avg_days
FROM simo_prod.mysql_cdc_sync.card_billing_v2_aug
GROUP BY billing_state, types ORDER BY billing_state, types
