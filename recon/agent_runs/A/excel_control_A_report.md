# Batch A Excel control review

Scope: read-only review of the user-provided local Excel directory and independent SELECT/WITH facts from the three simo_prod.mysql_cdc_sync.wa_* tables. No lifecycle table or platform card JOIN was performed in this control step.

## File inventory

- Readable source workbooks: 13.
- Temporary Excel lock files excluded from source evidence: 12.
- Other files present but not treated as Excel truth: 35 (PDF/CSV/script/SQL/Markdown).
- No local source workbook was modified, renamed, or overwritten.

## Readable source workbooks and sheets

| local_excel_file | sheet_names |
|---|---|
| 006-V2 - SIMO Data Purchase Invoice Details - SEP 2025.xlsx | Invoice Summary/Invoice Details - SEP 2025 |
| 01-INVOICE_FROM_ WA_USD_772,765.00_SIMO Data Purchase Invoice Details - OCT 2025.xlsx | Charges Summary/Detail Charges/Prorated-In SEP - Pending Charg |
| 01-1-INVOICE_FROM_ WA_USD_773,793.84_SIMO Data Purchase Invoice Details - OCT 2025.xlsx | Charges Summary/Detail Charges/Prorated-In OCT - Pending Charg |
| 01-2-Credit _FROM_ WA_ USD_585.45 wing response New_Query_2025-12-10_5_49pm_2025_12_16.xlsx | Sheet1/Sheet2 |
| SIMO Data Purchase Invoice Details - DEC 2025.xlsx | Charges Summary/Detail Charges |
| 01-SIMO Data Purchase Invoice Details - JAN 2025.xlsx | Charges Summary/Detail Charges/Prorated-In DEC - Pending Charg |
| 01-SIMO Data Purchase Invoice Details - FEB 2026.xlsx | Charges Summary/Detail Charges/Prorated-In JAN - Pending Charg |
| 01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx | Charges Summary/Detail Charges/Prorated-In FEB - Pending Charg |
| 01-SIMO Data Purchase Invoice Details - APR 2026.xlsx | Charges Summary/Detail Charges/Prorated-In MAR - Pending Charg |
| 01-SIMO Data Purchase Invoice Details - MAY 2026.xlsx | Charges Summary/Detail Charges/Prorated-In APR - Pending Charg |
| 01-SIMO Data Purchase Invoice Details - JUNE 2026.xlsx | Charges Summary/Detail Charges |
| 01-SIMO Data Purchase Invoice Details - JULY 2026.xlsx | Charges Summary/Detail Charges/Prorated-In JUN - Pending Charg |
| SIMO Data Purchase Invoice Details - AUGUST 2026.xlsx | Charges Summary/Detail Charges/Prorated-In JUL - Pending Charg |

## Local data-sheet facts

