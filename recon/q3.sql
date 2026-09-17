-- 独立模型 + Excel 费率：验证「当月费用」对齐程度
WITH presence AS (
  SELECT imsi, COUNT(DISTINCT DATE(partition_time)) AS pres_days,
         MIN(DATE(partition_time)) AS first_seen, MAX(DATE(partition_time)) AS last_seen
  FROM simo_prod.tc_cdr.sim_status_for_sftp_bak
  WHERE year = 2026 AND month = 8 GROUP BY imsi
),
anchor AS (
  SELECT imsi, TO_DATE(MIN(SPLIT(Cycle_Start_Time,' ')[0])) AS month_anchor
  FROM simo_prod.tc_cdr.sim_status_for_sftp_bak
  WHERE year = 2026 AND month = 8
    AND SPLIT(Cycle_Start_Time,' ')[0] BETWEEN '2026-08-01' AND '2026-08-31'
  GROUP BY imsi
),
stopped AS (
  SELECT IMSI AS imsi, DATE_SUB(MIN(TO_DATE(CREATE_DATE)), 1) AS stop_offstock
  FROM simo_prod.ods.resource_res_vsim_status_log
  WHERE NEXT_STATUS = '\u4f5c\u5e9f'
    AND CREATE_DATE >= '2026-08-01' AND CREATE_DATE < '2026-10-01'
  GROUP BY IMSI
),
xl AS (
  SELECT imsi, MAX(charge_type) AS charge_type, MAX(TO_DATE(offstock_date)) AS xl_offstock,
         MAX(TRY_CAST(final_days AS DOUBLE)) AS fd, MAX(TRY_CAST(monthly_rate AS DOUBLE)) AS rate,
         SUM(TRY_CAST(final_charge AS DOUBLE)) AS chg
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE source_file LIKE '%AUGUST 2026%' GROUP BY imsi
),
rows AS (
  SELECT x.imsi, x.charge_type, x.fd, x.rate, x.chg,
         p.pres_days, p.first_seen, p.last_seen, n.month_anchor, s.stop_offstock
  FROM xl x
  LEFT JOIN presence p ON p.imsi = x.imsi
  LEFT JOIN anchor   n ON n.imsi = x.imsi
  LEFT JOIN stopped  s ON s.imsi = x.imsi
),
scored AS (
  SELECT *,
    CASE
      WHEN charge_type = 'Partial Charge - Card Replaced Mid Cycle'
           AND month_anchor IS NOT NULL AND stop_offstock IS NOT NULL AND stop_offstock >= month_anchor
        THEN DATEDIFF(stop_offstock, month_anchor) + 1
      WHEN charge_type = 'Partial Charge - New Card Used as Replacement Mid Cycle'
           AND month_anchor IS NOT NULL
        THEN DATEDIFF(TO_DATE('2026-08-31'), month_anchor) + 1
      WHEN charge_type = 'New Activation: Prorated-in Charge' AND month_anchor IS NOT NULL
        THEN DAY(month_anchor) - 1
      WHEN first_seen = TO_DATE('2026-08-01') AND last_seen = TO_DATE('2026-08-31') THEN 31
      ELSE COALESCE(pres_days, 0)
    END AS bill_days
  FROM rows
)
SELECT COUNT(1) AS cards,
       ROUND(SUM(chg),2) AS excel,
       ROUND(SUM(ROUND(rate/31*bill_days,4)),2) AS calc,
       ROUND(SUM(ROUND(rate/31*bill_days,4)) - SUM(chg),2) AS diff,
       SUM(CASE WHEN bill_days = CAST(fd AS INT) THEN 1 ELSE 0 END) AS days_match
FROM scored
