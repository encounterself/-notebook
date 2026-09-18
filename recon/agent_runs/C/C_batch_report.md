# 注意：本文件为新增硬约束前的 C v1 报告，已被 C_batch_report_v2.md supersede。请以 [C_batch_report_v2.md](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/C_batch_report_v2.md) 及 10_*_v2 SQL/TSV 为准。`n`n# WA SIM 月度账单独立对账批次 C

范围：2026-03、2026-04、2026-05。所有平台数字均来自本次 `simo_cdc` profile 的只读 `SELECT/WITH` 查询；平台表统一使用 `simo_prod.<schema>.<table>` 全限定名。没有执行任何 Databricks 写操作，也没有修改 `recon` 现有参考文件。

## 0. 来源、映射与只读边界

逻辑来源分为两层：

- Excel 逻辑来源：`simo_prod.mysql_cdc_sync.wa_invoice_detail`；补充 pending-prorated 使用 `simo_prod.mysql_cdc_sync.wa_invoice_prorated`。本批次按 live source_file 精确映射：MAR/ APR/ MAY 2026 文件分别对应 2026-03/04/05。
- 平台逻辑来源：`simo_prod.tc_cdr.sim_status_for_sftp_bak`、`simo_prod.ods.resource_res_vsim_cycle_history`、`simo_prod.ods.resource_res_vsim_status_log`、`simo_prod.ods.resource_res_vsim_product`。carrier 也做过可用性探针；换卡/核心日志做过只读访问探针但被权限拒绝。

`recon/dbx.ps1` 内部使用 `databricks auth token -p simo_cdc`、固定 SQL Warehouse，并将结果以 INLINE JSON 拉回本地；本批次没有给它传不存在的 profile 参数。每次执行前都对实际 SQL 文本做了首 token、禁写关键字和分号检查。

## C1. 每月事实统计

### 月度总览

| 月份 | WA detail 行数 | WA detail IMSI | pending 行数/IMSI | detail 金额 | pending final_charge_for_usage_days | WA 合计（detail+pending） |
|---|---:|---:|---:|---:|---:|---:|
| 2026-03 | 13,082 | 12,763 | 127 / 127 | 578,406.306470 | 3,686.928571 | 582,093.235041 |
| 2026-04 | 7,780 | 7,317 | 284 / 284 | 372,289.307489 | 9,827.387097 | 382,116.694586 |
| 2026-05 | 7,887 | 7,494 | 9 / 9 | 389,800.952660 | 298.766667 | 390,099.719327 |

金额保留 Excel 原始负数；Credit 没有被改成正数。月度合计只是逐项加总，不含任何为接近 0 而添加的补差 CASE。 月度总览金额来自 reconciliation 侧直接聚合；charge_type 表按组先 round 到 6 位，逐组相加可能出现约 0.00002 的展示舍入差。

### charge_type 事实

| 月份 | charge_type | 卡数 | WA amount | Excel price 值 | 事实备注 |
|---|---|---:|---:|---|---|
| 03 | Credit for Offstocked Card | 8 | -170.500000 | 62 | Credit，负数保留 |
| 03 | Full Cycle Charge | 6,164 | 324,001.000000 | 21/32/43/62 | `final_days=31` |
| 03 | Full Cycle Charge - Backbilled for FEB Invoice | 269 | 12,371.000000 | 21/43/62 | FEB backbill，日期跨度 28 日 |
| 03 | New Activation: Prorated-in Charge | 1,229 | 33,640.677419 | 43/62 | 新激活 |
| 03 | Offstocked before cycle start | 1 | NULL | 62 | 无可用金额/日期 |
| 03 | Partial Charge - Card Replaced Mid Cycle | 496 | 7,327.741935 | 43/62 | 旧卡换卡 |
| 03 | Prorated Out - Transferred to Wing's Simbank | 4,901 | 200,751.290323 | 43/62 | 4,881 行带 Simbank 标记 |
| 03 | Prorated-out Charge - Offstocked Card | 14 | 485.096774 | 43/62 | offstock |
| 04 | Full Cycle Charge | 7,025 | 355,210.000000 | 21/32/43/62 | `final_days` 30/31 |
| 04 | New Activation: Prorated-in Charge | 706 | 16,597.540860 | 43/62 | 新激活 |
| 04 | Partial Charge - Card Replaced Mid Cycle | 49 | 481.766667 | 43/62 | 旧卡换卡 |
| 05 | Credit for Offstocked Card | 2 | -51.600000 | 43 | Credit，负数保留 |
| 05 | Full Cycle Charge | 7,251 | 371,255.000000 | 21/32/43/62 | `final_days=31` |
| 05 | New Activation: Prorated-in Charge | 200 | 4,340.000000 | 62 | 新激活 |
| 05 | Partial Charge - Card Replaced Mid Cycle | 30 | 665.806452 | 43 | 旧卡换卡 |
| 05 | Partial Charge - New Card Used as Replacement Mid Cycle | 402 | 13,479.746237 | 43/62 | 新卡换卡 |
| 05 | Prorated-out Charge - Offstocked Card | 2 | 112.000000 | 62 | offstock |

