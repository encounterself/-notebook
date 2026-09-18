# WA SIM 月度账单独立对账：批次 A

范围：2025-09、2025-10、2025-11。执行连接：工作区现有 `recon\dbx.ps1` 的唯一有效 `simo_cdc` profile。平台对象统一使用 `simo_prod.<schema>.<table>` 全限定名。

## 结论摘要

- 发票计费月按 `final_start_date` 取证，不按文件名猜月。9 月、10 月、11 月分别对应 3 个来源文件；其中 11 月行仍来自文件名含 `OCT 2025` 的文件。
- 10 月和 11 月平台快照可读；平台卡集合先按目标月份分区，再按产品表 supplier_id=2275 这个当前可查询的 Wing Alpha 范围键过滤。产品表当前只有 create_time/modify_time，没有历史价格有效区间，因此平台价格只作为观察值复现，历史生效状态仍单独保留为 UNRESOLVED。
- 10 月、11 月 FULL OUTER JOIN 没有 WA_ONLY；平台侧分别多出 411、4,219 张卡。它们属于平台 WA 产品范围，但未出现在当月 Excel 逻辑明细中，不能用补差消除。
- 日数规则和单价规则分开验证。`final_days` 与 `monthly_rate` 均保留原始发票值；候选金额只在平台价格唯一且生命周期字段可用时计算，不用金额倒推 days，不用 MAX/MIN 掩盖多价格，不添加补差 CASE。
- replacement、transfer、Simbank 没有形成可审计的卡级映射；`wa_invoice_credit` 对本批次来源文件无行，`transferred_to_wing_simbank` 没有非空证据。相关结论保持 `UNRESOLVED/MISSING_DATA/MISSING_MAPPING`。

## A1. 每月事实统计

| 计费月 | Excel 逻辑来源文件（按 final_start_date） | charge_type 数 | 发票行数 | distinct 卡数 | final_days 合计 | final_charge 合计 |
|---|---|---:|---:|---:|---:|---:|
| 2025-09 | `006-V2 - SIMO Data Purchase Invoice Details - SEP 2025.xlsx` | 4 | 25,237 | 14,793 | 563,559 | 1,139,393.53 |
| 2025-10 | `01-INVOICE_FROM_ WA_USD_772,765.00_SIMO Data Purchase Invoice Details - OCT 2025.xlsx` | 3 | 12,677 | 12,675 | 391,410 | 772,750.53 |
| 2025-11 | `01-1-INVOICE_FROM_ WA_USD_773,793.84_SIMO Data Purchase Invoice Details - OCT 2025.xlsx` | 2 | 12,663 | 12,641 | 379,547 | 773,737.84 |

9 月按类型：Full Rate 12,602 行 / 771,254.00；Partial Charge (Activated AUG) 11,484 / 339,332.26；Prorated-in Charge (Activated SEPT) 1,085 / 27,478.40；Prorated-out Charge (Activated SEPT) 66 / 1,328.87。

10 月按类型：Full Cycle Charge 12,573 / 769,456.00；New Activation: Prorated-in Charge 72 / 2,364.53；Prorated-out Charge (Activated OCT) 32 / 930.00。

11 月按类型：Full Cycle Charge 12,641 / 773,292.00；New Activation: Prorated-in Charge 22 / 445.84。

价格证据没有被压成单一价格：

- 2025-09：Full Rate 为 $43/530 行、$62/12,072 行；Partial 为 $43/530、$62/10,954；两种 prorated 均为 $62。
- 2025-10：Full Cycle 为 $43/530、$62/12,043；两个非 full 类型均为 $62。
- 2025-11：Full Cycle 为 $43/550、$62/12,091；New Activation 为 $43/20、$62/2。

证据文件：`01_probe_invoice_mapping.tsv`、`11_invoice_month_type_stats.tsv`、`12_invoice_rate_breakdown.tsv`、`23_invoice_card_grain.tsv`。

## A2. charge_type 候选日期规则、命中率和未命中卡

“exact”均为卡级/发票行级候选 `candidate_days = invoice final_days`；金额列不是规则反推依据。10 月、11 月的完整未命中卡在 `35_unresolved_cards_oct.tsv`、`36_unresolved_cards_nov.tsv`。

