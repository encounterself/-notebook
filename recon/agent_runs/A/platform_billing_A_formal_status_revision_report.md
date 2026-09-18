# WA SIM 月度账单批次 A：统一 MATCHED 定义修订报告

本报告只修订平台状态与金额汇总口径，不修改已通过的 Excel control。正式 invoice 左表仍是 `simo_prod.mysql_cdc_sync.wa_invoice_detail.final_charge` 全行 SUM；prorated、credit 不并入 detail。

## 1. 统一状态定义

逐行同时输出：

- `numeric_match_status`：仅表示 days、price、amount 数字是否在既定 tolerance 内相等。
- `formal_match_status`：必须同时满足唯一平台 row/window、charge_type 规则证据、days exact、唯一 price/已证明映射、amount exact，以及 product/lifecycle/replacement/transfer mapping 完整。
- `platform_calculated_amount_known`：只保留唯一平台候选、规则支持、唯一平台价格、days/amount 可计算且非 NULL 的候选金额。
- `platform_total`：仅当该官方 detail batch 的每一条 detail row 都是 `formal_match_status=MATCHED` 时才汇总；否则 NULL。

因此：数值相等但 product_id 缺失为 `numeric_match_status=MATCHED, formal_match_status=MISSING_MAPPING`；一对多窗口为 `UNRESOLVED`；Credit 无平台候选为 `WA_ONLY`。

## 2. Excel 正式金额与月度平台结果

| batch | Excel row_count | distinct_imsi_count | Excel detail.final_charge | known partial platform amount | platform_total | numeric MATCHED rows | formal MATCHED rows | unknown candidate amount rows | unresolved/unproven Excel impact |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 2025-09 | 25,237 | 14,793 | 1,139,393.524729100000 | 358,999.443489000000 | NULL | 11,470 | 0 | 12,780 | 1,139,393.524729100000 |
| 2025-10 (v1) | 12,714 | 12,712 | 772,285.533333333334 | 2,350.000000000000 | NULL | 66 | 0 | 12,642 | 772,285.533333333334 |
| 2025-10 (v2) | 12,663 | 12,641 | 773,737.838709677419 | 55,015.833327000000 | NULL | 226 | 0 | 11,682 | 773,737.838709677419 |
| 2026-01 | 0 | 0 | 0 | NULL | NULL | 0 | 0 | 0 | 0 |

v1 的 `772,750.533333333334` 仍只是排除 37 行 Credit 的正向子集；正式 Excel invoice total 是含 `-465` 的 `772,285.533333333334`。

`platform_calculated_amount` 在逐行 Candidate 中保留所选候选的诊断值；月度汇总不把它称为完整平台总额。完整 `platform_total` 目前全部 NULL，符合正式 MATCHED 门槛。

## 3. formal 状态分拆

| batch | formal_match_status | row_count | distinct_imsi_count | Excel amount |
|---|---|---:|---:|---:|
| 2025-09 | MISSING_MAPPING | 12,457 | 12,457 | 367,192.124726300000 |
| 2025-09 | UNRESOLVED | 12,780 | 12,639 | 772,201.400002800000 |
| 2025-10 (v1) | MISSING_MAPPING | 72 | 72 | 2,364.533333333334 |
| 2025-10 (v1) | UNRESOLVED | 12,605 | 12,605 | 770,386.000000000000 |
| 2025-10 (v1) | WA_ONLY | 37 | 37 | -465.000000000000 |
| 2025-10 (v2) | MISSING_MAPPING | 981 | 981 | 59,746.838709677419 |
| 2025-10 (v2) | UNRESOLVED | 11,682 | 11,681 | 713,991.000000000000 |

detail formal `MISSING_DATA` 当前为 0；v1 Credit 的平台字段 NULL 由 `WA_ONLY` 表示，不被转成 0。平台独立事实另有 `PLATFORM_ONLY`，不是 Excel row。

## 4. charge_type 卡级命中率

卡级表的 `row_count` 与 `distinct_imsi_count` 分开；卡级 exact 定义为该 charge_type + IMSI 下所代表的 invoice rows 全部 exact。

