# WA SIM 月度账单独立对账与审查计划

> **For agentic workers:** 本计划由主代理负责审查，月度分析由独立子代理完成。子代理只能使用 `gpt-5.6-luna`，推理强度使用该模型最高级别 `max`。

**目标：** 对平台已导入的 WA 原始 Excel 发票和平台原始数据按月独立逆向计费规则，并由主代理逐批审查证据、规则、SQL 和未解决问题。

**范围基线：** 先处理当前参考目录已覆盖的 2025-10 至 2026-08 共 11 个月。2025-09 虽然存在参考结果，但不在当前主验证 SQL 范围内；2026-09 未出现在本地参考范围内，均不自动纳入本轮。

**职责边界：** 主代理只做目录/结果审查、证据质量检查、退回和验收；不执行月度对账、不补写规则、不修改 SQL/notebook、不把参考 TSV/报告当作最终证据。子代理负责实际月度分析和候选 SQL。

**证据原则：** 平台中重新查询的 WA Invoice、`sim_status_for_sftp_bak`、账期历史、状态日志、产品维度及其他必要原始表是最终证据；本地 `recon` 目录仅用于了解已有实现、字段和潜在陷阱。

## 全局约束

- 每次只运行一个子代理，按批次串行，不并行派发。
- 所有子代理固定模型为 `gpt-5.6-luna`，固定推理强度为 `max`。
- 每个子代理负责一个批次中的最多 3 个月；最后一批只有 2 个月。
- 子代理不得把现有 SQL、TSV、Markdown 报告中的数字直接作为证据，必须重新查询平台数据。
- 不允许为了缩小总差异添加补差 CASE、平均 days、金额倒推 days 或未经卡级证明的跨月规则。
- 每个 charge type 必须独立分析；无法从平台字段证明的结果必须标记 `UNRESOLVED`、`MISSING_DATA` 或 `MISSING_MAPPING`。
- 子代理不得修改现有参考文件；若需要落盘，只能写入自己的唯一批次目录，不得覆盖其他批次输出。
- SQL 必须只读、可审计、可回溯到 `card_id`/`imsi`，并明确月份映射和时区处理。

## 批次安排

| 批次 | 月份 | 重点风险 | 处理顺序 |
|---|---|---|---:|
| A | 2025-10、2025-11、2025-12 | 基准 Full Cycle、早期新激活、发票文件命名与计费月映射 | 1 |
| B | 2026-01、2026-02、2026-03 | Product Transfer、Credit、Simbank Transfer；3 月为最大已知缺口 | 2 |
| C | 2026-04、2026-05、2026-06 | 新激活分支、换卡新卡、跨月生命周期 | 3 |
| D | 2026-07、2026-08 | 已有规则复核、月末边界、预付与当月费用口径 | 4 |

批次 B 不拆成并行代理；它虽然风险最高，但仍保持单代理、单批次，以减少共享平台查询和并发错误。若代理失败，优先恢复同一代理；不得同时启动重复代理。

## 每个子代理的固定任务

### 1. 只读盘点和月份确认

- 确认平台中的发票记录、`source_file`/计费月映射、行数和卡数。
- 确认平台快照、账期历史、状态日志、产品价格表的可访问性。
- 记录字段类型、字符串日期、时区偏移、分区过滤要求。
- 明确哪些本地参考文件被阅读过，但不把其中结果作为证据。

### 2. WA Invoice 事实分析

按月输出：

- `charge_type`、卡数、金额、最小/最大金额；
- `invoice_days` 分布；
- `product` × `charge_type` × `invoice_unit_price` 分布；
- `invoice_days`、单价、金额之间的公式验证、命中率、最大误差；
- 负数 Credit、Replacement、Transfer、Simbank 类型的独立统计。

### 3. 平台卡月事实

以 `card_id`/`imsi` 为粒度建立月度事实，至少保留：

- 首次/最后快照、激活、首次/最后在网、作废或停用相关日期；
- `Cycle_Start_Time`、`Cycle_End_Time`、账期历史；
- 状态日志事件；
- 产品 ID、产品名称、平台价格、卡状态；
- 所有候选日期及其来源。

### 4. 卡集合和 charge type 对应

对每个月做 WA Invoice 与平台卡月事实的 `FULL OUTER JOIN`，必须分别列出：