### pending-prorated 独立事实

| 账单月 | sheet | 行/IMSI | monthly_rate | original_charge | final_charge_for_usage_days | pending_charge | final_start 日期数 / final_end 日期数 |
|---|---|---:|---|---:|---:|---:|---:|
| 03 | Prorated-In FEB - Pending Charg | 127 / 127 | 43/62 | 2,621.760000 | 3,686.928571 | 1,065.168571 | 9 / 7 |
| 04 | Prorated-In MAR - Pending Charg | 284 / 284 | 43/62 | 7,636.320000 | 9,827.387097 | 2,191.067097 | 6 / 13 |
| 05 | Prorated-In APR - Pending Charg | 9 / 9 | 43/62 | 257.240000 | 298.766667 | 41.526667 | 2 / 5 |

`wa_invoice_prorated` 没有 `final_days` 字段，因此 pending 不被强行并入任何 detail charge_type，也不产出已证明的 days 规则；candidate SQL 将其标为 `PENDING_NO_FINAL_DAYS / MISSING_DATA`。

## C2. 日期规则、单价与卡级验证

### 验证原则

- `Full Cycle Charge` 候选：账单月自然日数；金额按逐卡 Excel monthly_rate 验证为月价，不按 days 再折算。
- `Backbilled` 候选：保留 Excel final_start/final_end 日期跨度作为日期事实，金额候选仍按 monthly_rate 月价验证。
- 其他非 Credit detail：候选 days 为 `DATEDIFF(final_end, final_start)+1`，金额候选仅在平台 `resource_res_vsim_product.package_price` 有唯一/精确价格证据时计算；不使用金额倒推 days。
- Credit：保留负数，不做金额倒推。
- 平台价格证据用 `resource_res_vsim_product.package_price` 的 distinct 值；live 探针得到 `{21,32,43,62}`。`monthly_rent` 另有值 `6`，没有被用来掩盖多价格。

### 逐 charge_type 规则结果

`WA exact` 是 Excel 卡级 candidate days 与 WA 原始 final_days 的 exact match；`platform date exact` 是对应平台候选日期规则的卡级 exact match，分母是该规则可评估卡；`price exact` 是平台 package_price 与 Excel monthly_rate 的 exact match；`amount exact` 仅在 candidate amount 可计算时验证。

