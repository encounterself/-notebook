# 批次 A：WA SIM Excel detail 平台卡级复算报告

生成时间：2026-09-18  
证据范围：本次 simo_cdc 连接上的 Databricks 只读 SELECT/WITH/EXPLAIN 结果。  
本报告只写入 recon/agent_runs/A，不修改 recon 既有 SQL、TSV、Markdown、notebook，也不向 Databricks 写入任何对象。

## 结论先行

Excel control 三分支结构保持不变。本轮只对 excel_detail_invoice 做正式平台复算：

- detail：wa_invoice_detail.final_charge 逐行保留。
- prorated：wa_invoice_prorated 仍是独立辅助分支，本轮未加到 detail。
- credit：wa_invoice_credit 仍是独立辅助分支；detail 中的 Credit for Offstocked Card 也不被当作普通周期计费，负数保留，规则标为未解析/WA_ONLY。
- OCT 2025 v2 严格保留 official_excel_billing_month = 2025-10 (v2)，其 observed_start_month = 2025-11；没有改写成 2025-11。
- Excel 没有 product_id，平台 product_id 独立展示；因此唯一候选且数值匹配的行仍需标记 MISSING_MAPPING，不伪造产品映射。
- 多个 platform cycle 与同一 imsi + Excel final 窗口重叠时，候选不被任意选定为匹配，标记 UNRESOLVED / AMBIGUOUS_PLATFORM_CANDIDATE。
- 没有补差 CASE，没有把金额倒推为 days，也没有使用 product_name 做正式价格 JOIN。

整体状态：当前批次不能作为已闭合对账通过；可用于审查的候选结果已完成，但仍有大量周期候选歧义、产品映射缺失和 2025-09 snapshot 分区不可读问题。

## 1. Excel detail 真值范围

严格使用 source_file CASE；官方金额没有按 final_start_date 重分月。

| official_excel_billing_month | observed_start_month | source_file 行数 | distinct IMSI | Excel total_final_charge |
|---|---:|---:|---:|---:|
| 2025-09 | 2025-09 | 25,237 | 14,793 | 1,139,393.524729100000 |
| 2025-10 (v1) | 2025-10 | 12,677 个非 Credit detail 行 | 12,675 | 772,750.533333333334 |
| 2025-10 (v1) | NULL | 37 个 Credit for Offstocked Card 行 | 37 | -465.000000000000 |
| 2025-10 (v1) 合计 | — | 12,714 | 12,712 | 772,285.533333333334 |
| 2025-10 (v2) | 2025-11 | 12,663 | 12,641 | 773,737.838709677419 |

v1 的 37 条 Credit 行保留负数；它们没有 final_start_month，不能被伪造归入 observed_start_month。

## 2. 平台字段和卡集合证据

本次 schema probe 发现：

- tc_cdr.sim_status_for_sftp_bak：imsi、product_id、Cycle_Start_Time、Cycle_End_Time、year/month/day/hour、partition_time、SimStatus、DispatchStatus；没有 supplier_id。
- ods.resource_res_vsim_cycle_history：imsi、product_id、cycle_time、next_cycle_time、package_price、time_zone。
- ods.resource_res_vsim_status_log：IMSI、PRE_STATUS、NEXT_STATUS、CREATE_DATE、partition_date。
- ods.resource_res_vsim_product：product_id、product_name、supplier_id、package_price、package_price_withusd、time_zone、billing_cycle 等。

supplier_id=2275 的产品表证据：

- 产品记录：312。
- package_price 分布：21 美元 1 个 product_id、32 美元 2 个、43 美元 72 个、62 美元 237 个。
- 正式价格候选只使用 resource_res_vsim_product.product_id → package_price；product_name 仅展示，不用于价格 JOIN。

平台生命周期卡集合定义：

- 先以 supplier_id=2275 的 product_id 限定 cycle_history。
- 再限定 cycle_time < 2026-01-01 且 next_cycle_time > 2025-09-01。
- 再按 imsi、product_id、cycle_start_date、cycle_end_date 聚合。
- Excel 关联使用 imsi + Excel final_start/final_end 窗口 overlap；exact cycle window 优先，重叠天数较长者排前，但 candidate_count > 1 仍标 UNRESOLVED。
- PLATFORM_ONLY 只来自这个已限定的 cycle_history lifecycle 集合，并用 imsi + exact cycle 或 final 窗口 overlap 对 Excel 做 anti-join；没有把全量 snapshot、status_log、cycle_history UNION。

status_log 受限卡集结果：

