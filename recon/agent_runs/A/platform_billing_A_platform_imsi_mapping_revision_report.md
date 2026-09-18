# WA SIM 批次 A：platform-imsi 产品映射证明后的统一 MATCHED 复算

本次修订采用用户确认的产品映射方式：`wa_invoice_detail` 的 `excel_product_id` 保持 NULL；平台通过 `imsi + Excel 计费窗口` 唯一确定 `platform_product_id`，且该 product 已由 `resource_res_vsim_product.supplier_id=2275` 限定，价格唯一并与 Excel monthly_rate exact。product_name 仅展示，不作为 JOIN 键。

## 1. 统一正式状态

- `numeric_match_status`：仅表示 days、price、amount 是否 exact。
- `platform_product_mapping_status`：
  - `PROVEN_BY_PLATFORM_IMSI`：唯一 lifecycle/window 候选、product_id 非 NULL、且 product 来自 supplier=2275 产品集合。
  - `MULTIPLE_PLATFORM_PRODUCTS_OR_WINDOWS`：一对多窗口或产品候选。
  - `NO_PLATFORM_PRODUCT`：没有平台候选。
  - `PLATFORM_PRODUCT_PRICE_NOT_PROVEN`：平台价格缺失或多值。
- `formal_match_status=MATCHED`：唯一 product/window + 规则证据 + days exact + 唯一平台价格与 Excel monthly_rate exact + amount exact + 必要映射完整。
- Excel product_id NULL 本身不再导致 MISSING_MAPPING。
- `platform_calculated_amount_known` 只汇总唯一平台候选且规则、价格、days、amount 均可证明的非 NULL 候选。
- `platform_total` 只有该 batch 全部 detail rows formal MATCHED 时才计算；否则 NULL。

## 2. 月度结果

| batch | Excel row_count | distinct_imsi_count | Excel detail.final_charge | known partial platform amount | platform_total | numeric MATCHED rows | formal MATCHED rows | unknown candidate amount rows | unresolved/unproven Excel impact |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 2025-09 | 25,237 | 14,793 | 1,139,393.524729100000 | 358,999.443489000000 | NULL | 11,470 | 11,470 | 12,780 | 801,731.333326700000 |
| 2025-10 (v1) | 12,714 | 12,712 | 772,285.533333333334 | 2,350.000000000000 | NULL | 66 | 66 | 12,642 | 770,009.533333333334 |
| 2025-10 (v2) | 12,663 | 12,641 | 773,737.838709677419 | 55,015.833327000000 | NULL | 226 | 226 | 11,682 | 759,725.838709677419 |
| 2026-01 | 0 | 0 | 0 | NULL | NULL | 0 | 0 | 0 | 0 |

v1 正式 Excel invoice total 仍为含负 Credit 的 `772,285.533333333334`；`772,750.533333333334` 只是排除 Credit 的正向子集。

`platform_total` 全部 NULL 是有意保留的门禁结果，不把 known partial amount 冒充完整平台总额。

## 3. formal 状态拆分

| batch | formal_match_status | row_count | distinct_imsi_count | Excel amount |
|---|---|---:|---:|---:|
| 2025-09 | MATCHED | 11,470 | 11,470 | 337,662.191402400000 |
| 2025-09 | UNRESOLVED | 13,767 | 13,767 | 801,731.333326700000 |
| 2025-10 (v1) | MATCHED | 66 | 66 | 2,276.000000000000 |
| 2025-10 (v1) | UNRESOLVED | 12,611 | 12,611 | 770,474.533333333334 |
| 2025-10 (v1) | WA_ONLY | 37 | 37 | -465.000000000000 |
| 2025-10 (v2) | MATCHED | 226 | 226 | 14,012.000000000000 |
| 2025-10 (v2) | UNRESOLVED | 12,437 | 12,437 | 759,725.838709677419 |

正式 `MISSING_MAPPING` 的产品原因不再由 Excel product_id NULL 触发；当前主要未解决原因是多生命周期候选、days/price/amount 不一致或规则窗口未唯一证明。

## 4. charge_type 卡级命中率