| 月份 / charge_type | WA exact | day error +1 / >=2 | 平台日期候选 exact | price exact | amount exact | 结论 |
|---|---:|---:|---:|---:|---:|---|
| 03 Credit | 7/8 = 87.5000% | 0 / 1 | final_start→void−1: 0/8 | 8/8 | 不倒推 | `CREDIT_SIGN_PRESERVED` |
| 03 Full Cycle | 6,164/6,164 = 100% | 0 / 0 | cycle→月末 1,064/6,164 = 17.2615% | 4,910/6,164 = 79.6561% | 6,164/6,164 | WA full-month 与金额成立；平台周期规则未成立 |
| 03 FEB Backbilled | 269/269 = 100% | 0 / 0 | cycle→月末 0/269 | 269/269 | 269/269 | 月价候选成立；平台周期证据不足 |
| 03 New Activation | 1,056/1,229 = 85.9235% | 18 / 155 | activation→月末 11/1,229 = 0.8950%；cycle→月末 8/1,229 = 0.6509% | 1,229/1,229 | 988/1,229 = 80.3906% | `UNRESOLVED` |
| 03 old replacement | 489/496 = 98.5887% | 1 / 6 | final_start→void−1 91/496 = 18.3468% | 496/496 | 489/496 | `UNRESOLVED`，缺少可读换卡日志 |
| 03 Simbank transfer | 4,478/4,901 = 91.3691% | 128 / 295 | cycle→月末 3,103/4,901 = 63.3136%；final_start→void−1 236/495 = 47.6768% | 4,804/4,901 = 98.0208% | 4,478/4,901 | `UNRESOLVED`，不能用金额差解释 days |
| 03 offstock out | 14/14 = 100% | 0 / 0 | final_start→void−1 0/14 | 14/14 | 14/14 | WA 日期跨度成立，平台 void 规则不成立 |
| 04 Full Cycle | 7,011/7,025 = 99.8007% full-month | 14 / 0 | cycle→月末 1,039/7,025 = 14.7900% | 6,325/7,025 = 90.0356% | 7,025/7,025 | 金额为月价；平台周期规则未成立 |
| 04 New Activation | 674/706 = 95.4674% | 10 / 22 | cycle→月末 27/706 = 3.8244% | 706/706 | 236/706 = 33.4278% | `UNRESOLVED` |
| 04 old replacement | 46/49 = 93.8776% | 1 / 2 | final_start→void−1 24/49 = 48.9796% | 43/49 = 87.7551% | 46/49 | `UNRESOLVED` |
| 05 Credit | 2/2 = 100% | 0 / 0 | final_start→void−1 0/2 | 2/2 | 不倒推 | `CREDIT_SIGN_PRESERVED` |
| 05 Full Cycle | 7,251/7,251 = 100% | 0 / 0 | cycle→月末 1,094/7,251 = 15.0876% | 6,551/7,251 = 90.3462% | 7,251/7,251 | 金额为月价；平台周期规则未成立 |
| 05 New Activation | 200/200 = 100% | 0 / 0 | activation/cycle 均 0/200 | 200/200 | 0/200 | WA 日期跨度与金额公式不一致，`UNRESOLVED` |
| 05 old replacement | 30/30 = 100% | 0 / 0 | final_start→void−1 30/30 | 30/30 | 30/30 | 仅这一类的平台 void 候选在本批次成立 |
| 05 new-card replacement | 390/402 = 97.0149% | 5 / 7 | cycle→月末 7/402 = 1.7413% | 402/402 | 200/402 = 49.7512% | `UNRESOLVED` |
| 05 offstock out | 2/2 = 100% | 0 / 0 | cycle→月末 2/2；final_start→void−1 2/2 | 2/2 | 2/2 | 小样本成立，仍需业务确认 |

结论：没有任何需要“补差 CASE”才能成立的规则。尤其 2026-03 Simbank 的平台候选规则只有 63.3136%（cycle→月末）或 47.6768%（void 候选可评估子集）exact，不能将金额差直接归因于某个 days 规则。

## C3. Excel 与平台逐卡 reconciliation

reconciliation 使用 `(billing_month, imsi)` FULL OUTER JOIN：

- Excel 侧：detail 与 pending 先按月/卡聚合，再与平台事实连接。
- 平台侧：`sim_status_for_sftp_bak`、cycle history、status log 的月内/跨月覆盖事实分别保留；生命周期的第一激活、第一作废、cycle/next_cycle、产品和价格集合都保留为审计字段。
- `PLATFORM_ONLY` 是 `ALL_VISIBLE_PLATFORM` 的广域集合，不是已证明的 WA-only/WA discrepancy；产品范围状态另外输出 `WA_NAMED`、`PI_NAMED`、`MULTIPLE_PRODUCT_SCOPE`、`UNCLASSIFIED`、`MISSING_MAPPING`。

