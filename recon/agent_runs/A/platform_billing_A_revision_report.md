# WA SIM 月度账单独立对账批次 A：平台卡级复算修订

本修订不改 Excel control，只使用 `wa_invoice_detail.final_charge` 作为正式 invoice 左表；`wa_invoice_prorated` 与 `wa_invoice_credit` 不加入正式 detail 金额。本地文件均落在本批次独立目录，平台查询全部通过 SQL 只读预检。

## 1. 只读门禁与可执行性

- 平台 profile：`simo_cdc`；平台对象统一使用 `simo_prod` 全限定名。
- 每次执行前检查首 token 与禁用关键字；本次 revision SQL 均为 `WITH`，`FORBIDDEN=NONE`。
- `platform_billing_A_revision_02_candidate_explain.tsv`：`EXPLAIN` 成功，说明 Candidate SQL 的全部 CTE 定义完整且可编译。
- `platform_billing_A_revision_03_reconciliation_summary.sql`：完整 Candidate CTE + row/status/imsi/platform-only 汇总；未引用未定义 recon 终端。
- `platform_billing_A_revision_04_candidate_row_sample.tsv`：100 行逐行证据样例。

## 2. 冻结的 Excel detail invoice 左表

金额直接来自 `simo_prod.mysql_cdc_sync.wa_invoice_detail.final_charge`；不并入 prorated 或 credit 表。v1 的 `772,750.533333333334` 是去掉 37 行 Credit 后的非 Credit 子集；正式 detail 全行金额减去 `465` Credit 后为 `772,285.533333333334`，不是补差。

| official_excel_billing_month | source_file | observed_start_month | Excel row_count | distinct_imsi_count | Excel total_final_charge |
|---|---|---:|---:|---:|---:|
| 2025-09 | 006-V2 - SIMO Data Purchase Invoice Details - SEP 2025.xlsx | 2025-09 | 25,237 | 14,793 | 1,139,393.524729100000 |
| 2025-10 (v1) | 01-INVOICE_FROM_ WA_USD_772,765.00_SIMO Data Purchase Invoice Details - OCT 2025.xlsx | 2025-10 | 12,714 | 12,712 | 772,285.533333333334 |
| 2025-10 (v2) | 01-1-INVOICE_FROM_ WA_USD_773,793.84_SIMO Data Purchase Invoice Details - OCT 2025.xlsx | 2025-11 | 12,663 | 12,641 | 773,737.838709677419 |
| 2026-01 | 无官方 JAN 2026 detail source_file | 2026-01 | 0 | 0 | 0 |

三个月 detail source_file 的逐行 SUM 重算差异均为 0；基线 SQL 同时输出 source_file、charge_type 子集和 `row_sum_amount_diff`。

## 3. 月度平台候选与统一粒度

`MONTH_RECONCILIATION` 是 invoice-row 粒度；`IMSI_STATUS` 是 distinct IMSI 粒度，其中 `row_count` 表示该卡集合代表的 detail invoice rows。平台候选金额不是把 NULL 变成 0；Credit 没有平台候选时 platform amount 和 amount_diff 保持 NULL。

| official_excel_billing_month | Excel row_count | Excel distinct IMSI | Excel amount | platform calculated amount | amount_diff | days exact rows | price exact rows | amount exact rows | unresolved/unproven Excel impact |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 2025-09 | 25,237 | 14,793 | 1,139,393.524729100000 | 1,114,993.843517000000 | -24,399.681212100000 | 24,826 | 23,661 | 23,397 | 1,139,393.524729100000 |
| 2025-10 (v1) | 12,714 | 12,712 | 772,285.533333333334 | 751,375.709677000000 | -21,374.823656333340 | 9,947 | 11,552 | 11,546 | 772,285.533333333334 |
| 2025-10 (v2) | 12,663 | 12,641 | 773,737.838709677419 | 745,519.999994000000 | -28,217.838715677420 | 12,126 | 11,188 | 11,168 | 773,737.838709677419 |
| 2026-01 | 0 | 0 | 0 | NULL | NULL | 0 | 0 | 0 | 0 |

解释：`unresolved_or_unproven_excel_amount` 包含正式 source match 未证明的行；由于 Excel detail 没有 product_id，即使数值三项都命中，也必须保留 MISSING_MAPPING，不得升级为正式 MATCHED。

## 4. 状态、row_count 与 distinct_imsi_count