| 月份 / charge_type | 候选规则 | exact | day error 分层 | 规则状态与证据 |
|---|---|---:|---:|---|
| 2025-09 Full Rate | G_FULL_MONTH_CALENDAR | 12,602/12,602（发票日历公式） | 平台卡级不可验证；cycle start exact 12,349/12,602 | `MISSING_DATA`：快照不可读；date-span mismatch 2,279 |
| 2025-09 Partial Charge (Activated AUG) | 未定 | 0/11,484（按月正向公式） | cycle start exact 141/11,484；公式差 +11,311.09 | `UNRESOLVED`：发票日期边界与平台生命周期不一致 |
| 2025-09 Prorated-in Charge (Activated SEPT) | E_ACTIVATION_TO_CYCLE_END（候选） | 发票公式 1,085/1,085；平台 activation+1 exact 1/1,085 | date-span mismatch 169 | `MISSING_DATA/UNRESOLVED` |
| 2025-09 Prorated-out Charge (Activated SEPT) | C_CYCLE_START_TO_OFFSTOCK（候选） | 发票公式 66/66；cycle start exact 66/66 | invoice offstock 字段为空，offstock 日期匹配 0 | `MISSING_DATA/UNRESOLVED` |
| 2025-10 Full Cycle Charge | G_FULL_MONTH_CALENDAR | 12,573/12,573（100%） | sum abs day error 0 | 日规则已由卡级 exact 验证；平台 `presence_days` 不作为计费日数 |
| 2025-10 New Activation: Prorated-in Charge | E_ACTIVATION_TO_CYCLE_END，当前候选 end=`cycle_end-1` | 66/72（91.67%） | sum abs day error 69；end-inclusive alternative exact 3/72 | `UNRESOLVED`：需确认 activation/cycle-end 边界 |
| 2025-10 Prorated-out Charge (Activated OCT) | C_CYCLE_START_TO_OFFSTOCK | 21/32（65.63%） | sum abs day error 25；status offstock raw/minus5h 日期匹配 21/32 | 候选规则，仍有 11 张未命中 |
| 2025-11 Full Cycle Charge | G_FULL_MONTH_CALENDAR | 12,641/12,641（100%） | sum abs day error 0 | 日规则已由卡级 exact 验证；不得改成 presence days |
| 2025-11 New Activation: Prorated-in Charge | E_ACTIVATION_TO_CYCLE_END，当前候选 end=cycle_end-1 | 0/22 | 10 张为 DAY_MISMATCH，12 张为 INVALID_DATE_WINDOW；有效窗口 sum abs day error 254；end-inclusive alternative exact 0/22 | UNRESOLVED：12 张候选结束日早于 activation，不能计算平台 days/amount |

价格卡级验证：

- 10 月 Full Cycle：平台唯一 WA 价格匹配 11,449/12,573；价格不匹配 1,121；卡级多平台价格 3。
- 10 月 New Activation：匹配 72/72；Prorated-out 匹配 31/32。
- 11 月 Full Cycle：匹配 11,296/12,641（89.36%）；价格不匹配 1,344；卡级多平台价格 1。
- 11 月 New Activation：匹配 20/22（90.91%）；其中价格不匹配 2。

10 月 Full Cycle 价格匹配率为 11,449/12,573（91.06%）；New Activation 为 72/72（100%）；Prorated-out 为 31/32（96.88%）。这些是 platform price 与 Excel monthly_rate 的观察值相等率，不代表历史价格生效条件已证实。

supplier_id=2275 的产品表探针返回 312 个 product_id、4 个观察价格；候选 SQL 只按 product_id + billing_month 取平台产品并保留 platform product_id/name/price。Excel 源表没有 product_id 字段，不能用 product_name 做正式价格 JOIN；因此每条匹配行保留 excel_product_id=NULL 和 MISSING_MAPPING_EXCEL_PRODUCT_ID。平台产品表没有历史有效区间，unique price 的计算结果仍标记 UNRESOLVED_NO_HISTORICAL_PRICE_EFFECTIVE_CONDITION；候选 SQL 保留完整价格集合，没有使用 MAX/MIN。

Excel 自算证据为 `38_excel_formula_validation.tsv`：Full Cycle/Full Rate 和 prorated-out 的分币公式可复现，Partial Charge (Activated AUG) 分币公式不成立，2025-11 New Activation 也不成立。平台生命周期和价格观察证据为 `15_lifecycle_event_evidence.tsv`、`16_offstock_event_mapping.tsv`、`18_platform_scope_summary.tsv`、`26_reconciliation_summary_oct.tsv`、`27_reconciliation_summary_nov.tsv`。

## A3. Excel 与平台逐卡 reconciliation

