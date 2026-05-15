"""
render_timelines.py
-------------------
Read 5 CSVs (exports from timeline_pipeline.sql PART B), emit one v2-style
HTML per patient.

Usage:
    python3 render_timelines.py --input_dir ./input --output_dir ./out
    python3 render_timelines.py --input_dir ./input --output_dir ./out --limit 5

Input files (expected in --input_dir):
    patient_header.csv
    rx_episodes.csv
    dx_events.csv
    procedure_events.csv
    physician_episodes.csv

Output: one timeline_<PATIENT_ID>.html per patient.

No external dependencies. Python 3.8+.
"""

from __future__ import annotations
import argparse
import csv
import math
from datetime import date, datetime
from pathlib import Path


# ============================================================
# CONSTANTS
# ============================================================

# Fixed timeline window. All patients share the same axis for cross-patient comparability.
TIMELINE_START = date(2020, 1, 1)
TIMELINE_END   = date(2026, 4, 30)
SPAN_DAYS      = (TIMELINE_END - TIMELINE_START).days  # 2311

# SVG geometry (matches v2 mock)
SVG_WIDTH      = 1220
LEFT_MARGIN    = 200
RIGHT_MARGIN   = 130
PLOT_WIDTH     = SVG_WIDTH - LEFT_MARGIN - RIGHT_MARGIN  # 890
PX_PER_DAY     = PLOT_WIDTH / SPAN_DAYS                  # ~0.385

# Vertical rhythm
ROW_H          = 28
BAR_H          = 14
SECTION_GAP    = 30
TOP_AXIS_PAD   = 30
BOT_AXIS_PAD   = 30

# Therapy group palette (sampled from production timeline)
THERAPY_COLOR = {
    "ACEi":              "#2B7A5C",
    "ARB":               "#4FAA8B",
    "SGLT2i":            "#5D7A2E",
    "Steroid":           "#C0742B",
    "Immunosuppressant": "#5D4FA0",
    "Tarpeyo":           "#155FA0",
}
THERAPY_ORDER = ["ACEi", "ARB", "SGLT2i", "Steroid", "Immunosuppressant", "Tarpeyo"]
DEFAULT_RX_COLOR = "#888780"

# Dx palette
DX_COLOR = {
    "IgAN":          "#8E2D5C",
    "CKD stage 2":   "#D49CA6",
    "CKD stage 3a":  "#A32D2D",
    "CKD stage 3b":  "#A32D2D",
    "CKD stage 4":   "#A32D2D",
    "CKD stage 5":   "#A32D2D",
    "Hypertension":  "#888780",
    "Nephrotic syndrome": "#5D4FA0",
    "Proteinuria":   "#5D4FA0",
}
DEFAULT_DX_COLOR = "#888780"

# Procedure marker shape + color
PROC_STYLE = {
    "Kidney biopsy":         ("diamond", "#854F0B"),
    "Dialysis":              ("square",  "#A32D2D"),
    "Kidney transplant":     ("star",    "#0C447C"),
    "Other renal procedure": ("circle",  "#888780"),
}
DEFAULT_PROC_STYLE = ("circle", "#888780")
PROC_ORDER = ["Kidney biopsy", "Dialysis", "Kidney transplant", "Other renal procedure"]

# Physician specialty palette
SPECIALTY_COLOR = {
    "Nephrology":       "#185FA5",
    "Primary care":     "#6B7280",
    "Hospitalist":      "#854F0B",
    "Urology":          "#5A8F4A",
    "Lab / path / rad": "#9AA0A6",
    "Other":            "#A32D2D",
    "Unknown":          "#C8C4B5",
}
SPECIALTY_SORT_RANK = {
    "Nephrology":       0,
    "Primary care":     1,
    "Hospitalist":      2,
    "Urology":          3,
    "Other":            4,
    "Lab / path / rad": 5,
    "Unknown":          6,
}


# ============================================================
# HELPERS
# ============================================================

