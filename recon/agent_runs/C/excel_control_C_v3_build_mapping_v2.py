import csv, json, re
from pathlib import Path
root=Path(r"C:\Users\EDY\Desktop\WA账单20260914")
outdir=Path(r"C:\Users\EDY\Desktop\对账notebook\recon\agent_runs\C")
def norm(s):
    if s is None:return ""
    return re.sub(r"\s+"," ",str(s).replace("\u00a0"," ").replace("\u200b"," ")).strip().casefold()
def nhead(s):
    return re.sub(r"[^a-z0-9]+","_",str(s).replace("\u00a0"," ").strip().lower()).strip("_")
def fnum(x):
    if x in (None,"","NULL"):return None
    try:return float(x)
    except:return None
def first_sheet(f, kind):
    for s in f.get("sheets",[]):
        n=nhead(s.get("sheet_name","")); hs=[nhead(x) for x in s.get("headers",[])]
        if kind=="detail" and ("detail" in n or "invoice_details" in n or "invoice_detail" in n):return s
        if kind=="prorated" and "prorated" in n:return s
        if kind=="credit" and any("credit_owed"==h for h in hs):return s
    return None
def stat(s, keys):
    for k,v in s.get("amount_stats",{}).items():
        nk=nhead(k)
        if nk in keys or any(nk.endswith("_"+x) for x in keys):return v
    return {}
def dstat(s, keys):
    for k,v in s.get("date_stats",{}).items():
        nk=nhead(k)
        if nk in keys or any(nk.endswith("_"+x) for x in keys):return v
    return {}
def obs_range(s):
    vals=[]
    for k,v in s.get("date_stats",{}).items():
        if nhead(k) in ("final_start_date","charge_start_date"):
            if v.get("min"):vals.append(v["min"][:7])
            if v.get("max"):vals.append(v["max"][:7])
    return ",".join(sorted(set(vals)))
def local_rows(s):
    return s.get("nonempty_data_rows")
def local_schema(s, kind):
    hs=[nhead(x) for x in s.get("headers",[])]
    if kind=="detail":
        return "OK" if "charge_type" in hs else "CONFLICT_MISSING_LOCAL_CHARGE_TYPE"
    if kind=="prorated":
        return "OK" if "final_charge_for_usage_days" in hs and "pending_charge" in hs else "CONFLICT_MISSING_LOCAL_PRORATED_AMOUNT_FIELD"
    if kind=="credit":
        return "OK" if "credit_owed" in hs else "CONFLICT_MISSING_LOCAL_CREDIT_AMOUNT_FIELD"
    return "UNKNOWN"
def csvrows(p):
    with open(p,"r",encoding="utf-8-sig",newline="") as fh:return list(csv.DictReader(fh,delimiter="\t"))
local=[]
for i in range(1,14):
    p=outdir/f"excel_control_C_v3_local_v4_{i}.json"
    local.append(json.loads(p.read_text(encoding="utf-8")))
platform={}
for kind,fn in [("detail","excel_control_C_v3_platform_detail_sources.tsv"),("prorated","excel_control_C_v3_platform_prorated_sources.tsv"),("credit","excel_control_C_v3_platform_credit_sources.tsv")]:
    rows=csvrows(outdir/fn)
    for r in rows:
        r["_kind"]=kind
        platform.setdefault(norm(r["platform_source_file"]),[]).append(r)
