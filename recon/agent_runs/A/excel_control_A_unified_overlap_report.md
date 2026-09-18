# Batch A unified detail/prorated overlap review

本次结果只来自当前 simo_cdc 连接上的只读 SQL。没有引用其他代理结论，没有修改平台、Excel 或旧参考文件。

## 统一标准化规则

- 字符串字段：CAST AS STRING 后 TRIM，空字符串转 NULL。
- 日期字段：统一 TO_DATE。
- 金额/价格/天数字段：统一 TRY_CAST AS DECIMAL(38,12)。
- detail 与 prorated 的公共字段映射：

| detail | prorated | 语义判断 |
|---|---|---|
| imsi | imsi | 同一卡标识 |
| source_file | source_file | 文件来源标识 |
| product_name | product_name | 产品名称字段 |
| cycle_start_date | cycle_start_date | 周期开始日期 |
| cycle_end_date | cycle_end_date | 周期结束日期 |
| final_start_date | final_start_date | 最终计费开始日期 |
| final_end_date | final_end_date | 最终计费结束日期 |
| monthly_rate | monthly_rate | 月价字段，可比较 |
| final_charge | final_charge_for_usage_days | 不同金额语义，不可视为同一金额 |
| final_days | usage_days | 不同天数字段，不纳入公共 exact key |
| 无直接对应字段 | pending_charge | prorated 辅助金额，不纳入公共 exact key |
| charge_type | 无直接对应字段 | detail 独有，不纳入公共 exact key |

采用的完整 key：

1. IMSI overlap：trim(imsi)。
2. COMMON_FIELDS_EXACT：trim(source_file) + trim(imsi) + trim(product_name) + TO_DATE(cycle_start) + TO_DATE(cycle_end) + TO_DATE(final_start) + TO_DATE(final_end) + DECIMAL(monthly_rate)。
3. SOURCE_IMSI_CYCLE_EXACT：trim(source_file) + trim(imsi) + TO_DATE(cycle_start) + TO_DATE(cycle_end)。
4. SOURCE_IMSI_CYCLE_FINAL_EXACT：trim(source_file) + trim(imsi) + TO_DATE(cycle_start) + TO_DATE(cycle_end) + TO_DATE(final_start) + TO_DATE(final_end)。

## 统一 overlap 结果

| overlap_type | key_fields | shared_key_count | detail_rows | prorated_rows | one_to_one | non_one_to_one | detail_amount | prorated_amount | pending_amount |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| COMMON_FIELDS_EXACT_OVERLAP | source_file/imsi/product_name/cycle_start/cycle_end/final_start/final_end/monthly_rate | 0 |  |  |  |  |  |  |  |
| IMSI_OVERLAP | imsi | 828 | 5494 | 828 | 0 | 828 | 264,158.819728 | 30,619.75867 | 7,195.895829 |
| SOURCE_IMSI_CYCLE_EXACT_OVERLAP | source_file/imsi/cycle_start/cycle_end | 0 |  |  |  |  |  |  |  |
| SOURCE_IMSI_CYCLE_FINAL_EXACT_OVERLAP | source_file/imsi/cycle_start/cycle_end/final_start/final_end | 0 |  |  |  |  |  |  |  |

结论：IMSI overlap 为 828，但三个更严格的 exact key 均为 0。也就是说，不能按 IMSI 去重或把两表当成重复账单行。IMSI overlap 只说明同一卡在两个来源中出现过。

## 20 个 IMSI overlap 样例

样例查询按每个共享 IMSI 各取一条 detail 和一条 prorated 记录；因为严格 cycle/full key overlap 为 0，这些是 IMSI-only 样例，不是 exact-key 配对。

