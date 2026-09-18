# 批次 A：本地参考文件清单（仅参考）

本清单记录本次查阅过的工作区 `recon` 参考材料。所有数字证据均来自本批次在 `simo_cdc` 连接上执行的只读查询及其 TSV 输出；下列文件没有被当作最终数字证据，也没有被修改或覆盖。

## 执行器与结构参考

- `recon\dbx.ps1`：确认已有的 `simo_cdc` 连接方式、warehouse 和本地只读结果落盘方式；本批次沿用它执行查询。
- `tables.tsv`、`cols.tsv`：历史表/字段索引，仅用于定位对象和字段。

## 规则、核验和 SQL 参考

- `WA计费规则集.md`、`WA记账复算_报告.md`：历史规则假设、已知陷阱和前期结论，仅用于提出待验证候选规则。
- `platform_full.sql`、`billing_all_months.sql`、`all_rules_verify.sql`、`card_by_card.sql`、`card_by_card_summary.sql`、`c_final.sql`、`d_final.sql`：历史平台事实、计费和卡级核验查询模式，仅供参考。
- `fix_g_verified.sql`、`fix_verify_4rules.sql`、`method1_verify.sql`、`method2_verify.sql`、`months_gap.sql`、`probe_aug.sql`、`jul_aug_compare.sql`：历史诊断和规则比较查询，仅供参考。
- `wa_billing_fixed.sql`、`wa_billing_fixed_verify.sql`、`wa_billing_recalc.sql`、`wa_billing_recalc_probe.sql`、`wa_billing_verify.sql`、`billing_all4.sql`、`billing_gce.sql`、`c_compare.sql`、`c_zuofei_verify.sql`、`d_probe.sql`、`q.sql`–`q7.sql`：历史核验/诊断查询，仅供参考。本批次没有运行其中的写入步骤。

## 历史结果与 notebook 参考

- `excel_rule.tsv`、`excel_formula.tsv`、`excel_combos.tsv`、`gap_by_type.tsv`、`price_map.tsv`、`status_log.tsv`、`replaced_by_month.tsv`、`month_map.tsv`：历史 Excel/规则/价格/状态结果，仅用于交叉理解字段和待查问题。
- `all_months.tsv`、`all_months_4rules.tsv`、`final_all_months.tsv`、`platform_full.tsv`、`all4_result.tsv`、`fixed_aug.tsv`、`aug_card_summary.tsv`、`aug_excel.tsv`、`aug_xl_types.tsv`、`gce_result.tsv`、`jul_card_summary.tsv`、`jul_aug_compare.tsv`：历史结果快照，仅参考。
- `nb_card_billing_v2.py`、`nb_card_billing_v2_aug.py`、`nb_card_billing_v2_jul.py`、`nb_card_billing.sql.txt`、`nb_v2_aug.py.txt`：历史 notebook/脚本逻辑，仅用于了解先前粒度和候选规则；本批次没有运行其写表步骤。
- `extract_nb.ps1`、`ls_nb.ps1`：历史 notebook 检查脚本，仅参考。

## 本批次最终证据

本批次最终证据仅指本目录内编号 `01`–`37` 的已执行 `.sql` 以及成功查询对应的 `.tsv`；失败的 9 月快照探针也作为当前连接返回的缺失数据证据保留。每一条已执行 SQL 均先做了本地只读预检；平台端仅使用 `SELECT/WITH/SHOW/DESCRIBE/EXPLAIN` 类语句。