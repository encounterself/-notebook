import csv, json, re
from pathlib import Path
root=Path(r"C:\Users\EDY\Desktop\WA账单20260914")
out=Path(r"C:\Users\EDY\Desktop\对账notebook\recon\agent_runs\C")
def wtsv(path, rows, fields):
    with open(out/path,"w",encoding="utf-8-sig",newline="") as f:
        w=csv.DictWriter(f,fieldnames=fields,delimiter="\t");w.writeheader();w.writerows(rows)
def norm(s):
    return re.sub(r"\s+"," ",str(s).replace("\u00a0"," ")).strip().casefold()
# directory inventory
rows=[]
for p in sorted([x for x in root.rglob("*") if x.is_file()],key=lambda x:str(x).lower()):
    name=p.name
    if name.startswith("~$") and p.suffix.lower()==".xlsx":
        category="excel_temp_lock_invalid"
    elif p.suffix.lower() in (".xlsx",".xls",".xlsm"):
        category="excel_official_candidate"
    elif p.suffix.lower()==".csv":
        category="csv_export_auxiliary"
    else:
        category="non_excel_auxiliary"
    rows.append({"local_path":str(p),"relative_path":str(p.relative_to(root)),"file_name":name,"extension":p.suffix.lower(),"size_bytes":p.stat().st_size,"category":category})
wtsv("excel_control_C_v3_local_directory_inventory.tsv",rows,list(rows[0].keys()))
# exact workbook sheet inventory
sheetrows=[]
for i in range(1,14):
    j=json.loads((out/f"excel_control_C_v3_local_v4_{i}.json").read_text(encoding="utf-8"))
    for s in j.get("sheets",[]):
        sheetrows.append({"local_excel_file":j["local_excel_file"],"relative_path":str(Path(j["local_excel_file"]).relative_to(root)),"local_file_name":j["file_name"],"read_status":j["read_status"],"sheet_name":s["sheet_name"],"header_row":s["header_row"],"data_rows_after_header":s["data_rows_after_header"],"nonempty_data_rows":s["nonempty_data_rows"],"key_columns":json.dumps(s["key_columns"],ensure_ascii=False),"headers":json.dumps(s["headers"],ensure_ascii=False),"amount_fields":json.dumps(list(s["amount_stats"].keys()),ensure_ascii=False),"amount_stats":json.dumps(s["amount_stats"],ensure_ascii=False),"date_stats":json.dumps(s["date_stats"],ensure_ascii=False)})
wtsv("excel_control_C_v3_local_sheet_inventory.tsv",sheetrows,list(sheetrows[0].keys()))
# filename amount diagnostics from current mapping
with open(out/"excel_control_C_v3_local_platform_mapping.tsv",encoding="utf-8-sig",newline="") as f: maps=list(csv.DictReader(f,delimiter="\t"))
fd=[]
for r in maps:
    fn=r["local_file_name"]; m=re.search(r"(773,793\.84|772,765\.00|585\.45)",fn)
    expected=float(m.group(1).replace(",","")) if m else None
    table=r["platform_source_table"]
    pamt=float(r["platform_primary_amount"]) if r["platform_primary_amount"] else None
    if expected is None:
        status="NO_FILENAME_AMOUNT_TOKEN"
        comp="NOT_APPLICABLE"
        diff=""
    elif table.endswith("wa_invoice_prorated"):
        status="NOT_COMPARABLE_PRORATED_AUXILIARY"
        comp="prorated amount is auxiliary, not invoice total"
        diff="" if pamt is None else f"{pamt-expected:.10f}"
    elif pamt is None:
        status="MISSING_TABLE_AMOUNT"
        comp="invoice total comparison"
        diff=""
    else:
        diff=f"{pamt-expected:.10f}"
        status="MATCH_FILENAME_WITHIN_TOLERANCE" if abs(pamt-expected)<=0.00001 else "CONFLICT_FILENAME_VS_TABLE"
        comp="invoice total comparison"
    fd.append({"local_excel_file":r["local_excel_file"],"platform_source_table":table,"platform_source_file":r["platform_source_file"],"invoice_batch_label":r["invoice_batch_label"],"observed_start_month":r["observed_start_month"],"filename_amount_token":"" if expected is None else f"{expected:.2f}","table_amount_semantics":r["amount_semantics"],"platform_table_amount":r["platform_primary_amount"],"table_amount_minus_filename_amount":diff,"comparison_status":status,"comparison_note":comp})
wtsv("excel_control_C_v3_filename_amount_diff.tsv",fd,list(fd[0].keys()))
# file-level issues
issues=[]
for p in sorted([x for x in root.rglob("*") if x.is_file() and x.name.startswith("~$") and x.suffix.lower()==".xlsx"],key=lambda x:str(x).lower()):
    issues.append({"issue_type":"INVALID_TEMP_LOCK_FILE","local_excel_file":str(p),"platform_source_table":"","platform_source_file":"","details":"Hidden Excel lock file; not a valid workbook and excluded from source mapping."})
for r in maps:
    if r["local_schema_status"]!="OK":
        issues.append({"issue_type":"LOCAL_SCHEMA_CONFLICT","local_excel_file":r["local_excel_file"],"platform_source_table":r["platform_source_table"],"platform_source_file":r["platform_source_file"],"details":r["local_schema_status"]})
    if r["amount_status"].startswith("CONFLICT"):
        issues.append({"issue_type":"AMOUNT_CONFLICT","local_excel_file":r["local_excel_file"],"platform_source_table":r["platform_source_table"],"platform_source_file":r["platform_source_file"],"details":r["amount_status"]})
# sheet2 auxiliary
credit=[r for r in sheetrows if "Credit _FROM_" in r["local_file_name"] and r["sheet_name"]=="Sheet2"]
for r in credit:
    issues.append({"issue_type":"AUXILIARY_SHEET_NO_HEADER","local_excel_file":r["local_excel_file"],"platform_source_table":"simo_prod.mysql_cdc_sync.wa_invoice_credit","platform_source_file":"","details":"Sheet2 has no header/key/amount fields; retained as auxiliary, not mapped as credit facts."})
wtsv("excel_control_C_v3_local_file_issues.tsv",issues,list(issues[0].keys()))
print("directory_rows",len(rows),"sheet_rows",len(sheetrows),"mapping_rows",len(maps),"issues",len(issues))