| # | imsi | detail source_file | prorated source_file | detail cycle | prorated cycle | detail final window | prorated final window | detail amount | prorated amount | pending | source equal | cycle equal | final equal | classification |
|---:|---|---|---|---|---|---|---|---:|---:|---:|---|---|---|---|
| 1 | 083901143008430841 | 01-SIMO Data Purchase Invoice Details - APR 2026.xlsx | 01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx | 2026-04-04 to 2026-05-03 | 2026-02-04 to 2026-03-03 | 2026-04-04 to 2026-05-03 | 2026-02-19 to 2026-03-03 | 43 | 27.642857 | 6.142857 | DIFFERENT | DIFFERENT | DIFFERENT | IMSI_ONLY_OVERLAP_DIFFERENT_RECORD_CONTEXT |
| 2 | 083901143008438757 | 01-SIMO Data Purchase Invoice Details - APR 2026.xlsx | 01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx | 2026-04-04 to 2026-05-03 | 2026-02-04 to 2026-03-03 | 2026-04-04 to 2026-05-03 | 2026-02-19 to 2026-03-03 | 43 | 33.785714 | 7.675714 | DIFFERENT | DIFFERENT | DIFFERENT | IMSI_ONLY_OVERLAP_DIFFERENT_RECORD_CONTEXT |
| 3 | 083901143008439712 | 01-SIMO Data Purchase Invoice Details - APR 2026.xlsx | 01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx | 2026-04-04 to 2026-05-03 | 2026-02-04 to 2026-03-03 | 2026-04-04 to 2026-05-03 | 2026-02-19 to 2026-03-03 | 43 | 27.642857 | 1.532857 | DIFFERENT | DIFFERENT | DIFFERENT | IMSI_ONLY_OVERLAP_DIFFERENT_RECORD_CONTEXT |
| 4 | 083901143008439722 | 01-SIMO Data Purchase Invoice Details - APR 2026.xlsx | 01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx | 2026-04-04 to 2026-05-03 | 2026-02-04 to 2026-03-03 | 2026-04-04 to 2026-05-03 | 2026-02-19 to 2026-03-03 | 43 | 43 | 13.82 | DIFFERENT | DIFFERENT | DIFFERENT | IMSI_ONLY_OVERLAP_DIFFERENT_RECORD_CONTEXT |
| 5 | 083901143008439731 | 01-SIMO Data Purchase Invoice Details - APR 2026.xlsx | 01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx | 2026-04-04 to 2026-05-03 | 2026-02-04 to 2026-03-03 | 2026-04-04 to 2026-05-03 | 2026-02-19 to 2026-03-03 | 43 | 36.857143 | 3.067143 | DIFFERENT | DIFFERENT | DIFFERENT | IMSI_ONLY_OVERLAP_DIFFERENT_RECORD_CONTEXT |
| 6 | 083901143008439741 | 01-SIMO Data Purchase Invoice Details - APR 2026.xlsx | 01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx | 2026-04-04 to 2026-05-03 | 2026-02-04 to 2026-03-03 | 2026-04-04 to 2026-05-03 | 2026-02-19 to 2026-03-03 | 43 | 21.5 | 1.54 | DIFFERENT | DIFFERENT | DIFFERENT | IMSI_ONLY_OVERLAP_DIFFERENT_RECORD_CONTEXT |
| 7 | 083901144006265895 | 01-SIMO Data Purchase Invoice Details - JULY 2026.xlsx | SIMO Data Purchase Invoice Details - AUGUST 2026.xlsx | 2026-07-04 to 2026-08-03 | 2026-07-04 to 2026-08-03 | 2026-07-06 to 2026-08-03 | 2026-07-06 to 2026-08-03 | 41.612903 | 43 | 1.39 | DIFFERENT | EQUAL | EQUAL | IMSI_ONLY_OVERLAP_DIFFERENT_RECORD_CONTEXT |
| 8 | 083901144006950406 | 01-SIMO Data Purchase Invoice Details - JULY 2026.xlsx | SIMO Data Purchase Invoice Details - AUGUST 2026.xlsx | 2026-07-04 to 2026-08-03 | 2026-07-04 to 2026-08-03 | 2026-07-06 to 2026-08-03 | 2026-07-06 to 2026-08-03 | 41.612903 | 43 | 1.39 | DIFFERENT | EQUAL | EQUAL | IMSI_ONLY_OVERLAP_DIFFERENT_RECORD_CONTEXT |
| 9 | 083901144012174367 | 01-SIMO Data Purchase Invoice Details - APR 2026.xlsx | 01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx | 2026-04-04 to 2026-05-03 | 2026-02-04 to 2026-03-03 | 2026-04-04 to 2026-05-03 | 2026-02-24 to 2026-03-03 | 43 | 15.357143 | 3.067143 | DIFFERENT | DIFFERENT | DIFFERENT | IMSI_ONLY_OVERLAP_DIFFERENT_RECORD_CONTEXT |
| 10 | 083901144025199730 | 01-SIMO Data Purchase Invoice Details - JULY 2026.xlsx | SIMO Data Purchase Invoice Details - AUGUST 2026.xlsx | 2026-07-04 to 2026-08-03 | 2026-07-04 to 2026-08-03 | 2026-07-06 to 2026-08-03 | 2026-07-06 to 2026-08-03 | 40.225806 | 41.612903 | 1.382903 | DIFFERENT | EQUAL | EQUAL | IMSI_ONLY_OVERLAP_DIFFERENT_RECORD_CONTEXT |
| 11 | 083901144045426123 | 01-SIMO Data Purchase Invoice Details - APR 2026.xlsx | 01-SIMO Data Purchase Invoice Details - MAY 2026.xlsx | 2026-04-02 to 2026-05-01 | 2026-04-02 to 2026-05-01 | 2026-04-20 to 2026-05-01 | 2026-04-20 to 2026-05-01 | 28.933333 | 31 | 2.07 | DIFFERENT | EQUAL | EQUAL | IMSI_ONLY_OVERLAP_DIFFERENT_RECORD_CONTEXT |
| 12 | 083901144052166453 | 01-SIMO Data Purchase Invoice Details - APR 2026.xlsx | 01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx | 2026-04-04 to 2026-05-03 | 2026-02-04 to 2026-03-03 | 2026-04-04 to 2026-05-03 | 2026-02-24 to 2026-03-03 | 43 | 32.25 | 3.07 | DIFFERENT | DIFFERENT | DIFFERENT | IMSI_ONLY_OVERLAP_DIFFERENT_RECORD_CONTEXT |
| 13 | 083901144055160839 | 01-1-INVOICE_FROM_ WA_USD_773,793.84_SIMO Data Purchase Invoice Details - OCT 2025.xlsx | 01-1-INVOICE_FROM_ WA_USD_773,793.84_SIMO Data Purchase Invoice Details - OCT 2025.xlsx | 2025-11-16 to 2025-12-15 | 2025-10-16 to 2025-11-15 | 2025-11-16 to 2025-12-15 | 2025-10-24 to 2025-11-15 | 62 | 62 | 16 | EQUAL | DIFFERENT | DIFFERENT | IMSI_ONLY_OVERLAP_DIFFERENT_RECORD_CONTEXT |
| 14 | 083901144055264931 | 01-1-INVOICE_FROM_ WA_USD_773,793.84_SIMO Data Purchase Invoice Details - OCT 2025.xlsx | 01-1-INVOICE_FROM_ WA_USD_773,793.84_SIMO Data Purchase Invoice Details - OCT 2025.xlsx | 2025-11-16 to 2025-12-15 | 2025-10-16 to 2025-11-15 | 2025-11-16 to 2025-12-15 | 2025-10-24 to 2025-11-15 | 62 | 54 | 8 | EQUAL | DIFFERENT | DIFFERENT | IMSI_ONLY_OVERLAP_DIFFERENT_RECORD_CONTEXT |
| 15 | 083901144055269476 | 01-1-INVOICE_FROM_ WA_USD_773,793.84_SIMO Data Purchase Invoice Details - OCT 2025.xlsx | 01-1-INVOICE_FROM_ WA_USD_773,793.84_SIMO Data Purchase Invoice Details - OCT 2025.xlsx | 2025-11-16 to 2025-12-15 | 2025-10-16 to 2025-11-15 | 2025-11-16 to 2025-12-15 | 2025-10-24 to 2025-11-15 | 62 | 54 | 8 | EQUAL | DIFFERENT | DIFFERENT | IMSI_ONLY_OVERLAP_DIFFERENT_RECORD_CONTEXT |
| 16 | 083901144055858410 | 01-1-INVOICE_FROM_ WA_USD_773,793.84_SIMO Data Purchase Invoice Details - OCT 2025.xlsx | 01-1-INVOICE_FROM_ WA_USD_773,793.84_SIMO Data Purchase Invoice Details - OCT 2025.xlsx | 2025-11-16 to 2025-12-15 | 2025-10-16 to 2025-11-15 | 2025-11-16 to 2025-12-15 | 2025-10-24 to 2025-11-15 | 62 | 62 | 16 | EQUAL | DIFFERENT | DIFFERENT | IMSI_ONLY_OVERLAP_DIFFERENT_RECORD_CONTEXT |
| 17 | 083901144055958464 | 01-1-INVOICE_FROM_ WA_USD_773,793.84_SIMO Data Purchase Invoice Details - OCT 2025.xlsx | 01-1-INVOICE_FROM_ WA_USD_773,793.84_SIMO Data Purchase Invoice Details - OCT 2025.xlsx | 2025-11-16 to 2025-12-15 | 2025-10-16 to 2025-11-15 | 2025-11-16 to 2025-12-15 | 2025-10-24 to 2025-11-15 | 62 | 62 | 8 | EQUAL | DIFFERENT | DIFFERENT | IMSI_ONLY_OVERLAP_DIFFERENT_RECORD_CONTEXT |
| 18 | 083901144064110679 | 01-SIMO Data Purchase Invoice Details - APR 2026.xlsx | 01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx | 2026-04-04 to 2026-05-03 | 2026-02-04 to 2026-03-03 | 2026-04-04 to 2026-05-03 | 2026-02-24 to 2026-03-03 | 43 | 21.5 | 4.61 | DIFFERENT | DIFFERENT | DIFFERENT | IMSI_ONLY_OVERLAP_DIFFERENT_RECORD_CONTEXT |
| 19 | 083901144064110695 | 01-SIMO Data Purchase Invoice Details - APR 2026.xlsx | 01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx | 2026-04-04 to 2026-05-03 | 2026-02-04 to 2026-03-03 | 2026-04-04 to 2026-05-03 | 2026-02-24 to 2026-03-03 | 43 | 15.357143 | 3.067143 | DIFFERENT | DIFFERENT | DIFFERENT | IMSI_ONLY_OVERLAP_DIFFERENT_RECORD_CONTEXT |
| 20 | 083901144064111762 | 01-SIMO Data Purchase Invoice Details - APR 2026.xlsx | 01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx | 2026-04-04 to 2026-05-03 | 2026-02-04 to 2026-03-03 | 2026-04-04 to 2026-05-03 | 2026-02-24 to 2026-03-03 | 43 | 24.571429 | 12.281429 | DIFFERENT | DIFFERENT | DIFFERENT | IMSI_ONLY_OVERLAP_DIFFERENT_RECORD_CONTEXT |

