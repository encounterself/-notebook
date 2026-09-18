# Batch A 审查硬门槛摘要（只读 live evidence）

本文件是批次 A 的补充审查摘要，范围为 2025-09、2025-10、2025-11。Databricks 证据均由本次 `simo_cdc` profile 通过 `SELECT/WITH` 或 `EXPLAIN` 取得；本地 SQL/TSV/Markdown 仅作可复跑载体，不是平台写入结果。现有参考文件未修改。

## 1. Excel 完整目标与来源去重

逻辑 Excel 来源分层如下：

- 主目标：`simo_prod.mysql_cdc_sync.wa_invoice_detail`，以 `final_start_date` 落入账单月确定月份。目标字段是 `final_start_date/final_end_date/final_days/monthly_rate/final_charge/charge_type`，平台只用于解释/复现。
- 辅助 Credit：`simo_prod.mysql_cdc_sync.wa_invoice_credit`。本批次按 source_file 映射后 0 行，不能用它补主目标；若后续有行，`credit_owed` 的负号原样保留。
- 辅助 prorated：`simo_prod.mysql_cdc_sync.wa_invoice_prorated`。只用于重叠审计，不与 detail 直接 UNION；重叠说明其不能再次计入完整 Excel 目标。
- detail 去重审计粒度：`(billing_month, imsi, charge_type)`；三个月重复行均为 0。prorated 的辅助审计粒度为 `(billing_month, imsi)`，本批次没有被并入 detail。

可重算结果（`42_excel_source_completeness.tsv`）：

| 月份 | detail 行数 / 卡数 / Excel amount | detail 重复行 | credit 行数 / 卡数 / amount | prorated 行数 / 卡数 / amount | prorated 与 detail 重叠 |
|---|---:|---:|---:|---:|---:|
| 2025-09 | 25,237 / 14,793 / 1,139,393.5247 | 0 | 0 / 0 / 0 | 36 / 36 / 1,521.0667 | 36 行 / 36 卡 |
| 2025-10 | 12,677 / 12,675 / 772,750.5333 | 0 | 0 / 0 / 0 | 5 / 5 / 294.0000 | 5 行 / 5 卡 |
| 2025-11 | 12,663 / 12,641 / 773,737.8387 | 0 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 |

Excel 自身公式验证（`38_excel_formula_validation.tsv`）：Full Cycle：Sep 12,602/12,602、Oct 12,573/12,573、Nov 12,641/12,641 exact；Sep Partial 0/11,484 exact，Sep Prorated-in 1,085/1,085，Sep Prorated-out 66/66；Oct New Activation 70/72；Nov New Activation 0/22。异常保留为 Excel 自身待解释项，没有让平台规则覆盖 Excel 真实目标。

来源文件映射已由 live probe 确认：Sep 为 `006-V2 - SIMO Data Purchase Invoice Details - SEP 2025.xlsx`；Oct 为 `01-INVOICE_FROM_ WA_USD_772,765.00_SIMO Data Purchase Invoice Details - OCT 2025.xlsx`；Nov 为 `01-1-INVOICE_FROM_ WA_USD_773,793.84_SIMO Data Purchase Invoice Details - OCT 2025.xlsx`。月份按 `final_start_date` 与 live 结果确认，不按文件名猜测。

## 2. 平台 Wing Alpha 集合与 PLATFORM_ONLY

平台月集合先限定 `tc_cdr.sim_status_for_sftp_bak` 的目标 `year/month` 分区，再以 `product_id` 连接 `ods.resource_res_vsim_product`，只保留 `supplier_id=2275`，最后按 `imsi` 聚合。没有把全量 snapshot、全量 status_log、全量 cycle_history UNION 成卡集合。

| 月份 | scoped snapshot distinct rows（imsi/product/date 去重） | Wing Alpha 卡数 | product_id 数 | observed price 数 | PLATFORM_ONLY | 排除：非 WA supplier | 排除：缺失 product mapping |
|---|---:|---:|---:|---:|---:|---:|---:|
| 2025-09 | — | — | — | — | — | — | — |
| 2025-10 | 400,495 | 13,086 | 68 | 2 | 411 | 41,696 | 22 |
| 2025-11 | 414,865 | 16,860 | 77 | 3 | 4,219 | 41,485 | 106 |

Sep 的原始快照分区在 live 读取时返回 `AccessDeniedException`（已验证多个分区），因此 A 不生成 Sep PLATFORM_ONLY；Sep 的平台卡集合与平台计算金额均为 `MISSING_DATA`。Oct/Nov 每个 PLATFORM_ONLY 的统一来源理由是：目标月 `sim_status_for_sftp_bak` 分区中、映射为 `supplier_id=2275` 的 imsi 不在 Excel detail imsi 中。非 WA supplier 和无 product mapping 均在 supplier scope 之前排除，不计 PLATFORM_ONLY。

正式价格证据保留 platform `product_id/product_name/package_price/create_time/modify_time`；Excel 源没有 product_id，因此 Excel `excel_product_id` 明确为 NULL，不能用 product_name 做正式价格 JOIN，也没有用 MAX/MIN 把多价格压成单价。当前 product 表缺少有效结束时间字段，价格有效期状态仍为 unresolved。

## 3. 卡级 FULL OUTER JOIN、金额和命中率

Sep：Excel 25,237 行、14,793 卡、Excel amount **1,139,393.5247**；platform calculated amount、amount_diff、days/price hit rate 均为 NULL，状态为 `MISSING_DATA_PLATFORM_SNAPSHOT`。这不是已证明的 WA_ONLY 或 PLATFORM_ONLY。

