-- =====================================================
-- USAGE OVER TIME UP TO TARPEYO - DRUG UTILIZATION ANALYSIS
-- =====================================================

-- =====================================================
-- LOAD DRUG HISTORIES DATA
-- =====================================================

SELECT * FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_drug_histories;


-- =====================================================
-- PYTHON CODE FOR TIME-RELATIVE DRUG UTILIZATION ANALYSIS
-- =====================================================

/*
# =============================================================================
# Find first Tarpeyo month for each patient
# =============================================================================

import pandas as pd

tarpeyo = dataframe_1[
    dataframe_1["THERAPY_GROUP"].str.upper() == "TARPEYO"
].copy()

first_tarpeyo = (
    tarpeyo
    .groupby("PATIENT_ID")["MONTH_IDX"]
    .min()
    .reset_index()
    .rename(columns={"MONTH_IDX": "FIRST_TARPEYO_MONTH_IDX"})
)

print(first_tarpeyo.head())
print(first_tarpeyo.shape)


# =============================================================================
# Check max first Tarpeyo month index
# ============================================================================

first_tarpeyo.max()


# =============================================================================
# Create relative month column (months relative to first Tarpeyo)
# =============================================================================

df = dataframe_1.merge(
    first_tarpeyo,
    on="PATIENT_ID",
    how="inner"
)

df["REL_MONTH"] = (df["MONTH_IDX"] - df["FIRST_TARPEYO_MONTH_IDX"])

print(df[[
    "PATIENT_ID",
    "MONTH_IDX",
    "FIRST_TARPEYO_MONTH_IDX",
    "REL_MONTH",
    "THERAPY_GROUP",
    "DRUG_GENERIC_NAME"
]].head(20))


# =============================================================================
# Calculate percentage of patients on each therapy over relative time
# =============================================================================

n_patients = df["PATIENT_ID"].nunique()

therapy_month = (
    df[
        ["PATIENT_ID", "REL_MONTH", "THERAPY_GROUP"]
    ]
    .drop_duplicates()
)

print(therapy_month.head())

summary = (
    therapy_month
    .groupby(["REL_MONTH", "THERAPY_GROUP"])["PATIENT_ID"]
    .nunique()
    .reset_index(name="N_PATIENTS_ON_THERAPY")
)

summary["PCT_PATIENTS"] = (
    summary["N_PATIENTS_ON_THERAPY"] / n_patients * 100
)

summary = summary.sort_values(
    ["REL_MONTH", "PCT_PATIENTS"],
    ascending=[True, False]
)

print(summary.head(30))


# =============================================================================
# Create full patient-month panel for logistic regression
# =============================================================================

import numpy as np

patients = df["PATIENT_ID"].unique()

# Define analysis window: 48 months before through 12 months after
months = np.arange(-48, 12)

# All therapy groups
therapy_groups = sorted(df["THERAPY_GROUP"].unique())

# Create full patient-month panel (Cartesian product)
panel = pd.MultiIndex.from_product(
    [patients, months, therapy_groups],
    names=["PATIENT_ID", "REL_MONTH", "THERAPY_GROUP"]
).to_frame(index=False)

print(panel.head())


# =============================================================================
# Mark observed therapy use in panel
# =============================================================================

observed = (
    df[
        ["PATIENT_ID", "REL_MONTH", "THERAPY_GROUP"]
    ]
    .drop_duplicates()
)

# If row exists => ON therapy
observed["ON_THERAPY"] = 1

# Merge onto full panel (missing = OFF therapy)
panel = panel.merge(
    observed,
    on=["PATIENT_ID", "REL_MONTH", "THERAPY_GROUP"],
    how="left"
)

panel["ON_THERAPY"] = (
    panel["ON_THERAPY"]
    .fillna(0)
    .astype(int)
)

print(panel.head(20))

# Quick sanity check
print(panel["ON_THERAPY"].value_counts())


# =============================================================================
# Logistic regression for each therapy group
# =============================================================================

import statsmodels.api as sm

predictions = []

for therapy in sorted(panel["THERAPY_GROUP"].unique()):

    temp = panel[panel["THERAPY_GROUP"] == therapy].copy()

    if temp["ON_THERAPY"].nunique() < 2:
        continue

    X = sm.add_constant(temp["REL_MONTH"])
    y = temp["ON_THERAPY"]

    model = sm.Logit(y, X).fit(disp=False)

    grid = pd.DataFrame({
        "REL_MONTH": np.arange(panel["REL_MONTH"].min(),
                               panel["REL_MONTH"].max() + 1)
    })

    grid_X = sm.add_constant(grid)

    # Prediction on probability scale with confidence intervals
    pred = model.get_prediction(grid_X).summary_frame()

    grid["PRED"] = pred["predicted"]
    grid["LOW"] = pred["ci_lower"]
    grid["HIGH"] = pred["ci_upper"]
    grid["THERAPY_GROUP"] = therapy

    predictions.append(grid)

pred_df = pd.concat(predictions, ignore_index=True)

# Remove Tarpeyo from predictions (keep only background therapies)
pred_df = pred_df[pred_df["THERAPY_GROUP"].str.upper() != "TARPEYO"]


# =============================================================================
# Plot probability of therapy use over time
# =============================================================================

import matplotlib.pyplot as plt
import matplotlib.cm as cm

plt.figure(figsize=(10, 5))

therapies = pred_df["THERAPY_GROUP"].unique()
colors = cm.get_cmap("tab20", len(therapies))

for i, therapy in enumerate(therapies):
    sub = pred_df[pred_df["THERAPY_GROUP"] == therapy]

    plt.plot(
        sub["REL_MONTH"],
        sub["PRED"],
        label=therapy,
        color=colors(i)
    )

    plt.fill_between(
        sub["REL_MONTH"],
        sub["LOW"],
        sub["HIGH"],
        color=colors(i),
        alpha=0.15
    )

# Vertical line at Tarpeyo initiation (month 0)
plt.axvline(0, linestyle="--", color="black", linewidth=1)

# Remove grid and spines for cleaner look
plt.grid(False)
ax = plt.gca()
ax.spines["top"].set_visible(False)
ax.spines["right"].set_visible(False)
ax.spines["left"].set_visible(False)
ax.spines["bottom"].set_visible(False)

# Bold text settings
plt.title(
    "Probability of being ON therapy over time",
    fontweight="bold"
)

plt.xlabel(
    "Months relative to first Tarpeyo",
    fontweight="bold"
)

plt.ylabel(
    "Probability of therapy use",
    fontweight="bold"
)

# Bold ticks
plt.xticks(fontweight="bold")
plt.yticks(fontweight="bold")

# Bold legend
plt.legend(
    bbox_to_anchor=(1.02, 1),
    loc="upper left",
    prop={"weight": "bold"},
    frameon=False
)

plt.tight_layout()
plt.show()

*/


