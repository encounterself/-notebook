# WA SIM 月度账单独立对账批次 C（v2，新增硬约束后权威版）

本版 supersede 之前的 C 报告。范围：2026-03、2026-04、2026-05。

所有平台数字均来自本次 `simo_cdc` profile 的只读 `SELECT/WITH` 查询；平台表统一使用 `simo_prod.<schema>.<table>` 全限定名。没有执行 Databricks 写操作，也没有修改现有参考文件。

## 1. 新增硬约束的落实方式

1. Excel `final_start_date/final_end_date/final_days/monthly_rate/final_charge/charge_type` 是当月真实目标。先对 Excel 自身日期跨度、整月月价公式、按 days prorate 公式做 live 验证；平台只做解释/复现。
2. `wa_invoice_detail` live schema 没有 `product_id`，因此 `excel_product_id` 显式保留为 NULL/MISSING_MAPPING；不能用 Excel `product_name` 去 JOIN 平台价格。
3. 平台先用目标月分区的 `tc_cdr.sim_status_for_sftp_bak`，以及目标月交叠窗口的 `cycle_history`，按 `resource_res_vsim_product.product_id` 过滤 Wing Alpha scope；然后才按 IMSI 聚合。`status_log` 只 JOIN 这些已限定的 platform keys，并限制 `partition_date` 与 `CREATE_DATE` 在目标月。
4. 正式平台价格候选来自同一 `product_id` 的 `resource_res_vsim_product.package_price`，并保留 `cycle_history.package_price`、平台 product_id/name、产品 create/modify 字段。`cycle_history.package_price` 在目标数据中为 0，未被用来计算价格。
5. 产品维度没有 valid_from/valid_to 历史版本字段，故任何平台价格只能标为 `PRODUCT_ID_TARGET_MONTH_CURRENT_DIMENSION_NO_VALID_TO`，不冒充已证明的历史生效价格。
6. candidate SQL 实际计算 `platform_calculated_days`、`platform_calculated_price`、`platform_calculated_amount`，并输出 days/price/amount 差异字段。`UNRESOLVED` 只在完成候选窗口、UTC/−5 时区、平台覆盖和卡级残差后使用。

Wing Alpha 范围探针发现专属 scope 字段不可用；本批次只把产品维表中 product_name 的 `(WA)` 标记作为 scope classifier，不把它用于价格 JOIN。正式价格仍按 product_id + 目标月 cycle window 连接。

## 2. Excel 月账单事实与自身公式

### 月度总览

| 月份 | detail 行数 / IMSI | pending 行数 / IMSI | detail amount | pending final_charge_for_usage_days | Excel/WА 合计 |
|---|---:|---:|---:|---:|---:|
| 2026-03 | 13,082 / 12,763 | 127 / 127 | 578,406.306470 | 3,686.928571 | 582,093.235041 |
| 2026-04 | 7,780 / 7,317 | 284 / 284 | 372,289.307489 | 9,827.387097 | 382,116.694586 |
| 2026-05 | 7,887 / 7,494 | 9 / 9 | 389,800.952660 | 298.766667 | 390,099.719327 |

### Excel 公式验证

`date exact` 是 `final_days = DATEDIFF(final_end_date, final_start_date)+1`。`full exact` 是 `final_charge = monthly_rate`；`prorate exact` 是 `final_charge = monthly_rate × final_days / month_days`，误差阈值 0.01。Credit 不强行套正向 prorate，负数原样保留。

| 月份 / charge_type | date exact | full exact | prorate exact | Excel 公式结论 |
|---|---:|---:|---:|---|
| 03 Credit | 7/8 | 0/8 | 0/8 | Credit 保留负数，未证明公式 |
| 03 Full Cycle | 6,164/6,164 | 6,164/6,164 | 6,164/6,164 | 月价公式成立 |
| 03 FEB Backbilled | 269/269 | 269/269 | 0/269 | 月价公式成立 |
| 03 New Activation | 1,056/1,229 | 9/1,229 | 1,157/1,229 | 72 张金额公式残差，173 张日期跨度残差 |
| 03 old replacement | 489/496 | 2/496 | 496/496 | Excel prorate 成立 |
| 03 Simbank transfer | 4,478/4,901 | 1,339/4,901 | 4,901/4,901 | Excel prorate 成立；平台解释另审 |
| 03 offstock out | 14/14 | 0/14 | 14/14 | Excel prorate 成立 |
| 04 Full Cycle | 7,025/7,025 | 7,025/7,025 | 7,011/7,025 | 应用月价，不应用日期跨度 |
| 04 New Activation | 674/706 | 3/706 | 243/706 | 463 张金额公式残差 |
| 04 old replacement | 46/49 | 0/49 | 49/49 | Excel prorate 成立 |
| 05 Credit | 2/2 | 0/2 | 0/2 | Credit 保留负数，未证明公式 |
| 05 Full Cycle | 7,163/7,251 | 7,251/7,251 | 7,251/7,251 | 应用月价；final_days 不总等于日期跨度 |
| 05 New Activation | 200/200 | 0/200 | 0/200 | 200 张金额公式残差 |
| 05 old replacement | 30/30 | 0/30 | 30/30 | Excel prorate 成立 |
| 05 new-card replacement | 390/402 | 4/402 | 209/402 | 193 张金额公式残差，12 张日期跨度残差 |
| 05 offstock out | 2/2 | 0/2 | 2/2 | Excel prorate 成立 |

