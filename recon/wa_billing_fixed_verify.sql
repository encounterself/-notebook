-- 修正版（一次算天数，避免多层派生列）：2026-08 验证
WITH presence AS (
  SELECT imsi, COUNT(DISTINCT DATE(partition_time)) AS presence_days,
         MIN(DATE(partition_time)) AS first_seen, MAX(DATE(partition_time)) AS last_seen
  FROM simo_prod.tc_cdr.sim_status_for_sftp_bak
  WHERE year = 2026 AND month = 8 GROUP BY imsi
),
new_cycle AS (
  SELECT imsi, TO_DATE(MIN(SPLIT(Cycle_Start_Time,' ')[0])) AS new_cs
  FROM simo_prod.tc_cdr.sim_status_for_sftp_bak
  WHERE year = 2026 AND month = 8
    AND SPLIT(Cycle_Start_Time,' ')[0] BETWEEN '2026-08-02' AND '2026-08-31'
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
  SELECT x.imsi, x.charge_type, x.xl_offstock, x.fd, x.rate, x.chg,
         p.presence_days, p.first_seen, p.last_seen, n.new_cs, s.stop_offstock
  FROM xl x
  LEFT JOIN presence p ON p.imsi = x.imsi
  LEFT JOIN new_cycle n ON n.imsi = x.imsi
  LEFT JOIN stopped  s ON s.imsi = x.imsi
),
scored AS (
  SELECT *,
    CASE
      -- 换卡旧卡：新账期起点 → 停用日
      WHEN charge_type = 'Partial Charge - Card Replaced Mid Cycle'
           AND new_cs IS NOT NULL AND stop_offstock IS NOT NULL AND stop_offstock >= new_cs
        THEN DATEDIFF(stop_offstock, new_cs) + 1
      -- 换卡新卡：新账期起点 → 月末
      WHEN charge_type = 'Partial Charge - New Card Used as Replacement Mid Cycle'
           AND new_cs IS NOT NULL
        THEN DATEDIFF(TO_DATE('2026-08-31'), new_cs) + 1
      -- 新激活：月初 → 新账期起点前一天
      WHEN charge_type = 'New Activation: Prorated-in Charge' AND new_cs IS NOT NULL
        THEN DAY(new_cs) - 1
      -- 其余：满月 或 实际在网天数
      WHEN first_seen = TO_DATE('2026-08-01') AND last_seen = TO_DATE('2026-08-31') THEN 31
      ELSE COALESCE(presence_days, 0)
    END AS bill_days
  FROM rows
)
SELECT charge_type, COUNT(1) AS cards,
       ROUND(SUM(chg),2) AS excel_charge,
       SUM(CASE WHEN bill_days = CAST(fd AS INT) THEN 1 ELSE 0 END) AS days_match,
       ROUND(SUM(ROUND(rate/31*bill_days,4)),2) AS fixed_charge,
       ROUND(SUM(ROUND(rate/31*bill_days,4)) - SUM(chg),2) AS diff
FROM scored GROUP BY charge_type
UNION ALL
SELECT '=== TOTAL ===', COUNT(1), ROUND(SUM(chg),2),
       SUM(CASE WHEN bill_days = CAST(fd AS INT) THEN 1 ELSE 0 END),
       ROUND(SUM(ROUND(rate/31*bill_days,4)),2),
       ROUND(SUM(ROUND(rate/31*bill_days,4)) - SUM(chg),2)
FROM scored
ORDER BY excel_charge