-- =====================================================
-- ALTERNATIVE SQL APPROACH FOR THERAPY SUMMARY STATISTICS
-- =====================================================

WITH first_tarpeyo AS (
    SELECT 
        PATIENT_ID,
        MIN(MONTH_IDX) AS first_tarpeyo_month
    FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_drug_histories
    WHERE UPPER(THERAPY_GROUP) = 'TARPEYO'
    GROUP BY PATIENT_ID
),
relative_months AS (
    SELECT 
        h.PATIENT_ID,
        h.MONTH_IDX,
        h.THERAPY_GROUP,
        h.DRUG_GENERIC_NAME,
        h.MONTH_IDX - f.first_tarpeyo_month AS rel_month
    FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_drug_histories h
    JOIN first_tarpeyo f ON f.PATIENT_ID = h.PATIENT_ID
)
SELECT 
    rel_month,
    THERAPY_GROUP,
    COUNT(DISTINCT PATIENT_ID) AS n_patients_on_therapy,
    COUNT(DISTINCT PATIENT_ID) * 100.0 / (SELECT COUNT(DISTINCT PATIENT_ID) FROM first_tarpeyo) AS pct_patients
FROM relative_months
WHERE rel_month BETWEEN -48 AND 12
GROUP BY rel_month, THERAPY_GROUP
ORDER BY rel_month, pct_patients DESC;