def parse_date(s):
    """Tolerant date parser. Accepts 'YYYY-MM-DD', 'YYYY-MM', date, or empty."""
    if s is None or s == "" or s == "NULL":
        return None
    if isinstance(s, date):
        return s
    s = str(s).strip()[:10]
    if len(s) == 7:  # YYYY-MM -> centre at the 15th
        return datetime.strptime(s + "-15", "%Y-%m-%d").date()
    return datetime.strptime(s, "%Y-%m-%d").date()


def x_of(d):
    """Map date to SVG x, clipped to plot region."""
    if d is None:
        return None
    days = (d - TIMELINE_START).days
    return LEFT_MARGIN + days * PX_PER_DAY


def xml_escape(s):
    if s is None:
        return ""
    return (str(s)
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace('"', "&quot;"))


def read_csv_grouped(path, key="PATIENT_ID"):
    """Read CSV, group rows by key. Normalises column names to upper-case."""
    grouped = {}
    if not path.exists():
        print(f"  warning: {path.name} not found, returning empty")
        return grouped
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            row = {k.upper(): v for k, v in row.items()}
            pid = row.get(key.upper())
            if pid is None:
                continue
            grouped.setdefault(pid, []).append(row)
    return grouped


# ============================================================
# PANEL RENDERERS
# Each returns (svg_fragment, y_bottom_of_panel)
# ============================================================

def render_rx_panel(episodes, y_top):
    """Rx episodes: one row per drug, pill bars, therapy-group label on right."""
    # Group by drug, preserving therapy_group
    by_drug = {}
    for ep in episodes:
        drug = ep.get("DRUG_NAME") or "Unknown"
        tg = ep.get("THERAPY_GROUP") or "Other"
        if drug not in by_drug:
            by_drug[drug] = {"therapy_group": tg, "episodes": []}
        by_drug[drug]["episodes"].append(ep)

    # Sort: by therapy_group order, then by drug name
    def sort_key(item):
        drug, info = item
        tg = info["therapy_group"]
        rank = THERAPY_ORDER.index(tg) if tg in THERAPY_ORDER else 99
        return (rank, drug)

    rows = sorted(by_drug.items(), key=sort_key)
    parts = []
    for i, (drug, info) in enumerate(rows):
        y_centre = y_top + i * ROW_H + ROW_H // 2
        y_block = y_centre - BAR_H // 2
        tg = info["therapy_group"]
        color = THERAPY_COLOR.get(tg, DEFAULT_RX_COLOR)
        # row rule
        parts.append(
            f'<line class="row-rule" x1="{LEFT_MARGIN}" y1="{y_centre + 6}" '
            f'x2="{SVG_WIDTH - RIGHT_MARGIN}" y2="{y_centre + 6}"/>'
        )
        # left drug label
        parts.append(
            f'<text class="row-label-left" x="{LEFT_MARGIN - 10}" y="{y_centre + 2}">'
            f'{xml_escape(drug)}</text>'
        )
        # episode bars
        for ep in info["episodes"]:
            s = parse_date(ep.get("EPISODE_START"))
            e = parse_date(ep.get("EPISODE_END"))
            if s is None or e is None:
                continue
            x0 = x_of(s)
            x1 = x_of(e)
            w = max(3.0, x1 - x0)
            days = (e - s).days
            parts.append(
                f'<rect class="rx-bar" x="{x0:.1f}" y="{y_block}" '
                f'width="{w:.1f}" height="{BAR_H}" rx="8" ry="8" fill="{color}" '
                f'data-drug="{xml_escape(drug)}" data-group="{xml_escape(tg)}" '
                f'data-start="{s}" data-end="{e}" data-days="{days}"/>'
            )
        # right therapy-group label
        parts.append(
            f'<text class="row-label-right" x="{SVG_WIDTH - RIGHT_MARGIN + 10}" '
            f'y="{y_centre + 2}" fill="{color}">{xml_escape(tg)}</text>'
        )

    y_bot = y_top + max(1, len(rows)) * ROW_H
    return "\n      ".join(parts), y_bot