| batch / charge_type | row_count | card_count | days exact cards | price exact cards | amount exact cards | numeric match cards | formal match cards | numeric rate | formal rate |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 2025-09 Full Rate | 12,602 | 12,602 | 12,455 | 11,749 | 11,749 | 110 | 0 | 0.8729% | 0% |
| 2025-09 Partial Charge (Activated AUG) | 11,484 | 11,484 | 11,389 | 11,036 | 10,941 | 10,769 | 0 | 93.7740% | 0% |
| 2025-09 Prorated-in Charge (Activated SEPT) | 1,085 | 1,085 | 916 | 810 | 641 | 591 | 0 | 54.4700% | 0% |
| 2025-09 Prorated-out Charge (Activated SEPT) | 66 | 66 | 66 | 66 | 66 | 0 | 0 | 0% | 0% |
| 2025-10 (v1) Credit for Offstocked Card | 37 | 37 | 0 | 0 | 0 | 0 | 0 | 0% | 0% |
| 2025-10 (v1) Full Cycle Charge | 12,573 | 12,573 | 9,847 | 11,449 | 11,449 | 0 | 0 | 0% | 0% |
| 2025-10 (v1) New Activation: Prorated-in Charge | 72 | 72 | 68 | 72 | 66 | 66 | 0 | 91.6667% | 0% |
| 2025-10 (v1) Prorated-out Charge (Activated OCT) | 32 | 32 | 32 | 31 | 31 | 0 | 0 | 0% | 0% |
| 2025-10 (v2) Full Cycle Charge | 12,641 | 12,641 | 12,120 | 11,168 | 11,168 | 226 | 0 | 1.7878% | 0% |
| 2025-10 (v2) New Activation: Prorated-in Charge | 22 | 22 | 6 | 20 | 0 | 0 | 0 | 0% | 0% |

## 5. PLATFORM_ONLY

平台人口固定为 supplier=2275 产品目录经 `product_id` 过滤后的 cycle_history，时间窗口为 `cycle_time < 2026-02-01` 且 `next_cycle_time > 2025-09-01`；再以 IMSI 与 Excel cycle/final window 做排除。

| observed_start_month | official label | row_count | distinct_imsi_count |
|---|---|---:|---:|
| 2025-08 | NULL | 464 | 464 |
| 2025-09 | 2025-09 | 333 | 333 |
| 2025-10 | 2025-10 (v1) | 5 | 5 |
| 2025-11 | 2025-10 (v2) | 1,275 | 1,013 |
| 2025-12 | NULL | 13,609 | 13,020 |
| 2026-01 | 2026-01 | 14,089 | 13,009 |

## 6. 证据与待解决项

- Excel detail 无 `product_id`，所以 numeric 命中不能升级 formal MATCHED。
- 多个生命周期候选保留为 `UNRESOLVED`，未任意挑选候选来制造完整平台总额。
- replacement/transfer/Simbank 只有在对应字段证据完整时才能正式匹配；当前没有将缺失映射默认为已通过。
- 2025-09 status snapshot 分区存在只读探针层面的 parquet AccessDenied；没有用它补造平台人口。
- `2025-10 (v2)` 保留 official label，observed_start_month 仍为 `2025-11`，未改成单一 billing_month。

## 7. 本次独立产物

- [统一 formal Candidate SQL](<C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/A/platform_billing_A_revision_06_formal_candidate_billing.sql>)
- [Candidate EXPLAIN 结果](<C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/A/platform_billing_A_revision_06_formal_candidate_explain.tsv>)
- [统一 formal Reconciliation SQL](<C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/A/platform_billing_A_revision_07_formal_reconciliation_summary.sql>)
- [统一 formal Reconciliation 结果](<C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/A/platform_billing_A_revision_07_formal_reconciliation_summary.tsv>)
- [charge_type formal/numeric SQL](<C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/A/platform_billing_A_revision_08_formal_charge_type_metrics.sql>)
- [charge_type formal/numeric 结果](<C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/A/platform_billing_A_revision_08_formal_charge_type_metrics.tsv>)
- [统一状态逐行样例](<C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/A/platform_billing_A_revision_09_formal_candidate_row_sample.tsv>)