mapping=[]
matched_local=set()
for rlist in platform.values():
    for r in rlist:
        kind=r["_kind"]; key=norm(r["platform_source_file"])
        candidates=[f for f in local if norm(f["file_name"])==key]
        for f in candidates:
            matched_local.add(f["local_excel_file"])
            s=first_sheet(f,kind)
            lrows=local_rows(s) if s else None
            lschema=local_schema(s,kind) if s else "CONFLICT_MISSING_LOCAL_SHEET"
            if kind=="detail":
                amt=stat(s,{"final_charge"}) if s else {}
                lamount=fnum(amt.get("sum"))
                pamount=fnum(r.get("total_excel_amount"))
                laux=fnum((stat(s,{"monthly_rate","price"}) if s else {}).get("sum"))
                paux=fnum(r.get("total_monthly_rate_sum"))
                lstart=dstat(s,{"final_start_date","charge_start_date"}) if s else {}
                lend=dstat(s,{"final_end_date","charge_end_date"}) if s else {}
                primary_sem="detail.final_charge"
            elif kind=="prorated":
                amt=stat(s,{"final_charge_for_usage_days"}) if s else {}
                pend=stat(s,{"pending_charge"}) if s else {}
                lamount=fnum(amt.get("sum")); pamount=fnum(r.get("total_final_charge_for_usage_days"))
                laux=fnum(pend.get("sum")); paux=fnum(r.get("total_pending_charge"))
                lstart=dstat(s,{"final_start_date","charge_start_date"}) if s else {}
                lend=dstat(s,{"final_end_date","charge_end_date"}) if s else {}
                primary_sem="prorated.final_charge_for_usage_days"
            else:
                amt=stat(s,{"credit_owed"}) if s else {}
                lamount=fnum(amt.get("sum")); pamount=fnum(r.get("total_credit_owed"))
                laux=fnum((stat(s,{"correct_price"}) if s else {}).get("sum")); paux=fnum(r.get("total_correct_price"))
                lstart=dstat(s,{"cycle_start"}) if s else {}
                lend=dstat(s,{"cycle_end"}) if s else {}
                primary_sem="credit.credit_owed"
            diff=None if lamount is None or pamount is None else lamount-pamount
            auxdiff=None if laux is None or paux is None else laux-paux
            amount_status="MISSING_LOCAL_OR_PLATFORM_AMOUNT"
            if diff is not None:
                amount_status="MATCH_WITH_FLOATING_TOLERANCE" if abs(diff)<=0.00001 else "CONFLICT_AMOUNT"
            if kind=="credit" and laux is not None and paux is None:
                amount_status="CONFLICT_PLATFORM_CORRECT_PRICE_MISSING"
            local_obs=obs_range(s) if s else ""
            date_status="MISSING_LOCAL_DATE_FIELD"
            if s and lstart.get("min") and r.get("min_final_start_date") and lstart.get("min")==r.get("min_final_start_date") and lstart.get("max")==r.get("max_final_start_date"):
                date_status="MATCH_DATE_RANGE"
            elif s and kind=="credit" and lstart.get("min") and lstart.get("min")==r.get("min_cycle_start") and lstart.get("max")==r.get("max_cycle_start"):
                date_status="MATCH_CYCLE_START_RANGE"
            elif s and lstart.get("min"):
                date_status="CONFLICT_DATE_RANGE"
            mapping.append({
                "local_excel_file":f["local_excel_file"],"local_relative_path":f["relative_path"] if "relative_path" in f else str(Path(f["local_excel_file"]).relative_to(root)),
                "local_file_name":f["file_name"],"platform_source_table":r["source_table"],"platform_source_file":r["platform_source_file"],
                "invoice_batch_label":r["invoice_batch_label"],"observed_start_month":r.get("observed_start_month",""),
                "local_observed_start_month_range":local_obs,"observed_cycle_start_month":r.get("observed_cycle_start_month",""),"observed_cycle_end_month":r.get("observed_cycle_end_month",""),
                "local_sheet_name":s.get("sheet_name") if s else "","local_sheet_rows":lrows if lrows is not None else "","platform_record_count":r.get("record_count",""),"row_count_diff":("" if lrows is None else str(lrows-int(r["record_count"]))),
                "platform_imsi_count":r.get("imsi_count",""),"local_key_columns":json.dumps(s.get("key_columns",[]) if s else [],ensure_ascii=False),
                "local_amount_fields":json.dumps(list(s.get("amount_stats",{}).keys()) if s else [],ensure_ascii=False),
                "amount_semantics":primary_sem,"local_primary_amount":"" if lamount is None else f"{lamount:.10f}","platform_primary_amount":"" if pamount is None else r.get("total_excel_amount",r.get("total_final_charge_for_usage_days",r.get("total_credit_owed",""))),
                "primary_amount_diff_local_minus_platform":"" if diff is None else f"{diff:.10f}",
                "local_aux_amount":"" if laux is None else f"{laux:.10f}","platform_aux_amount":"" if paux is None else str(paux),"aux_amount_diff_local_minus_platform":"" if auxdiff is None else f"{auxdiff:.10f}",
                "amount_status":amount_status,"local_min_observed_start_or_cycle_start":lstart.get("min",""),"local_max_observed_start_or_cycle_start":lstart.get("max",""),"platform_min_start_or_cycle_start":r.get("min_final_start_date",r.get("min_cycle_start","")),"platform_max_start_or_cycle_start":r.get("max_final_start_date",r.get("max_cycle_start","")),
                "date_status":date_status,"local_schema_status":lschema,"identity_status":"MATCHED_NORMALIZED_FILENAME"
            })
for f in local:
    if f["local_excel_file"] not in matched_local:
        mapping.append({"local_excel_file":f["local_excel_file"],"local_relative_path":f.get("relative_path",""),"local_file_name":f["file_name"],"platform_source_table":"","platform_source_file":"","invoice_batch_label":"","observed_start_month":"","local_observed_start_month_range":"","observed_cycle_start_month":"","observed_cycle_end_month":"","local_sheet_name":"","local_sheet_rows":"","platform_record_count":"","row_count_diff":"","platform_imsi_count":"","local_key_columns":"","local_amount_fields":"","amount_semantics":"","local_primary_amount":"","platform_primary_amount":"","primary_amount_diff_local_minus_platform":"","local_aux_amount":"","platform_aux_amount":"","aux_amount_diff_local_minus_platform":"","amount_status":"CONFLICT_LOCAL_FILE_WITHOUT_PLATFORM_SOURCE_FILE","local_min_observed_start_or_cycle_start":"","local_max_observed_start_or_cycle_start":"","platform_min_start_or_cycle_start":"","platform_max_start_or_cycle_start":"","date_status":"","local_schema_status":"","identity_status":"UNMATCHED_LOCAL_FILE"})
fields=list(mapping[0].keys())
with open(outdir/"excel_control_C_v3_local_platform_mapping.tsv","w",encoding="utf-8-sig",newline="") as fh:
    w=csv.DictWriter(fh,fieldnames=fields,delimiter="\t");w.writeheader();w.writerows(mapping)
print("ROWS",len(mapping))