| batch / charge_type | row_count | card_count | days exact cards | price exact cards | amount exact cards | numeric MATCHED cards | formal MATCHED cards | formal rate |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 2025-09 Full Rate | 12,602 | 12,602 | 12,455 | 11,749 | 11,749 | 110 | 110 | 0.8729% |
| 2025-09 Partial Charge (Activated AUG) | 11,484 | 11,484 | 11,389 | 11,036 | 10,941 | 10,769 | 10,769 | 93.7740% |
| 2025-09 Prorated-in Charge (Activated SEPT) | 1,085 | 1,085 | 916 | 810 | 641 | 591 | 591 | 54.4700% |
| 2025-09 Prorated-out Charge (Activated SEPT) | 66 | 66 | 66 | 66 | 66 | 0 | 0 | 0% |
| 2025-10 (v1) Credit for Offstocked Card | 37 | 37 | 0 | 0 | 0 | 0 | 0 | 0% |
| 2025-10 (v1) Full Cycle Charge | 12,573 | 12,573 | 9,847 | 11,449 | 11,449 | 0 | 0 | 0% |
| 2025-10 (v1) New Activation: Prorated-in Charge | 72 | 72 | 68 | 72 | 66 | 66 | 66 | 91.6667% |
| 2025-10 (v1) Prorated-out Charge (Activated OCT) | 32 | 32 | 32 | 31 | 31 | 0 | 0 | 0% |
| 2025-10 (v2) Full Cycle Charge | 12,641 | 12,641 | 12,120 | 11,168 | 11,168 | 226 | 226 | 1.7878% |
| 2025-10 (v2) New Activation: Prorated-in Charge | 22 | 22 | 6 | 20 | 0 | 0 | 0 | 0% |

## 5. 逐行证据

正式 MATCHED 样例同时保留：

- `excel_product_id = NULL`
- `excel_product_name`
- `platform_product_id`
- `platform_product_name`
- `platform_product_mapping_status = PROVEN_BY_PLATFORM_IMSI`
- `numeric_match_status = MATCHED`
- `formal_match_status = MATCHED`
- `platform_calculated_days`
- `platform_calculated_amount`
- `platform_calculated_amount_known`
- `numeric_difference_reason`
- `difference_reason = FORMAL_MATCH_PROVEN_BY_PLATFORM_IMSI`

多候选样例的 mapping status 为 `MULTIPLE_PLATFORM_PRODUCTS_OR_WINDOWS`，formal status 为 `UNRESOLVED`，没有因金额相等而升级。

## 6. 平台独占人口

平台集合仍固定为 supplier=2275 产品集合内的 cycle_history，窗口为 `cycle_time < 2026-02-01` 且 `next_cycle_time > 2025-09-01`，再以 IMSI + Excel window 排除。

| observed_start_month | official label | row_count | distinct_imsi_count |
|---|---|---:|---:|
| 2025-08 | NULL | 464 | 464 |
| 2025-09 | 2025-09 | 333 | 333 |
| 2025-10 | 2025-10 (v1) | 5 | 5 |
| 2025-11 | 2025-10 (v2) | 1,275 | 1,013 |
| 2025-12 | NULL | 13,609 | 13,020 |
| 2026-01 | 2026-01 | 14,089 | 13,009 |

## 7. 只读产物

- [完整 platform-imsi formal Candidate SQL](<C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/A/platform_billing_A_revision_15_platform_imsi_proven_candidate.sql>)
- [Candidate EXPLAIN 结果](<C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/A/platform_billing_A_revision_15_platform_imsi_proven_explain.tsv>)
- [完整 platform-imsi Reconciliation SQL](<C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/A/platform_billing_A_revision_16_platform_imsi_proven_reconciliation.sql>)
- [Reconciliation 结果](<C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/A/platform_billing_A_revision_16_platform_imsi_proven_reconciliation.tsv>)
- [charge_type SQL](<C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/A/platform_billing_A_revision_17_platform_imsi_proven_charge_type_metrics.sql>)
- [charge_type 结果](<C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/A/platform_billing_A_revision_17_platform_imsi_proven_charge_type_metrics.tsv>)
- [正式 MATCHED 样例](<C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/A/platform_billing_A_revision_18_formal_matched_sample.tsv>)