def render_dx_panel(events, y_top):
    """Dx events as dots: one row per dx_group, monthly dedup applied upstream."""
    by_group = {}
    for ev in events:
        g = ev.get("DX_GROUP") or "Unknown"
        by_group.setdefault(g, []).append(ev)

    def rank(g):
        if g.startswith("IgAN") or "N02.B" in g: return 0
        if g.startswith("CKD"):                   return 1
        if g == "Nephrotic syndrome":             return 2
        if g == "Proteinuria":                    return 3
        if g == "Hypertension":                   return 4
        return 9

    rows = sorted(by_group.items(), key=lambda x: (rank(x[0]), x[0]))
    parts = []
    for i, (group, evs) in enumerate(rows):
        y_centre = y_top + i * ROW_H + ROW_H // 2
        color = DX_COLOR.get(group, DEFAULT_DX_COLOR)
        parts.append(
            f'<line class="row-rule" x1="{LEFT_MARGIN}" y1="{y_centre + 4}" '
            f'x2="{SVG_WIDTH - RIGHT_MARGIN}" y2="{y_centre + 4}"/>'
        )
        parts.append(
            f'<text class="row-label-left" x="{LEFT_MARGIN - 10}" y="{y_centre + 2}">'
            f'{xml_escape(group)}</text>'
        )
        for ev in evs:
            d = parse_date(ev.get("MONTH_START"))
            if d is None: continue
            x = x_of(d)
            parts.append(
                f'<circle class="dx-dot" cx="{x:.1f}" cy="{y_centre}" r="4" '
                f'fill="{color}" data-event="{xml_escape(group)}" '
                f'data-date="{d.strftime("%Y-%m")}"/>'
            )

    y_bot = y_top + max(1, len(rows)) * ROW_H
    return "\n      ".join(parts), y_bot


def render_proc_panel(events, y_top):
    """Procedure markers: diamonds (biopsy), squares (dialysis), stars (transplant)."""
    by_group = {}
    for ev in events:
        g = ev.get("PROC_GROUP") or "Other renal procedure"
        by_group.setdefault(g, []).append(ev)

    def rank(g):
        return PROC_ORDER.index(g) if g in PROC_ORDER else 99

    rows = sorted(by_group.items(), key=lambda x: rank(x[0]))
    parts = []
    for i, (group, evs) in enumerate(rows):
        y_centre = y_top + i * ROW_H + ROW_H // 2
        shape, color = PROC_STYLE.get(group, DEFAULT_PROC_STYLE)
        parts.append(
            f'<line class="row-rule" x1="{LEFT_MARGIN}" y1="{y_centre + 4}" '
            f'x2="{SVG_WIDTH - RIGHT_MARGIN}" y2="{y_centre + 4}"/>'
        )
        parts.append(
            f'<text class="row-label-left" x="{LEFT_MARGIN - 10}" y="{y_centre + 2}">'
            f'{xml_escape(group)}</text>'
        )
        for ev in evs:
            d = parse_date(ev.get("MONTH_START"))
            if d is None: continue
            x = x_of(d)
            parts.append(_proc_marker(shape, x, y_centre, color, group, d))

    y_bot = y_top + max(1, len(rows)) * ROW_H
    return "\n      ".join(parts), y_bot


def _proc_marker(shape, x, y, color, group, d):
    meta = f'data-event="{xml_escape(group)}" data-date="{d.strftime("%Y-%m")}"'
    if shape == "diamond":
        return (f'<polygon class="proc-marker" '
                f'points="{x:.1f},{y-7} {x+7:.1f},{y} {x:.1f},{y+7} {x-7:.1f},{y}" '
                f'fill="{color}" {meta}/>')
    if shape == "square":
        return (f'<rect class="proc-marker" x="{x-5:.1f}" y="{y-5}" width="10" height="10" '
                f'fill="{color}" {meta}/>')
    if shape == "star":
        pts = []
        for k in range(10):
            ang = math.pi / 2 + k * math.pi / 5
            r = 7 if k % 2 == 0 else 3
            pts.append(f"{x + r * math.cos(ang):.1f},{y - r * math.sin(ang):.1f}")
        return f'<polygon class="proc-marker" points="{" ".join(pts)}" fill="{color}" {meta}/>'
    return f'<circle class="proc-marker" cx="{x:.1f}" cy="{y}" r="4" fill="{color}" {meta}/>'


