import csv
import json
import os
import re
import unicodedata
from collections import Counter, defaultdict

OUT_DIR = r"C:\Users\EDY\Desktop\对账notebook\recon\agent_runs\A"

def text(v):
    if v is None:
        return ""
    return str(v).replace("\t", " ").replace("\r", " ").replace("\n", " ").strip()

def nfkc(v):
    return unicodedata.normalize("NFKC", text(v)).replace("\u00a0", " ")

def canon_name(v):
    return re.sub(r"[^a-z0-9]+", "", nfkc(v).lower())

def read_tsv(path):
    with open(path, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f, delimiter="\t"))

def num(v):
    if v in (None, ""):
        return None
    try:
        return float(v)
    except Exception:
        return None

def amount_from_name(name):
    m = re.search(r"USD[_ ]*([0-9][0-9,]*\.[0-9]{2})", nfkc(name), flags=re.I)
    if not m:
        return None
    return float(m.group(1).replace(",", ""))

def amount_from_parent(relpath):
    parent = os.path.basename(os.path.dirname(relpath))
    return amount_from_name(parent)

def sheet_kind(row):
    name = nfkc(row.get("sheet_name", "")).lower()
    if "prorated-in" in name:
        return "prorated"
    amount_cols = nfkc(row.get("amount_columns", "")).lower()
    if "credit owed" in amount_cols or name == "sheet1":
        return "credit"
    if "detail charges" in name or "invoice details" in name:
        return "detail"
    return "summary_or_other"

def relevant_amount_key(platform_table):
    if platform_table.endswith("wa_invoice_detail"):
        return "Final Charge"
    if platform_table.endswith("wa_invoice_prorated"):
        return "Final Charge For Usage Days"
    return "Credit Owed"

def relevant_date_keys(platform_table):
    if platform_table.endswith("wa_invoice_detail"):
        return ["Final Start Date", "Charge Start Date", "final start date"]
    if platform_table.endswith("wa_invoice_prorated"):
        return ["Final Start Date", "Charge Start Date", "cycle_time"]
    return ["date line went down", "cycle start", "cycle end"]

def json_obj(v):
    try:
        return json.loads(v) if v else {}
    except Exception:
        return {}

def choose_local_sheet(sheet_rows, platform_table):
    wanted = "detail" if platform_table.endswith("wa_invoice_detail") else "prorated" if platform_table.endswith("wa_invoice_prorated") else "credit"
    candidates = [r for r in sheet_rows if sheet_kind(r) == wanted]
    if not candidates:
        return None
    return sorted(candidates, key=lambda r: (int(r.get("data_row_count") or 0), r.get("sheet_name", "")), reverse=True)[0]