- 目标 cycle_history IMSI：16,876。
- 有 2025-09 至 2025-11 status_log 的 IMSI：15,836。
- status_log 行数：94,628。
- 时间范围：2025-09-01 00:04:31 至 2025-11-30 23:58:53。

status snapshot 限制：

- 2025-10、2025-11 分区可读取并纳入独立摘要。
- 2025-09 查询遭遇底层 parquet 分区 AccessDenied；没有绕过、替换或用不可读分区制造匹配。
- 当前 billing days/price/amount 候选主要依赖可读的 cycle_history + product_id/product price；2025-09 snapshot 可用性仍列为 source-level MISSING_DATA 风险。

## 3. Candidate charge_type 规则

| charge_type | rule_id | platform_calculated_days | platform_calculated_price | platform_calculated_amount |
|---|---|---|---|---|
| Full Rate / Full Cycle Charge | R_FULL_CYCLE_PRICE | Excel final 窗口与平台 cycle 窗口的含首尾交集天数 | supplier=2275 的 product_id 对应 package_price | 单价；不从金额倒推 days |
| Partial Charge (Activated AUG) | R_PARTIAL_LIFECYCLE_DAYS_ACTIVATION_MONTH | 生命周期交集天数 | product_id 对应 package_price | price × days ÷ cycle_start 所在月份自然日数 |
| Prorated-in / Prorated-out | R_PRORATED_LIFECYCLE_DAYS_ACTIVATION_MONTH | 生命周期交集天数 | product_id 对应 package_price | price × days ÷ final_start 所在月份自然日数 |
| New Activation: Prorated-in Charge | R_PRORATED_LIFECYCLE_DAYS_ACTIVATION_MONTH | 生命周期交集天数 | product_id 对应 package_price | price × days ÷ new_activation_date 所在月份自然日数；缺失时回退 final_start |
| Credit for Offstocked Card | R_CREDIT_REQUIRES_CREDIT_EVIDENCE | NULL | 不作为普通 detail 周期价 | NULL；Excel 负数保留，需 credit/status 证据 |

Partial Charge 的分母由当前 Excel 行样本验证：例如 Activated AUG 的 11 天、43 美元、Excel amount=15.2580645，等于 43×11÷31；不能使用 final_start 所在 9 月的 30 天。

## 4. 月度 Excel/platform 金额和总体残差

platform_calculated_total 是候选平台金额，不是对 Excel 真值的替代。

| official label | observed month | detail population | Excel total | platform calculated total | amount_diff | numeric exact rows | days exact | price exact | amount exact | UNRESOLVED rows | MISSING_MAPPING rows | WA_ONLY rows |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 2025-09 | 2025-09 | 25,237 | 1,139,393.524729 | 1,114,993.843517 | -24,399.681212 | 11,470 (45.45%) | 24,826 (98.37%) | 23,661 (93.76%) | 23,397 (92.71%) | 12,780 (50.64%) | 12,457 | 0 |
| 2025-10 (v1)，非 Credit | 2025-10 | 12,677 | 772,750.533333 | 751,375.709677 | -21,374.823656 | 66 (0.52%) | 9,947 (78.46%) | 11,552 (91.13%) | 11,546 (91.08%) | 12,605 (99.43%) | 72 | 0 |
| 2025-10 (v1)，Credit | NULL | 37 | -465.000000 | NULL | NULL | 0 | 0 | 0 | 0 | 0 | 0 | 37 |
| 2025-10 (v2) | 2025-11 | 12,663 | 773,737.838710 | 745,519.999994 | -28,217.838716 | 226 (1.78%) | 12,126 (95.76%) | 11,188 (88.35%) | 11,168 (88.19%) | 11,682 (92.25%) | 981 | 0 |

定义：

- numeric exact = 唯一平台候选且 days、price、amount 均在容差内；多候选不计为 numeric exact。
- days/price/amount exact 是独立字段命中率，即便该行因 product_id 缺失或候选不唯一仍可单独观察。
- source_match_status=MISSING_MAPPING 表示平台数值可比较，但 Excel product_id=NULL，不能形成正式 product_id 映射。
- source_match_status=UNRESOLVED 表示多个平台 lifecycle 候选或其他无法证明的规则。
- source_match_status=WA_ONLY 表示 Excel detail 行没有平台 lifecycle 候选；本批次为 37 条 Credit 行。

## 5. 每个 charge_type 的卡级证据