def render_phys_panel(episodes, first_tarpeyo_npi, y_top):
    """Physician rows: one row per NPI; first-Tarpeyo prescriber has a heavier outline."""
    by_npi = {}
    for ep in episodes:
        npi = ep.get("NPI")
        if not npi: continue
        if npi not in by_npi:
            by_npi[npi] = {
                "specialty_desc":  ep.get("SPECIALTY_DESC") or "Unknown",
                "specialty_group": ep.get("SPECIALTY_GROUP") or "Unknown",
                "state":           ep.get("PHYSICIAN_STATE") or "",
                "episodes":        [],
            }
        by_npi[npi]["episodes"].append(ep)

    def first_start(info):
        starts = [parse_date(e.get("EPISODE_START")) for e in info["episodes"]]
        starts = [s for s in starts if s is not None]
        return min(starts) if starts else TIMELINE_END

    rows = sorted(
        by_npi.items(),
        key=lambda x: (
            SPECIALTY_SORT_RANK.get(x[1]["specialty_group"], 99),
            first_start(x[1]),
        ),
    )

    parts = []
    for i, (npi, info) in enumerate(rows):
        y_centre = y_top + i * ROW_H + ROW_H // 2
        y_block = y_centre - BAR_H // 2
        color = SPECIALTY_COLOR.get(info["specialty_group"], SPECIALTY_COLOR["Unknown"])
        is_init = (str(npi) == str(first_tarpeyo_npi)) if first_tarpeyo_npi else False
        stroke = ('stroke="#0D0B09" stroke-width="1.25"' if is_init
                  else 'stroke="rgba(0,0,0,0.08)" stroke-width="0.5"')

        parts.append(
            f'<line class="row-rule" x1="{LEFT_MARGIN}" y1="{y_centre + 6}" '
            f'x2="{SVG_WIDTH - RIGHT_MARGIN}" y2="{y_centre + 6}"/>'
        )
        label_left = (info["specialty_desc"] or "Unknown")[:22]
        parts.append(
            f'<text class="row-label-left" x="{LEFT_MARGIN - 10}" y="{y_centre + 2}">'
            f'{xml_escape(label_left)}</text>'
        )

        for ep in info["episodes"]:
            s = parse_date(ep.get("EPISODE_START"))
            e = parse_date(ep.get("EPISODE_END"))
            if s is None or e is None:
                continue
            x0 = x_of(s); x1 = x_of(e)
            w = max(3.0, x1 - x0)
            parts.append(
                f'<rect class="phys-bar" x="{x0:.1f}" y="{y_block}" '
                f'width="{w:.1f}" height="{BAR_H}" rx="7" ry="7" fill="{color}" {stroke} '
                f'data-spec="{xml_escape(info["specialty_desc"])}" data-npi="{npi}" '
                f'data-state="{xml_escape(info["state"])}" '
                f'data-start="{s}" data-end="{e}" '
                f'data-rx="{ep.get("N_RX", 0) or 0}" '
                f'data-dx="{ep.get("N_DX", 0) or 0}" '
                f'data-px="{ep.get("N_PX", 0) or 0}" '
                f'data-is-tarpeyo-prescriber="{str(is_init).lower()}"/>'
            )
        parts.append(
            f'<text class="phys-meta-right" x="{SVG_WIDTH - RIGHT_MARGIN + 10}" '
            f'y="{y_centre + 2}">NPI {npi}</text>'
        )

    y_bot = y_top + max(1, len(rows)) * ROW_H
    return "\n      ".join(parts), y_bot


