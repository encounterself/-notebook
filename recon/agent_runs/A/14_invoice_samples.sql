-- Batch A / read-only invoice field samples by month and charge_type.
WITH x AS (
  SELECT
    DATE_FORMAT(TRY_CAST(final_start_date AS DATE), 'yyyy-MM') AS billing_month,
    imsi, iccid, product_name, cycle_start_date, cycle_end_date,
    new_activation_date, offstock_date, charge_type, status,
    new_card_imsi_replacement, old_card_imsi_replaced,
    final_start_date, final_end_date, active_days, usage_days, usage_days_alt,
    usage_days_gt_active, final_days, monthly_rate, final_charge,
    transferred_to_wing_simbank, note, source_file,
    ROW_NUMBER() OVER (
      PARTITION BY DATE_FORMAT(TRY_CAST(final_start_date AS DATE), 'yyyy-MM'), charge_type
      ORDER BY imsi
    ) AS rn
  FROM simo_prod.mysql_cdc_sync.wa_invoice_detail
  WHERE TRY_CAST(final_start_date AS DATE) >= DATE('2025-09-01')
    AND TRY_CAST(final_start_date AS DATE) < DATE('2025-12-01')
)
SELECT *
FROM x
WHERE rn <= 5
ORDER BY billing_month, charge_type, rn;