样例中的 detail final_charge 与 prorated final_charge_for_usage_days/pending_charge 处于不同字段语义；即使 source_file 相同，周期窗口仍可能不同。因此当前证据支持“同一业务卡的辅助/不同记录上下文”，不支持“重复账单行”。

## detail 内部 191 个重复键

191 个键对应统一定义：trim(imsi) + trim(source_file) + TO_DATE(cycle_start_date) + TO_DATE(cycle_end_date) + trim(charge_type)。每个键正好 2 行，共 382 行，额外行数 191。

| duplicate_classification | duplicate_key_count | duplicate_row_count | extra_rows | max_rows_per_key | amount_sum | exact_duplicate_keys | different_field_keys |
|---|---:|---:|---:|---:|---:|---:|---:|
| MULTIPLE_DETAIL_ROWS_SAME_CYCLE_CHARGE_TYPE_DIFFERENT_FIELDS | 191 | 382 | 191 | 2 | 10,358.451612 | 0 | 191 |

总体结果：191/191 个重复键的非键字段指纹不同，0 个是所有被比较字段完全相同的重复行。样例显示主要为 Partial Charge - Product Transfer Mid Cycle，final_start/final_end、days、price 或 final_charge 等字段存在差异。

因此当前对账应保留多行，不得按这 191 个键自动 dedupe。没有可依赖的声明约束/主键结果，必须等待明确的业务事件键或换卡/transfer 规则后再决定是否折叠。

