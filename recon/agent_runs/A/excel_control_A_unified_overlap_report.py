import csv
import os

OUT = r"C:\Users\EDY\Desktop\对账notebook\recon\agent_runs\A"
def rows(name):
    with open(os.path.join(OUT,name),encoding="utf-8-sig",newline="") as f:
        return list(csv.DictReader(f,delimiter="\t"))
def m(v):
    return str(v or "").replace("|","/").replace("\r"," ").replace("\n"," ")
def f(v):
    if v in (None,""):
        return ""
    try:
        return f"{float(v):,.6f}".rstrip("0").rstrip(".")
    except Exception:
        return str(v)

metrics=rows("excel_control_A_11_unified_overlap_metrics.tsv")
samples=rows("excel_control_A_12_overlap_samples.tsv")
dups=rows("excel_control_A_13_detail_duplicate_samples.tsv")
dupsummary=rows("excel_control_A_14_detail_duplicate_summary.tsv")
constraints=rows("excel_control_A_15_detail_constraints.tsv")

lines = []
lines += [
"# Batch A unified detail/prorated overlap review",
"",
"本次结果只来自当前 simo_cdc 连接上的只读 SQL。没有引用其他代理结论，没有修改平台、Excel 或旧参考文件。",
"",
"## 统一标准化规则",
"",
"- 字符串字段：CAST AS STRING 后 TRIM，空字符串转 NULL。",
"- 日期字段：统一 TO_DATE。",
"- 金额/价格/天数字段：统一 TRY_CAST AS DECIMAL(38,12)。",
"- detail 与 prorated 的公共字段映射：",
"",
"| detail | prorated | 语义判断 |",
"|---|---|---|",
"| imsi | imsi | 同一卡标识 |",
"| source_file | source_file | 文件来源标识 |",
"| product_name | product_name | 产品名称字段 |",
"| cycle_start_date | cycle_start_date | 周期开始日期 |",
"| cycle_end_date | cycle_end_date | 周期结束日期 |",
"| final_start_date | final_start_date | 最终计费开始日期 |",
"| final_end_date | final_end_date | 最终计费结束日期 |",
"| monthly_rate | monthly_rate | 月价字段，可比较 |",
"| final_charge | final_charge_for_usage_days | 不同金额语义，不可视为同一金额 |",
"| final_days | usage_days | 不同天数字段，不纳入公共 exact key |",
"| 无直接对应字段 | pending_charge | prorated 辅助金额，不纳入公共 exact key |",
"| charge_type | 无直接对应字段 | detail 独有，不纳入公共 exact key |",
"",
"采用的完整 key：",
"",
"1. IMSI overlap：trim(imsi)。",
"2. COMMON_FIELDS_EXACT：trim(source_file) + trim(imsi) + trim(product_name) + TO_DATE(cycle_start) + TO_DATE(cycle_end) + TO_DATE(final_start) + TO_DATE(final_end) + DECIMAL(monthly_rate)。",
"3. SOURCE_IMSI_CYCLE_EXACT：trim(source_file) + trim(imsi) + TO_DATE(cycle_start) + TO_DATE(cycle_end)。",
"4. SOURCE_IMSI_CYCLE_FINAL_EXACT：trim(source_file) + trim(imsi) + TO_DATE(cycle_start) + TO_DATE(cycle_end) + TO_DATE(final_start) + TO_DATE(final_end)。",
"",
"## 统一 overlap 结果",
"",
"| overlap_type | key_fields | shared_key_count | detail_rows | prorated_rows | one_to_one | non_one_to_one | detail_amount | prorated_amount | pending_amount |",
"|---|---|---:|---:|---:|---:|---:|---:|---:|---:|"
]
for r in metrics:
    lines.append("| " + " | ".join([
        m(r["overlap_type"]), m(r["key_fields"]), r["shared_key_count"], r["detail_rows_on_shared_keys"],
        r["prorated_rows_on_shared_keys"], r["one_to_one_key_count"], r["non_one_to_one_key_count"],
        f(r["detail_amount_on_shared_keys"]), f(r["prorated_amount_on_shared_keys"]), f(r["prorated_pending_on_shared_keys"])
    ]) + " |")