正式 `source_match_status=MATCHED` 为 0：Excel 没有 product_id，不能完成产品映射证明。`numeric_match_status=MATCHED` 仍作为有规则证据的数值命中单独报告，不等同正式 MATCHED。

| batch | status | row_count | distinct_imsi_count | Excel amount | platform amount | amount_diff |
|---|---|---:|---:|---:|---:|---:|
| 2025-09 | MISSING_MAPPING / numeric MATCHED | 11,470 | 11,470 | 337,662.191402400000 | 337,662.191774000000 | 0.000371600000 |
| 2025-09 | MISSING_MAPPING / numeric mismatch | 987 | 987 | 29,529.933323900000 | 21,337.251715000000 | -8,192.681608900000 |
| 2025-09 | UNRESOLVED / ambiguous candidate | 12,780 | 12,639 | 772,201.400002800000 | 755,994.400028000000 | -16,206.999974800000 |
| 2025-10 (v1) | MISSING_MAPPING | 72 | 72 | 2,364.533333333334 | 2,350.000000000000 | -14.533333333334 |
| 2025-10 (v1) | UNRESOLVED / ambiguous candidate | 12,605 | 12,605 | 770,386.000000000000 | 749,025.709677000000 | -21,360.290323000000 |
| 2025-10 (v1) | WA_ONLY | 37 | 37 | -465.000000000000 | NULL | NULL |
| 2025-10 (v2) | MISSING_MAPPING | 981 | 981 | 59,746.838709677419 | 55,015.833327000000 | -4,731.005382677419 |
| 2025-10 (v2) | UNRESOLVED / ambiguous candidate | 11,682 | 11,681 | 713,991.000000000000 | 690,504.166667000000 | -23,486.833333000000 |

`PLATFORM_ONLY` 是独立 platform lifecycle row 粒度，另给 distinct IMSI，不能当作 detail 卡数：

| observed_start_month | official label | platform-only row_count | distinct_imsi_count | 来源/排除理由 |
|---|---|---:|---:|---|
| 2025-08 | NULL | 464 | 464 | supplier=2275 产品集合内的 cycle_history；与目标 detail window 无 exact/overlap match |
| 2025-09 | 2025-09 | 333 | 333 | 同上 |
| 2025-10 | 2025-10 (v1) | 5 | 5 | 同上 |
| 2025-11 | 2025-10 (v2) | 1,275 | 1,013 | 同上 |
| 2025-12 | NULL | 13,609 | 13,020 | cycle_history 事实超出官方 detail source_file，但仍在统一生命周期探针窗口 |
| 2026-01 | 2026-01 | 14,089 | 13,009 | 无 JAN 2026 detail source_file，故全部独立标 platform-only |

## 5. charge_type 规则与命中率

规则证据：

- `Full Rate` / `Full Cycle Charge` → `R_FULL_CYCLE_PRICE`，平台价格仅取 `product_id` 对应产品目录唯一 `package_price`。
- `Partial Charge%` → `R_PARTIAL_LIFECYCLE_DAYS_ACTIVATION_MONTH`，按 Excel cycle start 月作 proration denominator。
- `Prorated-in%`、`Prorated-out%`、`New Activation:%` → `R_PRORATED_LIFECYCLE_DAYS_ACTIVATION_MONTH`，按 Excel final start / new activation 月作 denominator。
- `Credit for Offstocked Card` → `R_CREDIT_REQUIRES_CREDIT_EVIDENCE`，当前没有 detail 平台 Credit 证据，保留 WA_ONLY/NULL。

下表是 distinct IMSI 卡级命中率；numeric match 是 days+price+amount 同时命中且有 rule_id 的数值证据，formal match 还要求 Excel product_id 映射，因此当前均为 0。

