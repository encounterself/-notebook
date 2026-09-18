-- Batch A / Excel logical-source completeness and self-recomputability.
-- Read-only. Detail is the authoritative monthly target; credit/prorated are audited as auxiliary sources.
-- No source UNION is used to create the target until a proven one-to-one mapping exists.
WITH cfg AS (
  SELECT '2025-09' AS billing_month, DATE('2025-09-01') AS month_start, DATE('2025-09-30') AS month_end
  UNION ALL SELECT '2025-10', DATE('2025-10-01'), DATE('2025-10-31')
  UNION ALL SELECT '2025-11', DATE('2025-11-01'), DATE('2025-11-30')
), detail_base AS (
  SELECT
    c.billing_month,
    x.imsi,
    x.charge_type,
    x.source_file,
    TRY_CAST(x.final_days AS DOUBLE) AS final_days,
    TRY_CAST(x.monthly_rate AS DOUBLE) AS monthly_rate,
    TRY_CAST(x.final_charge AS DOUBLE) AS final_charge
  FROM cfg c
  JOIN simo_prod.mysql_cdc_sync.wa_invoice_detail x
    ON TRY_CAST(x.final_start_date AS DATE) BETWEEN c.month_start AND c.month_end
), detail_grain AS (
  SELECT billing_month, imsi, charge_type, COUNT(*) AS grain_rows
  FROM detail_base
  GROUP BY billing_month, imsi, charge_type
), detail_rows AS (
  SELECT d.*, g.grain_rows
  FROM detail_base d
  JOIN detail_grain g
    ON g.billing_month = d.billing_month
   AND g.imsi = d.imsi
   AND COALESCE(g.charge_type, '') = COALESCE(d.charge_type, '')
), detail_agg AS (
  SELECT
    billing_month,
    'DETAIL_AUTHORITATIVE' AS source_role,
    COUNT(*) AS source_rows,
    COUNT(DISTINCT imsi) AS source_cards,
    ROUND(SUM(final_charge), 4) AS source_amount,
    ROUND(SUM(final_days), 4) AS source_days,
    SUM(CASE WHEN grain_rows > 1 THEN grain_rows - 1 ELSE 0 END) AS duplicate_rows_at_billing_month_imsi_charge_type,
    CAST(NULL AS BIGINT) AS overlap_rows_with_detail,
    CAST(NULL AS BIGINT) AS overlap_cards_with_detail,
    'Authoritative Excel target: final_start_date month; no union with auxiliary tables.' AS evidence_status
  FROM detail_rows
  GROUP BY billing_month
), credit_base AS (
  SELECT
    CASE
      WHEN source_file LIKE '%SEP 2025%' THEN '2025-09'
      WHEN source_file LIKE '%772,765.00%' THEN '2025-10'
      WHEN source_file LIKE '%773,793.84%' THEN '2025-11'
      ELSE 'UNMAPPED'
    END AS billing_month,
    imsi,
    TRY_CAST(credit_owed AS DOUBLE) AS credit_amount,
    source_file
  FROM simo_prod.mysql_cdc_sync.wa_invoice_credit
), credit_agg AS (
  SELECT
    c.billing_month,
    'CREDIT_AUXILIARY' AS source_role,
    COUNT(cb.imsi) AS source_rows,
    COUNT(DISTINCT cb.imsi) AS source_cards,
    ROUND(SUM(cb.credit_amount), 4) AS source_amount,
    CAST(NULL AS DOUBLE) AS source_days,
    CAST(NULL AS BIGINT) AS duplicate_rows_at_billing_month_imsi_charge_type,
    CAST(NULL AS BIGINT) AS overlap_rows_with_detail,
    CAST(NULL AS BIGINT) AS overlap_cards_with_detail,
    'Auxiliary credit source; negative sign preserved; not unioned into detail target.' AS evidence_status
  FROM cfg c
  LEFT JOIN credit_base cb ON cb.billing_month = c.billing_month
  GROUP BY c.billing_month
), prorated_base AS (
  SELECT
    CASE
      WHEN TRY_CAST(final_start_date AS DATE) BETWEEN DATE('2025-09-01') AND DATE('2025-09-30') THEN '2025-09'
      WHEN TRY_CAST(final_start_date AS DATE) BETWEEN DATE('2025-10-01') AND DATE('2025-10-31') THEN '2025-10'
      WHEN TRY_CAST(final_start_date AS DATE) BETWEEN DATE('2025-11-01') AND DATE('2025-11-30') THEN '2025-11'
      ELSE 'UNMAPPED'
    END AS billing_month,
    imsi,
    TRY_CAST(final_charge_for_usage_days AS DOUBLE) AS source_amount,
    TRY_CAST(active_days AS DOUBLE) AS source_days,
    source_file
  FROM simo_prod.mysql_cdc_sync.wa_invoice_prorated
), prorated_agg AS (
  SELECT
    c.billing_month,
    'PRORATED_AUXILIARY' AS source_role,
    COUNT(pb.imsi) AS source_rows,
    COUNT(DISTINCT pb.imsi) AS source_cards,
    ROUND(SUM(pb.source_amount), 4) AS source_amount,
    ROUND(SUM(pb.source_days), 4) AS source_days,
    CAST(NULL AS BIGINT) AS duplicate_rows_at_billing_month_imsi_charge_type,
    CAST(NULL AS BIGINT) AS overlap_rows_with_detail,
    CAST(NULL AS BIGINT) AS overlap_cards_with_detail,
    'Auxiliary prorated source; audited for overlap; not unioned into detail target.' AS evidence_status
  FROM cfg c
  LEFT JOIN prorated_base pb ON pb.billing_month = c.billing_month
  GROUP BY c.billing_month
), prorated_overlap AS (
  SELECT
    c.billing_month,
    'PRORATED_OVERLAP_WITH_DETAIL' AS source_role,
    COUNT(pb.imsi) AS source_rows,
    COUNT(DISTINCT pb.imsi) AS source_cards,
    ROUND(SUM(pb.source_amount), 4) AS source_amount,
    ROUND(SUM(pb.source_days), 4) AS source_days,
    CAST(NULL AS BIGINT) AS duplicate_rows_at_billing_month_imsi_charge_type,
    COUNT(d.imsi) AS overlap_rows_with_detail,
    COUNT(DISTINCT d.imsi) AS overlap_cards_with_detail,
    'Overlap is evidence against naive union; detail remains authoritative.' AS evidence_status
  FROM cfg c
  LEFT JOIN prorated_base pb ON pb.billing_month = c.billing_month
  LEFT JOIN detail_base d
    ON d.billing_month = pb.billing_month
   AND d.imsi = pb.imsi
  GROUP BY c.billing_month
)
SELECT * FROM detail_agg
UNION ALL SELECT * FROM credit_agg
UNION ALL SELECT * FROM prorated_agg
UNION ALL SELECT * FROM prorated_overlap
ORDER BY billing_month, source_role