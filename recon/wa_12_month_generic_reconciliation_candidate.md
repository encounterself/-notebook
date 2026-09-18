# WA SIM 12个月通用 SQL 候选审查说明

状态：CANDIDATE / NOT FINAL / NOT EXECUTED。仅根据当前对话和 A/C 已交回证据推导；B 的旧 provisional 结果未使用。

## 来源

Excel 主账单是 simo_prod.mysql_cdc_sync.wa_invoice_detail；Excel 辅助 prorated 是 wa_invoice_prorated；Excel 辅助 credit 是 wa_invoice_credit。三张表不合并。平台候选来源是 tc_cdr.sim_status_for_sftp_bak、ods.resource_res_vsim_cycle_history、ods.resource_res_vsim_status_log、ods.resource_res_vsim_product、ods.resource_res_carrier；其中平台真实 catalog、字段名、粒度必须先只读 DESCRIBE。

## 12个批次

2025-01、2025-09、2025-10 (v1)、2025-10 (v2)、2025-12、2026-02、2026-03、2026-04、2026-05、2026-06、2026-07、2026-08。SQL 同时保留 invoice_batch_label 和 observed_start_month，避免文件批次与自然月混淆。

## 匹配

优先保留平台真实 card key。当前 Excel 证据无法稳定连接 card key，因此允许 IMSI，但必须同时 exact start/end window、唯一 platform product_id、唯一 rate，并与 Excel monthly_rate 相等。Excel product_id 为空不失败；product_name 不作为 JOIN 键；不允许 IMSI 单字段连接或用 MAX/MIN 掩盖多产品/多价格。

numeric_match_status 只表示金额；formal_match_status 表示完整证据链。输出 MATCHED、WA_ONLY、PLATFORM_ONLY、UNRESOLVED、MISSING_DATA、MISSING_MAPPING。PLATFORM_ONLY 单独作为平台多卡或平台额外卡候选，不并入 Excel 分母。

## 金额桥

platform_total - excel_total = platform_only_amount + same_card_net_diff - wa_only_amount + approved_adjustment_amount。

platform_calculated_amount_known 不能冒充 platform_total；平台金额覆盖不完整时 platform_total 必须保持 NULL。prorated、pending、credit 默认只披露，不自动加进主 detail 桥。平台理论上大于 Excel 时优先检查 PLATFORM_ONLY 数量和金额；其余差异按 DAYS、RATE、PRODUCT、CHARGE_TYPE、BACKBILL、CREDIT、REPLACEMENT、TRANSFER、OTHER_AMOUNT_DIFF 拆解。

## 输出

MONTHLY_WATERFALL：月度 Excel 总额、平台总额、已知平台金额、平台额外卡金额、同卡差异、WA_ONLY、桥接残差。

CARD_LEAK_CANDIDATE：方向、IMSI/card key、平台窗口、Excel 窗口、产品、金额、原因码、numeric/formal 状态、证据状态。平台有而 Excel 没匹配为 PLATFORM_TO_WA_MISSING；Excel 有而平台没有可证明匹配为 WA_TO_PLATFORM_MISSING；同 IMSI 但窗口/映射不完整为 REVIEW。

## A/C 可冻结证据

detail：140,452 行、21,920 个 IMSI、final_charge 约 $7,246,026.47834。prorated：828 行/828 IMSI，final_charge_for_usage_days 约 $30,619.758679，pending_charge 约 $7,195.895778。credit：393 行/393 IMSI，credit_owed $585.45。

OCT v1 detail 全量 final_charge 约 $772,285.533333；排除37条 credit 行的正数子集约 $772,750.533333。OCT v2 约 $773,737.838710。2026-03/04/05 分别约 $578,406.306452、$372,289.307527、$389,800.952688。文件名金额不直接用于补差。detail 内部 cycle key 重复在补充 final start/end 后为0，不能简单去重。

## 最小只读验证

只执行 SHOW、DESCRIBE、SELECT 或 WITH SELECT：

1. DESCRIBE 三张 wa_invoice 表，确认金额、窗口、days、product_id 可空性。
2. DESCRIBE 平台 cycle_history、product、status_log、carrier、sim_status_for_sftp_bak，替换 SQL 中 PENDING_MAP。
3. 检查 supplier_id=2275 下同 IMSI/窗口的 distinct product_id、distinct rate、重复主键。
4. 检查 platform_amount 覆盖率；有 NULL 就不填 platform_total。
5. 按批次输出 Excel 总额、平台已知金额、平台额外卡数/金额、WA_ONLY 和桥接残差。
6. 对 CARD_LEAK_CANDIDATE 按原因码聚合并抽样回查状态/换卡证据；证据闭环后才称正式漏卡。