Excel 自身公式逐卡残差：[08_excel_formula_exceptions.tsv](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/08_excel_formula_exceptions.tsv)。

## 3. 受限平台事实与候选规则

平台人口先限定 Wing Alpha 和目标月，再按 IMSI 聚合：

| 月份 | Wing Alpha 平台卡 | status snapshot | cycle | status log（限定 keys + 月分区） | 唯一 product_dim price | 多 price | 缺 price |
|---|---:|---:|---:|---:|---:|---:|---:|
| 03 | 10,787 | 10,618 | 8,591 | 8,179 | 8,437 | 154 | 2,196 |
| 04 | 11,615 | 11,046 | 9,091 | 7,827 | 8,918 | 173 | 2,524 |
| 05 | 9,899 | 9,565 | 8,205 | 6,767 | 8,205 | 0 | 1,694 |

### 平台 candidate days / price / amount

价格分母仅是目标月、目标 product_id 窗口内存在唯一 `product_dim.package_price` 的卡；没有 valid_to 的价格不视为历史最终证据。

| 月份 / charge_type | platform days exact | platform price exact | platform amount exact | 主要残差 |
|---|---:|---:|---:|---|
| 03 Full Cycle | 6,164/6,164 | 4,437/5,691 | 4,437/5,691 | 473 missing price；1,254 price residual |
| 03 FEB Backbilled | 269/269 | 142/146 | 142/146 | 123 missing price；4 residual |
| 03 New Activation | 11/1,192 | 600/600 | 10/600 | 37 missing day；629 missing price；其余 day residual |
| 03 old replacement | 91/496 | 496/496 | 91/496 | 405 day residual |
| 03 Simbank transfer | 460/460（仅 460 可评估） | 460/460 | 460/460 | 4,441 missing platform days/scope |
| 03 offstock out | 0/1 | 1/1 | 0/1 | 13 missing platform days |
| 04 Full Cycle | 7,011/7,025 | 6,157/6,857 | 6,157/6,857 | 168 missing price；700 price residual |
| 04 New Activation | 8/706 | 702/702 | 10/702 | 平台激活规则不复现 Excel；4 张缺 price |
| 04 old replacement | 24/49 | 43/49 | 24/49 | 25 day residual |
| 05 Full Cycle | 7,251/7,251 | 6,551/7,251 | 6,551/7,251 | 700 price residual |
| 05 New Activation | 0/200 | 200/200 | 0/200 | 200 day/amount residual |
| 05 old replacement | 30/30 | 30/30 | 30/30 | 平台候选在小样本成立 |
| 05 new-card replacement | 0/10（392 missing） | 402/402 | 0/10 | 392 missing day；10 residual |
| 05 offstock out | 2/2 | 2/2 | 2/2 | 小样本成立 |

### UTC 与 UTC−5 时区残差

同一受限平台集合上同时计算了 UTC 和 UTC−5 的 candidate days/amount：

| 月份 / charge_type | UTC days exact | UTC−5 days exact | 两时区 days 不同 | 结论 |
|---|---:|---:|---:|---|
| 03 New Activation | 11/1,192 | 6/1,192 | 641 | 时区不能解释全部残差 |
| 03 old replacement | 91/496 | 0/496 | 95 | 时区选择实质影响结果，未解决 |
| 03 Simbank | 460/460 | 460/460 | 0 | 仅限 460 张可评估子集，不能外推 |
| 04 New Activation | 8/706 | 13/706 | 617 | 两时区均低命中 |
| 04 old replacement | 24/49 | 24/49 | 0 | 仍有 25 张卡级残差 |
| 05 old replacement | 30/30 | 0/30 | 30 | 时区选择实质影响结果，未解决 |
| 05 new-card replacement | 0/10 | 0/10 | 0 | 392 张没有平台日期事件 |

时区分析结果：[09_scoped_timezone_validation.tsv](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/09_scoped_timezone_validation.tsv)。
平台候选 SQL 先计算字段再产出状态：[10_candidate_billing_v2.sql](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/10_candidate_billing_v2.sql)。实际汇总：[10_candidate_billing_v2_summary.tsv](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/10_candidate_billing_v2_summary.tsv)。

## 4. 受限范围 FULL OUTER JOIN reconciliation

新版 FULL OUTER JOIN 使用 `(billing_month, imsi)`：