- `MATCHED`；
- `WA_ONLY`；
- `PLATFORM_ONLY`。

`PLATFORM_ONLY` 不得自动收费或删除，必须继续区分新激活、WA 尚未计费、产品差异、映射问题和数据范围问题。

### 5. 候选规则和分层验证

每个 `charge_type` 单独输出：

- 卡群定义；
- 候选起止日期；
- 候选 `days` 规则的 exact match、match rate、平均误差；
- 未命中卡的逐卡明细和子群；
- 规则 ID、适用条件、依据字段、数据来源；
- `PROVEN`、`PARTIAL`、`UNRESOLVED` 状态。

重点检查：换卡旧卡、换卡新卡、Product Transfer、Simbank Transfer、Credit、新激活，以及跨月和月末边界。

### 6. Candidate SQL 和逐卡 reconciliation SQL

只有在事实分析完成后才生成 SQL，至少分为：

1. `invoice_normalized`
2. `platform_card_month`
3. `rule_match`
4. `candidate_days`
5. `price_resolution`
6. `calculated_billing`
7. `reconciliation`

逐卡输出必须包含：

```text
billing_month
card_id / imsi
product
charge_type
invoice_days
calculated_days
day_diff
invoice_unit_price
calculated_unit_price
price_diff
invoice_amount
calculated_amount
amount_diff
rule_id
calculation_status
difference_reason
```

### 7. 批次交付物

每个批次只提交以下五类结果，不覆盖已有参考文件：

- 月度事实统计；
- charge type 规则证据表；
- 卡级 reconciliation 结果或可复现查询；
- Candidate Billing SQL 与 Reconciliation SQL；
- 未解决问题清单：卡数、金额影响、缺失字段/数据源、已有证据、下一步需要的数据。

## 主代理审查门槛

主代理对每个批次只做以下审查，不重跑月度工作：

### Gate 1：范围和来源

- 月份、发票文件映射、卡数和金额来自平台新查询；
- 没有把本地参考结果冒充最终证据；
- SQL 只读且有必要的分区过滤。

### Gate 2：卡级完整性

- WA_ONLY、PLATFORM_ONLY、MATCHED 全部明确；
- charge type 没有被混合计算；
- 规则命中率不是只看总金额；
- 未命中卡存在逐卡原因。

### Gate 3：规则可证明性

- 日期规则能回溯到原始字段；
- 价格规则没有用 `MAX(price)`/`MIN(price)` 掩盖多价格；
- Credit 保留负数；
- Replacement、Transfer、Simbank 没有使用猜测字段；
- 无法证明的部分保留 `UNRESOLVED`。

### Gate 4：金额和 SQL

- 金额只用于验证，不用于反推规则；
- days、price、population、unresolved 的差异拆分可解释；
- SQL 分层、可执行、可审计；
- 结果能回到卡级明细。

审查结论只允许三种：

- `ACCEPTED`：证据完整，可进入下一批；
- `ACCEPTED_WITH_UNRESOLVED`：已证明部分可接受，缺口明确保留；
- `RETURN_FOR_REVIEW`：证据不足、引用参考结果、总额驱动规则或卡级链路不完整。

## 批次间控制

- 批次 A 审查通过后才启动 B；B 通过后才启动 C；依次到 D。
- 后批次可以阅读前批次的已审查规则，但不能自动推广；仍须在本月平台数据中重新验证。
- 发现其他月份问题时，只记录 `OBSERVATION_FOR_OTHER_MONTH`，不得顺手修改其他月份规则。
- 主代理不创建统一 Billing Engine，不做跨月规则重构；只有所有月度结果分别审查完成后，才另立计划比较公共规则。

## 最终汇总交付

11 个月全部通过审查后，主代理只汇总审查结果：

1. 每月结论；
2. 每个 charge type 的已证明规则；
3. 卡级 days、price、amount 命中率；
4. WA total、calculated total、net difference；
5. days、price、population、unresolved 差异拆分；
6. 所有 `UNRESOLVED`、`MISSING_DATA`、`PLATFORM_ONLY`、`WA_ONLY`；
7. 哪些 SQL 通过审查，哪些仅为候选 SQL。

2025-09 和 2026-09 只有在确认范围、发票映射和平台数据可用后，才新增批次；不并入现有结论。

