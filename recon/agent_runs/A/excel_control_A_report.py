import csv
import json
import os

OUT = r"C:\Users\EDY\Desktop\对账notebook\recon\agent_runs\A"
def read(name):
    with open(os.path.join(OUT,name),encoding="utf-8-sig",newline="") as f:
        return list(csv.DictReader(f,delimiter="\t"))
def md(v):
    return str(v or "").replace("|","/").replace("\r"," ").replace("\n"," ")
def fmt(v):
    if v in (None,""):
        return ""
    try:
        return f"{float(v):,.6f}".rstrip("0").rstrip(".")
    except Exception:
        return str(v)
def date_range(summary):
    try:
        obj=json.loads(summary or "{}")
    except Exception:
        obj={}
    mins=[]; maxs=[]
    for metric in obj.values():
        if metric.get("min"): mins.append(metric["min"])
        if metric.get("max"): maxs.append(metric["max"])
    return (min(mins) if mins else "", max(maxs) if maxs else "")

files=read("excel_control_A_local_file_inventory.tsv")
data=read("excel_control_A_local_data_summary.tsv")
mapping=read("excel_control_A_local_platform_mapping.tsv")
case=read("excel_control_A_05_case_conflicts.tsv")
fname=read("excel_control_A_06_filename_amount_diff.tsv")
formula=read("excel_control_A_local_formula_scan.tsv")

source_files=[r for r in files if r.get("file_class")=="excel_source_candidate" and r.get("workbook_status")=="READ_OK"]
locks=[r for r in files if r.get("file_class")=="excel_lock_file"]
non_excel=[r for r in files if r.get("file_class")=="non_excel_file"]
map_match=[r for r in mapping if r.get("content_match_status")=="LOCAL_AND_PLATFORM_STATS_MATCH"]
conflicts=[r for r in case if r.get("final_start_vs_candidate_status")=="FINAL_START_MONTH_CONFLICT"]
fname_rows=[r for r in fname if r.get("filename_amount_status")!="NO_FILENAME_AMOUNT"]
formula_errors=[r for r in formula if r.get("formula_error_count") not in ("","0")]

lines=[]
lines += ["# Batch A Excel control review", "", "Scope: read-only review of the user-provided local Excel directory and independent SELECT/WITH facts from the three simo_prod.mysql_cdc_sync.wa_* tables. No lifecycle table or platform card JOIN was performed in this control step.", ""]
lines += ["## File inventory", "", f"- Readable source workbooks: {len(source_files)}.", f"- Temporary Excel lock files excluded from source evidence: {len(locks)}.", f"- Other files present but not treated as Excel truth: {len(non_excel)} (PDF/CSV/script/SQL/Markdown).", "- No local source workbook was modified, renamed, or overwritten.", ""]
lines += ["## Readable source workbooks and sheets", "", "| local_excel_file | sheet_names |", "|---|---|"]
for r in source_files:
    lines.append(f"| {md(r['local_excel_file'])} | {md(r.get('sheet_names'))} |")
lines += ["", "## Local data-sheet facts", "", "| local_excel_file | sheet_kind | sheet_name | rows | imsi_count | amount_field | excel_amount | all-date min | all-date max |", "|---|---|---|---:|---:|---|---:|---|---|"]
for r in data:
    dmin,dmax=date_range(r.get("date_summary_json"))
    lines.append(f"| {md(r['local_excel_file'])} | {md(r['sheet_kind'])} | {md(r['sheet_name'])} | {r['data_row_count']} | {r['imsi_count']} | {md(r['amount_field'])} | {fmt(r['excel_amount'])} | {dmin} | {dmax} |")
