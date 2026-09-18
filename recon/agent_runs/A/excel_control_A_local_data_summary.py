import csv
import json
import os

OUT_DIR = r"C:\Users\EDY\Desktop\对账notebook\recon\agent_runs\A"
sheet_path = os.path.join(OUT_DIR, "excel_control_A_local_sheet_inventory.tsv")
out_path = os.path.join(OUT_DIR, "excel_control_A_local_data_summary.tsv")

def kind(row):
    s = row["sheet_name"].lower()
    cols = row["amount_columns"].lower()
    if "prorated-in" in s:
        return "prorated"
    if "credit owed" in cols or s == "sheet1":
        return "credit"
    if "detail charges" in s or "invoice details" in s:
        return "detail"
    return "summary_or_other"

def key_for(k):
    return {"detail":"Final Charge","prorated":"Final Charge For Usage Days","credit":"Credit Owed"}.get(k, "")

rows = []
with open(sheet_path, encoding="utf-8-sig", newline="") as f:
    for r in csv.DictReader(f, delimiter="\t"):
        k = kind(r)
        if k == "summary_or_other":
            continue
        summary = json.loads(r["amount_summary_json"] or "{}")
        metric = summary.get(key_for(k), {})
        rows.append({
            "local_excel_file": r["local_excel_file"],
            "local_relative_path": r["local_relative_path"],
            "sheet_name": r["sheet_name"],
            "sheet_kind": k,
            "data_row_count": r["data_row_count"],
            "imsi_count": r["imsi_count"],
            "key_columns": r["key_columns"],
            "amount_field": key_for(k),
            "excel_amount": metric.get("sum", ""),
            "amount_min": metric.get("min", ""),
            "amount_max": metric.get("max", ""),
            "date_columns": r["date_columns"],
            "date_summary_json": r["date_summary_json"],
            "charge_type_values": r["charge_type_values"],
        })
fields = ["local_excel_file","local_relative_path","sheet_name","sheet_kind","data_row_count","imsi_count","key_columns","amount_field","excel_amount","amount_min","amount_max","date_columns","date_summary_json","charge_type_values"]
with open(out_path, "w", encoding="utf-8-sig", newline="") as f:
    w = csv.DictWriter(f, fieldnames=fields, delimiter="\t")
    w.writeheader()
    w.writerows(rows)

