# A/C 追加硬性要求门禁记录

## A 已通过

- Excel 目标字段保持为 final_start_date、final_end_date、final_days、monthly_rate、final_charge、charge_type；38_excel_formula_validation.sql 在当前 simo_cdc 上验证 Excel 自算金额和日期跨度，平台字段不替代 Excel 原始目标。
- Excel 明细 schema 没有 product_id，只有 product_name；候选 SQL 不用 product_name 做正式价格 JOIN，输出 excel_product_id=NULL、excel_product_name，以及平台 product_id/name/price 集合。
- 10/11 月平台集合先按 tc_cdr.sim_status_for_sftp_bak 的目标年/月分区，再按 resource_res_vsim_product.product_id + supplier_id=2275 过滤；39_platform_scope_early_wa.sql 为早期范围证据。
- 9 月快照不可读时不使用全量 status_log/cycle_history 制造 PLATFORM_ONLY；32/33/34 只输出 MISSING_DATA shell。
- 24/25 和 30/31 实际输出 platform_calculated_days、platform_calculated_price、platform_calculated_amount、days_difference、price_difference、amount_difference。
- 2025-11 New Activation 的 12 个负/无效候选窗口已置 NULL，并标记 UNRESOLVED_INVALID_DATE_WINDOW；没有负 platform days/amount。
- 每条新执行 SQL 均先通过本地禁写关键字预检，平台端只执行 SELECT/WITH/SHOW/DESCRIBE/information_schema。

## C 当前状态

现有 C_batch_report.md 明确写明 PLATFORM_ONLY 使用 ALL_VISIBLE_PLATFORM 广域集合，并包含 PI/UNCLASSIFIED/MISSING_MAPPING 范围。按追加硬性要求，这不是目标月份 Wing Alpha 限定卡集合，因此 C 的既有 platform-only、匹配率和候选金额不能直接作为新门禁下的最终证据。

C 目录本次未修改；C 如继续交付，必须先重跑目标月分区 + Wing Alpha product_id 范围、Excel 自算验证和实际 platform_calculated_* 差异字段。