| # | imsi | source_file | cycle window | charge_type | rows | distinct fingerprints | distinct final dates | distinct days | distinct price | distinct amount | classification |
|---:|---|---|---|---|---:|---:|---|---:|---:|---:|---|
| 1 | 083901144035616472 | 01-SIMO Data Purchase Invoice Details - JAN 2025.xlsx | 2026-01-05 to 2026-02-04 | Partial Charge - Product Transfer Mid Cycle | 2 | 2 | 2/2 | 2 | 2 | 2 | MULTIPLE_DETAIL_ROWS_SAME_CYCLE_CHARGE_TYPE_DIFFERENT_FIELDS |
| 2 | 083901516060070015 | 01-SIMO Data Purchase Invoice Details - JAN 2025.xlsx | 2026-01-23 to 2026-02-22 | Partial Charge - Product Transfer Mid Cycle | 2 | 2 | 2/2 | 2 | 2 | 2 | MULTIPLE_DETAIL_ROWS_SAME_CYCLE_CHARGE_TYPE_DIFFERENT_FIELDS |
| 3 | 083901516060074992 | 01-SIMO Data Purchase Invoice Details - JAN 2025.xlsx | 2026-01-26 to 2026-02-25 | Partial Charge - Product Transfer Mid Cycle | 2 | 2 | 2/2 | 2 | 2 | 2 | MULTIPLE_DETAIL_ROWS_SAME_CYCLE_CHARGE_TYPE_DIFFERENT_FIELDS |
| 4 | 083901516060080836 | 01-SIMO Data Purchase Invoice Details - JAN 2025.xlsx | 2026-01-20 to 2026-02-19 | Partial Charge - Product Transfer Mid Cycle | 2 | 2 | 2/2 | 2 | 2 | 2 | MULTIPLE_DETAIL_ROWS_SAME_CYCLE_CHARGE_TYPE_DIFFERENT_FIELDS |
| 5 | 083901516060083965 | 01-SIMO Data Purchase Invoice Details - JAN 2025.xlsx | 2026-01-20 to 2026-02-19 | Partial Charge - Product Transfer Mid Cycle | 2 | 2 | 2/2 | 1 | 2 | 2 | MULTIPLE_DETAIL_ROWS_SAME_CYCLE_CHARGE_TYPE_DIFFERENT_FIELDS |
| 6 | 083901516060090103 | 01-SIMO Data Purchase Invoice Details - JAN 2025.xlsx | 2026-01-09 to 2026-02-08 | Partial Charge - Product Transfer Mid Cycle | 2 | 2 | 2/2 | 2 | 2 | 2 | MULTIPLE_DETAIL_ROWS_SAME_CYCLE_CHARGE_TYPE_DIFFERENT_FIELDS |
| 7 | 083901516060090352 | 01-SIMO Data Purchase Invoice Details - JAN 2025.xlsx | 2026-01-19 to 2026-02-18 | Partial Charge - Product Transfer Mid Cycle | 2 | 2 | 2/2 | 2 | 2 | 2 | MULTIPLE_DETAIL_ROWS_SAME_CYCLE_CHARGE_TYPE_DIFFERENT_FIELDS |
| 8 | 083901516060095584 | 01-SIMO Data Purchase Invoice Details - JAN 2025.xlsx | 2026-01-19 to 2026-02-18 | Partial Charge - Product Transfer Mid Cycle | 2 | 2 | 2/2 | 2 | 2 | 2 | MULTIPLE_DETAIL_ROWS_SAME_CYCLE_CHARGE_TYPE_DIFFERENT_FIELDS |
| 9 | 083901516060095798 | 01-SIMO Data Purchase Invoice Details - JAN 2025.xlsx | 2026-01-09 to 2026-02-08 | Partial Charge - Product Transfer Mid Cycle | 2 | 2 | 2/2 | 2 | 2 | 2 | MULTIPLE_DETAIL_ROWS_SAME_CYCLE_CHARGE_TYPE_DIFFERENT_FIELDS |
| 10 | 083901516060095928 | 01-SIMO Data Purchase Invoice Details - JAN 2025.xlsx | 2026-01-04 to 2026-02-03 | Partial Charge - Product Transfer Mid Cycle | 2 | 2 | 2/2 | 2 | 2 | 2 | MULTIPLE_DETAIL_ROWS_SAME_CYCLE_CHARGE_TYPE_DIFFERENT_FIELDS |
| 11 | 083901516060096255 | 01-SIMO Data Purchase Invoice Details - JAN 2025.xlsx | 2026-01-02 to 2026-02-01 | Partial Charge - Product Transfer Mid Cycle | 2 | 2 | 2/2 | 2 | 2 | 2 | MULTIPLE_DETAIL_ROWS_SAME_CYCLE_CHARGE_TYPE_DIFFERENT_FIELDS |
| 12 | 083901516060098613 | 01-SIMO Data Purchase Invoice Details - JAN 2025.xlsx | 2026-01-06 to 2026-02-05 | Partial Charge - Product Transfer Mid Cycle | 2 | 2 | 2/2 | 2 | 2 | 2 | MULTIPLE_DETAIL_ROWS_SAME_CYCLE_CHARGE_TYPE_DIFFERENT_FIELDS |
| 13 | 083901516060098620 | 01-SIMO Data Purchase Invoice Details - JAN 2025.xlsx | 2026-01-03 to 2026-02-02 | Partial Charge - Product Transfer Mid Cycle | 2 | 2 | 2/2 | 2 | 2 | 2 | MULTIPLE_DETAIL_ROWS_SAME_CYCLE_CHARGE_TYPE_DIFFERENT_FIELDS |
| 14 | 083901516060171201 | 01-SIMO Data Purchase Invoice Details - JAN 2025.xlsx | 2026-01-23 to 2026-02-22 | Partial Charge - Product Transfer Mid Cycle | 2 | 2 | 2/2 | 2 | 2 | 2 | MULTIPLE_DETAIL_ROWS_SAME_CYCLE_CHARGE_TYPE_DIFFERENT_FIELDS |
| 15 | 083901516060176289 | 01-SIMO Data Purchase Invoice Details - JAN 2025.xlsx | 2026-01-26 to 2026-02-25 | Partial Charge - Product Transfer Mid Cycle | 2 | 2 | 2/2 | 2 | 2 | 2 | MULTIPLE_DETAIL_ROWS_SAME_CYCLE_CHARGE_TYPE_DIFFERENT_FIELDS |
| 16 | 083901516060176723 | 01-SIMO Data Purchase Invoice Details - JAN 2025.xlsx | 2026-01-23 to 2026-02-22 | Partial Charge - Product Transfer Mid Cycle | 2 | 2 | 2/2 | 2 | 2 | 2 | MULTIPLE_DETAIL_ROWS_SAME_CYCLE_CHARGE_TYPE_DIFFERENT_FIELDS |
| 17 | 083901516060190862 | 01-SIMO Data Purchase Invoice Details - JAN 2025.xlsx | 2026-01-09 to 2026-02-08 | Partial Charge - Product Transfer Mid Cycle | 2 | 2 | 2/2 | 2 | 2 | 2 | MULTIPLE_DETAIL_ROWS_SAME_CYCLE_CHARGE_TYPE_DIFFERENT_FIELDS |
| 18 | 083901516060191296 | 01-SIMO Data Purchase Invoice Details - JAN 2025.xlsx | 2026-01-06 to 2026-02-05 | Partial Charge - Product Transfer Mid Cycle | 2 | 2 | 2/2 | 2 | 2 | 2 | MULTIPLE_DETAIL_ROWS_SAME_CYCLE_CHARGE_TYPE_DIFFERENT_FIELDS |
| 19 | 083901516060192182 | 01-SIMO Data Purchase Invoice Details - JAN 2025.xlsx | 2026-01-03 to 2026-02-02 | Partial Charge - Product Transfer Mid Cycle | 2 | 2 | 2/2 | 2 | 2 | 2 | MULTIPLE_DETAIL_ROWS_SAME_CYCLE_CHARGE_TYPE_DIFFERENT_FIELDS |
| 20 | 083901516060192769 | 01-SIMO Data Purchase Invoice Details - JAN 2025.xlsx | 2026-01-03 to 2026-02-02 | Partial Charge - Product Transfer Mid Cycle | 2 | 2 | 2/2 | 2 | 2 | 2 | MULTIPLE_DETAIL_ROWS_SAME_CYCLE_CHARGE_TYPE_DIFFERENT_FIELDS |

## 控制结论

- detail/prorated overlap 现在已用完全相同的标准化键重算，结果一致：828 个 IMSI overlap，严格 exact overlap 全部为 0。
- 不能以 IMSI 作为去重键，也不能把 detail.final_charge 与 prorated.final_charge_for_usage_days 或 pending_charge 相加后当作自动补差。
- Excel control 仍不能标记为通过；至少需要主代理确认 191 个 detail 多行的业务事件语义，以及是否允许进入后续卡级 reconciliation。

只读 SQL 与结果：

- excel_control_A_11_unified_overlap_metrics.sql / .tsv
- excel_control_A_12_overlap_samples.sql / .tsv
- excel_control_A_13_detail_duplicate_samples.sql / .tsv
- excel_control_A_14_detail_duplicate_summary.sql / .tsv
- excel_control_A_15_detail_constraints.sql / .tsv
