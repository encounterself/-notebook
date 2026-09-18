# C 批金额与分母控制修正版

本报告仅使用本次 simo_cdc 只读查询结果。平台 SQL 只执行 WITH/SELECT；没有平台写入。

## 金额字段定义

- `excel_total_final_charge`：官方 `wa_invoice_detail.final_charge` 全部 detail invoice rows 的 SUM，包含负 Credit 行。
- `platform_calculated_amount_known_total`：仅汇总 `platform_amount_evidence_status = 'KNOWN'` 且 `platform_calculated_amount IS NOT NULL` 的 Excel-side 候选行，是部分已知金额，不是完整平台总额。
- `known_amount_diff`：严格为 `platform_calculated_amount_known_total - excel_total_final_charge`。
- `candidate_row_amount_diff_total`：逐行 `amount_diff` 在候选 Excel rows 上的诊断合计；不能代替 `known_amount_diff`。
- `platform_total`：只有全部 Excel detail rows 都具备完整规则证据并正式 MATCHED 时才非 NULL；本批三个月均为 NULL/UNRESOLVED。

## 月度可复算结果

| 月份 | Excel rows | Excel IMSI | Excel total | Known amount | Known amount diff | Candidate-row diff（诊断） | Platform total |
|---|---:|---:|---:|---:|---:|---:|---|
| 2026-03 | 13082 | 12763 | 578406.3064516085 | 248869.299562 | -329537.006890 | -30594.746111 | NULL / UNRESOLVED |
| 2026-04 | 7780 | 7317 | 372289.3075268780 | 259840.766667 | -112448.540860 | -13571.172043 | NULL / UNRESOLVED |
| 2026-05 | 7887 | 7494 | 389800.9526881709 | 324648.533333 | -65152.419355 | -13339.925807 | NULL / UNRESOLVED |

例如 2026-03：`248869.299562 - 578406.3064516085 = -329537.0068896085`，输出按 DECIMAL 汇总显示为 `-329537.006890`。此前的 `-30594.746111` 仍存在，但它只作为 `candidate_row_amount_diff_total` 诊断值，不再作为整月 known diff。

## 状态分母

`EXCEL_DETAIL` 与 `PLATFORM_FACT` 是两个独立 record_side：

| 月份 | Excel 侧分母 rows / IMSI | PLATFORM_ONLY rows / IMSI |
|---|---:|---:|
| 2026-03 | 13082 / 12763 | 3272 / 3145 |
| 2026-04 | 7780 / 7317 | 15218 / 8780 |
| 2026-05 | 7887 / 7494 | 14697 / 8633 |

Excel 侧状态的 row_count 按官方 detail invoice row 分组；distinct_imsi_count 是该状态内的 distinct IMSI。状态内 distinct IMSI 可能重叠，因此不能把各状态 distinct IMSI 相加。PLATFORM_ONLY 使用 scoped platform fact 独立分母，不与 Excel rows/IMSI 相加。

## SQL 一致性

已修订的月度 SQL 输出：

- `platform_calculated_amount_known_total`
- `known_amount_diff`
- `candidate_row_amount_diff_total`
- `candidate_row_amount_abs_diff_total`
- `platform_total`
- `platform_total_status`

修订 SQL 已通过本地只读文本门禁，并在 simo_cdc 成功执行：3 rows / 34 columns。状态 SQL 也通过只读门禁并成功执行：16 rows / 18 columns；其 `record_side` 已将 Excel 侧与 PLATFORM_ONLY 分开。