- Excel 侧 detail 与 pending 先聚合。
- 平台侧只使用 Wing Alpha product_id scope 和目标月分区/窗口事实。
- `status_log` 不再独立制造全量平台集合，而是只连接已限定的 platform keys。
- Excel 没有 product_id，故 `excel_product_id` 显式为 NULL；平台 product_id/name/历史 package_price/当前 dimension package_price 均保留。

| 月份 | MATCHED | WA_ONLY | PLATFORM_ONLY | MATCHED Excel amount | WA_ONLY amount |
|---|---:|---:|---:|---:|---:|
| 03 | 7,991 | 4,772 | 2,796 | 370,428.988503 | 211,664.246538 |
| 04 | 7,317 | 0 | 4,298 | 382,116.694586 | 0 |
| 05 | 7,494 | 0 | 2,405 | 390,099.719327 | 0 |

2026-03 的 4,772 张 WA_ONLY 是严格 product_id scope 后没有受限平台事实的卡，不能再按旧版广域 UNION 结果宣称 MATCHED；它们更接近 `MISSING_MAPPING/MISSING_PLATFORM_FACT`，因为 Excel 本身没有 product_id。

受限 reconciliation SQL：[10_reconciliation_v2.sql](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/10_reconciliation_v2.sql)。摘要：[10_reconciliation_v2_summary.tsv](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/10_reconciliation_v2_summary.tsv)。

## 5. 卡级残差与未解决问题

| 问题 | 卡数 | 金额/残差 | 当前证据 | 下一步 |
|---|---:|---:|---|---|
| 03 Simbank 平台事件缺失 | 4,441 | Excel amount 182,843.032258 | Excel prorate 4,901/4,901；受限平台只有 460 张有 cycle candidate | 获取 transfer/Simbank 事件的 product_id、事件时间和生效状态 |
| 03 Simbank 可评估子集 | 460 | platform amount diff 约 0.000009 | cycle UTC→月末在这 460 张为 exact；不能外推到 4,441 张 | 补齐缺失 product_id/cycle scope 后重跑 |
| 03/04/05 New Activation | 37 missing + 1,181 residual；698 residual；200 residual | 平台 amount exact 11/1,192、10/706、0/200 | 已分别测试 activation UTC、月分区、卡级 days residual | 获取业务激活事件与 invoice 起算定义；比较 UTC/−5 |
| 03 old replacement | 405 | Excel amount 6,520.903226 | platform final_start→void UTC−1 exact 91/496 | 开放换卡事件日志，核对 old/new 关联 |
| 04 old replacement | 25 | Excel amount 382.566667 | platform final_start→void UTC−1 exact 24/49 | 同上 |
| 05 new-card replacement | 392 missing + 10 residual | Excel amount 13,479.746236 | 仅 10 张有 platform day candidate；price 402/402 | 获取新卡激活、旧卡失效、replacement reason |
| Full Cycle / Backbilled price | 03: 473+1,254；backbill 123+4；04: 168+700；05: 700 | 对应 Excel amount 保留在 candidate summary | product_id 唯一价格/多价格/缺失已分层；无 valid_to 历史 | 提供按 billing_month 生效的历史产品价格版本 |
| pending-prorated | 127 / 284 / 9 | 3,686.928571 / 9,827.387097 / 298.766667 | pending 表没有 final_days，仍独立保留 | 确认 pending 归属月和正式 days 定义 |
| Excel product_id | 全部 detail 卡 | 无法按 Excel product_id 做正式价格 JOIN | live schema 没有该列 | 上游补 product_id 或提供受控 product_name→product_id 映射，仅用于映射，不直接按名称定价 |
| 产品历史有效期 | 受影响的所有平台价格卡 | 无法证明当前 package_price 是历史月生效价 | product_dim 只有 create/modify，没有 valid_to/version | 提供 SCD/价格历史表或按月快照 |
| 换卡/核心日志 | UNKNOWN | UNKNOWN | `dm.card_replacement_details`、`dm.change_card_data`、`ods.core_dse_applylog` 只读探针均为 `AccessDeniedException` | 由数据所有者提供只读授权或 approved view |

卡级平台残差文件：

- [Simbank residuals](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/10_scoped_simbank_residuals.tsv)
- [Activation residuals](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/10_scoped_activation_residuals.tsv)
- [Replacement residuals](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/10_scoped_replacement_residuals.tsv)
- [Full Cycle/Backbilled residuals](C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C/10_scoped_full_cycle_residuals.tsv)

## 6. 仅参考的本地文件

以下文件只用于了解工作区结构、字段线索和 wrapper；最终数字均重新来自本次 `simo_cdc` live read-only query：

- `C:/Users/EDY/Desktop/对账notebook/recon/dbx.ps1`
- `C:/Users/EDY/Desktop/对账notebook/recon/tables.tsv`
- `C:/Users/EDY/Desktop/对账notebook/recon/cols.tsv`
- `C:/Users/EDY/Desktop/对账notebook/recon/c_final.sql`
- `C:/Users/EDY/Desktop/对账notebook/recon/c_zuofei_verify.sql`

本版独立输出目录：`C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/C`。