| official label | charge_type | rows | numeric exact | days exact | price exact | amount exact | UNRESOLVED | Excel total | platform total | amount_diff |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 2025-09 | Full Rate | 12,602 | 110 (0.87%) | 12,455 (98.83%) | 11,749 (93.23%) | 11,749 (93.23%) | 12,492 (99.13%) | 771,254.000000 | 755,047.000000 | -16,207.000000 |
| 2025-09 | Partial Charge (Activated AUG) | 11,484 | 10,769 (93.77%) | 11,389 (99.17%) | 11,036 (96.10%) | 10,941 (95.27%) | 172 (1.50%) | 339,332.258055 | 335,059.709884 | -4,272.548171 |
| 2025-09 | Prorated-in Charge (Activated SEPT) | 1,085 | 591 (54.47%) | 916 (84.42%) | 810 (74.65%) | 641 (59.08%) | 50 (4.61%) | 27,478.400006 | 23,558.266955 | -3,920.133051 |
| 2025-09 | Prorated-out Charge (Activated SEPT) | 66 | 0 | 66 (100.00%) | 66 (100.00%) | 66 (100.00%) | 66 (100.00%) | 1,328.866668 | 1,328.866678 | 0.000010 |
| 2025-10 (v1) | Full Cycle Charge | 12,573 | 0 | 9,847 (78.32%) | 11,449 (91.06%) | 11,449 (91.06%) | 12,573 (100.00%) | 769,456.000000 | 748,100.000000 | -21,356.000000 |
| 2025-10 (v1) | New Activation: Prorated-in Charge | 72 | 66 (91.67%) | 68 (94.44%) | 72 (100.00%) | 66 (91.67%) | 0 | 2,364.533333 | 2,350.000000 | -14.533333 |
| 2025-10 (v1) | Prorated-out Charge (Activated OCT) | 32 | 0 | 32 (100.00%) | 31 (96.88%) | 31 (96.88%) | 32 (100.00%) | 930.000000 | 925.709677 | -4.290323 |
| 2025-10 (v1) | Credit for Offstocked Card | 37 | 0 | 0 | 0 | 0 | 0 | -465.000000 | NULL | NULL |
| 2025-10 (v2) | Full Cycle Charge | 12,641 | 226 (1.79%) | 12,120 (95.88%) | 11,168 (88.35%) | 11,168 (88.35%) | 11,681 (92.41%) | 773,292.000000 | 745,305.000000 | -27,987.000000 |
| 2025-10 (v2) | New Activation: Prorated-in Charge | 22 | 0 | 6 (27.27%) | 20 (90.91%) | 0 | 1 (4.55%) | 445.838710 | 214.999994 | -230.838716 |

Full Cycle / Full Rate 的低 numeric exact 主要不是 price，而是同一 imsi + Excel 窗口存在多个平台周期候选；平台单价本身通常可直接从 product_id 验证。

## 6. FULL OUTER / population 状态

正式逐行 Candidate 输出包含每条 Excel detail 行的：

- excel_source_file
- official_excel_billing_month
- official_excel_total_final_charge 由 Excel 行 amount 保留
- platform_calculated_days
- platform_calculated_price
- platform_calculated_amount
- day_diff
- price_diff
- amount_diff
- rule_id
- difference_reason
- numeric_match_status
- source_match_status

平台独占 lifecycle anti-join 统计：

| cycle_start month | PLATFORM_ONLY lifecycle rows | distinct IMSI |
|---|---:|---:|
| 2025-08 | 464 | 464 |
| 2025-09 | 333 | 333 |
| 2025-10 | 5 | 5 |
| 2025-11 | 1,275 | 1,013 |
| 2025-12 | 13,609 | 13,020 |

这些 PLATFORM_ONLY 不是全量表快照，而是 supplier_id=2275/product_id/date-window 限定后的 cycle_history lifecycle 行，再按 imsi + Excel cycle/final 窗口排除。

按 source_match_status 的 Excel amount impact：

- 2025-09：UNRESOLVED 12,780 行，Excel amount=772,201.40；MISSING_MAPPING 12,457 行，Excel amount=367,192.12。
- 2025-10 (v1) detail：UNRESOLVED 12,605 行，Excel amount=770,386.00；MISSING_MAPPING 72 行，Excel amount=2,364.53；另有 Credit WA_ONLY=-465.00。
- 2025-10 (v2)：UNRESOLVED 11,682 行，Excel amount=713,991.00；MISSING_MAPPING 981 行，Excel amount=59,746.84。

## 7. 未解决问题和下一步

