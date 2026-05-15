-- =====================================================
-- INTERACTIVE HTML PATIENT TIMELINE GENERATION
-- =====================================================

-- =====================================================
-- LIST ALL TARPEYO-RELATED TABLES
-- =====================================================

SELECT table_name, row_count
FROM P_CALT_022_ZDH_01.information_schema.tables
WHERE table_schema = 'SCH_ANA_DATA'
  AND table_name ILIKE 'KP_TARP_%'
ORDER BY table_name;

-- =====================================================
-- PREVIEW PROCEDURE EVENTS (for data structure)
-- =====================================================

SELECT * FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_proc_events LIMIT 1;

-- =====================================================
-- GET PATIENT LIST FOR TIMELINE GENERATION
-- =====================================================

SELECT PATIENT_ID
FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_cohort
ORDER BY first_tarpeyo_fill;


-- =====================================================
-- PYTHON CODE FOR INTERACTIVE HTML TIMELINES
-- =====================================================

/*
=============================================================================
Initialize Snowflake session and list tables
=============================================================================

import pandas as pd
import numpy as np
import json
from datetime import datetime, date
from snowflake.snowpark.context import get_active_session
import os

session = get_active_session()

DB = "P_CALT_022_ZDH_01"
SCHEMA = f"{DB}.SCH_ANA_DATA"

tables = session.sql("""
    SELECT table_name, row_count
    FROM P_CALT_022_ZDH_01.information_schema.tables
    WHERE table_schema = 'SCH_ANA_DATA'
      AND table_name ILIKE 'KP_TARP_%'
    ORDER BY table_name
""").to_pandas()

tables


=============================================================================
Category configurations for visualization
=============================================================================

RX_CAT_CONFIG = {
    "Tarpeyo":           {"color": "#185FA5", "bg": "#deeaf7", "order": 0},
    "Other IgAN":        {"color": "#854F0B", "bg": "#faebd4", "order": 1},
    "SGLT2i":            {"color": "#3B6D11", "bg": "#e4f1d4", "order": 2},
    "ACEi":              {"color": "#0F6E56", "bg": "#d6f0e7", "order": 3},
    "ARB":               {"color": "#1D9E75", "bg": "#d6f0e7", "order": 4},
    "Immunosuppressant": {"color": "#534AB7", "bg": "#eae8fc", "order": 5},
    "Systemic steroid":  {"color": "#BA7517", "bg": "#faebd4", "order": 6},
    "Diuretic / MRA":    {"color": "#5F5E5A", "bg": "#ebebeb", "order": 7},
    "Omega-3":           {"color": "#3B6D11", "bg": "#e4f1d4", "order": 8},
}

DX_CAT_CONFIG = {
    "IgAN (specific)":       {"color": "#0C447C", "bg": "#c8daf4", "panel": "kidney"},
    "IgAN (proxy)":          {"color": "#185FA5", "bg": "#deeaf7", "panel": "kidney"},
    "Recurrent hematuria":   {"color": "#378ADD", "bg": "#deeaf7", "panel": "kidney"},
    "CKD stage 5 / ESRD":    {"color": "#791F1F", "bg": "#fcd8d8", "panel": "kidney"},
    "CKD stage 4":           {"color": "#A32D2D", "bg": "#fcd8d8", "panel": "kidney"},
    "CKD stage 3":           {"color": "#BA7517", "bg": "#faebd4", "panel": "kidney"},
    "CKD stage 2":           {"color": "#3B6D11", "bg": "#e4f1d4", "panel": "kidney"},
    "CKD stage 1":           {"color": "#639922", "bg": "#e4f1d4", "panel": "kidney"},
    "CKD unspecified":       {"color": "#888780", "bg": "#ebebeb", "panel": "kidney"},
    "Nephrotic syndrome":    {"color": "#72243E", "bg": "#f4c0d1", "panel": "kidney"},
    "Proteinuria":           {"color": "#534AB7", "bg": "#eae8fc", "panel": "kidney"},
    "Hypertension":          {"color": "#5F5E5A", "bg": "#ebebeb", "panel": "comorbidity"},
    "Type 2 diabetes":       {"color": "#633806", "bg": "#faeeda", "panel": "comorbidity"},
    "Dependence on dialysis":{"color": "#3C3489", "bg": "#eeedfe", "panel": "comorbidity"},
}

PROC_CONFIG = {
    "Kidney biopsy":        {"color": "#854F0B", "sym": "\u25c6"},
    "Dialysis":             {"color": "#A32D2D", "sym": "\u25a0"},
    "Kidney transplant":    {"color": "#0C447C", "sym": "\u2605"},
    "Other renal procedure":{"color": "#888780", "sym": "\u25cf"},
}

TIME_START = "2020-01-01"
TIME_END = "2026-01-01"
TOTAL_DAYS = (datetime.strptime(TIME_END, "%Y-%m-%d") -
               datetime.strptime(TIME_START, "%Y-%m-%d")).days


=============================================================================
Data loader function
=============================================================================

def load_patient(session, patient_id: str) -> dict:
    pid = f"'{patient_id}'"
    def q(tbl, extra=""):
        return session.sql(
            f"SELECT * FROM {SCHEMA}.{tbl} WHERE PATIENT_ID = {pid} {extra}"
        ).to_pandas()
    return {
        "cohort":   q("kp_tarp_cohort"),
        "episodes": q("kp_tarp_rx_episodes", "ORDER BY episode_start"),
        "dx":       q("kp_tarp_dx_events",   "ORDER BY event_date"),
        "procs":    q("kp_tarp_proc_events",  "ORDER BY event_date"),
    }


=============================================================================
Payload builders for JSON serialization
=============================================================================

def to_days(val) -> int | None:
    if pd.isna(val):
        return None
    if isinstance(val, str):
        d = datetime.strptime(val[:10], "%Y-%m-%d").date()
    elif isinstance(val, datetime):
        d = val.date()
    else:
        d = val
    n = (d - datetime.strptime(TIME_START, "%Y-%m-%d").date()).days
    return max(0, min(n, TOTAL_DAYS))

def build_rx_rows(episodes: pd.DataFrame) -> list:
    if episodes.empty:
        return []
    ep = episodes.copy()
    ep["_order"] = ep["DRUG_CATEGORY"].map(
        lambda x: RX_CAT_CONFIG.get(x, {}).get("order", 99)
    )
    ep = ep.sort_values(["_order", "GENERIC_NAME", "EPISODE_START"])
    rows = []
    for (cat, name), grp in ep.groupby(["DRUG_CATEGORY", "GENERIC_NAME"], sort=False):
        cfg = RX_CAT_CONFIG.get(cat, {"color": "#888780", "bg": "#ebebeb"})
        eps = []
        for _, r in grp.iterrows():
            s, e = to_days(r["EPISODE_START"]), to_days(r["EPISODE_END"])
            if s is None or e is None:
                continue
            eps.append({
                "s": s, "e": e,
                "fills": int(r.get("N_FILLS", 0)),
                "days":  int(r.get("EPISODE_SPAN_DAYS", 0)),
                "dates": f"{str(r['EPISODE_START'])[:10]} to {str(r['EPISODE_END'])[:10]}",
            })
        if eps:
            rows.append({"label": name, "cat": cat,
                         "color": cfg["color"], "bg": cfg["bg"], "eps": eps})
    return rows

def build_dx_rows(dx: pd.DataFrame) -> tuple:
    if dx.empty:
        return [], []
    kidney, comorbidity = [], []
    for cat, grp in dx.dropna(subset=["DX_CATEGORY"]).groupby("DX_CATEGORY"):
        cfg = DX_CAT_CONFIG.get(cat)
        if not cfg:
            continue
        g = grp.copy()
        g["_month"] = pd.to_datetime(
            g["EVENT_DATE"].astype(str).str[:10]
        ).dt.to_period("M")
        days = [to_days(r) for r in
                g.drop_duplicates("_month").sort_values("EVENT_DATE")["EVENT_DATE"]
                if to_days(r) is not None]
        if not days:
            continue
        row = {"label": cat, "color": cfg["color"], "bg": cfg["bg"], "days": days}
        (kidney if cfg["panel"] == "kidney" else comorbidity).append(row)

    kid_order = ["IgAN (specific)", "IgAN (proxy)", "Recurrent hematuria",
                 "CKD stage 5 / ESRD", "CKD stage 4", "CKD stage 3",
                 "CKD stage 2", "CKD stage 1", "CKD unspecified",
                 "Nephrotic syndrome", "Proteinuria"]
    kidney.sort(key=lambda r: kid_order.index(r["label"])
                if r["label"] in kid_order else 99)
    return kidney, comorbidity

def build_proc_events(procs: pd.DataFrame) -> list:
    if procs.empty:
        return []
    out = []
    for _, r in procs.iterrows():
        day = to_days(r["EVENT_DATE"])
        if day is None:
            continue
        cfg = PROC_CONFIG.get(r["PROC_CATEGORY"], {"color": "#888780", "sym": "\u25cf"})
        out.append({"label": r["PROC_CATEGORY"], "code": r["PROCEDURE_CODE"],
                    "color": cfg["color"], "sym": cfg["sym"], "day": day})
    return out


=============================================================================
HTML generator with JavaScript Canvas rendering
=============================================================================

_JS_TEMPLATE = r"""
const D = %%PAYLOAD%%;

const LM=175, RM=120, RH=20, RG=4, PG=20, SH=16, TOP=32;

function dayToDate(n){
  const d=new Date(2020,0,1); d.setDate(d.getDate()+n);
  return d.toLocaleDateString('en-GB',{day:'numeric',month:'short',year:'numeric'});
}

const cv=document.getElementById('cv');
const tip=document.getElementById('tip');
const wrap=cv.parentElement;

function pill(ctx,x1,cy,x2,h,color){
  const r=h/2, bw=Math.max(x2-x1,2);
  ctx.fillStyle=color;
  if(bw<h){ ctx.beginPath(); ctx.arc(x1+bw/2,cy,Math.max(bw/2,1),0,Math.PI*2); ctx.fill(); }
  else{
    ctx.beginPath();
    ctx.moveTo(x1+r,cy-r); ctx.lineTo(x2-r,cy-r);
    ctx.arc(x2-r,cy,r,-Math.PI/2,Math.PI/2);
    ctx.lineTo(x1+r,cy+r);
    ctx.arc(x1+r,cy,r,Math.PI/2,-Math.PI/2);
    ctx.closePath(); ctx.fill();
  }
}

function render(){
  const W=wrap.offsetWidth||900;
  cv.width=W;
  const TW=W-LM-RM;
  const hits=[];
  function px(d){ return LM+(d/D.total)*TW; }

  let y=TOP;
  const rxY=[], rxSY=y;
  y+=SH+6; D.rx.forEach(()=>{rxY.push(y); y+=RH+RG;});
  const rxEY=y; y+=PG;
  const kidY=[], kidSY=y;
  y+=SH+6; D.kidney.forEach(()=>{kidY.push(y); y+=RH+RG;}); y+=PG;
  const comY=[], comSY=y;
  if(D.comorbidity.length>0){ y+=SH+6; D.comorbidity.forEach(()=>{comY.push(y); y+=RH+RG;}); y+=PG; }
  const procSY=y, procRY=y+SH+6;
  y+=SH+6+RH+16;

  cv.height=y;
  const ctx=cv.getContext('2d');
  ctx.clearRect(0,0,W,y);
  ctx.fillStyle='#fff'; ctx.fillRect(0,0,W,y);

  for(let yr=2020;yr<=2026;yr++){
    const d=(new Date(yr,0,1)-new Date(2020,0,1))/86400000, x=px(d);
    ctx.strokeStyle='#eaeaf2'; ctx.lineWidth=0.5; ctx.setLineDash([]);
    ctx.beginPath(); ctx.moveTo(x,TOP+2); ctx.lineTo(x,y-6); ctx.stroke();
    ctx.fillStyle='#bbb'; ctx.font='10px sans-serif'; ctx.textAlign='center';
    ctx.fillText(yr,x,TOP-7);
  }

  const tx=px(D.tarpeyo_day);
  ctx.strokeStyle='#185FA599'; ctx.lineWidth=1.2; ctx.setLineDash([5,3]);
  ctx.beginPath(); ctx.moveTo(tx,TOP+2); ctx.lineTo(tx,y-6); ctx.stroke();
  ctx.setLineDash([]);
  ctx.fillStyle='#185FA5'; ctx.font='500 9.5px sans-serif'; ctx.textAlign='center';
  ctx.fillText('\u25b2 Tarpeyo',tx,TOP-7);

  function hdr(label,color,ry){
    ctx.fillStyle=color+'18'; ctx.fillRect(LM,ry,TW,SH);
    ctx.fillStyle=color; ctx.font='500 9.5px sans-serif'; ctx.textAlign='left';
    ctx.fillText(label.toUpperCase(),LM+6,ry+SH-4);
  }

  hdr('Rx treatment','#185FA5',rxSY);
  D.rx.forEach((row,i)=>{
    const ry=rxY[i], cy=ry+RH/2;
    ctx.fillStyle=row.bg+'99'; ctx.fillRect(LM,ry,TW,RH);
    ctx.fillStyle='#444'; ctx.font='11px sans-serif'; ctx.textAlign='right';
    ctx.fillText(row.label,LM-7,cy+4);
    row.eps.forEach(ep=>{
      const x1=px(ep.s),x2=px(ep.e);
      pill(ctx,x1,cy,x2,RH-5,row.color);
      hits.push({x1,y1:ry,x2,y2:ry+RH,
        html:`<strong>${row.label}</strong>${ep.dates}<br>Fills: ${ep.fills} &middot; ${ep.days} days<br>Category: ${row.cat}`});
    });
  });

  const catGroups=[]; let cg=null;
  D.rx.forEach((row,i)=>{
    const ry=rxY[i];
    if(!cg||cg.cat!==row.cat){if(cg)catGroups.push(cg); cg={cat:row.cat,color:row.color,y1:ry,y2:ry+RH};}
    else{cg.y2=ry+RH;}
  });
  if(cg) catGroups.push(cg);

  catGroups.forEach(g=>{
    const bx=W-RM+10, mid=(g.y1+g.y2)/2, span=g.y2-g.y1;
    ctx.strokeStyle=g.color+'bb'; ctx.lineWidth=0.75; ctx.setLineDash([]);
    if(span>RH+2){
      ctx.beginPath();
      ctx.moveTo(bx-3,g.y1+2); ctx.lineTo(bx,g.y1+2);
      ctx.lineTo(bx,g.y2-2); ctx.lineTo(bx-3,g.y2-2);
      ctx.stroke();
    } else {
      ctx.beginPath(); ctx.moveTo(bx-4,mid); ctx.lineTo(bx,mid); ctx.stroke();
    }
    ctx.fillStyle=g.color; ctx.font='10px sans-serif'; ctx.textAlign='left';
    ctx.fillText(g.cat,bx+5,mid+4);
  });

  hdr('Kidney Dx','#0C447C',kidSY);
  D.kidney.forEach((row,i)=>{
    const ry=kidY[i], cy=ry+RH/2;
    ctx.fillStyle=row.bg+'77'; ctx.fillRect(LM,ry,TW,RH);
    ctx.fillStyle='#555'; ctx.font='11px sans-serif'; ctx.textAlign='right';
    ctx.fillText(row.label,LM-7,cy+4);
    row.days.forEach(d=>{
      const x=px(d);
      ctx.beginPath(); ctx.arc(x,cy,4,0,Math.PI*2); ctx.fillStyle=row.color; ctx.fill();
      hits.push({x1:x-5,y1:cy-5,x2:x+5,y2:cy+5,
        html:`<strong>${row.label}</strong>Date: ${dayToDate(d)}`});
    });
  });

  if(D.comorbidity.length>0){
    hdr('Comorbidities','#5F5E5A',comSY);
    D.comorbidity.forEach((row,i)=>{
      const ry=comY[i], cy=ry+RH/2;
      ctx.fillStyle=row.bg+'77'; ctx.fillRect(LM,ry,TW,RH);
      ctx.fillStyle='#555'; ctx.font='11px sans-serif'; ctx.textAlign='right';
      ctx.fillText(row.label,LM-7,cy+4);
      row.days.forEach(d=>{
        const x=px(d);
        ctx.beginPath(); ctx.arc(x,cy,4,0,Math.PI*2); ctx.fillStyle=row.color; ctx.fill();
        hits.push({x1:x-5,y1:cy-5,x2:x+5,y2:cy+5,
          html:`<strong>${row.label}</strong>Date: ${dayToDate(d)}`});
      });
    });
  }

  hdr('Procedures','#854F0B',procSY);
  const pcy=procRY+RH/2;
  ctx.fillStyle='#f5f5f5'; ctx.fillRect(LM,procRY,TW,RH);
  ctx.fillStyle='#888'; ctx.font='11px sans-serif'; ctx.textAlign='right';
  ctx.fillText('Events',LM-7,pcy+4);
  D.procs.forEach(ev=>{
    const x=px(ev.day);
    ctx.fillStyle=ev.color+'22'; ctx.strokeStyle=ev.color+'88'; ctx.lineWidth=0.5;
    ctx.beginPath(); ctx.arc(x,pcy,9,0,Math.PI*2); ctx.fill(); ctx.stroke();
    ctx.font='bold 12px sans-serif'; ctx.fillStyle=ev.color; ctx.textAlign='center';
    ctx.fillText(ev.sym,x,pcy+5);
    hits.push({x1:x-10,y1:pcy-10,x2:x+10,y2:pcy+10,
      html:`<strong>${ev.label}</strong>Code: ${ev.code}<br>Date: ${dayToDate(ev.day)}`});
  });

  cv.onmousemove=e=>{
    const r=cv.getBoundingClientRect(), mx=e.clientX-r.left, my=e.clientY-r.top;
    const h=hits.find(h=>mx>=h.x1&&mx<=h.x2&&my>=h.y1&&my<=h.y2);
    if(h){
      tip.innerHTML=h.html; tip.style.display='block';
      let lx=mx+14; if(lx+235>W)lx=mx-245;
      tip.style.left=Math.max(0,lx)+'px'; tip.style.top=Math.max(0,my-24)+'px';
    } else { tip.style.display='none'; }
  };
  cv.onmouseleave=()=>{ tip.style.display='none'; };

  const leg=document.getElementById('leg'); leg.innerHTML='';
  const seen=new Set();
  [
    ...D.rx.map(r=>({label:r.label+' \u00b7 '+r.cat,color:r.color,type:'bar'})),
    ...D.kidney.map(r=>({label:r.label,color:r.color,type:'dot'})),
    ...D.comorbidity.map(r=>({label:r.label,color:r.color,type:'dot'})),
    ...D.procs.map(e=>({label:e.label+' '+e.sym,color:e.color,type:'dot'})),
  ].forEach(it=>{
    if(seen.has(it.label))return; seen.add(it.label);
    const div=document.createElement('div'); div.className='li';
    const ic=document.createElement('div'); ic.className=it.type==='bar'?'libar':'lidot';
    ic.style.background=it.color; div.appendChild(ic);
    const lbl=document.createElement('span'); lbl.textContent=it.label;
    div.appendChild(lbl); leg.appendChild(div);
  });
}

render();
window.addEventListener('resize',render);
"""

_HTML_WRAPPER = """\
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Patient timeline {pid_short}</title>
<style>
*{{box-sizing:border-box;margin:0;padding:0}}
body{{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
      background:#fff;padding:14px;color:#1a1a1a}}
.ptcard{{display:flex;align-items:center;flex-wrap:wrap;gap:6px;
         padding:10px 14px;background:#f8f9fb;border:0.5px solid #e0e0e8;
         border-radius:8px;margin-bottom:10px}}
.ptid{{font-size:13px;font-weight:500}}
.ptsub{{font-size:11px;color:#888;margin-left:6px}}
.badge{{font-size:10.5px;font-weight:500;padding:2px 8px;border-radius:4px}}
.chart-wrap{{position:relative}}
#tip{{position:absolute;background:#fff;border:0.5px solid #ccc;border-radius:6px;
      padding:7px 11px;font-size:11px;line-height:1.6;color:#333;pointer-events:none;
      display:none;z-index:10;max-width:230px}}
#tip strong{{font-weight:500;color:#111;display:block;margin-bottom:1px}}
.legend{{display:flex;flex-wrap:wrap;gap:10px;margin-top:10px;
         padding-top:10px;border-top:0.5px solid #e8e8f0}}
.li{{display:flex;align-items:center;gap:5px;font-size:10px;color:#666}}
.libar{{width:14px;height:7px;border-radius:3px;flex-shrink:0}}
.lidot{{width:8px;height:8px;border-radius:50%;flex-shrink:0}}
</style>
</head>
<body>
<div class="ptcard">
  <span class="ptid">{pid_short}</span>
  <span class="ptsub">Symphony APLD &middot; IgAN / Tarpeyo</span>
  <span class="badge" style="background:#E6F1FB;color:#185FA5;margin-left:auto">
    Tarpeyo start: {first_fill}
  </span>
  <span class="badge" style="background:#EAF3DE;color:#3B6D11">
    {n_fills} fills in Symphony
  </span>
</div>
<div class="chart-wrap">
  <canvas id="cv"></canvas>
  <div id="tip"></div>
</div>
<div class="legend" id="leg"></div>
<script>
{js}
</script>
</body>
</html>"""

def generate_timeline_html(data: dict, patient_id: str) -> str:
    cohort = data["cohort"]
    if cohort.empty:
        return f"<p>No cohort record for patient {patient_id}</p>"

    meta = cohort.iloc[0]
    first_fill = str(meta["FIRST_TARPEYO_FILL"])[:10]
    n_fills = int(meta["N_TARPEYO_FILLS"])
    tarpeyo_day = to_days(first_fill)

    kidney, comorbidity = build_dx_rows(data["dx"])

    payload = {
        "patient_id":  patient_id,
        "pid_short":   patient_id[:8] + "...",
        "first_fill":  first_fill,
        "n_fills":     n_fills,
        "total":       TOTAL_DAYS,
        "tarpeyo_day": tarpeyo_day,
        "time_start":  TIME_START,
        "time_end":    TIME_END,
        "rx":          build_rx_rows(data["episodes"]),
        "kidney":      kidney,
        "comorbidity": comorbidity,
        "procs":       build_proc_events(data["procs"]),
    }

    js = _JS_TEMPLATE.replace("%%PAYLOAD%%", json.dumps(payload))
    return _HTML_WRAPPER.format(
        pid_short  = patient_id[:8] + "...",
        first_fill = first_fill,
        n_fills    = n_fills,
        js         = js,
    )


=============================================================================
Generate timelines for ALL patients (local files only)
=============================================================================

TMP_DIR = "/tmp/kp_timelines"
os.makedirs(TMP_DIR, exist_ok=True)

patients = session.sql("""
SELECT PATIENT_ID
FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_cohort
ORDER BY first_tarpeyo_fill
""").to_pandas()["PATIENT_ID"].tolist()

print(f"Generating timelines for {len(patients)} patients...")

for i, pid in enumerate(patients):
    try:
        data = load_patient(session, pid)
        html = generate_timeline_html(data, pid)

        fpath = os.path.join(TMP_DIR, f"timeline_{pid}.html")

        with open(fpath, "w", encoding="utf-8") as f:
            f.write(html)

        if (i + 1) % 25 == 0 or i == 0:
            print(f"Saved {i+1}/{len(patients)} : {fpath}")

    except Exception as e:
        print(f"FAILED for {pid}: {e}")

print("\nDone.")
print(f"Local files saved under: {TMP_DIR}")

*/


-- =====================================================
-- ALTERNATIVE SQL: GET PATIENT DATA FOR SINGLE TIMELINE
-- =====================================================

/*
-- To get data for a single patient's timeline (replace with actual patient ID):

-- Cohort info
SELECT FIRST_TARPEYO_FILL, N_TARPEYO_FILLS
FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_cohort
WHERE PATIENT_ID = '00000000000406938296';

-- Rx episodes
SELECT DRUG_CATEGORY, GENERIC_NAME, EPISODE_START, EPISODE_END, N_FILLS, EPISODE_SPAN_DAYS
FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_rx_episodes
WHERE PATIENT_ID = '00000000000406938296'
ORDER BY EPISODE_START;

-- Diagnosis events
SELECT DX_CATEGORY, EVENT_DATE
FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_dx_events
WHERE PATIENT_ID = '00000000000406938296'
ORDER BY EVENT_DATE;

-- Procedure events
SELECT PROC_CATEGORY, PROCEDURE_CODE, EVENT_DATE
FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_proc_events
WHERE PATIENT_ID = '00000000000406938296'
ORDER BY EVENT_DATE;

*/


-- =====================================================
-- END OF SCRIPT
-- =====================================================