### FULL OUTER JOIN 总览

| 月份 | MATCHED 卡数 / WA amount | WA_ONLY | PLATFORM_ONLY | status 快照覆盖 / cycle 覆盖 / status log 覆盖 |
|---|---:|---:|---:|---|
| 03 | 12,763 / 582,093.235041 | 0 | 45,023 | 12,763 / 12,763 / 11,101 |
| 04 | 7,317 / 382,116.694586 | 0 | 52,319 | 7,317 / 7,317 / 5,692 |
| 05 | 7,494 / 390,099.719327 | 0 | 49,403 | 7,494 / 7,494 / 6,231 |

### PLATFORM_ONLY 范围分解

| 月份 | WA_NAMED | PI_NAMED | MULTIPLE_PRODUCT_SCOPE | UNCLASSIFIED | MISSING_MAPPING | 合计 |
|---|---:|---:|---:|---:|---:|---:|
| 03 | 2,237 | 725 | 64 | 31,581 | 10,416 | 45,023 |
| 04 | 1,545 | 6,024 | 534 | 32,628 | 11,588 | 52,319 |
| 05 | 645 | 7,066 | 66 | 31,577 | 10,049 | 49,403 |

重要范围结论：当前广域平台集合中 WA 侧没有 WA_ONLY，但 `PLATFORM_ONLY` 大量是 PI 或未分类平台卡，不能计为 WA 账单漏计。2026-03 的 MATCHED 中有 4,782 张卡落在 `PI_NAMED`（另有 150 张多产品范围），这是产品范围/映射异常，不是可以直接用日期规则解释的金额差。

逐卡结果的完整可复跑 SQL：`06_reconciliation.sql`。当前 wrapper 对超大 INLINE 结果会限制返回行数，因此本地保存的是完整 SQL 和完整摘要；卡级异常清单来自完整 4,291 行 live SELECT 结果：`05_exception_cards.tsv`。

## C4. candidate billing SQL 与 reconciliation SQL

- [06_candidate_billing.sql](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/06_candidate_billing.sql)：detail/pending 分层、逐卡 candidate days、price distinct evidence、multiple-price 状态、candidate amount 和 `CREDIT_SIGN_PRESERVED`。
- [06_candidate_billing_summary.sql](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/06_candidate_billing_summary.sql)：候选 SQL 的 live 摘要；31 行返回成功。
- [06_reconciliation.sql](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/06_reconciliation.sql)：Excel 与平台 FULL OUTER JOIN 明细，保留平台来源字段及产品范围状态。
- [06_reconciliation_summary.sql](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/06_reconciliation_summary.sql)：reconciliation live 摘要；22 行返回成功。

相关 live 结果：

- [05_selected_validation_summary.tsv](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/05_selected_validation_summary.tsv)
- [05_pending_validation.tsv](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/05_pending_validation.tsv)
- [05_exception_summary.tsv](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/05_exception_summary.tsv)
- [05_exception_cards.tsv](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/05_exception_cards.tsv)
- [06_candidate_billing_summary.tsv](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/06_candidate_billing_summary.tsv)
- [06_reconciliation_summary.tsv](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/06_reconciliation_summary.tsv)

## C5. 未解决问题清单