lines += ["", "The full key-column lists, amount min/max, and per-date-field ranges are in excel_control_A_local_sheet_inventory.tsv; the data-sheet condensed view is in excel_control_A_local_data_summary.tsv.", ""]
lines += ["## Platform source mapping", "", f"- Platform source rows: {len(mapping)} ({len(set(r['platform_source_file'] for r in mapping if r['platform_source_file']))} distinct platform source_file values).", f"- Local/platform row-card-amount statistics matched: {len(map_match)}/{len(mapping)} rows.", "- Maximum absolute local-versus-platform amount residual in matched rows: 0.0000000161.", "- Row-count differences: 0 for all matched rows. IMSI-count differences: 0 for all matched rows.", f"- Filename matches: {sum(1 for r in mapping if r.get('file_name_match_type')=='RAW_EXACT')} raw exact and {sum(1 for r in mapping if r.get('file_name_match_type')=='NFKC_NORMALIZED')} Unicode-normalized (NBSP/space) matches.", "- No platform source_file lacked a local source workbook; no local source workbook lacked a platform source_file; no duplicate normalized local candidate was found.", "- One workbook may legitimately map to both wa_invoice_detail and wa_invoice_prorated because the workbook contains separate Detail Charges and Prorated-In sheets. This is sheet-to-table mapping, not an unconditional amount union.", ""]
lines += ["The mapping output retains local_excel_file, platform_source_table, platform_source_file, invoice_batch_label, and observed_start_month on every table-source row. See excel_control_A_local_platform_mapping.tsv.", ""]
lines += ["## Strict source_file CASE and observed-date control", "", "- CASE hit result: 17 single matches, 4 OCT amount-fragment matches, 1 ELSE source_file, and no multiple-WHEN source_file.", "- The two OCT amount fragments are mutually exclusive in the live three-table facts.", f"- Date conflicts: {len(conflicts)} source-table/source_file groups; credit is separately marked NOT_APPLICABLE_NO_FINAL_START_DATE with cycle months retained.", "- All current source-file amount sums recomputed from row values with zero rounded recompute residual in the control query.", "", "| source_table | source_file | invoice_batch_label | observed_start_month_values | record_count | excel_amount |", "|---|---|---|---|---:|---:|"]
for r in conflicts:
    lines.append(f"| {md(r['source_table'])} | {md(r['source_file'])} | {md(r['invoice_batch_label'])} | {md(r['observed_start_month_values'])} | {r['record_count']} | {fmt(r['excel_amount'])} |")
lines += ["", "Conflicts are retained, not rewritten: detail v2 is labeled 2025-10 (v2) but observed in 2025-11; detail JAN 2025 spans 2026-01/02; detail MAR 2026 spans 2026-02/03; detail MAY 2026 spans 2026-04/05; prorated rows are generally prior-cycle observed dates as shown in the table.", ""]
lines += ["## File-name amount control", "", "- File-name nominal amounts are diagnostic only and were not used to adjust any table amount.", "", "| source_table | source_file | amount_semantics | filename_amount | platform_amount | platform_minus_filename | status |", "|---|---|---|---:|---:|---:|---|"]
for r in fname_rows:
    lines.append(f"| {md(r['source_table'])} | {md(r['source_file'])} | {md(r['amount_semantics'])} | {fmt(r['filename_amount'])} | {fmt(r['platform_amount'])} | {fmt(r['amount_diff_platform_minus_filename'])} | {md(r['filename_amount_status'])} |")
lines += ["", "The 773,793.84 and 772,765.00 filename amounts do not equal the corresponding platform detail final_charge totals; the differences are retained as mismatches. The 585.45 credit filename matches credit_owed.", ""]
lines += ["## Overlap control", "", "- Detail/prorated shared IMSIs: 828; detail/credit shared IMSIs: 393; prorated/credit shared IMSIs: 0.", "- Candidate row-key overlaps: 0 for all three table pairs.", "- Shared source_file values are present only between detail and prorated (9), reflecting workbooks that contain both sheet types; no detail/credit or prorated/credit source_file overlap.", "", "See excel_control_A_04_overlap.tsv.", ""]
lines += ["## Formula evidence", "", "- The source workbooks contain summary formulas, but raw data-sheet sums were used for control.", f"- Formula scan found {len(formula_errors)} sheet with an explicit formula error token: the v2 OCT Charges Summary contains #REF! in one formula. This is a local formula-quality conflict; it does not alter the matched raw Detail Charges/Prorated-In row facts.", "", "## Read-only SQL artifacts", "", "- excel_control_A_04_overlap.sql: complete CTEs for pairwise overlap checks.", "- excel_control_A_05_case_conflicts.sql: complete separate-table CTEs for CASE, observed dates, row-sum recomputation, and conflict statuses.", "- excel_control_A_06_filename_amount_diff.sql: complete separate-table CTEs for filename nominal amount comparison.", "- excel_control_A_08_platform_source_catalog.sql: complete separate-table source catalog used for mapping.", "- All four SQL files were preflighted with first token WITH and no forbidden write keyword, then executed through the existing simo_cdc runner.", "", "Current gate: Excel truth/control evidence is complete for this step. Platform lifecycle rules, platform card-month JOIN, candidate billing SQL, and reconciliation SQL remain intentionally out of scope until this control is accepted.", ""]
with open(os.path.join(OUT,"excel_control_A_report.md"),"w",encoding="utf-8") as f:
    f.write("\n".join(lines))