def render_axis(tarpeyo_date, y_top_panel, y_bot_panel):
    """Year gridlines + Tarpeyo-start anchor that span the entire SVG."""
    parts = []
    for yr in range(2020, 2027):
        x = x_of(date(yr, 1, 1))
        parts.append(
            f'<line class="year-rule" x1="{x:.1f}" y1="{y_top_panel}" '
            f'x2="{x:.1f}" y2="{y_bot_panel}"/>'
        )
    if tarpeyo_date:
        xt = x_of(tarpeyo_date)
        parts.append(
            f'<line class="anchor-line" x1="{xt:.1f}" y1="{y_top_panel}" '
            f'x2="{xt:.1f}" y2="{y_bot_panel}"/>'
        )
        parts.append(
            f'<text class="anchor-label" x="{xt + 5:.1f}" y="{y_top_panel + 10}">'
            f'Tarpeyo start</text>'
        )
    return "\n      ".join(parts)


def render_year_labels(y):
    return "\n      ".join(
        f'<text class="year-label" x="{x_of(date(yr,1,1)):.1f}" y="{y}">{yr}</text>'
        for yr in range(2020, 2027)
    )


# ============================================================
# FULL-PAGE TEMPLATE
# ============================================================

TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Tarpeyo timeline · {patient_id}</title>
<style>
  :root {{
    --bg: #F0EBDE; --panel: #FFFFFF; --border: rgba(0,0,0,0.07);
    --ink: #1A1714; --meta: #8A847A; --rule: #ECE6D6; --axis: #B0A99C;
    --tarpeyo: #155FA0;
  }}
  body {{ margin:0; font-family: ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
         background: var(--bg); color: var(--ink); font-size: 13px; line-height: 1.4; }}
  .page {{ max-width: 1220px; margin: 0 auto; padding: 28px 28px 36px; }}
  .header-pill {{ background: #FFFFFF; border: 1px solid var(--border); border-radius: 10px;
                  padding: 12px 18px; margin-bottom: 16px; display: flex; gap: 18px;
                  align-items: baseline; flex-wrap: wrap; box-shadow: 0 1px 2px rgba(0,0,0,0.025); }}
  .header-pill .pid {{ font-weight: 600; font-size: 14px; }}
  .header-pill .field {{ color: var(--meta); font-size: 12.5px; }}
  .header-pill .field b {{ color: var(--ink); font-weight: 600; }}
  .timeline-card {{ background: var(--panel); border: 1px solid var(--border); border-radius: 14px;
                    padding: 18px 22px 14px; box-shadow: 0 1px 2px rgba(0,0,0,0.025); }}
  svg.timeline {{ display: block; width: 100%; }}
  .section-label {{ font-size: 10px; font-weight: 600; letter-spacing: 0.09em;
                    text-transform: uppercase; fill: var(--meta); }}
  .row-label-left {{ font-size: 12px; fill: var(--ink); text-anchor: end; font-weight: 400; }}
  .row-label-right {{ font-size: 12px; text-anchor: start; font-weight: 600; }}
  .row-rule {{ stroke: var(--rule); stroke-width: 0.5; }}
  .year-rule {{ stroke: var(--rule); stroke-width: 0.5; stroke-dasharray: 2 4; }}
  .year-label {{ font-size: 11px; fill: var(--axis); text-anchor: middle; }}
  .anchor-line {{ stroke: var(--tarpeyo); stroke-width: 1; stroke-dasharray: 4 3; }}
  .anchor-label {{ font-size: 11px; fill: var(--tarpeyo); font-weight: 500; }}
  .rx-bar, .phys-bar {{ }} .dx-dot {{ stroke: #FFFFFF; stroke-width: 0.6; }}
  .phys-meta-right {{ font-size: 10px; fill: var(--meta); text-anchor: start;
                      font-variant-numeric: tabular-nums; }}
  .tooltip {{ position: absolute; background: var(--ink); color: #FFFFFF;
              padding: 8px 11px; border-radius: 6px; font-size: 11px; line-height: 1.45;
              pointer-events: none; max-width: 280px; opacity: 0; transition: opacity 90ms ease;
              z-index: 10; box-shadow: 0 6px 18px rgba(0,0,0,0.18); }}
  .tooltip b {{ font-weight: 600; }}
  .tooltip .sep {{ height: 1px; background: rgba(255,255,255,0.15); margin: 5px 0; }}
  .tooltip .head-init {{ color:#FFD089; font-weight:600; margin-bottom:4px; }}
  .footnote {{ color: var(--meta); font-size: 11.5px; margin: 12px 0 0; line-height: 1.5; }}
</style>
</head>
<body>
<div class="page">
  <div class="header-pill">
    <span class="pid">PATIENT {patient_id}</span>
    <span class="field">first Tarpeyo fill <b>{first_tarpeyo_fill}</b></span>
    <span class="field">pre-Tx drug classes <b>{pre_tx_classes}</b></span>
    <span class="field">distinct physicians <b>{n_physicians}</b></span>
    <span class="field">sourcing pool <b>{sourcing_pool}</b></span>
  </div>
  <div class="timeline-card">
    <svg class="timeline" viewBox="0 0 {svg_w} {svg_h}" preserveAspectRatio="none">
      {top_year_labels}
      {axis_lines}
      <text class="section-label" x="20" y="{rx_label_y}">RX EPISODES</text>
      {rx_svg}
      <text class="section-label" x="20" y="{dx_label_y}">DX EVENTS · MONTHLY DEDUP</text>
      {dx_svg}
      <text class="section-label" x="20" y="{proc_label_y}">PROCEDURES</text>
      {proc_svg}
      <text class="section-label" x="20" y="{phys_label_y}">PHYSICIANS</text>
      {phys_svg}
      {bot_year_labels}
    </svg>
    <p class="footnote">
      Hover any bar or dot for details. Heavier outline = first Tarpeyo prescriber.
      60-day Rx gap-fill · monthly Dx / Procedure dedup · physician spans gap-filled at 60 days.
    </p>
  </div>
</div>
<div class="tooltip" id="tt"></div>
<script>
  const tt = document.getElementById('tt');
  function show(h) {{ tt.innerHTML = h; tt.style.opacity = '1'; }}
  function move(e) {{ tt.style.left = (e.clientX + 12) + 'px'; tt.style.top = (e.clientY + 12) + 'px'; }}
  function hide() {{ tt.style.opacity = '0'; }}
  function bind(sel, fmt) {{
    document.querySelectorAll(sel).forEach(el => {{
      el.addEventListener('mouseenter', () => show(fmt(el.dataset)));
      el.addEventListener('mousemove', move);
      el.addEventListener('mouseleave', hide);
    }});
  }}
  bind('.rx-bar', d => `<b>${{d.drug}}</b> <span style="opacity:.7">(${{d.group}})</span>
                       <div class="sep"></div>${{d.start}} &rarr; ${{d.end}}<br>episode ${{d.days}} days`);
  bind('.dx-dot', d => `<b>${{d.event}}</b><div class="sep"></div>${{d.date}}`);
  bind('.proc-marker', d => `<b>${{d.event}}</b><div class="sep"></div>${{d.date}}`);
  bind('.phys-bar', d => {{
    const head = d.isTarpeyoPrescriber === 'true'
      ? '<div class="head-init">First Tarpeyo prescriber</div>' : '';
    return head + `<b>${{d.spec}}</b>${{d.state ? ', ' + d.state : ''}}<br>
            <span style="opacity:.85;font-variant-numeric:tabular-nums">NPI ${{d.npi}}</span>
            <div class="sep"></div>${{d.start}} &rarr; ${{d.end}}<br>
            Rx ${{d.rx}} &middot; Dx ${{d.dx}} &middot; Px ${{d.px}}`;
  }});
</script>
</body>
</html>
"""


# ============================================================
# PER-PATIENT ASSEMBLY
# ============================================================

def render_patient(patient_id, header, rx, dx, proc, phys):
    """Assemble full HTML for one patient."""
    h = header.get(patient_id, {})
    tarpeyo_date = parse_date(h.get("FIRST_TARPEYO_FILL"))
    first_tarpeyo_npi = h.get("SOURCING_POOL_NPI")

    # Section layout: each panel starts a fixed gap below the previous
    y_cursor = TOP_AXIS_PAD + 18  # space for top axis labels + RX section label
    rx_label_y = y_cursor - 12

    rx_svg, y_cursor = render_rx_panel(rx.get(patient_id, []), y_cursor)

    y_cursor += SECTION_GAP
    dx_label_y = y_cursor - 12
    dx_svg, y_cursor = render_dx_panel(dx.get(patient_id, []), y_cursor)

    y_cursor += SECTION_GAP
    proc_label_y = y_cursor - 12
    proc_svg, y_cursor = render_proc_panel(proc.get(patient_id, []), y_cursor)

    y_cursor += SECTION_GAP
    phys_label_y = y_cursor - 12
    phys_svg, y_cursor = render_phys_panel(phys.get(patient_id, []), first_tarpeyo_npi, y_cursor)

    # Total height of the SVG
    panel_bottom = y_cursor + 12
    svg_h = panel_bottom + BOT_AXIS_PAD

    # Axis lines span the panel area; year labels at top and bottom
    axis_top    = TOP_AXIS_PAD - 6
    axis_bottom = panel_bottom
    axis_lines       = render_axis(tarpeyo_date, axis_top, axis_bottom)
    top_year_labels  = render_year_labels(16)
    bot_year_labels  = render_year_labels(panel_bottom + 14)

    return TEMPLATE.format(
        patient_id          = xml_escape(patient_id),
        first_tarpeyo_fill  = tarpeyo_date.strftime("%Y-%m-%d") if tarpeyo_date else "n/a",
        pre_tx_classes      = h.get("PRE_TX_DRUG_CLASSES", "?") or "0",
        n_physicians        = h.get("N_DISTINCT_PHYSICIANS", "?") or "0",
        sourcing_pool       = xml_escape(h.get("SOURCING_POOL") or "n/a"),
        svg_w               = SVG_WIDTH,
        svg_h               = svg_h,
        top_year_labels     = top_year_labels,
        bot_year_labels     = bot_year_labels,
        axis_lines          = axis_lines,
        rx_label_y          = rx_label_y,
        rx_svg              = rx_svg,
        dx_label_y          = dx_label_y,
        dx_svg              = dx_svg,
        proc_label_y        = proc_label_y,
        proc_svg            = proc_svg,
        phys_label_y        = phys_label_y,
        phys_svg            = phys_svg,
    )


# ============================================================
# MAIN
# ============================================================

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input_dir", default="./input")
    ap.add_argument("--output_dir", default="./timelines_out")
    ap.add_argument("--limit", type=int, default=None,
                    help="Render only the first N patients (debug)")
    args = ap.parse_args()

    inp = Path(args.input_dir)
    out = Path(args.output_dir)
    out.mkdir(parents=True, exist_ok=True)

    print(f"Loading CSVs from {inp}/")
    header_rows = read_csv_grouped(inp / "patient_header.csv")
    header = {pid: rows[0] for pid, rows in header_rows.items()}
    rx     = read_csv_grouped(inp / "rx_episodes.csv")
    dx     = read_csv_grouped(inp / "dx_events.csv")
    proc   = read_csv_grouped(inp / "procedure_events.csv")
    phys   = read_csv_grouped(inp / "physician_episodes.csv")

    print(f"  header: {len(header)} patients")
    print(f"  rx:     {sum(len(v) for v in rx.values())} episodes across {len(rx)} patients")
    print(f"  dx:     {sum(len(v) for v in dx.values())} events  across {len(dx)} patients")
    print(f"  proc:   {sum(len(v) for v in proc.values())} events  across {len(proc)} patients")
    print(f"  phys:   {sum(len(v) for v in phys.values())} episodes across {len(phys)} patients")

    pids = sorted(header.keys())
    if args.limit:
        pids = pids[:args.limit]

    print(f"Rendering {len(pids)} HTMLs to {out}/")
    for i, pid in enumerate(pids, start=1):
        html = render_patient(pid, header, rx, dx, proc, phys)
        (out / f"timeline_{pid}.html").write_text(html, encoding="utf-8")
        if i % 50 == 0:
            print(f"  {i}/{len(pids)}")
    print(f"Done. {len(pids)} files written.")


if __name__ == "__main__":
    main()