| batch / charge_type | card_count | days exact | price exact | amount exact | numeric match | numeric match rate | formal MATCHED | UNRESOLVED cards |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 2025-09 Full Rate | 12,602 | 12,455 | 11,749 | 11,749 | 110 | 0.8729% | 0 | 12,492 |
| 2025-09 Partial Charge (Activated AUG) | 11,484 | 11,389 | 11,036 | 10,941 | 10,769 | 93.7740% | 0 | 172 |
| 2025-09 Prorated-in Charge (Activated SEPT) | 1,085 | 916 | 810 | 641 | 591 | 54.4700% | 0 | 50 |
| 2025-09 Prorated-out Charge (Activated SEPT) | 66 | 66 | 66 | 66 | 0 | 0.0000% | 0 | 66 |
| 2025-10 (v1) Credit for Offstocked Card | 37 | 0 | 0 | 0 | 0 | 0.0000% | 0 | 0 |
| 2025-10 (v1) Full Cycle Charge | 12,573 | 9,847 | 11,449 | 11,449 | 0 | 0.0000% | 0 | 12,573 |
| 2025-10 (v1) New Activation: Prorated-in Charge | 72 | 68 | 72 | 66 | 66 | 91.6667% | 0 | 0 |
| 2025-10 (v1) Prorated-out Charge (Activated OCT) | 32 | 32 | 31 | 31 | 0 | 0.0000% | 0 | 32 |
| 2025-10 (v2) Full Cycle Charge | 12,641 | 12,120 | 11,168 | 11,168 | 226 | 1.7878% | 0 | 11,681 |
| 2025-10 (v2) New Activation: Prorated-in Charge | 22 | 6 | 20 | 0 | 0 | 0.0000% | 0 | 1 |

## 6. 平台人口固定规则

- 产品目录固定过滤 `resource_res_vsim_product.supplier_id = 2275`，再以 `product_id` 连接 cycle_history；`sim_status_for_sftp_bak` 本身没有 supplier_id，因此只通过 `product_id` 落入 supplier=2275 产品集合。
- cycle_history 只读取 `cycle_time < 2026-02-01` 且 `next_cycle_time > 2025-09-01`，并先按 supplier=2275 产品集合限定生命周期，再做 Excel window 关联。
- status snapshot 只在已限定的 `imsi + product_id` 人口上读取 2025-10/11 分区；status_log 只在已限定的生命周期 IMSI 上读取 2025-09 至 2025-11 分区。没有将全量 snapshot、全量 status_log、全量 cycle_history UNION 成人口。
- Excel 没有 product_id，平台 product_id/name/price 独立保留；正式价格 JOIN 未使用 product_name。

## 7. 未解决 / 缺失影响

1. `MISSING_MAPPING`：`wa_invoice_detail` 没有 product_id；需要可审计的 Excel product_id 或经证据确认的映射表，才能把数值命中升级为正式 MATCHED。
2. `UNRESOLVED`：主要是同一 IMSI 在生命周期窗口命中多个 platform cycle candidate；当前保留候选数量、最长 overlap 选择和 `MULTIPLE_PLATFORM_CYCLE_CANDIDATES`，没有任意择一计费。
3. `WA_ONLY`：v1 Credit 37 行、37 IMSI、-465；不能由平台 lifecycle 价格/天数复算，必须独立 Credit 证据。
4. 2025-09 `sim_status_for_sftp_bak` 目标分区曾在只读探针中返回底层 parquet AccessDenied；本修订没有用它制造 2025-09 卡人口，也没有把缺失数据改成 0。平台金额复算主要使用 supplier/product 约束后的 cycle_history 与产品目录。
5. 2026-01 无官方 JAN 2026 detail source_file；Excel 基准必须为 0，平台 14,089 lifecycle rows / 13,009 IMSI 单独标 PLATFORM_ONLY。
6. 2025-10 v2 仍保留 `official_excel_billing_month=2025-10 (v2)`、`observed_start_month=2025-11`，没有改写为 2025-11；v1/v2 与 observed month 未合并。

## 8. 本次独立产物

- [冻结 detail Excel 基线 SQL](platform_billing_A_revision_01_frozen_excel_baseline.sql) / [结果](platform_billing_A_revision_01_frozen_excel_baseline.tsv)
- [完整 Candidate Billing SQL](platform_billing_A_revision_02_candidate_billing.sql)
- [Candidate EXPLAIN SQL](platform_billing_A_revision_02_candidate_explain.sql) / [结果](platform_billing_A_revision_02_candidate_explain.tsv)
- [完整 Reconciliation 汇总 SQL](platform_billing_A_revision_03_reconciliation_summary.sql) / [结果](platform_billing_A_revision_03_reconciliation_summary.tsv)
- [Candidate 逐行样例 SQL](platform_billing_A_revision_04_candidate_row_sample.sql) / [结果](platform_billing_A_revision_04_candidate_row_sample.tsv)
- [charge_type row/card 指标 SQL](platform_billing_A_revision_05_charge_type_metrics.sql) / [结果](platform_billing_A_revision_05_charge_type_metrics.tsv)

这些 revision 文件均在本批次独立目录，不覆盖既有 Excel control 或参考文件。