Excel 逻辑来源是 `simo_prod.mysql_cdc_sync.wa_invoice_detail`；必要时检查的辅助 Excel 逻辑来源为 `simo_prod.mysql_cdc_sync.wa_invoice_credit`、`simo_prod.mysql_cdc_sync.wa_invoice_prorated`。平台来源是 `simo_prod.tc_cdr.sim_status_for_sftp_bak`、`simo_prod.ods.resource_res_vsim_cycle_history`、`simo_prod.ods.resource_res_vsim_status_log`、`simo_prod.ods.resource_res_vsim_product`；`simo_prod.ods.resource_res_carrier` 已做只读 schema 探针，但当前卡级规则不需要 carrier join，因此未把它作为计费证据。cycle history 与 status log 是本批次确认可读的核心生命周期事件来源。FULL OUTER JOIN 的粒度为 `billing_month + imsi`，发票侧同时保留 `charge_type` 行粒度。

| 月份 | 平台事实范围 | MATCHED | WA_ONLY | PLATFORM_ONLY | 备注 |
|---|---|---:|---:|---:|---|
| 2025-09 | 未形成可验证的 Wing Alpha 月度平台卡集合 | 未评估 | 未评估 | 未评估 | MISSING_DATA；不把全量事件表制造成 MATCHED/PLATFORM_ONLY |
| 2025-10 | 完整月快照 + 产品映射 | 12,675 卡 / 12,677 行 | 0 | 411 卡 | 平台 WA 产品范围共 13,086 卡 |
| 2025-11 | 完整月快照 + 产品映射 | 12,641 卡 / 12,663 行 | 0 | 4,219 卡 | 平台 WA 产品范围共 16,860 卡 |

9 月探针：SHOW PARTITIONS 能看到 720 个小时分区，但读取快照时分别在 day=16/hour=6、day=15/hour=7、day=10/hour=22 等 raw Parquet 文件收到 AccessDeniedException；因此不能用“分区存在”替代“快照可读”，也不能用未限定 Wing Alpha 的全量 status_log/cycle_history 制造 PLATFORM_ONLY。最终 9 月 reconciliation 只保留 MISSING_DATA shell，不输出虚假的平台卡集合。

10 月、11 月先限定月份分区并按 product_id 连接 supplier_id=2275：10 月 9,586,426 条该 supplier 范围快照行 / 13,086 distinct IMSI；11 月 9,891,751 条 / 16,860 distinct IMSI。41 探针显示 supplier_id=2275 下关联多个 carrier（T-Mobile、AT&T、Vodafone、U.S. Cellular、Verizon），carrier 表本身不是 supplier/Wing Alpha 名称表；因此正式范围键保留为 supplier_id=2275，不用 carrier_name 代替。非该 supplier 或 product_id 未映射的快照行不进入平台卡集合；非发票平台卡没有被强行冲销或补金额。

## A4. candidate billing SQL 与 reconciliation SQL

以下文件均是本批次独立目录中的 SELECT/WITH SQL，已执行前通过只读预检，并在 `simo_cdc` 上成功执行：

- 10 月候选计费：`30_candidate_billing_oct.sql`；10 月逐卡 reconciliation：`24_card_reconciliation_oct.sql`。
- 11 月候选计费：`31_candidate_billing_nov.sql`；11 月逐卡 reconciliation：`25_card_reconciliation_nov.sql`。
- 9 月候选计费：32_candidate_billing_sep.sql；9 月 reconciliation shell：33_reconciliation_sep.sql，汇总为 34_reconciliation_summary_sep.sql。由于平台卡集合不可读，9 月不输出事件级伪匹配，金额/日期验证保持 MISSING_DATA。
- 汇总：`26_reconciliation_summary_oct.sql`、`27_reconciliation_summary_nov.sql`、`34_reconciliation_summary_sep.sql`。
- 未命中卡：35_unresolved_cards_oct.sql、36_unresolved_cards_nov.sql。
- Excel 自算验证：38_excel_formula_validation.sql；早期 Wing Alpha 范围：39_platform_scope_early_wa.sql；产品生效字段探针：40_product_effective_probe.sql。
- supplier/carrier 映射探针：41_supplier_carrier_probe.sql。

SQL 的审计特征：

- FULL OUTER JOIN 显式输出 MATCHED、WA_ONLY、PLATFORM_ONLY。
- 候选天数来自独立日期字段和候选规则；`xl_days`、`xl_rate`、`xl_charge` 永远保留原始 Excel 逻辑值。
- 平台价格只有唯一时才作为 candidate price；SQL 实际输出 platform_calculated_days、platform_calculated_price、platform_calculated_amount，以及 days_difference、price_difference、amount_difference。多价格标为 UNRESOLVED_MULTIPLE_PLATFORM_PRICES，缺失标为 MISSING_MAPPING_OR_PRICE；无效生命周期窗口不计算负 days/amount。
- 候选金额仅是 forward candidate，不用于反推天数，不为总额接近 0 添加补差分支；Credit 若存在也应保留负数，本批次 credit 来源未发现行。

## A5. 未解决问题清单