def main():
    file_rows = read_tsv(os.path.join(OUT_DIR, "excel_control_A_local_file_inventory.tsv"))
    sheet_rows = read_tsv(os.path.join(OUT_DIR, "excel_control_A_local_sheet_inventory.tsv"))
    platform_rows = read_tsv(os.path.join(OUT_DIR, "excel_control_A_08_platform_source_catalog.tsv"))

    local_candidates = [r for r in file_rows if r.get("file_class") == "excel_source_candidate" and r.get("workbook_status") == "READ_OK"]
    local_by_key = defaultdict(list)
    for r in local_candidates:
        local_by_key[canon_name(r["local_excel_file"])].append(r)
    sheets_by_path = defaultdict(list)
    for r in sheet_rows:
        sheets_by_path[r["local_relative_path"]].append(r)
    platform_by_key = defaultdict(list)
    for r in platform_rows:
        platform_by_key[canon_name(r["platform_source_file"])].append(r)

    mapping = []
    for p in platform_rows:
        pkey = canon_name(p["platform_source_file"])
        candidates = local_by_key.get(pkey, [])
        if not candidates:
            mapping.append({
                "local_excel_file": "",
                "local_relative_path": "",
                "local_sheet_name": "",
                "platform_source_table": p["platform_source_table"],
                "platform_source_file": p["platform_source_file"],
                "invoice_batch_label": p["invoice_batch_label"],
                "observed_start_month": p["observed_start_month"],
                "observed_cycle_start_month": p["observed_cycle_start_month"],
                "observed_cycle_end_month": p["observed_cycle_end_month"],
                "local_sheet_kind": "",
                "local_sheet_data_row_count": "",
                "platform_record_count": p["platform_record_count"],
                "row_count_diff": "",
                "local_imsi_count": "",
                "platform_imsi_count": p["platform_imsi_count"],
                "imsi_count_diff": "",
                "local_amount": "",
                "platform_amount": p["platform_amount"],
                "amount_diff": "",
                "amount_semantics": p["platform_amount_semantics"],
                "local_amount_field": "",
                "local_date_summary_json": "",
                "file_name_amount": "",
                "file_name_amount_diff": "",
                "file_name_amount_status": "NO_LOCAL_FILE",
                "folder_amount": "",
                "folder_amount_diff": "",
                "folder_amount_status": "NO_LOCAL_FILE",
                "file_name_match_type": "PLATFORM_SOURCE_WITHOUT_LOCAL_FILE",
                "content_match_status": "MISSING_LOCAL_FILE",
                "split_merge_status": "PLATFORM_SOURCE_WITHOUT_LOCAL_FILE",
            })
            continue
        for local in candidates:
            local_sheets = sheets_by_path[local["local_relative_path"]]
            sheet = choose_local_sheet(local_sheets, p["platform_source_table"])
            amount_key = relevant_amount_key(p["platform_source_table"])
            local_amount = None
            local_date_json = ""
            local_rows = ""
            local_imsis = ""
            if sheet:
                summary = json_obj(sheet.get("amount_summary_json"))
                metric = summary.get(amount_key, {})
                local_amount = metric.get("sum")
                local_rows = sheet.get("data_row_count", "")
                local_imsis = sheet.get("imsi_count", "")
                local_date_json = sheet.get("date_summary_json", "")
            p_amount = num(p["platform_amount"])
            l_amount = num(local_amount)
            row_diff = (int(local_rows) - int(p["platform_record_count"])) if local_rows != "" else None
            imsi_diff = (int(local_imsis) - int(p["platform_imsi_count"])) if local_imsis != "" else None
            amount_diff = (l_amount - p_amount) if l_amount is not None and p_amount is not None else None
            fn_amount = amount_from_name(local["local_excel_file"])
            folder_amount = amount_from_parent(local["local_relative_path"])
            fn_diff = (fn_amount - p_amount) if fn_amount is not None and p_amount is not None else None
            folder_diff = (folder_amount - p_amount) if folder_amount is not None and p_amount is not None else None
            if sheet is None:
                content_status = "MISSING_LOCAL_DATA_SHEET"
            elif row_diff == 0 and imsi_diff == 0 and abs(amount_diff or 0) <= 0.01:
                content_status = "LOCAL_AND_PLATFORM_STATS_MATCH"
            else:
                content_status = "LOCAL_PLATFORM_STATS_CONFLICT"
            if fn_amount is None:
                fn_status = "NO_FILENAME_AMOUNT"
            elif abs(fn_diff or 0) <= 0.01:
                fn_status = "FILENAME_AMOUNT_MATCH"
            else:
                fn_status = "FILENAME_AMOUNT_MISMATCH_NO_ADJUSTMENT"
            if folder_amount is None:
                folder_status = "NO_PARENT_FOLDER_AMOUNT"
            elif abs(folder_diff or 0) <= 0.01:
                folder_status = "PARENT_FOLDER_AMOUNT_MATCH"
            else:
                folder_status = "PARENT_FOLDER_AMOUNT_MISMATCH_NO_ADJUSTMENT"
            mapping.append({
                "local_excel_file": local["local_excel_file"],
                "local_relative_path": local["local_relative_path"],
                "local_sheet_name": sheet["sheet_name"] if sheet else "",
                "platform_source_table": p["platform_source_table"],
                "platform_source_file": p["platform_source_file"],
                "invoice_batch_label": p["invoice_batch_label"],
                "observed_start_month": p["observed_start_month"],
                "observed_cycle_start_month": p["observed_cycle_start_month"],
                "observed_cycle_end_month": p["observed_cycle_end_month"],
                "local_sheet_kind": sheet_kind(sheet) if sheet else "",
                "local_sheet_data_row_count": local_rows,
                "platform_record_count": p["platform_record_count"],
                "row_count_diff": row_diff,
                "local_imsi_count": local_imsis,
                "platform_imsi_count": p["platform_imsi_count"],
                "imsi_count_diff": imsi_diff,
                "local_amount": l_amount,
                "platform_amount": p_amount,
                "amount_diff": amount_diff,
                "amount_semantics": p["platform_amount_semantics"],
                "local_amount_field": amount_key if sheet else "",
                "local_date_summary_json": local_date_json,
                "file_name_amount": fn_amount,
                "file_name_amount_diff": fn_diff,
                "file_name_amount_status": fn_status,
                "folder_amount": folder_amount,
                "folder_amount_diff": folder_diff,
                "folder_amount_status": folder_status,
                "file_name_match_type": "RAW_EXACT" if local["local_excel_file"] == p["platform_source_file"] else "NFKC_NORMALIZED",
                "content_match_status": content_status,
                "split_merge_status": "ONE_LOCAL_WORKBOOK_MATCHES_PLATFORM_SOURCE_FILE",
            })

    # Local source candidates with no platform source_file counterpart.
    mapped_local_keys = {canon_name(r["platform_source_file"]) for r in platform_rows}
    for local in local_candidates:
        lkey = canon_name(local["local_excel_file"])
        if lkey not in mapped_local_keys:
            mapping.append({
                "local_excel_file": local["local_excel_file"],
                "local_relative_path": local["local_relative_path"],
                "local_sheet_name": "",
                "platform_source_table": "",
                "platform_source_file": "",
                "invoice_batch_label": "",
                "observed_start_month": "",
                "observed_cycle_start_month": "",
                "observed_cycle_end_month": "",
                "local_sheet_kind": "",
                "local_sheet_data_row_count": "",
                "platform_record_count": "",
                "row_count_diff": "",
                "local_imsi_count": "",
                "platform_imsi_count": "",
                "imsi_count_diff": "",
                "local_amount": "",
                "platform_amount": "",
                "amount_diff": "",
                "amount_semantics": "",
                "local_amount_field": "",
                "local_date_summary_json": "",
                "file_name_amount": amount_from_name(local["local_excel_file"]),
                "file_name_amount_diff": "",
                "file_name_amount_status": "LOCAL_FILE_WITHOUT_PLATFORM_SOURCE",
                "folder_amount": amount_from_parent(local["local_relative_path"]),
                "folder_amount_diff": "",
                "folder_amount_status": "LOCAL_FILE_WITHOUT_PLATFORM_SOURCE",
                "file_name_match_type": "LOCAL_FILE_WITHOUT_PLATFORM_SOURCE",
                "content_match_status": "UNMAPPED_LOCAL_FILE",
                "split_merge_status": "LOCAL_FILE_WITHOUT_PLATFORM_SOURCE",
            })

    fields = [
        "local_excel_file", "local_relative_path", "local_sheet_name", "platform_source_table",
        "platform_source_file", "invoice_batch_label", "observed_start_month",
        "observed_cycle_start_month", "observed_cycle_end_month", "local_sheet_kind",
        "local_sheet_data_row_count", "platform_record_count", "row_count_diff",
        "local_imsi_count", "platform_imsi_count", "imsi_count_diff", "local_amount",
        "platform_amount", "amount_diff", "amount_semantics", "local_amount_field",
        "local_date_summary_json", "file_name_amount", "file_name_amount_diff",
        "file_name_amount_status", "folder_amount", "folder_amount_diff",
        "folder_amount_status", "file_name_match_type", "content_match_status",
        "split_merge_status",
    ]
    with open(os.path.join(OUT_DIR, "excel_control_A_local_platform_mapping.tsv"), "w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, delimiter="\t", extrasaction="ignore")
        w.writeheader()
        for row in mapping:
            w.writerow({k: text(row.get(k, "")) for k in fields})

    split_rows = []
    for key, locals_ in sorted(local_by_key.items()):
        ps = platform_by_key.get(key, [])
        split_rows.append({
            "normalized_file_key": key,
            "local_file_count": len(locals_),
            "local_files": "|".join(x["local_excel_file"] for x in locals_),
            "platform_source_file_count": 1 if ps else 0,
            "platform_tables": "|".join(sorted(set(x["platform_source_table"] for x in ps))),
            "platform_source_file": ps[0]["platform_source_file"] if ps else "",
            "assessment": "DUPLICATE_LOCAL_CANDIDATES" if len(locals_) > 1 else "LOCAL_FILE_WITH_PLATFORM_SOURCE" if ps else "LOCAL_FILE_WITHOUT_PLATFORM_SOURCE",
        })
    for key, ps in sorted(platform_by_key.items()):
        if key not in local_by_key:
            split_rows.append({
                "normalized_file_key": key,
                "local_file_count": 0,
                "local_files": "",
                "platform_source_file_count": 1,
                "platform_tables": "|".join(sorted(set(x["platform_source_table"] for x in ps))),
                "platform_source_file": ps[0]["platform_source_file"],
                "assessment": "PLATFORM_SOURCE_WITHOUT_LOCAL_FILE",
            })
    with open(os.path.join(OUT_DIR, "excel_control_A_local_split_merge_checks.tsv"), "w", encoding="utf-8-sig", newline="") as f:
        fields2 = ["normalized_file_key", "local_file_count", "local_files", "platform_source_file_count", "platform_tables", "platform_source_file", "assessment"]
        w = csv.DictWriter(f, fieldnames=fields2, delimiter="\t")
        w.writeheader()
        for row in split_rows:
            w.writerow(row)

if __name__ == "__main__":
    main()

