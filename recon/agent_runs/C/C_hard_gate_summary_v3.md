# WA SIM 月度账单独立对账批次 C：硬门槛摘要 v3

范围：2026-03、2026-04、2026-05。本文是新增审查门槛后的独立补充报告，并 supersede `C_batch_report_v2.md` 中未应用 supplier_id=2275 的平台人口/匹配数字；最终证据只使用本次 `simo_cdc` 连接的只读 `SELECT/WITH/EXPLAIN` 查询。所有平台表均为 `simo_prod.<schema>.<table>` 全限定名。未执行任何 Databricks 写操作。

## 1. 门槛结论

| 审查项 | 结果 | 证据 |
|---|---|---|
| Excel detail/credit/prorated 来源、行数、卡数、金额、去重 | 已补齐 | [12_excel_source_audit_v2.sql](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/12_excel_source_audit_v2.sql)、[12_excel_source_audit_v2.tsv](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/12_excel_source_audit_v2.tsv) |
| Wing Alpha supplier scope | 已补齐；正式过滤为 `CAST(resource_res_vsim_product.supplier_id AS BIGINT)=2275` | [11_supplier_schema_probe.tsv](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/11_supplier_schema_probe.tsv)、[09_scoped_platform_population.tsv](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/09_scoped_platform_population.tsv) |
| Candidate SQL CTE 完整性 | 已通过；EXPLAIN 与完整逐卡执行成功 | [10_candidate_billing_v2_explain.tsv](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/10_candidate_billing_v2_explain.tsv)、[10_candidate_billing_v2_full.tsv](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/10_candidate_billing_v2_full.tsv) |
| Reconciliation SQL CTE 完整性 | SQL EXPLAIN 与完整 CTE smoke/count 成功；全量明细未导出是 wrapper 25MB 内联传输限制，不是 SQL 缺失 | [10_reconciliation_v2_explain.tsv](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/10_reconciliation_v2_explain.tsv)、[10_reconciliation_v2_smoke.tsv](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/10_reconciliation_v2_smoke.tsv) |
| Excel amount / platform calculated amount / amount_diff / 命中率 / unresolved impact | 已补齐，按月、按 charge_type | [10_candidate_billing_v2_quality_summary.tsv](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/10_candidate_billing_v2_quality_summary.tsv) |

