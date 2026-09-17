-- 诊断：8月 WA 卡，多账期 types=1 分支——原逻辑(COUNT-1) vs 修正A(满月) 的费用差
WITH basic_data AS (
  SELECT
    imsi, product_id, SIM_Product_Data_Capacity,
    partition_time - INTERVAL 4 HOUR AS partition_time,
    Cycle_Start_Time - INTERVAL 5 HOUR AS Cycle_Start_Time,
    Cycle_End_Time   - INTERVAL 5 HOUR AS Cycle_End_Time,
    ROW_NUMBER() OVER (PARTITION BY DATE(partition_time - INTERVAL 4 HOUR), imsi ORDER BY partition_time) AS rm
  FROM (
    SELECT s1.imsi,
      IF(DATE(Cycle_End_Time) <= DATE('2026-08-31'), s2.product_id, s1.product_id) AS product_id,
      ICCID, SIM_Product_Threshold, SIM_Product_Data_Capacity,
      IF(DATE(Cycle_End_Time) <= DATE('2026-08-31'), DATE_FORMAT(s2.cycle_time,'yyyy-MM-dd HH:mm:ss'), s1.Cycle_Start_Time) AS Cycle_Start_Time,
      IF(DATE(Cycle_End_Time) <= DATE('2026-08-31'), DATE_FORMAT(s2.next_cycle_time,'yyyy-MM-dd HH:mm:ss'), s1.Cycle_End_Time) AS Cycle_End_Time,
      DispatchStatus, SimStatus, year, month, day, hour, partition_time
    FROM (SELECT * FROM simo_prod.tc_cdr.sim_status_for_sftp_bak
          WHERE DATE(partition_time - INTERVAL 4 HOUR) > DATE('2026-07-31')
            AND DATE(partition_time - INTERVAL 4 HOUR) <= DATE('2026-08-31')) s1
    LEFT JOIN (SELECT imsi, product_id, cycle_time, next_cycle_time FROM (
                 SELECT *, ROW_NUMBER() OVER (PARTITION BY imsi, YEAR(cycle_time), MONTH(cycle_time) ORDER BY create_time DESC) rm
                 FROM simo_prod.ods.resource_res_vsim_cycle_history) WHERE rm = 1) s2
      ON s1.imsi = s2.imsi
     AND YEAR(s1.Cycle_Start_Time) = YEAR(s2.cycle_time)
     AND MONTH(s1.Cycle_Start_Time) = MONTH(s2.cycle_time)
  )
  WHERE SimStatus != 'Installed' AND Cycle_Start_Time IS NOT NULL
),
prod AS (
  SELECT product_id, TRIM(product_name) AS product_name, CAST(package_price AS DOUBLE) AS price, supplier_id
  FROM simo_prod.ods.resource_res_vsim_product
),
cycle_counts AS (
  SELECT imsi, COUNT(DISTINCT Cycle_Start_Time) AS cycles_nums FROM basic_data GROUP BY imsi
),
agg AS (
  SELECT b.imsi, MAX(b.product_id) AS product_id,
         DATE_DIFF(DATE(MAX(b.Cycle_End_Time + INTERVAL 1 MINUTES)), DATE(MAX(b.Cycle_Start_Time))) AS cycle_days,
         CASE WHEN MAX(DATE(b.partition_time)) >= LAST_DAY(DATE('2026-08-01'))
               AND DATE(MAX(b.Cycle_End_Time)) > LAST_DAY(DATE('2026-08-01'))
              THEN COUNT(1) - 1 ELSE COUNT(1) END AS days_orig,
         CASE WHEN MIN(DATE(b.partition_time)) = DATE('2026-08-01')
               AND MAX(DATE(b.partition_time)) = DATE('2026-08-31')
              THEN DAY(LAST_DAY(DATE('2026-08-01')))
              ELSE COUNT(DISTINCT DATE(b.partition_time)) END AS days_fixed
  FROM basic_data b
  JOIN cycle_counts c ON c.imsi = b.imsi
  WHERE c.cycles_nums > 1 AND b.rm = 1
  GROUP BY b.imsi
)
SELECT
  COUNT(1) AS wa_cards,
  ROUND(AVG(a.days_orig),2)  AS avg_days_orig,
  ROUND(AVG(a.days_fixed),2) AS avg_days_fixed,
  ROUND(SUM(ROUND(a.days_orig  / a.cycle_days * p.price, 4)),2) AS fee_orig,
  ROUND(SUM(ROUND(a.days_fixed / a.cycle_days * p.price, 4)),2) AS fee_fixed,
  ROUND(SUM(ROUND(a.days_fixed / a.cycle_days * p.price, 4))
      - SUM(ROUND(a.days_orig  / a.cycle_days * p.price, 4)),2) AS delta
FROM agg a JOIN prod p ON p.product_id = a.product_id
WHERE p.supplier_id = 2275 AND p.product_name NOT LIKE '%PI%'
