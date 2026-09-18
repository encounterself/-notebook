# Batch C 审查硬门槛补充摘要（v3，snapshot-anchored）

范围：2026-03、2026-04、2026-05。此文件补充并限制旧 C 报告的使用边界：旧 v2 的 `platform_keys` 曾把 cycle_history 卡并入平台键，因此旧 v2 的 PLATFORM_ONLY 数字不作为本硬门槛最终证据。新增 v3 只在 C 独立目录中生成，未修改旧文件。

## 1. Excel 完整目标、来源与去重

- 主 Excel 目标：`simo_prod.mysql_cdc_sync.wa_invoice_detail`，按已确认 source_file 取 2026-03/04/05，目标字段为 `final_start_date/final_end_date/final_days/monthly_rate/final_charge/charge_type`。
- Credit：本批次 `wa_invoice_credit` 0 行；detail 内的 Credit charge_type 仍保留负数。
- prorated/pending：`simo_prod.mysql_cdc_sync.wa_invoice_prorated` 单独按 `(billing_month, imsi)` 审计，不与 detail 直接 UNION；因为该表没有可靠的 detail `final_days` 字段，candidate 标为 `PENDING_MISSING_FINAL_DAYS`。
- detail 审计粒度为 `(billing_month, imsi, charge_type)`；prorated 辅助粒度为 `(billing_month, imsi)`，每月只附着一次。

`12_excel_source_audit.tsv` 的 live 可重算结果：

| 月份 | detail 行 / 卡 / amount | credit 表行 / amount | prorated 行 / 卡 / usage amount | 完整 Excel target amount |
|---|---:|---:|---:|---:|
| 2026-03 | 13,082 / 12,763 / 578,406.306452 | 0 / 0 | 127 / 127 / 3,686.928571 | 582,093.235023 |
| 2026-04 | 7,780 / 7,317 / 372,289.307527 | 0 / 0 | 284 / 284 / 9,827.387097 | 382,116.694624 |
| 2026-05 | 7,887 / 7,494 / 389,800.952688 | 0 / -51.6（detail Credit） | 9 / 9 / 298.766667 | 390,099.719355 |

Excel 公式验证使用 `08_excel_formula_validation.tsv`：Full Cycle 月价公式在 Mar 6,164/6,164、Apr 7,025/7,025、May 7,251/7,251 成立；New Activation、replacement、Simbank 等保留各自的日期/金额异常，不让平台金额反推 days。

## 2. supplier_id=2275 平台集合与排除

新 `18_platform_scope_gate.sql` 先读取 `sim_status_for_sftp_bak` 的目标 `year/month` 分区，再按 `product_id` 连接 `resource_res_vsim_product`，只保留 `supplier_id=2275`，最后按 imsi 形成月卡集合。cycle_history/status_log 只补充已进入快照集合的卡，不能产生 PLATFORM_ONLY。

| 月份 | scoped card-product rows | Wing Alpha 卡数 | product_id 数 | observed price 数 | PLATFORM_ONLY | 排除：非 WA supplier | 排除：缺失 mapping |
|---|---:|---:|---:|---:|---:|---:|---:|
| 2026-03 | 16,616 | 15,537 | 86 | 4 | 2,774 | 38,620 | 2 |
| 2026-04 | 18,058 | 16,002 | 97 | 4 | 8,685 | 38,830 | 0 |
| 2026-05 | 16,677 | 16,086 | 99 | 4 | 8,592 | 39,088 | 0 |

每个 PLATFORM_ONLY 的来源理由固定为“目标月 `sim_status_for_sftp_bak` 分区中、product_id 映射为 `supplier_id=2275` 的 imsi 不在 Excel detail/pending 月卡集合”；非 WA supplier 与缺失 product mapping 在进入平台卡集合前排除，不能被计成 PLATFORM_ONLY。

价格正式关联只使用 `product_id + supplier_id + target month`；`product_name` 仅保留为审计字段。当前 `resource_res_vsim_product` 没有 valid_to 历史有效区间，因此 `PRODUCT_ID_TARGET_MONTH_CURRENT_DIMENSION_NO_VALID_TO` 仍是 unresolved。多价格只有在 distinct count = 1 时才取单价；没有用 MAX/MIN 掩盖多价格。

## 3. v3 FULL OUTER JOIN 与金额/命中率

`13_reconciliation_v3.sql` 是完整 CTE 的 `FULL OUTER JOIN`；平台侧只来自目标月 supplier-scoped snapshot 卡。当前 v3 的月级 MATCHED/PLATFORM_ONLY：