所有最新 SQL 均经过本地只读门禁：首词为 `WITH` 或 `EXPLAIN`，无写操作关键字、无多语句分号、无字面量 `` `n `` 残留。

## 2. Excel 逻辑来源、去重与可重算金额

逻辑 Excel 来源与平台来源严格分开：

- Excel detail：`simo_prod.mysql_cdc_sync.wa_invoice_detail`，按 source_file 映射实际 MAR/APR/MAY 文件。
- Excel credit：`simo_prod.mysql_cdc_sync.wa_invoice_credit`，作为 credit 交叉核验源；目标三个月均为 0 行，因此不与 detail 再相加。
- Excel prorated：`simo_prod.mysql_cdc_sync.wa_invoice_prorated`，作为 pending/prorated 逻辑源，按 `(billing_month, imsi)` 去重后只附加一次。
- detail 的 canonical 去重粒度是 `(billing_month, imsi, charge_type)`；保留原始行数，并对同一卡同 charge_type 的冲突金额做可审计聚合。当前三个月 `detail_raw_rows = detail_canonical_rows`，没有发现该复合键重复。
- detail 中的 Credit 负数直接保留；不使用 `wa_invoice_credit` 的空表推导或金额倒推。
- prorated 不与 detail 行 UNION 成第二张账单；先按 `(billing_month, imsi)` 聚合，再按 IMSI 附加 `final_charge_for_usage_days`。`pending_charge` 单独保留，不作为目标合计替代值。

| 月份 | detail 原始行 / distinct IMSI | detail canonical 行 / canonical IMSI | detail 金额 | detail Credit 卡 / 金额 | credit 表行 / 卡 | prorated 原始行 / 去重卡 | prorated usage 金额 | pending_charge 金额 | 完整 Excel 目标金额 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 2026-03 | 13,082 / 12,763 | 13,082 / 12,763 | 578,406.306452 | 8 / -170.500000 | 0 / 0 | 127 / 127 | 3,686.928571 | 1,065.168571 | 582,093.235023 |
| 2026-04 | 7,780 / 7,317 | 7,780 / 7,317 | 372,289.307527 | 0 / 0.000000 | 0 / 0 | 284 / 284 | 9,827.387097 | 2,191.067097 | 382,116.694624 |
| 2026-05 | 7,887 / 7,494 | 7,887 / 7,494 | 389,800.952688 | 2 / -51.600000 | 0 / 0 | 9 / 9 | 298.766667 | 41.526667 | 390,099.719355 |

重算公式：

`full_excel_target_amount = SUM(detail canonical final_charge) + SUM(prorated canonical final_charge_for_usage_days)`。

`pending_charge` 只作为独立审计字段；Credit 保留负数。上述金额来自 live source audit，而不是本地旧 SQL/TSV 推测。

## 3. supplier_id=2275 平台月度集合

`supplier_id` 仅在 `simo_prod.ods.resource_res_vsim_product` 中发现，类型为 `LONG`。正式平台集合执行：

1. 产品维表先过滤 `CAST(supplier_id AS BIGINT) = 2275`。
2. `sim_status_for_sftp_bak` 只取目标月份分区，再按该 product_id scope 连接。
3. `resource_res_vsim_cycle_history` 只取目标月份重叠时间窗口，再按同一 product_id scope 连接，并要求产品 `create_time <= cycle_time`（若可解析）。
4. `status_log` 只连接已经由 status snapshot/cycle history 形成的 `(billing_month, imsi)` platform keys，不独立制造平台卡集合。
5. 正式价格仍按 `product_id + 目标月窗口` 取 `resource_res_vsim_product.package_price`；保留 cycle history 的 `package_price`，但目标数据为 0，未拿它计算金额。没有 valid_to/version，因此价格状态仍是当前维度候选，不是历史生效证明。

| 月份 | supplier 2275 平台卡 | status snapshot 卡 | cycle 卡 | 限定 key 后 status_log 卡 | product_id 映射卡 | 唯一当前 price | 多 price | 缺 price |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 2026-03 | 15,798 | 15,537 | 13,508 | 12,191 | 13,508 | 13,354 | 154 | 2,290 |
| 2026-04 | 16,691 | 16,002 | 14,979 | 11,364 | 14,979 | 14,740 | 239 | 1,712 |
| 2026-05 | 16,660 | 16,086 | 14,599 | 12,223 | 14,599 | 14,533 | 66 | 2,061 |

## 4. PLATFORM_ONLY 来源与排除理由

FULL OUTER JOIN 键为 `(billing_month, imsi)`。每个 `PLATFORM_ONLY` 的统一排除理由是：

`PLATFORM_ONLY_NO_EXACT_EXCEL_IMSI_AFTER_DETAIL_PRORATED_DEDUP`。

也就是该 IMSI 在 supplier 2275 的受限平台集合中存在，但在 Excel detail canonical 集合与 prorated canonical 集合合并后没有同月精确 IMSI 键。它不是由全量 status_log/cycle_history UNION 产生的虚假卡。

| 月份 | PLATFORM_ONLY 来源 | 卡数 | 来源定义 |
|---|---|---:|---|
| 2026-03 | STATUS_SNAPSHOT_ONLY | 1,594 | supplier 2275 目标月 status snapshot 有卡，cycle history 无卡；未匹配 Excel IMSI |
| 2026-03 | STATUS_SNAPSHOT_AND_CYCLE | 1,180 | 两类受限事实均有；未匹配 Excel IMSI |
| 2026-03 | CYCLE_HISTORY_ONLY | 261 | supplier 2275 目标月 cycle window 有卡，status snapshot 无卡；未匹配 Excel IMSI |
| 2026-04 | STATUS_SNAPSHOT_ONLY | 1,708 | 同上 |
| 2026-04 | STATUS_SNAPSHOT_AND_CYCLE | 6,977 | 同上 |
| 2026-04 | CYCLE_HISTORY_ONLY | 689 | 同上 |
| 2026-05 | STATUS_SNAPSHOT_ONLY | 2,061 | 同上 |
| 2026-05 | STATUS_SNAPSHOT_AND_CYCLE | 6,531 | 同上 |
| 2026-05 | CYCLE_HISTORY_ONLY | 574 | 同上 |

因此 PLATFORM_ONLY 合计为：2026-03 `3,035`、2026-04 `9,374`、2026-05 `9,166`。没有 `STATUS_LOG_ONLY`，因为 status_log 被硬性限制为只能连接既有 platform keys。

## 5. Candidate/Reconciliation 可执行性

Candidate SQL：

- [10_candidate_billing_v2.sql](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/10_candidate_billing_v2.sql) 包含完整 CTE：`cfg → product_dim → wa_raw → wa_card → status_scope → cycle_scope_rows → cycle_scope → platform_keys → status_log_scope → platform_fact → scored → calculated → pending_raw`。
- 完整逐卡执行成功，返回 34 列、9,831 行；字段包含 `platform_calculated_days`、`platform_calculated_price`、`platform_calculated_amount`、`excel_minus_platform_days`、`excel_minus_platform_price`、`platform_amount_diff`。
- 审查过程中发现并修复 detail/pending UNION 缺少 `platform_amount_diff` 的列数错误；修复后的 EXPLAIN 和完整执行均成功。

Reconciliation SQL：

- [10_reconciliation_v2.sql](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/10_reconciliation_v2.sql) 包含完整 CTE：`cfg → product_dim → wa_raw → wa_card → status_scope → cycle_scope_rows → cycle_scope → platform_keys → status_log_scope → platform_fact → wa_pending → wa_month → recon`。
- [10_reconciliation_v2_explain.tsv](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/10_reconciliation_v2_explain.tsv) 成功，证明终端 `SELECT` 可解析。
- [10_reconciliation_v2_smoke.tsv](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/10_reconciliation_v2_smoke.tsv) 使用完全相同的 CTE 链执行 `COUNT(*)`，成功返回来源分层。另有同一 CTE 链的 [100 行逐卡预览 SQL](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/10_reconciliation_v2_preview.sql) 与 [预览结果](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/10_reconciliation_v2_preview.tsv)，返回 48 列。全量明细返回超过 DBSQL wrapper 的 25MB 内联上限，因此没有把“全量结果未传回”标成全量导出通过；SQL 本身由 EXPLAIN + 完整 CTE smoke 证明可执行。

## 6. 金额、命中率与 unresolved impact

下表由 live Candidate CTE 逐 charge_type 计算，Credit 不纳入正向 amount 命中率；`unresolved impact` 只包含缺 platform day、缺 platform price、pending 缺 final_days，不把可计算但金额残差混入 unresolved。

| 月份 | Excel detail amount | platform calculated amount | amount_diff | days exact / eval | price exact / eval | amount exact / eval | unresolved 卡数 / Excel impact | residual 卡数 / amount_diff |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 2026-03 | 578,406.306451 | 517,345.645047 | 36,480.387210 | 10,819/12,937 = 83.6284% | 10,897/12,232 = 89.0860% | 9,387/12,191 = 76.9994% | 1,010 / 28,437.702770 | 2,804 / 36,480.387185 |
| 2026-04 | 372,289.307527 | 372,290.333351 | -7,328.359157 | 7,043/7,780 = 90.5270% | 6,902/7,608 = 90.7203% | 6,191/7,608 = 81.3749% | 456 / 17,154.720422 | 1,417 / -7,328.359166 |
| 2026-05 | 389,800.952689 | 367,845.677411 | 8,567.262374 | 7,283/7,493 = 97.1974% | 7,187/7,887 = 91.1246% | 6,583/7,493 = 87.8553% | 401 / 13,738.379568 | 910 / 8,567.262362 |

逐 charge_type 的完整证据见 [10_candidate_billing_v2_quality_summary.tsv](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/10_candidate_billing_v2_quality_summary.tsv)。重点项：

| 月份 / charge_type | Excel amount | platform amount | amount_diff | days 命中 | price 命中 | amount 命中 | unresolved impact |
|---|---:|---:|---:|---:|---:|---:|---:|
| 03 Simbank Transfer | 200,751.290323 | 194,936.483845 | 3,112.032284 | 4,284/4,765 | 4,720/4,797 | 4,265/4,765 | 136 卡 / 2,702.774194 |
| 04 New Activation | 16,597.540860 | 37,217.200026 | -20,722.992499 | 8/706 | 702/702 | 10/702 | 4 卡 / 103.333333 |
| 05 New-card replacement | 13,479.746237 | -287.129029 | 327.262362 | 0/10 | 402/402 | 0/10 | 392 卡 / 13,439.612903 |

金额残差与 unresolved 分开报告；不能用“金额差很大”直接替换 days 规则，也没有添加补差 CASE。

## 7. 未解决影响与下一步

- 2026-03 Simbank：仍有 136 张缺平台日期事件，影响 Excel amount 2,702.774194；下一步需要 supplier 2275 范围内 approved transfer/void/cycle event view。已有可评估卡的 UTC/UTC−5 时区结果仍保留，不能外推到缺事件卡。
- 2026-04/05 New Activation：平台激活事件能提供价格，但日期规则卡级命中率很低；下一步需要确认激活事件业务时区、final_start_date 生成逻辑和月末边界。
- 2026-05 new-card replacement：392 张缺 platform day event，影响 Excel amount 13,439.612903；replacement/core 日志仍需 approved read-only view。
- 当前价格：product_dim 只有当前 package_price，没有 valid_to/version；所有 price exact 只能说明当前候选价与 Excel monthly_rate 一致，不能证明历史生效。
- Pending/prorated：2026-03/04/05 分别 127/284/9 张，Excel usage impact 分别 3,686.928571/9,827.387097/298.766667；源表没有 final_days，因此保留 `PENDING_MISSING_FINAL_DAYS`，不假设平台 days。
- 换卡/核心日志探针 `dm.card_replacement_details`、`dm.change_card_data`、`ods.core_dse_applylog` 仍为 `AccessDeniedException`，标记 `MISSING_DATA`，没有编造 replacement/transfer 规则。

## 8. 仅参考的本地文件

以下文件只用于了解工作区结构、字段线索和 dbx wrapper；其中数字未作为最终证据，也未修改：

- `C:/Users/EDY/Desktop/对账notebook/recon/dbx.ps1`
- `C:/Users/EDY/Desktop/对账notebook/recon/tables.tsv`
- `C:/Users/EDY/Desktop/对账notebook/recon/cols.tsv`
- `C:/Users/EDY/Desktop/对账notebook/recon/c_final.sql`
- `C:/Users/EDY/Desktop/对账notebook/recon/c_zuofei_verify.sql`

本次新增与重算结果仅写入：`C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C`。