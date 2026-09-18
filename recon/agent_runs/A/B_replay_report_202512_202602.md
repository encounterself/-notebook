# B 补跑：2025-12 与 2026-02

本目录文件均为 B 补跑专属产物，写入 `recon/agent_runs/A` 但使用 `B_replay_` 前缀；不重做、不覆盖 A 原批次结果。

## 执行状态

- DBSQL 执行器：成功。
- 所有 SQL 执行前首 token 为 `WITH` 或 `EXPLAIN`，禁用写入关键字为 `NONE`。
- Candidate `EXPLAIN` 成功。
- 本次仅查询 `2025-12` 与 `2026-02` source_file，未加入 SEP/OCT/2025-09/2025-10/2025-11/2026-01 Excel 行。

## 1. Excel detail 真值

金额只来自 `simo_prod.mysql_cdc_sync.wa_invoice_detail.final_charge` 全行 SUM；没有 UNION prorated/credit。

| official_excel_billing_month | source_file | observed_start_month | row_count | distinct_imsi_count | Excel total_final_charge |
|---|---|---:|---:|---:|---:|
| 2025-12 | SIMO Data Purchase Invoice Details - DEC 2025.xlsx | 2025-12 | 12,185 | 12,110 | 704,839.353763440731 |
| 2026-02 | 01-SIMO Data Purchase Invoice Details - FEB 2026.xlsx | 2026-02 | 12,572 | 12,309 | 690,572.723502304135 |

两张 source_file 的逐行 SUM 重算差异均为 0。

## 2. 月度平台复算

`platform_calculated_amount_known` 只汇总唯一 IMSI + Excel window 平台候选、supplier=2275、唯一平台产品价格且候选字段可计算的非 NULL 金额。`known_diff = platform_calculated_amount_known - Excel total_final_charge`，不是完整平台差异。

| batch | Excel rows | Excel IMSI | Excel total | known platform amount | known_diff | selected candidate amount_diff | platform_total | numeric MATCHED rows | formal MATCHED rows | unresolved/unproven impact |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 2025-12 | 12,185 | 12,110 | 704,839.353763440731 | 11,440.193529000000 | -693,399.160234440731 | -28,447.256999440320 | NULL | 544 | 544 | 694,091.869892473088 |
| 2026-02 | 12,572 | 12,309 | 690,572.723502304135 | 15,997.107126000000 | -674,575.616376304135 | -29,763.509276875150 | NULL | 195 | 195 | 682,635.759216589837 |

`platform_total` 保持 NULL，因为两个 batch 都有大量一对多、无候选、未映射或规则/金额不一致的 detail rows；不能把 known partial amount 当完整平台总额。

## 3. formal 状态

| batch | formal_match_status | row_count | distinct_imsi_count | Excel amount |
|---|---|---:|---:|---:|
| 2025-12 | MATCHED | 544 | 544 | 10,747.483870967643 |
| 2025-12 | UNRESOLVED | 11,630 | 11,630 | 693,618.869892473088 |
| 2025-12 | MISSING_MAPPING | 11 | 11 | 473.000000000000 |
| 2026-02 | MATCHED | 195 | 195 | 7,936.964285714298 |
| 2026-02 | UNRESOLVED | 12,374 | 12,374 | 682,574.330645161265 |
| 2026-02 | MISSING_MAPPING | 3 | 3 | 61.428571428572 |

2026-02 的 `UNRESOLVED` Excel amount 按行状态汇总为：Full Cycle 667,676.000000000000 + New Activation ambiguous 2,427.964285714264 + New Activation numeric mismatch 12,315.366359447002 + Offstocked rows金额为空 + Partial replaced 154.999999999999，具体明细保留在 Reconciliation TSV；平台/Excel NULL 未转成 0。

## 4. charge_type 卡级命中率

| batch / charge_type | row_count | card_count | days exact cards | price exact cards | amount exact cards | numeric MATCHED cards | formal MATCHED cards | formal rate |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 2025-12 Full Cycle Charge | 11,437 | 11,437 | 11,401 | 9,930 | 9,930 | 0 | 0 | 0% |
| 2025-12 New Activation: Prorated-in Charge | 748 | 748 | 746 | 748 | 673 | 544 | 544 | 72.7273% |
| 2026-02 Full Cycle Charge | 11,748 | 11,748 | 11,566 | 10,431 | 10,431 | 0 | 0 | 0% |
| 2026-02 New Activation: Prorated-in Charge | 729 | 729 | 421 | 629 | 288 | 195 | 195 | 26.7489% |
| 2026-02 Offstocked before cycle start | 91 | 91 | 0 | 90 | 0 | 0 | 0 | 0% |
| 2026-02 Partial Charge - Card Replaced Mid Cycle | 4 | 4 | 4 | 4 | 4 | 0 | 0 | 0% |

正式 MATCHED 样例证明：`excel_product_id=NULL`，但 `platform_product_mapping_status=PROVEN_BY_PLATFORM_IMSI`；平台 product_id 来自 supplier=2275 产品集合，价格唯一，与 Excel monthly_rate exact。

## 5. PLATFORM_ONLY

平台生命周期人口使用 supplier=2275 产品集合，cycle_history 窗口为 `cycle_time < 2026-04-01` 且 `next_cycle_time > 2025-12-01`，再以 Excel IMSI + cycle/final window 排除。row_count 与 distinct_imsi_count 分开：

| observed_start_month | official label | row_count | distinct_imsi_count |
|---|---|---:|---:|
| 2025-11 | NULL | 1,839 | 1,838 |
| 2025-12 | 2025-12 | 924 | 923 |
| 2026-01 | NULL | 1,862 | 1,787 |
| 2026-02 | 2026-02 | 424 | 420 |
| 2026-03 | NULL | 15,202 | 14,667 |

这些是独立平台 lifecycle rows，不并入 Excel amount，也不被称为 Excel 卡数。

## 6. B 补跑产物

- [Excel baseline SQL](<C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/A/B_replay_01_excel_baseline_202512_202602.sql>)
- [Excel baseline result](<C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/A/B_replay_01_excel_baseline_202512_202602.tsv>)
- [完整 Candidate SQL](<C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/A/B_replay_02_platform_imsi_proven_candidate_202512_202602.sql>)
- [Candidate EXPLAIN result](<C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/A/B_replay_02_platform_imsi_proven_candidate_explain.tsv>)
- [完整 Reconciliation SQL](<C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/A/B_replay_03_platform_imsi_proven_reconciliation_202512_202602.sql>)
- [Reconciliation result](<C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/A/B_replay_03_platform_imsi_proven_reconciliation_202512_202602.tsv>)
- [charge_type SQL](<C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/A/B_replay_04_platform_imsi_proven_charge_type_metrics_202512_202602.sql>)
- [charge_type result](<C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/A/B_replay_04_platform_imsi_proven_charge_type_metrics_202512_202602.tsv>)
- [formal MATCHED sample](<C:/Users/EDY/Desktop/对账notebook/recon/agent_runs/A/B_replay_05_formal_matched_sample_202512_202602.tsv>)