| local_excel_file | sheet_kind | sheet_name | rows | imsi_count | amount_field | excel_amount | all-date min | all-date max |
|---|---|---|---:|---:|---|---:|---|---|
| 006-V2 - SIMO Data Purchase Invoice Details - SEP 2025.xlsx | detail | Invoice Details - SEP 2025 | 25237 | 14793 | Final Charge | 1,139,393.524729 | 2025-08-02 | 2025-10-29 |
| 01-INVOICE_FROM_ WA_USD_772,765.00_SIMO Data Purchase Invoice Details - OCT 2025.xlsx | detail | Detail Charges | 12714 | 12712 | Final Charge | 772,285.533333 | 2025-09-10 | 2025-11-29 |
| 01-INVOICE_FROM_ WA_USD_772,765.00_SIMO Data Purchase Invoice Details - OCT 2025.xlsx | prorated | Prorated-In SEP - Pending Charg | 36 | 36 | Final Charge For Usage Days | 1,521.066667 | 2025-09-03 | 2025-10-03 |
| 01-1-INVOICE_FROM_ WA_USD_773,793.84_SIMO Data Purchase Invoice Details - OCT 2025.xlsx | detail | Detail Charges | 12663 | 12641 | Final Charge | 773,737.83871 | 2025-10-10 | 2025-12-29 |
| 01-1-INVOICE_FROM_ WA_USD_773,793.84_SIMO Data Purchase Invoice Details - OCT 2025.xlsx | prorated | Prorated-In OCT - Pending Charg | 5 | 5 | Final Charge For Usage Days | 294 | 2025-10-16 | 2025-11-15 |
| 01-2-Credit _FROM_ WA_ USD_585.45 wing response New_Query_2025-12-10_5_49pm_2025_12_16.xlsx | credit | Sheet1 | 393 | 393 | Credit Owed | 585.45 | 2025-10-30 | 2025-12-26 |
| SIMO Data Purchase Invoice Details - DEC 2025.xlsx | detail | Detail Charges | 12185 | 12110 | Final Charge | 704,839.353763 | 2025-11-24 | 2026-01-29 |
| 01-SIMO Data Purchase Invoice Details - JAN 2025.xlsx | detail | Detail Charges | 13661 | 13253 | Final Charge | 703,606.290323 | 2025-12-02 | 2026-02-27 |
| 01-SIMO Data Purchase Invoice Details - JAN 2025.xlsx | prorated | Prorated-In DEC - Pending Charg | 1 | 1 | Final Charge For Usage Days | 34 | 2025-12-14 | 2026-01-13 |
| 01-SIMO Data Purchase Invoice Details - FEB 2026.xlsx | detail | Detail Charges | 12572 | 12309 | Final Charge | 690,572.723502 | 2026-01-07 | 2026-03-29 |
| 01-SIMO Data Purchase Invoice Details - FEB 2026.xlsx | prorated | Prorated-In JAN - Pending Charg | 359 | 359 | Final Charge For Usage Days | 14,688.096774 | 2026-01-04 | 2026-02-24 |
| 01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx | detail | Detail Charges | 13082 | 12763 | Final Charge | 578,406.306452 | 2026-02-18 | 2026-04-27 |
| 01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx | prorated | Prorated-In FEB - Pending Charg | 127 | 127 | Final Charge For Usage Days | 3,686.928571 | 2026-02-02 | 2026-03-21 |
| 01-SIMO Data Purchase Invoice Details - APR 2026.xlsx | detail | Detail Charges | 7780 | 7317 | Final Charge | 372,289.307527 | 2026-03-19 | 2026-05-30 |
| 01-SIMO Data Purchase Invoice Details - APR 2026.xlsx | prorated | Prorated-In MAR - Pending Charg | 284 | 284 | Final Charge For Usage Days | 9,827.387097 | 2026-03-02 | 2026-04-25 |
| 01-SIMO Data Purchase Invoice Details - MAY 2026.xlsx | detail | Detail Charges | 7887 | 7494 | Final Charge | 389,800.952688 | 2026-04-19 | 2026-06-29 |
| 01-SIMO Data Purchase Invoice Details - MAY 2026.xlsx | prorated | Prorated-In APR - Pending Charg | 9 | 9 | Final Charge For Usage Days | 298.766667 | 2026-04-02 | 2026-05-08 |
| 01-SIMO Data Purchase Invoice Details - JUNE 2026.xlsx | detail | Detail Charges | 7598 | 7469 | Final Charge | 382,329.72043 | 2026-05-07 | 2026-07-29 |
| 01-SIMO Data Purchase Invoice Details - JULY 2026.xlsx | detail | Detail Charges | 7537 | 7472 | Final Charge | 373,918.313978 | 2026-06-09 | 2026-08-30 |
| 01-SIMO Data Purchase Invoice Details - JULY 2026.xlsx | prorated | Prorated-In JUN - Pending Charg | 4 | 4 | Final Charge For Usage Days | 141.9 | 2026-06-15 | 2026-07-25 |
| SIMO Data Purchase Invoice Details - AUGUST 2026.xlsx | detail | Detail Charges | 7536 | 7508 | Final Charge | 364,846.612903 | 2026-07-27 | 2026-09-29 |
| SIMO Data Purchase Invoice Details - AUGUST 2026.xlsx | prorated | Prorated-In JUL - Pending Charg | 3 | 3 | Final Charge For Usage Days | 127.612903 | 2026-07-04 | 2026-08-03 |

The full key-column lists, amount min/max, and per-date-field ranges are in excel_control_A_local_sheet_inventory.tsv; the data-sheet condensed view is in excel_control_A_local_data_summary.tsv.