lines += [
"",
"结论：IMSI overlap 为 828，但四个更严格的 exact key 均为 0。也就是说，不能按 IMSI 去重或把两表当成重复账单行。IMSI overlap 只说明同一卡在两个来源中出现过。",
"",
"## 20 个 IMSI overlap 样例",
"",
"样例查询按每个共享 IMSI 各取一条 detail 和一条 prorated 记录；因为严格 cycle/full key overlap 为 0，这些是 IMSI-only 样例，不是 exact-key 配对。",
"",
"| # | imsi | detail source_file | prorated source_file | detail cycle | prorated cycle | detail final window | prorated final window | detail amount | prorated amount | pending | source equal | cycle equal | final equal | classification |",
"|---:|---|---|---|---|---|---|---|---:|---:|---:|---|---|---|---|"
]
for r in samples:
    dc = str(r["detail_cycle_start"]) + " to " + str(r["detail_cycle_end"])
    pc = str(r["prorated_cycle_start"]) + " to " + str(r["prorated_cycle_end"])
    dfw = str(r["detail_final_start"]) + " to " + str(r["detail_final_end"])
    pfw = str(r["prorated_final_start"]) + " to " + str(r["prorated_final_end"])
    lines.append("| " + " | ".join([
        r["sample_no"], m(r["imsi"]), m(r["detail_source_file"]), m(r["prorated_source_file"]),
        dc, pc, dfw, pfw, f(r["detail_final_charge"]), f(r["prorated_final_charge_for_usage_days"]),
        f(r["prorated_pending_charge"]), r["source_file_equal"], r["cycle_window_equal"],
        r["final_window_equal"], m(r["record_context_classification"])
    ]) + " |")
lines += [
"",
"样例中的 detail final_charge 与 prorated final_charge_for_usage_days/pending_charge 处于不同字段语义；即使 source_file 相同，周期窗口仍可能不同。因此当前证据支持“同一业务卡的辅助/不同记录上下文”，不支持“重复账单行”。",
"",
"## detail 内部 191 个重复键",
"",
"191 个键对应统一定义：trim(imsi) + trim(source_file) + TO_DATE(cycle_start_date) + TO_DATE(cycle_end_date) + trim(charge_type)。每个键正好 2 行，共 382 行，额外行数 191。",
"",
"| duplicate_classification | duplicate_key_count | duplicate_row_count | extra_rows | max_rows_per_key | amount_sum | exact_duplicate_keys | different_field_keys |",
"|---|---:|---:|---:|---:|---:|---:|---:|"
]
for r in dupsummary:
    lines.append("| " + " | ".join([
        m(r["duplicate_classification"]), r["duplicate_key_count"], r["duplicate_row_count"],
        r["duplicate_extra_row_count"], r["max_rows_per_key"], f(r["amount_sum_on_duplicate_groups"]),
        r["exact_duplicate_key_count"], r["different_field_key_count"]
    ]) + " |")
lines += [
"",
"总体结果：191/191 个重复键的非键字段指纹不同，0 个是所有被比较字段完全相同的重复行。样例显示主要为 Partial Charge - Product Transfer Mid Cycle，final_start/final_end、days、price 或 final_charge 等字段存在差异。",
"",
"因此当前对账应保留多行，不得按这 191 个键自动 dedupe。没有可依赖的声明约束/主键结果，必须等待明确的业务事件键或换卡/transfer 规则后再决定是否折叠。",
"",
"| # | imsi | source_file | cycle window | charge_type | rows | distinct fingerprints | distinct final dates | distinct days | distinct price | distinct amount | classification |",
"|---:|---|---|---|---|---:|---:|---|---:|---:|---:|---|"
]
for r in dups:
    dates = str(r["distinct_final_start_count"]) + "/" + str(r["distinct_final_end_count"])
    lines.append("| " + " | ".join([
        r["sample_no"], m(r["imsi_std"]), m(r["source_file_std"]),
        str(r["cycle_start_std"]) + " to " + str(r["cycle_end_std"]), m(r["charge_type_std"]),
        r["duplicate_row_count"], r["distinct_non_key_fingerprint_count"], dates,
        r["distinct_final_days_count"], r["distinct_monthly_rate_count"],
        r["distinct_final_amount_count"], m(r["duplicate_classification"])
    ]) + " |")
lines += [
"",
"## 控制结论",
"",
"- detail/prorated overlap 现在已用完全相同的标准化键重算，结果一致：828 个 IMSI overlap，严格 exact overlap 全部为 0。",
"- 不能以 IMSI 作为去重键，也不能把 detail.final_charge 与 prorated.final_charge_for_usage_days 或 pending_charge 相加后当作自动补差。",
"- Excel control 仍不能标记为通过；至少需要主代理确认 191 个 detail 多行的业务事件语义，以及是否允许进入后续卡级 reconciliation。",
"",
"只读 SQL 与结果：",
"",
"- excel_control_A_11_unified_overlap_metrics.sql / .tsv",
"- excel_control_A_12_overlap_samples.sql / .tsv",
"- excel_control_A_13_detail_duplicate_samples.sql / .tsv",
"- excel_control_A_14_detail_duplicate_summary.sql / .tsv",
"- excel_control_A_15_detail_constraints.sql / .tsv"
]
with open(os.path.join(OUT,"excel_control_A_unified_overlap_report.md"),"w",encoding="utf-8") as f:
    f.write("\n".join(lines))

