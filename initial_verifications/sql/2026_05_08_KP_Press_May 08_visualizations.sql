-- =====================================================
-- TARPEYO PATIENT VISUALIZATION - SUPPORTING QUERIES
-- =====================================================

-- =====================================================
-- LOAD PATIENT DATA FOR VISUALIZATION
-- =====================================================

-- Rx episodes (treatment periods)
SELECT *
FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_rx_episodes;

-- Diagnosis events
SELECT *
FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_dx_events;

-- Procedure events
SELECT *
FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_proc_events;

-- Pre-Tarpeyo trajectory summary
SELECT *
FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_pre_trajectory;

-- Cohort information (patients with first Tarpeyo fill dates)
SELECT *
FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_cohort;

-- =====================================================
-- LABS ANALYSIS: DISTINCT STATES PER PATIENT
-- =====================================================

WITH per_patient AS (
    SELECT
        PATIENT_GID,
        COUNT(DISTINCT ORDERING_ACCOUNT_STATE) AS n_states
    FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_LABS
    GROUP BY PATIENT_GID
)
SELECT
    n_states,
    COUNT(*) AS n_patients
FROM per_patient
GROUP BY n_states
ORDER BY n_states;


-- =====================================================
-- PYTHON VISUALIZATION CODE
-- =====================================================

/*
=============================================================================
PATIENT TIMELINE VISUALIZATION (RX + DX + PROC unified style)
=============================================================================

import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
import matplotlib as mpl

# =============================================================================
# STYLE CONFIGURATION
# =============================================================================

mpl.rcParams.update({
    "font.size": 10,
    "font.weight": "bold",
    "axes.titleweight": "bold",
    "axes.labelweight": "bold",
})

RX_COLORS = {
    "Tarpeyo": "#185FA5",
    "Other IgAN": "#854F0B",
    "SGLT2i": "#3B6D11",
    "ACEi": "#0F6E56",
    "ARB": "#1D9E75",
    "Immunosuppressant": "#534AB7",
    "Systemic steroid": "#BA7517",
    "Diuretic / MRA": "#5F5E5A",
    "Omega-3": "#639922",
}

DX_COLORS = {
    "IgAN (specific)": "#0C447C",
    "IgAN (proxy)": "#185FA5",
    "Recurrent hematuria": "#378ADD",
    "CKD stage 5 / ESRD": "#791F1F",
    "CKD stage 4": "#A32D2D",
    "CKD stage 3": "#BA7517",
    "CKD stage 2": "#3B6D11",
    "CKD stage 1": "#639922",
    "CKD unspecified": "#888780",
    "Nephrotic syndrome": "#72243E",
    "Proteinuria": "#534AB7",
    "Hypertension": "#5F5E5A",
    "Type 2 diabetes": "#633806",
    "Dependence on dialysis": "#3C3489",
}

PROC_COLORS = {
    "Kidney biopsy": "#854F0B",
    "Dialysis": "#A32D2D",
    "Kidney transplant": "#0C447C",
    "Other renal procedure": "#888780",
}

# =============================================================================
# SELECT RANDOM PATIENT FROM COHORT
# =============================================================================

pid = dataframe_6.sample(1)["PATIENT_ID"].iloc[0]

print("Patient:", pid)

# =============================================================================
# FILTER DATA FOR SELECTED PATIENT
# =============================================================================

rx = dataframe_1[dataframe_1.PATIENT_ID == pid].copy()
dx = dataframe_2[dataframe_2.PATIENT_ID == pid].copy()
proc = dataframe_3[dataframe_3.PATIENT_ID == pid].copy()

# Convert to datetime
rx["EPISODE_START"] = pd.to_datetime(rx["EPISODE_START"])
rx["EPISODE_END"]   = pd.to_datetime(rx["EPISODE_END"])

dx["EVENT_DATE"] = pd.to_datetime(dx["EVENT_DATE"])
proc["EVENT_DATE"] = pd.to_datetime(proc["EVENT_DATE"])

# =============================================================================
# BUILD VISUALIZATION TRACKS
# =============================================================================

tracks = []

# ---- RX EPISODES (treatment periods as horizontal bars) ----
rx["_order"] = rx["DRUG_CATEGORY"].map({
    "Tarpeyo": 0,
    "Other IgAN": 1,
    "SGLT2i": 2,
    "ACEi": 3,
    "ARB": 4,
    "Immunosuppressant": 5,
    "Systemic steroid": 6,
    "Diuretic / MRA": 7,
    "Omega-3": 8
}).fillna(99)

rx = rx.sort_values(["_order", "GENERIC_NAME", "EPISODE_START"])

for (cat, drug), grp in rx.groupby(["DRUG_CATEGORY", "GENERIC_NAME"], sort=False):
    periods = [(r["EPISODE_START"], r["EPISODE_END"]) for _, r in grp.iterrows()]
    tracks.append({
        "label": drug,
        "type": "rx",
        "category": cat,
        "periods": periods
    })

# ---- DX EVENTS (dots per month, deduplicated) ----
for cat, grp in dx.groupby("DX_CATEGORY"):
    if pd.isna(cat):
        continue

    grp = grp.sort_values("EVENT_DATE")
    grp["_month"] = grp["EVENT_DATE"].dt.to_period("M")
    grp = grp.drop_duplicates("_month")  # One dot per month

    tracks.append({
        "label": cat,
        "type": "dx",
        "dates": grp["EVENT_DATE"].tolist()
    })

# ---- PROC EVENTS (single-day bars, same style as RX) ----
for cat, grp in proc.groupby("PROC_CATEGORY"):
    if pd.isna(cat):
        continue

    tracks.append({
        "label": cat,
        "type": "proc",
        "periods": [(d, d) for d in grp["EVENT_DATE"].tolist()]  # 1-day bars
    })

# =============================================================================
# CREATE THE PLOT
# =============================================================================

fig, ax = plt.subplots(figsize=(18, max(5, len(tracks) * 0.45)))
line_width = 9

for y, track in enumerate(tracks):

    # RX and PROC use horizontal bars
    if track["type"] in ["rx", "proc"]:

        color = (
            RX_COLORS.get(track["category"], "#777777")
            if track["type"] == "rx"
            else PROC_COLORS.get(track["label"], "#666666")
        )

        for start, end in track["periods"]:
            ax.hlines(
                y=y,
                xmin=start,
                xmax=end,
                color=color,
                linewidth=line_width,
                capstyle="round"
            )

    # DX uses dots
    else:
        color = DX_COLORS.get(track["label"], "#444444")

        ax.scatter(
            track["dates"],
            [y] * len(track["dates"]),
            color=color,
            s=90,
            edgecolors="white",
            linewidths=1.2,
            zorder=3
        )

# =============================================================================
# AXIS FORMATTING
# =============================================================================

yticks = list(range(len(tracks)))
ylabels = [t["label"] for t in tracks]

ax.set_yticks(yticks)
ax.set_yticklabels(ylabels)

ax.set_title(f"Patient Timeline\n{pid}", fontsize=18, pad=20)
ax.set_xlabel("Year")

ax.xaxis.set_major_locator(mdates.YearLocator())
ax.xaxis.set_major_formatter(mdates.DateFormatter("%Y"))

ax.set_xlim(pd.Timestamp("2020-01-01"), pd.Timestamp("2025-12-31"))

ax.grid(axis="x", linestyle="--", alpha=0.25)

# Remove all spines for cleaner look
for spine in ax.spines.values():
    spine.set_visible(False)

plt.tight_layout()
plt.show()

*/