## Platform source mapping

- Platform source rows: 22 (13 distinct platform source_file values).
- Local/platform row-card-amount statistics matched: 22/22 rows.
- Maximum absolute local-versus-platform amount residual in matched rows: 0.0000000161.
- Row-count differences: 0 for all matched rows. IMSI-count differences: 0 for all matched rows.
- Filename matches: 19 raw exact and 3 Unicode-normalized (NBSP/space) matches.
- No platform source_file lacked a local source workbook; no local source workbook lacked a platform source_file; no duplicate normalized local candidate was found.
- One workbook may legitimately map to both wa_invoice_detail and wa_invoice_prorated because the workbook contains separate Detail Charges and Prorated-In sheets. This is sheet-to-table mapping, not an unconditional amount union.

The mapping output retains local_excel_file, platform_source_table, platform_source_file, invoice_batch_label, and observed_start_month on every table-source row. See excel_control_A_local_platform_mapping.tsv.

## Strict source_file CASE and observed-date control

- CASE hit result: 17 single matches, 4 OCT amount-fragment matches, 1 ELSE source_file, and no multiple-WHEN source_file.
- The two OCT amount fragments are mutually exclusive in the live three-table facts.
- Date conflicts: 12 source-table/source_file groups; credit is separately marked NOT_APPLICABLE_NO_FINAL_START_DATE with cycle months retained.
- All current source-file amount sums recomputed from row values with zero rounded recompute residual in the control query.

| source_table | source_file | invoice_batch_label | observed_start_month_values | record_count | excel_amount |
|---|---|---|---|---:|---:|
| simo_prod.mysql_cdc_sync.wa_invoice_detail | 01-1-INVOICE_FROM_ WA_USD_773,793.84_SIMO Data Purchase Invoice Details - OCT 2025.xlsx | 2025-10 (v2) | 2025-11 | 12663 | 773,737.83871 |
| simo_prod.mysql_cdc_sync.wa_invoice_detail | 01-SIMO Data Purchase Invoice Details - JAN 2025.xlsx | 2025-01 | 2026-01,2026-02 | 13661 | 703,606.290323 |
| simo_prod.mysql_cdc_sync.wa_invoice_detail | 01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx | 2026-03 | 2026-02,2026-03 | 13082 | 578,406.306452 |
| simo_prod.mysql_cdc_sync.wa_invoice_detail | 01-SIMO Data Purchase Invoice Details - MAY 2026.xlsx | 2026-05 | 2026-04,2026-05 | 7887 | 389,800.952688 |
| simo_prod.mysql_cdc_sync.wa_invoice_prorated | 01-INVOICE_FROM_ WA_USD_772,765.00_SIMO Data Purchase Invoice Details - OCT 2025.xlsx | 2025-10 (v1) | 2025-09 | 36 | 1,521.066667 |
| simo_prod.mysql_cdc_sync.wa_invoice_prorated | 01-SIMO Data Purchase Invoice Details - APR 2026.xlsx | 2026-04 | 2026-03 | 284 | 9,827.387097 |
| simo_prod.mysql_cdc_sync.wa_invoice_prorated | 01-SIMO Data Purchase Invoice Details - FEB 2026.xlsx | 2026-02 | 2026-01 | 359 | 14,688.096774 |
| simo_prod.mysql_cdc_sync.wa_invoice_prorated | 01-SIMO Data Purchase Invoice Details - JAN 2025.xlsx | 2025-01 | 2025-12 | 1 | 34 |
| simo_prod.mysql_cdc_sync.wa_invoice_prorated | 01-SIMO Data Purchase Invoice Details - JULY 2026.xlsx | 2026-07 | 2026-06 | 4 | 141.9 |
| simo_prod.mysql_cdc_sync.wa_invoice_prorated | 01-SIMO Data Purchase Invoice Details - MAR 2026.xlsx | 2026-03 | 2026-02 | 127 | 3,686.928571 |
| simo_prod.mysql_cdc_sync.wa_invoice_prorated | 01-SIMO Data Purchase Invoice Details - MAY 2026.xlsx | 2026-05 | 2026-04 | 9 | 298.766667 |
| simo_prod.mysql_cdc_sync.wa_invoice_prorated | SIMO Data Purchase Invoice Details - AUGUST 2026.xlsx | 2026-08 | 2026-07 | 3 | 127.612903 |