| 月份 | MATCHED 卡 / Excel amount | PLATFORM_ONLY 卡 | WA_ONLY 卡 | platform calculated amount | amount_diff |
|---|---:|---:|---:|---:|---:|
| 2026-03 | 12,763 / 582,093.235041 | 2,774 | 0 | 517,345.645047 | +36,480.387212 |
| 2026-04 | 7,317 / 382,116.694586 | 8,685 | 0 | 372,290.333351 | -7,328.359157 |
| 2026-05 | 7,494 / 390,099.719327 | 8,592 | 0 | 367,845.677411 | +8,567.262374 |

`platform calculated amount` 只统计候选 days 与唯一 platform price 均可计算的卡；未计算的 Excel 金额在 unresolved impact 中单独列出。`amount_diff` 为 platform calculated amount 与 Excel amount 的差，未加任何补差 CASE。

| 月份 | days exact / evaluable | price exact / evaluable | amount exact / evaluable | 未解决影响（卡数 / Excel amount） |
|---|---:|---:|---:|---|
| 2026-03 | 10,819/12,937 = 83.63% | 10,897/12,232 = 89.08% | 9,387/12,191 = 76.99% | missing price 746 / 22,048.000000；missing day 137 / 2,702.774194；pending no final_days 127 / 3,686.928576 |
| 2026-04 | 7,043/7,780 = 90.53% | 6,902/7,608 = 90.72% | 6,191/7,608 = 81.38% | missing price 172 / 7,327.333333；pending no final_days 284 / 9,827.387089 |
| 2026-05 | 7,283/7,493 = 97.20% | 7,187/7,887 = 91.12% | 6,583/7,493 = 87.85% | missing day 392 / 13,439.612903；pending no final_days 9 / 298.766665 |

残差状态（platform amount 已可计算但不 exact）的卡数 / Excel amount / amount_diff：Mar 2,804 / 117,754.806452 / +36,480.387185；Apr 1,417 / 60,053.174194 / -7,328.359166；May 910 / 47,780.133333 / +8,567.262362。replacement、Simbank、New Activation 没有被金额倒推 days。

## 4. 完整 SQL / CTE 可执行性门槛

以下新增 v3 文件均包含完整 `WITH` 链：

- Candidate：`13_candidate_billing_v3.sql`，摘要 `13_candidate_billing_v3_summary.sql`。
- Reconciliation：`13_reconciliation_v3.sql`，摘要 `13_reconciliation_v3_summary.sql`。
- Candidate 终端实际计算 `platform_calculated_days`、`platform_calculated_price`、`platform_calculated_amount`、days/price 差异和 `platform_amount_diff`；reconciliation 终端保留 Excel/platform product_id/name/price 字段与 FULL OUTER 状态，月度 platform calculated amount 与 amount_diff 由同一 v3 candidate summary 的可计算行聚合给出。
- 修正 join 顺序后，完整 candidate 的只读 `EXPLAIN` 成功（`19_explain_13_candidate_billing_v3.tsv`），完整 reconciliation 的只读 `EXPLAIN` 成功（`20_explain_13_reconciliation_v3.tsv`）；两个 v3 summary 也由当前 `simo_cdc` live `SELECT/WITH` 成功返回（35 行、15 行）。

因此 C 旧 v2 不能作为本硬门槛通过；新增 v3 才是 snapshot-anchored 的可审查候选版本。现阶段 C 仍不能标记为业务规则完全通过，因为大量价格有效期、生命周期事件和 replacement/Simbank 规则 unresolved。

## 5. 未解决问题

- 月度 product 价格有效期：平台当前表缺少 valid_to/历史生效区间；需要按 billing_month 的 product version 或 approved history view。
- 2026-03 New Activation、replacement、Simbank：平台生命周期字段、时区和业务起算规则尚未足以解释全部 card-level residuals。
- pending-prorated：`wa_invoice_prorated` 没有可证明的 final_days；需要业务定义 pending 的归属月和 days 计算。
- 换卡/核心日志：之前的只读访问探针被权限拒绝；不能编造 replacement/transfer 规则。

这些问题已在 v3 中保留为 `MISSING_DATA`/`UNRESOLVED`，没有用总额接近或补差 CASE 伪造通过。

## 6. 仅参考本地文件

C 目录已有的 `C_batch_report.md`、`C_batch_report_v2.md`、`06_*`、`10_*_v2`、`12_excel_source_audit.*`、`08_excel_formula_validation.*` 只用于了解结构和复核历史 live 查询；旧 v2 的广域/周期历史平台集合不作为本摘要的最终平台集合。新增独立证据为：

- [13_candidate_billing_v3.sql](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/13_candidate_billing_v3.sql)
- [13_reconciliation_v3.sql](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/13_reconciliation_v3.sql)
- [18_platform_scope_gate.sql](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/18_platform_scope_gate.sql)
- [C_hard_gate_summary.md](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/C_hard_gate_summary.md)