| 问题 | 影响 | 当前证据 | 下一步 |
|---|---|---|---|
| Excel 没有 product_id | 正式 source_match_status 不能进入 MATCHED；只能 MISSING_MAPPING 或 numeric exact 辅助状态 | detail schema 只有 product_name，没有 product_id；平台 product_id/price 已独立输出 | 提供可信的 Excel 行到 platform product_id 映射，且按 billing month/effective condition 验证 |
| 多个 platform cycle 与同一 Excel 窗口 overlap | 2025-09 Full Rate、v1/v2 Full Cycle 大量 UNRESOLVED；不能任意挑一个 | Candidate SQL 保留 platform_candidate_count，按 exact cycle 优先、最大 overlap 排序，多候选仍 unresolved | 用已确认的核心/换卡/生命周期事件定义唯一 cycle tie-breaker；当前不编造 replacement/transfer/Simbank 规则 |
| 2025-09 sim_status snapshot 分区 AccessDenied | 2025-09 snapshot 状态事实缺失 | 本次只读探针直接返回底层 parquet AccessDenied；未绕过 | 恢复该分区读取权限或提供等价只读快照 |
| Credit for Offstocked Card | v1 37 行 -465.00 无 final window；不能从普通周期 lifecycle 复算 | WA detail 保留负数；候选标 R_CREDIT_REQUIRES_CREDIT_EVIDENCE、WA_ONLY | 以独立 wa_invoice_credit.credit_owed + offstock/status 证据复核，不加回 detail |
| v2 文件名是 OCT 2025、观察到 final_start 为 2025-11 | 不能将官方金额改标为 2025-11 | strict source_file CASE=2025-10 (v2)，observed_start_month=2025-11 | 审查时同时保留两个字段，不重写官方月份 |
| 金额 residual | Excel truth 不变；平台 candidate 只作为解释/复现候选 | 已输出 amount_diff 与按状态 impact；未做补差 | 先解决唯一周期和 product_id 映射，再重新验证 |

当前没有 MISSING_DATA 的 detail 行级状态；但 2025-09 status snapshot 的 source-level 访问缺口必须保留，不能被解读为平台数据完整。

## 8. 可审查证据和 SQL 文件

所有下列文件均位于独立目录 recon/agent_runs/A：

- platform_billing_A_01_schema_probe.sql / .tsv：平台表字段探针。
- platform_billing_A_03_target_products.sql / .tsv：supplier_id=2275 的 product_id、产品名、价格字段。
- platform_billing_A_04_cycle_scope_probe.sql / .tsv：限定 supplier/product/date-window 的 cycle_history scope。
- platform_billing_A_05_excel_detail_scope.sql / .tsv：detail Excel source_file/charge_type/price/amount 真值分层。
- platform_billing_A_06_status_scope_20251011.sql / .tsv：可读的 2025-10/11 status snapshot scope。
- platform_billing_A_08_status_log_probe.sql / .tsv：限定 platform card IMSI 的 status_log 可读性。
- platform_billing_A_09_candidate_billing.sql：完整逐行 Candidate Billing SQL；全部 CTE 已定义，结果字段完整。
- platform_billing_A_10_reconciliation_summary.sql / .tsv：完整 CTE 的 status、amount、days/price/amount 分层及 PLATFORM_ONLY 汇总。
- platform_billing_A_15_reconciliation_month_summary.sql / .tsv：月份级 Excel total、platform calculated total、amount_diff 和命中率。
- platform_billing_A_16_candidate_explain.sql / .tsv：Candidate Billing 完整 CTE 的 EXPLAIN；只读成功。
- platform_billing_A_11_join_diagnostics.sql / .tsv：IMSI、exact cycle、final-window overlap 三层诊断。
- platform_billing_A_13_mismatch_samples.sql / .tsv：500 条最新 mismatch 样本。

逐行 Candidate SQL 在 INLINE 返回时超过 25 MiB 载荷上限；这不是 SQL 写入或解析失败。完整语句已通过 EXPLAIN，汇总 Reconciliation SQL 已实际只读执行成功。

## 9. 只读审计门槛

本轮执行的 SQL 在本地逐条预检：

- 首语句仅为 SELECT/WITH/EXPLAIN。
- FORBIDDEN 写入词为空。
- 未执行 CREATE TABLE/VIEW、TEMP VIEW、INSERT、UPDATE、DELETE、MERGE、TRUNCATE、COPY INTO、ALTER、DROP、REPLACE、OPTIMIZE、VACUUM、ANALYZE、GRANT、REVOKE。
- 未运行 notebook 写入步骤。
- 本地输出仅写入 recon/agent_runs/A。