| 问题 | 卡数/行数 | 金额 | 缺失字段或来源 | 当前证据 | 下一步 |
|---|---:|---:|---|---|---|
| 2025-09 平台快照不可读 | 发票 14,793 卡；平台卡集合未评估 | 发票 1,139,393.53 | tc_cdr.sim_status_for_sftp_bak 多个 raw 分区 AccessDenied | 06 分区存在；03/07/09 读取失败；33/34 只保留 MISSING_DATA shell | 修复或提供可读的 9 月 Wing Alpha 月度快照，再做 FULL OUTER JOIN |
| 2025-09 Partial Charge 边界 | 11,484 卡 | 339,332.26 | 起止日与 AUG 周期的映射 | 月正向公式差 +11,311.09；cycle exact 141 | 取得已确认的计费边界/核心周期字段 |
| 2025-09 Prorated-in 边界 | 1,085 卡 | 27,478.40 | activation 与 cycle-end 的可审计边界 | activation+1 exact 1/1,085 | 逐卡确认 activation、周期结束和时区规则 |
| 2025-09 Prorated-out offstock | 66 卡 | 1,328.87 | 发票 offstock_date 为空；事件到发票字段映射 | cycle start exact 66/66；offstock date 匹配 0 | 确认 `作废`/`暂停`事件与 invoice 终止日字段 |
| 2025-10 平台价与发票价不一致 | 1,122 卡 | 69,516.00 | 产品/卡月价格版本映射 | 35 明细：PRICE_MISMATCH 1,122 | 逐卡核对产品变更、供应商价和生效日，不能用单一 MAX/MIN |
| 2025-10 平台多价格 | 3 卡 | 186.00 | 月内产品/价格集合 | `UNRESOLVED_MULTIPLE_PLATFORM_PRICES` | 确认价格生效边界后再决定归属 |
| 2025-10 日期未命中 | 17 卡 | 598.53 | activation/cycle-end 或 offstock 时点 | 35 明细：DAY_MISMATCH 17 | 逐卡检查生命周期事件时区和 inclusive/exclusive 规则 |
| 2025-11 平台价与发票价不一致 | 1,344 卡 | 83,328.00 | 产品/卡月价格版本映射 | 36 明细：PRICE_MISMATCH_OBSERVED 1,344 行/卡 | 逐卡核对产品变更和历史价格生效日 |
| 2025-11 平台多价格 | 1 卡 | 62.00 | 月内多产品/多价格 | `UNRESOLVED_MULTIPLE_PLATFORM_PRICES` | 确认产品切换日和计费价格归属 |
| 2025-11 New Activation 日期 | 10 张 DAY_MISMATCH、12 张 INVALID_DATE_WINDOW / 22 卡 | 445.84 | activation、cycle-end 边界 | exact 0/22；有效窗口 sum abs day error 254；12 张不计算平台 days/amount | 取得 replacement/core 事件或业务边界证据 |
| 平台额外卡 | 2025-10 411 卡；2025-11 4,219 卡 | 0（平台侧未对应 Excel 行） | Excel 映射或计费资格字段 | 平台 WA 产品 scope 与 FULL OUTER JOIN | 确认这些卡是否应计费、延期或属于非账单范围 |
| 平台价格历史生效条件 | 10/11 月匹配明细 25,340 行 | 1,546,488.37 | resource_res_vsim_product 无历史 valid_from/valid_to，仅有 create_time/modify_time | 40 探针：312 product_id、4 个观察价格；candidate price/amount 可计算但历史生效未证明 | 提供按 billing_month 或有效区间的产品价格历史表，再重算 platform_calculated_price/amount |
| replacement / transfer / Simbank | 当前无法证明卡级规则 | 未定 | transferred_to_wing_simbank、old/new IMSI、replacement 核心日志映射 | 本批次 50,577 条 Excel 明细没有 product_id 字段；transferred 字段无非空证据；wa_invoice_credit 0 行；wa_invoice_prorated 有 2025-09 36 行、2025-10 5 行但未证明与 invoice_detail 一一映射 | 指定已确认可用的换卡/核心日志表及 old/new IMSI 键，再做卡级映射；不要先编规则 |

## A6. 证据文件和本地参考

- 本批次证据和 SQL 均在独立目录 `recon\agent_runs\A`。
- `A6_local_reference_inventory.md` 记录了本次查阅的本地参考文件及其仅参考用途。
- 现有 `recon` 参考文件未被修改或覆盖；临时路径 `recon\A_TMP_27_reconciliation_summary_nov.sql` 不存在。
- 参考文件中的数字没有进入最终证据链；最终数字均来自本目录的本次 `simo_cdc` 只读查询输出。