| 问题 | 卡数 | WA amount 影响 | 缺失字段/数据源 | 当前证据 | 下一步 |
|---|---:|---:|---|---|---|
| 03 Simbank day mismatch | 423 | 13,451.096774 | transfer/void 的可信业务日期映射 | WA final span 4,478/4,901；平台 cycle→月末 63.3136% | 取得可读的 transfer/Simbank 事件日志，按事件发生时间核验 |
| 03 Simbank price/mapping unresolved | 69 保守 missing mapping；另 246 多价格 | 1,542.645161（missing mapping 子集） | product_id→WA 产品/单价的唯一映射 | platform package exact 4,804/4,901，但多价格不能压成单值 | 提供按卡、按计费月的有效产品版本或确认业务优先级 |
| 03 New Activation | 173 day mismatch；68 amount mismatch | day 子集 5,127.558756；amount 子集 1,435.892857 | 激活事件有效时间、时区/计费起算定义 | WA span 85.9235%；平台 activation exact 0.8950% | 确认 final_start_date 是否业务激活日及 timezone |
| 04 New Activation | 32 day mismatch；438 amount mismatch | day 子集 900.818280；amount 子集 8,903.322581 | 同上 | WA span 95.4674%；amount exact 33.4278% | 取业务激活/入网事件与 invoice 生成逻辑 |
| 05 New Activation | 200 amount mismatch | 4,340.000000 原额；候选差额 140.000000 | 新激活金额不是简单 price×final-span 的原因 | days 200/200，但 amount exact 0/200 | 获取 invoice 计算字段/规则，不以金额反推 days |
| 03 old replacement | 7 day mismatch | 226.322581 | replacement/old-card/new-card 事件 | 平台 void 候选 18.3468% | 开放 `dm.card_replacement_details` 或 approved read view |
| 04 old replacement | 3 day mismatch；6 mapping | 41.233333；155.000000 | replacement log 与唯一产品映射 | WA span 46/49；package exact 43/49 | 同上 |
| 05 new-card replacement | 12 day mismatch；190 amount mismatch | day 子集 338.675269；amount 子集 4,801.200000 | 新卡替换激活、旧卡失效、业务 replacement reason | WA span 390/402；package exact 402/402；platform date exact 很低 | 取得换卡核心事件和 reason mapping |
| pending-prorated | 127 / 284 / 9 | 3,686.928571 / 9,827.387097 / 298.766667 | `wa_invoice_prorated` 无 final_days；pending 来源是前月 pending sheet | 只有 active/usage/final_start/end/original/final/pending 字段 | 确认 pending charge 的业务归属月和 days 定义 |
| 03 Full Cycle price mapping | 1,254 保守 missing；220 多价格 | 77,748.000000；11,740.000000 | 唯一 product/package_price 版本 | WA 金额月价 exact；platform price exact 4,910/6,164 | 按账单月冻结 product version；不要用 MAX/MIN 代替版本规则 |
| 04 Full Cycle price mapping | 700 保守 missing；269 多价格 | 43,400.000000；11,605.000000 | 同上 | platform price exact 6,325/7,025 | 同上 |
| 05 Full Cycle price mapping | 700 保守 missing；200 多价格 | 43,400.000000；10,025.000000 | 同上 | platform price exact 6,551/7,251 | 同上 |
| 换卡/核心日志访问 | UNKNOWN | UNKNOWN | `dm.card_replacement_details`、`dm.change_card_data`、`ods.core_dse_applylog` SELECT 均返回 Delta `AccessDeniedException` | 本次只做了只读探针，没有尝试绕过或写入 | 由数据所有者提供只读授权、approved view 或导出 |

## C6. 已阅读的本地参考文件（仅参考，不是最终数字证据）

以下文件只用于了解工作区结构、既有 SQL/字段提示和执行 wrapper；最终数字没有从这些文件读取，全部重新用本次 `simo_cdc` live read-only query 验证：

- `C:/Users/EDY/Desktop/对账notebook/recon/dbx.ps1`：只读 SQL runner 的 host/warehouse/profile 调用方式。
- `C:/Users/EDY/Desktop/对账notebook/recon/tables.tsv`：既有表名/结构线索。
- `C:/Users/EDY/Desktop/对账notebook/recon/cols.tsv`：既有列名线索。
- `C:/Users/EDY/Desktop/对账notebook/recon/c_final.sql`：既有 C 批次候选 SQL 线索，仅参考。
- `C:/Users/EDY/Desktop/对账notebook/recon/c_zuofei_verify.sql`：既有作废/日期验证线索，仅参考。

本批次独立输出目录为：`C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C`。现有 `recon` 参考文件未被修改或覆盖。