-- =====================================================
-- ALTERNATIVE SQL FOR PATIENT TIMELINE DATA PREPARATION
-- =====================================================


-- To prepare timeline data for a specific patient in SQL:

WITH patient_episodes AS (
    SELECT 
        PATIENT_ID,
        DRUG_CATEGORY,
        GENERIC_NAME,
        EPISODE_START,
        EPISODE_END,
        'rx' AS event_type
    FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_rx_episodes
    WHERE PATIENT_ID = '00000000000406938296'  -- Replace with actual patient ID
    
    UNION ALL
    
    SELECT 
        PATIENT_ID,
        DX_CATEGORY AS DRUG_CATEGORY,
        DX_CATEGORY AS GENERIC_NAME,
        EVENT_DATE AS EPISODE_START,
        EVENT_DATE AS EPISODE_END,
        'dx' AS event_type
    FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_dx_events
    WHERE PATIENT_ID = '00000000000406938296'
    
    UNION ALL
    
    SELECT 
        PATIENT_ID,
        PROC_CATEGORY AS DRUG_CATEGORY,
        PROC_CATEGORY AS GENERIC_NAME,
        EVENT_DATE AS EPISODE_START,
        EVENT_DATE AS EPISODE_END,
        'proc' AS event_type
    FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_proc_events
    WHERE PATIENT_ID = '00000000000406938296'
)
SELECT *
FROM patient_episodes
ORDER BY EPISODE_START;



-- =====================================================
-- END OF SCRIPT
-- =====================================================