Conflicts are retained, not rewritten: detail v2 is labeled 2025-10 (v2) but observed in 2025-11; detail JAN 2025 spans 2026-01/02; detail MAR 2026 spans 2026-02/03; detail MAY 2026 spans 2026-04/05; prorated rows are generally prior-cycle observed dates as shown in the table.

## File-name amount control

- File-name nominal amounts are diagnostic only and were not used to adjust any table amount.

| source_table | source_file | amount_semantics | filename_amount | platform_amount | platform_minus_filename | status |
|---|---|---|---:|---:|---:|---|
| simo_prod.mysql_cdc_sync.wa_invoice_credit | 01-2-Credit _FROM_ WA_ USD_585.45 wing response New_Query_2025-12-10_5_49pm_2025_12_16.xlsx | credit_owed | 585.45 | 585.45 | 0 | FILENAME_AMOUNT_MATCH |
| simo_prod.mysql_cdc_sync.wa_invoice_detail | 01-1-INVOICE_FROM_ WA_USD_773,793.84_SIMO Data Purchase Invoice Details - OCT 2025.xlsx | final_charge | 773,793.84 | 773,737.83871 | -56.00129 | FILENAME_AMOUNT_MISMATCH_NO_ADJUSTMENT |
| simo_prod.mysql_cdc_sync.wa_invoice_detail | 01-INVOICE_FROM_ WA_USD_772,765.00_SIMO Data Purchase Invoice Details - OCT 2025.xlsx | final_charge | 772,765 | 772,285.533333 | -479.466667 | FILENAME_AMOUNT_MISMATCH_NO_ADJUSTMENT |
| simo_prod.mysql_cdc_sync.wa_invoice_prorated | 01-1-INVOICE_FROM_ WA_USD_773,793.84_SIMO Data Purchase Invoice Details - OCT 2025.xlsx | final_charge_for_usage_days | 773,793.84 | 294 | -773,499.84 | FILENAME_AMOUNT_MISMATCH_NO_ADJUSTMENT |
| simo_prod.mysql_cdc_sync.wa_invoice_prorated | 01-INVOICE_FROM_ WA_USD_772,765.00_SIMO Data Purchase Invoice Details - OCT 2025.xlsx | final_charge_for_usage_days | 772,765 | 1,521.066667 | -771,243.933333 | FILENAME_AMOUNT_MISMATCH_NO_ADJUSTMENT |

The 773,793.84 and 772,765.00 filename amounts do not equal the corresponding platform detail final_charge totals; the differences are retained as mismatches. The 585.45 credit filename matches credit_owed.

## Overlap control

- Detail/prorated shared IMSIs: 828; detail/credit shared IMSIs: 393; prorated/credit shared IMSIs: 0.
- Candidate row-key overlaps: 0 for all three table pairs.
- Shared source_file values are present only between detail and prorated (9), reflecting workbooks that contain both sheet types; no detail/credit or prorated/credit source_file overlap.

See excel_control_A_04_overlap.tsv.

## Formula evidence

- The source workbooks contain summary formulas, but raw data-sheet sums were used for control.
- Formula scan found 1 sheet with an explicit formula error token: the v2 OCT Charges Summary contains #REF! in one formula. This is a local formula-quality conflict; it does not alter the matched raw Detail Charges/Prorated-In row facts.

## Read-only SQL artifacts

- excel_control_A_04_overlap.sql: complete CTEs for pairwise overlap checks.
- excel_control_A_05_case_conflicts.sql: complete separate-table CTEs for CASE, observed dates, row-sum recomputation, and conflict statuses.
- excel_control_A_06_filename_amount_diff.sql: complete separate-table CTEs for filename nominal amount comparison.
- excel_control_A_08_platform_source_catalog.sql: complete separate-table source catalog used for mapping.
- All four SQL files were preflighted with first token WITH and no forbidden write keyword, then executed through the existing simo_cdc runner.

Current gate: Excel truth/control evidence is complete for this step. Platform lifecycle rules, platform card-month JOIN, candidate billing SQL, and reconciliation SQL remain intentionally out of scope until this control is accepted.