Oct/Nov 汇总如下。金额差定义为 `platform_calculated_amount - Excel amount`；平台金额只在候选 days 与唯一 observed package_price 均存在时计算，不用金额倒推 days。

| 月份 / charge_type | Excel amount | platform calculated amount | amount_diff | days exact / matched | observed price exact / matched | unresolved impact |
|---|---:|---:|---:|---:|---:|---|
| Oct Full Cycle | 769,456.0000 | 747,971.0000 | -21,485.0000 | 12,573/12,573 = 100.00% | 11,449/12,573 = 91.06% | 12,570 行无历史有效期条件；1,121 价格不等、3 多价 |
| Oct New Activation | 2,364.5333 | 2,474.0000 | +109.4667 | 66/72 = 91.67% | 72/72 = 100.00% | 72 行无历史有效期条件；6 日不匹配 |
| Oct Prorated-out | 930.0000 | 875.7097 | -54.2903 | 21/32 = 65.63% | 31/32 = 96.88% | 32 行无历史有效期条件；11 日不匹配 |
| Oct MATCHED total | **772,750.5333** | **751,320.7097** | **-21,429.8236** | — | — | 12,677 matched lines；平台历史价格有效期未证明 |
| Nov Full Cycle | 773,292.0000 | 747,694.0000 | -25,598.0000 | 12,641/12,641 = 100.00% | 11,296/12,641 = 89.36% | 12,640 行无历史有效期条件；1,344 价格不等、1 多价 |
| Nov New Activation | 445.8387 | 520.2997 | +74.4610 | 0/22 exact；10 日不匹配，12 invalid window | 20/22 = 90.91% | 22 行无历史有效期条件；12 行无效日期窗口 |
| Nov MATCHED total | **773,737.8387** | **748,214.2997** | **-25,523.5390** | — | — | 12,663 matched lines；平台历史价格有效期未证明 |

Oct FULL OUTER JOIN：MATCHED 12,677 行/12,675 卡，PLATFORM_ONLY 411 卡；Nov：MATCHED 12,663 行/12,641 卡，PLATFORM_ONLY 4,219 卡。上述 PLATFORM_ONLY 金额为 0，不与 Excel 金额混算。

## 4. Candidate / Reconciliation SQL 可执行性门槛

以下文件均保留完整 `WITH cfg ...` CTE 链，不是只有未定义的 recon 终端 SELECT：

- Oct full reconciliation：`24_card_reconciliation_oct.sql`；candidate：`30_candidate_billing_oct.sql`。
- Nov full reconciliation：`25_card_reconciliation_nov.sql`；candidate：`31_candidate_billing_nov.sql`。
- Sep evidence-safe candidate：`32_candidate_billing_sep.sql`；Sep missing-data FULL OUTER shell：`33_reconciliation_sep.sql`，以及金额/卡数摘要 `34_reconciliation_summary_sep.sql`。
- 对上述六份完整 SQL 已执行 `EXPLAIN`，结果文件为 `45_explain_24_card_reconciliation_oct.tsv` 至 `50_explain_33_reconciliation_sep.tsv`，均返回成功的 physical plan。

Candidate 终端列实际计算 `platform_calculated_days`、`platform_calculated_price`、`platform_calculated_amount`、`days_difference`、`price_difference`、`amount_difference`；reconciliation 保留 Excel/platform product_id、name、price 数组和 `FULL OUTER JOIN` 状态。Sep 终端显式返回平台字段 NULL 与 `MISSING_DATA_PLATFORM_SNAPSHOT`，没有把不可读平台误标为通过。

## 5. 未解决影响与状态

- Sep 平台快照：14,793 Excel 卡、1,139,393.5247 Excel amount 受影响；缺失字段/数据源为可读的 `sim_status_for_sftp_bak` Sep 分区；下一步是取得同一 profile 的只读授权或 approved snapshot view。
- Oct/Nov 平台价格有效期：所有 matched 行（25,340 行，Excel amount 1,546,488.3720）只有当前 product package_price 和 create/modify 字段，没有 valid_to/历史版本条件；不能证明 billing_month 生效价。
- Oct：17 卡日误差（含 6 New Activation、11 Prorated-out），价格 observed mismatch 1,122 卡/约 69,516 Excel amount，另 3 卡多价。
- Nov：10 卡日误差、12 卡 invalid date window（约 291.58 Excel amount），价格 observed mismatch 1,344 卡/约 83,328 Excel amount，另 1 卡多价。
- Excel source 没有 product_id；这是 `MISSING_MAPPING`，不是用 product_name 替代 join 的理由。需要上游产品 ID 或按月有效产品版本才能完成正式价格证明。

门槛结论：A 的 Excel 自身目标、supplier scope、排除理由、计算字段和 SQL 可执行性已补齐；Sep 平台事实和 Oct/Nov 历史价格有效期仍是明确 `MISSING_DATA/UNRESOLVED`，本批次没有标为完全通过，也没有补差 CASE。

## 6. 相关独立文件

- [42_excel_source_completeness.sql](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/A/42_excel_source_completeness.sql) / `.tsv`
- [43_platform_scope_and_exclusions.sql](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/A/43_platform_scope_and_exclusions.sql) / `.tsv`
- [A_reconciliation_report.md](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/A/A_reconciliation_report.md)
- [A6_local_reference_inventory.md](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/A/A6_local_reference_inventory.md)