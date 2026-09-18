# B 补跑报告：2025-12 与 2026-02

本报告为 B 补跑独立结果，仅使用本次 `simo_cdc` 只读查询；不引用 B 目录中的旧 provisional 结果，也不等待 A。

## 口径

- Excel 正式 invoice 左表只使用 `simo_prod.mysql_cdc_sync.wa_invoice_detail.final_charge`，逐行保留；credit/prorated 不并入。
- `excel_product_id` 保持 NULL。产品映射通过 `imsi + Excel final_start/final_end window` 唯一确定平台产品，且平台 `supplier_id = 2275`、平台价格唯一并与 Excel `monthly_rate` exact，状态为 `PROVEN_BY_PLATFORM_IMSI`。
- `numeric_match_status` 只比较 days/price/amount 数值；`formal_match_status` 另要求唯一平台 window、规则/生命周期证据、产品映射证明和金额 exact。
- Excel 侧使用 `record_side = EXCEL_DETAIL`；PLATFORM_ONLY 使用独立的 `record_side = PLATFORM_FACT`，两者不共用分母。

## Excel 与平台月度金额

| 月份 | Excel source_file | Excel rows / IMSI | Excel total | platform_calculated_amount_known | known diff = known - Excel | platform_total |
|---|---|---:|---:|---:|---:|---|
| 2025-12 | `SIMO Data Purchase Invoice Details - DEC 2025.xlsx` | 12,185 / 12,110 | 704,839.3537634288 | 553,619.935472 | -151,219.418291 | NULL / UNRESOLVED |
| 2026-02 | `01-SIMO Data Purchase Invoice Details - FEB 2026.xlsx` | 12,572 / 12,309 | 690,572.7235023013 | 551,842.000000 | -138,730.723502 | NULL / UNRESOLVED |

`platform_calculated_amount_known` 只汇总 evidence 已知且 amount 非 NULL 的候选。`platform_total` 因仍有非正式匹配行，保持 NULL。

逐月可复算：

- 2025-12：`553619.935472 - 704839.3537634288 = -151219.4182914288`，汇总显示 `-151219.418291`。
- 2026-02：`551842.000000 - 690572.7235023013 = -138730.7235023013`，汇总显示 `-138730.723502`。

## 状态与独立分母

| 月份 | Excel 侧分母 rows / IMSI | MATCHED | WA_ONLY | UNRESOLVED | MISSING_DATA | MISSING_MAPPING | PLATFORM_ONLY 独立分母 |
|---|---:|---:|---:|---:|---:|---:|---:|
| 2025-12 | 12,185 / 12,110 | 9,287 / 9,287 | 12 / 12 | 2 / 2 | 140 / 140 | 2,744 / 2,744 | 4,659 / 4,328 |
| 2026-02 | 12,572 / 12,309 | 9,474 / 9,474 | 4 / 4 | 272 / 272 | 474 / 474 | 2,348 / 2,272 | 3,877 / 3,437 |

Excel 侧状态 row_count 的合计分别为 12,185 和 12,572。各状态 distinct IMSI 可能重叠，不能相加作为 Excel distinct IMSI 分母。PLATFORM_ONLY 不加入 Excel 分母。

## charge_type / rule 结果

| 月份 / charge_type | rows | numeric match | formal MATCHED | mapping proven | 说明 |
|---|---:|---:|---:|---:|---|
| 2025-12 Full Cycle Charge | 11,437 | 10,022 | 9,102 | 9,104 | 周期窗口和价格证据已覆盖主要子集 |
| 2025-12 New Activation: Prorated-in Charge | 748 | 746 | 185 | 325 | activation/lifecycle 证据只对部分行完整 |
| 2026-02 Full Cycle Charge | 11,748 | 10,222 | 9,474 | 9,656 | 主要正式匹配来源 |
| 2026-02 New Activation: Prorated-in Charge | 729 | 380 | 0 | 474 | activation/window 或金额证据不足 |
| 2026-02 Offstocked before cycle start | 91 | 0 | 0 | 90 | WA_ONLY/规则未证明 |
| 2026-02 Partial Charge - Card Replaced Mid Cycle | 4 | 3 | 0 | 3 | replacement mapping 缺失 |

## 可审计文件

- [B 月度汇总 TSV](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/B/platform_card_b_reconciliation_month_summary.tsv)
- [B 状态分母拆分 TSV](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/B/platform_card_b_reconciliation_status_summary_corrected.tsv)
- [B charge_type/rule TSV](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/B/platform_card_b_candidate_rule_summary.tsv)
- [B Candidate Billing 逐行 TSV](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/B/platform_card_b_candidate_billing.tsv)
- [B Reconciliation 逐行 TSV](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/B/platform_card_b_reconciliation.tsv)
- [B Candidate Billing SQL](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/B/platform_card_b_candidate_billing.sql)
- [B Reconciliation SQL](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/B/platform_card_b_reconciliation.sql)
- [B 月度汇总 SQL](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/B/platform_card_b_reconciliation_month_summary.sql)
- [B 状态汇总 SQL](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/B/platform_card_b_reconciliation_status_summary.sql)