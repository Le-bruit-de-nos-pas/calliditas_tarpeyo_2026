import pandas as pd
import ast
import numpy as np

df_tarpeyo_dx_simplified = pd.read_csv("df_tarpeyo_dx_simplified.tsv", sep="\t", dtype="str" )
df_STG_PROGNOS = pd.read_csv("df_STG_PROGNOS.tsv", sep="\t", dtype="str")
df_pract_npi = pd.read_csv("df_pract_npi.tsv", sep="\t", dtype="str")

df_tarpeyo_dx_simplified = df_tarpeyo_dx_simplified.drop_duplicates()

df_tarpeyo_dx_simplified = df_tarpeyo_dx_simplified.merge(
    df_pract_npi[
        ["PRACTITIONER_ID", "NPI"]
    ].drop_duplicates(),
    on="PRACTITIONER_ID",
    how="left"
)

# ── drop practitioner id ──────────────────────────────────────────
df_tarpeyo_dx_simplified = df_tarpeyo_dx_simplified.drop(
    columns=["PRACTITIONER_ID"]
)



# -----------------------------
# Clean diagnosis code
# -----------------------------
def clean_dx(code):
    if pd.isna(code):
        return None
    return str(code).replace(".", "")

df_tarpeyo_dx_simplified["DIAGNOSIS_CODE"] = df_tarpeyo_dx_simplified["DIAGNOSIS_CODE"].apply(clean_dx)

# -----------------------------
# Keep only month-year
# -----------------------------
df_tarpeyo_dx_simplified["SERVICE_DATE"] = pd.to_datetime(df_tarpeyo_dx_simplified["SERVICE_DATE"])
df_tarpeyo_dx_simplified["SERVICE_DATE"] = df_tarpeyo_dx_simplified["SERVICE_DATE"].dt.to_period("M").astype(str)


df_tarpeyo_dx_simplified = df_tarpeyo_dx_simplified[
    df_tarpeyo_dx_simplified["SERVICE_DATE"].astype(str).str.contains("2025")
]

# group into vectors
df_tarpeyo_dx_simplified = df_tarpeyo_dx_simplified.dropna(subset=["DIAGNOSIS_CODE", "NPI"])

df_tarpeyo_dx_simplified = (
    df_tarpeyo_dx_simplified.groupby(["PATIENT_ID", "NPI"])
      .agg({
          "DIAGNOSIS_CODE": lambda x: list(pd.unique(x.dropna()))
      })
      .reset_index()
)


print(df_tarpeyo_dx_simplified.head())


df_STG_PROGNOS = df_STG_PROGNOS[['DV_TOKEN_1', 'ORDERING_PROVIDER_NPI', 'TEST_SPECIMEN_DRAW_DATETIME', 'TEST_RESULT_TYPE', 'ICD10_BILLABLES_VALIDATED']]

# ── year-month ────────────────────────────────────────────────────
df_STG_PROGNOS["TEST_SPECIMEN_DRAW_DATETIME"] = pd.to_datetime(
    df_STG_PROGNOS["TEST_SPECIMEN_DRAW_DATETIME"]
)

df_STG_PROGNOS = (
    df_STG_PROGNOS
    .dropna(subset=[
        "DV_TOKEN_1",
        "ORDERING_PROVIDER_NPI",
        "TEST_SPECIMEN_DRAW_DATETIME",
        "TEST_RESULT_TYPE"
    ])
    .drop_duplicates()
    .copy()
)

df_STG_PROGNOS["YEAR_MONTH"] = (
    df_STG_PROGNOS["TEST_SPECIMEN_DRAW_DATETIME"]
    .dt.to_period("M")
    .astype(str)
)

df_STG_PROGNOS =    df_STG_PROGNOS.drop_duplicates().copy()


# ── split ICD strings into lists ──────────────────────────────────
def extract_unique_icd_codes(series):
    codes = set()
    for val in series.dropna():
        for c in str(val).split("|"):
            c = c.strip()
            if c and c != "None":
                codes.add(c)
    return sorted(codes)

# ── aggregate ─────────────────────────────────────────────────────
df_STG_PROGNOS = (
    df_STG_PROGNOS.groupby([
        "DV_TOKEN_1",
        "ORDERING_PROVIDER_NPI",
        "YEAR_MONTH",
        "TEST_RESULT_TYPE"
    ])
    .agg(
        ICD10_CODES=(
            "ICD10_BILLABLES_VALIDATED",
            extract_unique_icd_codes
        )
    )
    .reset_index()
)


print(df_STG_PROGNOS.head())


# ── helper to collapse unique ICDs ────────────────────────────────
def collapse_icds(series):
    codes = set()
    for vals in series.dropna():
        if isinstance(vals, list):
            iterable = vals
        else:
            iterable = str(vals).split("|")
        for c in iterable:
            c = str(c).strip()
            if c and c != "None":
                codes.add(c)
    return sorted(codes)

# ── aggregate ignoring TEST_RESULT_TYPE ───────────────────────────
df_STG_PROGNOS = (
    df_STG_PROGNOS.groupby([
        "DV_TOKEN_1",
        "ORDERING_PROVIDER_NPI",
        "YEAR_MONTH"
    ])
    .agg(
        ICD10_CODES=(
            "ICD10_CODES",
            collapse_icds
        )
    )
    .reset_index()
)

df_STG_PROGNOS = df_STG_PROGNOS[
    df_STG_PROGNOS["YEAR_MONTH"] == "2025-05"
]

print(df_STG_PROGNOS.head())

df_STG_PROGNOS = df_STG_PROGNOS[['DV_TOKEN_1', 'ORDERING_PROVIDER_NPI', 'ICD10_CODES']]


print(df_tarpeyo_dx_simplified.head())
print("\n\n\n\n\n")
print(df_STG_PROGNOS.head())

# ── relevant CKD / IgAN ICD10 codes ──────────────────────────────
CKD_IGAN_CODES = {
    # IgAN / nephritic syndrome
    "N02B1", "N02B2", "N02B3", "N02B4", "N02B5",
    "N02B6", "N02B9", "N028", "N029",
    "N020", "N021", "N022", "N023", "N024",
    "N025", "N026", "N027", "N02A",

    # CKD
    "N181", "N182", "N1830", "N1831", "N1832",
    "N184", "N185", "N186", "N189", "N19",

    # nephrotic / proteinuria
    "N040", "N041", "N042", "N043", "N044",
    "N045", "N046", "N047", "N048", "N049",

    "R800", "R801", "R802", "R803", "R808", "R809",

    # hematuria
    "R310", "R311", "R3121", "R3129", "R319",

    # hypertension
    "I10", "I120", "I129", "I130", "I1310",
    "I1311", "I132",

    # dialysis / transplant
    "Z992", "Z9115", "Z940",

    # CKD anemia
    "D631",
    
    # mineral / bone metabolism
    "E8339", "E8331", "E8342", "E8351", "E8352",

    # secondary hyperparathyroidism
    "E211",

    # vitamin D deficiency
    "E559",

    # diabetes / metabolic
    "E1121", "E1122", "E119", "E1165",
    "E1140", "E1142",
    "E1021", "E1022", "E109",

    # heart failure
    "I5020", "I5022", "I5030", "I5032",
    "I5042", "I509",

    # CAD
    "I2510", "I25110", "I25118",

    # atrial fibrillation
    "I4891", "I480", "I4820",

    # hyperlipidemia
    "E780", "E781", "E782", "E785",

    # transplant complications
    "T8610", "T8611", "T8612", "T8613", "T8619",

    # BMI codes
    "Z6830", "Z6831", "Z6832", "Z6833", "Z6834",
    "Z6835", "Z6836", "Z6837", "Z6838", "Z6839",
    "Z6841", "Z6842", "Z6843", "Z6844", "Z6845"
} 


def has_ckd_igan(code_list):
    # missing
    if code_list is None:
        return 0
    # already list
    if isinstance(code_list, list):
        codes = code_list
    # string representation of list
    elif isinstance(code_list, str):
        try:
            parsed = ast.literal_eval(code_list)
            if isinstance(parsed, list):
                codes = parsed
            else:
                codes = [parsed]

        except:
            codes = [code_list]

    else:
        return 0

    # normalize
    codes = {
        str(c).replace(".", "").upper()
        for c in codes
    }

    # exact match
    return int(len(codes & CKD_IGAN_CODES) > 0)



# ── DX ─────────────────────────────────────────────────────────────
df_tarpeyo_dx_simplified["CKD_IGAN_FLAG"] = (
    df_tarpeyo_dx_simplified["DIAGNOSIS_CODE"]
    .apply(has_ckd_igan)
)

# ── PROGNOS ───────────────────────────────────────────────────────
df_STG_PROGNOS["CKD_IGAN_FLAG"] = (
    df_STG_PROGNOS["ICD10_CODES"]
    .apply(has_ckd_igan)
)

print(df_tarpeyo_dx_simplified.head())
print("\n\n\n\n")


print(df_STG_PROGNOS.head())
print("\n\n\n\n")


print(df_tarpeyo_dx_simplified["CKD_IGAN_FLAG"].value_counts())
print("\n\n\n\n")

print(df_STG_PROGNOS["CKD_IGAN_FLAG"].value_counts())



# ── DX side: keep CKD/IgAN relevant rows ──────────────────────────
df_dx_ckd = (
    df_tarpeyo_dx_simplified[
        df_tarpeyo_dx_simplified["CKD_IGAN_FLAG"] == 1
    ][["PATIENT_ID", "NPI"]]
    .drop_duplicates()
    .copy()
)

# ensure string
df_dx_ckd["NPI"] = df_dx_ckd["NPI"].astype(str)

# ── PROGNOS side: keep CKD/IgAN relevant rows ────────────────────

df_prog_ckd = (
    df_STG_PROGNOS[
        df_STG_PROGNOS["CKD_IGAN_FLAG"] == 1
    ][["DV_TOKEN_1", "ORDERING_PROVIDER_NPI"]]
    .drop_duplicates()
    .copy()
)

# ensure string
df_prog_ckd["ORDERING_PROVIDER_NPI"] = (
    df_prog_ckd["ORDERING_PROVIDER_NPI"]
    .astype(str)
)

# ── LEFT JOIN by NPI ──────────────────────────────────────────────

df_patient_dv = df_dx_ckd.merge(
    df_prog_ckd,
    left_on="NPI",
    right_on="ORDERING_PROVIDER_NPI",
    how="left"
)

df_patient_dv = df_patient_dv.drop(
    columns=["ORDERING_PROVIDER_NPI"]
)

print(df_patient_dv.head())

print(df_patient_dv.shape)

df_patient_dv = df_patient_dv[df_patient_dv["DV_TOKEN_1"].notna()]
df_patient_dv

# ── overall counts ────────────────────────────────────────────────

n_patients = df_patient_dv["PATIENT_ID"].nunique()
n_tokens = df_patient_dv["DV_TOKEN_1"].nunique()

print("Unique patients:", n_patients)
print("Unique DV tokens:", n_tokens)

# ── tokens per patient ────────────────────────────────────────────

tokens_per_patient = (
    df_patient_dv
    .groupby("PATIENT_ID")["DV_TOKEN_1"]
    .nunique()
    .reset_index(name="N_TOKENS")
)



# summary stats
print(
    tokens_per_patient["N_TOKENS"]
    .describe()
)

def parse_icd_list(x):
    # handle None safely first
    if x is None:
        return []
    # already list
    if isinstance(x, list):
        return x
    # only now check pandas NA safely
    if isinstance(x, float) and pd.isna(x):
        return []

    # string parsing
    try:
        return ast.literal_eval(x)
    except:
        return [x]



# ── parse ICD lists ───────────────────────────────────────────────

df_dx = df_tarpeyo_dx_simplified.copy()

df_dx["DIAGNOSIS_CODE"] = (
    df_dx["DIAGNOSIS_CODE"]
    .apply(parse_icd_list)
)

# ── explode to one ICD per row ────────────────────────────────────

patient_icd_long = (
    df_dx[["PATIENT_ID", "DIAGNOSIS_CODE"]]
    .explode("DIAGNOSIS_CODE")
    .dropna()
    .drop_duplicates()
    .rename(columns={"DIAGNOSIS_CODE": "ICD10_CODE"})
)

patient_icd_long = patient_icd_long[
    patient_icd_long["ICD10_CODE"]
    .astype(str)
    .str.replace(".", "", regex=False)
    .str.upper()
    .isin(CKD_IGAN_CODES)
].copy()

print(patient_icd_long.head())
print(patient_icd_long.shape)

patient_icd_long \
    .groupby("PATIENT_ID")["ICD10_CODE"] \
    .nunique() \
    .reset_index(name="unique_icd10_count")["unique_icd10_count"].describe()

print(patient_icd_long['PATIENT_ID'].nunique())

pd.DataFrame(patient_icd_long['ICD10_CODE'].value_counts())



# ── parse ICD lists ───────────────────────────────────────────────

df_prognos = df_STG_PROGNOS.copy()

df_prognos["ICD10_CODES"] = (
    df_prognos["ICD10_CODES"]
    .apply(parse_icd_list)
)

# ── explode to one ICD per row ────────────────────────────────────

patient_prognos_long = (
    df_prognos[["DV_TOKEN_1", "ICD10_CODES"]]
    .explode("ICD10_CODES")
    .dropna()
    .drop_duplicates()
    .rename(columns={"ICD10_CODES": "ICD10_CODE"})
)

patient_prognos_long = patient_prognos_long[
    patient_prognos_long["ICD10_CODE"]
    .astype(str)
    .str.replace(".", "", regex=False)
    .str.upper()
    .isin(CKD_IGAN_CODES)
].copy()

print(patient_prognos_long.head())
print(patient_prognos_long.shape)

patient_prognos_long \
    .groupby("DV_TOKEN_1")["ICD10_CODE"] \
    .nunique() \
    .reset_index(name="unique_icd10_count")["unique_icd10_count"].describe()

print(patient_prognos_long['DV_TOKEN_1'].nunique())

pd.DataFrame(patient_prognos_long['ICD10_CODE'].value_counts())


# ── normalize column names ────────────────────────────────────────

dx_long = patient_icd_long.copy()
dx_long = dx_long.rename(columns={"PATIENT_ID": "PATIENT"})
dx_long["SOURCE"] = "DX"

prog_long = patient_prognos_long.copy()
prog_long = prog_long.rename(columns={"DV_TOKEN_1": "PATIENT"})
prog_long["SOURCE"] = "PROGNOS"

# ── bind rows ─────────────────────────────────────────────────────

all_icd_long = pd.concat(
    [dx_long, prog_long],
    ignore_index=True
).drop_duplicates()

all_icd_long = all_icd_long.dropna(subset=["ICD10_CODE"])

print(all_icd_long.tail())
print(all_icd_long.shape)

# ── create weighted ICD matrix (TF-IDF style) ────────────────────

all_icd_long = all_icd_long.drop_duplicates()

# total patients
N = all_icd_long["PATIENT"].nunique()

# ICD frequency across all patients
icd_freq = (
    all_icd_long[["PATIENT", "ICD10_CODE"]]
    .drop_duplicates()
    ["ICD10_CODE"]
    .value_counts()
)

# inverse frequency weight
idf = np.log(N / icd_freq)

# weighted matrix
icd_wide = (
    all_icd_long
    .assign(W=all_icd_long["ICD10_CODE"].map(idf))
    .pivot_table(
        index="PATIENT",
        columns="ICD10_CODE",
        values="W",
        aggfunc="max",
        fill_value=0
    )
    .reset_index()
)

icd_wide

patient_source = (
    all_icd_long
    .groupby("PATIENT")["SOURCE"]
    .agg(lambda x: x.iloc[0])   # or x.mode()[0] if you want safety
    .reset_index()
    .rename(columns={"SOURCE": "SOURCE"})
)
patient_source

# ── merge source + matrix ─────────────────────────────────────────

final_icd_matrix = icd_wide.merge(
    patient_source,
    on="PATIENT",
    how="left"
)

final_icd_matrix['SOURCE'].value_counts()

# PATIENT + SOURCE first, everything else after
icd_cols = [c for c in final_icd_matrix.columns if c not in ["PATIENT", "SOURCE"]]

final_icd_matrix = final_icd_matrix[["PATIENT", "SOURCE"] + icd_cols]

print(final_icd_matrix.head())

dx_icd = final_icd_matrix[final_icd_matrix["SOURCE"] == "DX"].copy()
prog_icd = final_icd_matrix[final_icd_matrix["SOURCE"] == "PROGNOS"].copy()

icd_cols = [c for c in final_icd_matrix.columns if c not in ["PATIENT", "SOURCE"]]

dx_vec = dx_icd.set_index("PATIENT")[icd_cols]
prog_vec = prog_icd.set_index("PATIENT")[icd_cols]

allowed_map

allowed_map = (
    df_patient_dv
    .groupby("PATIENT_ID")["DV_TOKEN_1"]
    .apply(set)
)

allowed_map.index = allowed_map.index.astype(str)
allowed_map = allowed_map.apply(lambda s: set(map(str, s)))

sample_ids = allowed_map.sample(n=25111, random_state=42).index

# filter the map
allowed_map = allowed_map.loc[sample_ids]

allowed_map

import numpy as np
from sklearn.metrics.pairwise import cosine_similarity


dx_mat = dx_vec.values
prog_mat = prog_vec.values

dx_index = dx_vec.index.astype(str)
prog_index = prog_vec.index.astype(str)

# --- code cell ---
prog_lookup = {pid: i for i, pid in enumerate(prog_index)}
prog_lookup



# binary matrices for overlap calculation
dx_bin = (dx_mat > 0).astype(int)
prog_bin = (prog_mat > 0).astype(int)


# ── compute candidate similarities ────────────────────────────────

edges = []

for i, dx_id in enumerate(dx_index):

    if dx_id not in allowed_map.index:
        continue

    allowed_progs = allowed_map[dx_id]

    dx_vec_i = dx_mat[i].reshape(1, -1)

    for prog_id in allowed_progs:

        prog_id = str(prog_id)

        if prog_id not in prog_lookup:
            continue

        j = prog_lookup[prog_id]

        # cosine similarity
        sim = cosine_similarity(
            dx_vec_i,
            prog_mat[j].reshape(1, -1)
        )[0, 0]

        # ICD overlap count
        intersection = np.sum(
            (dx_bin[i] == 1) &
            (prog_bin[j] == 1)
        )

        # keep only meaningful edges
        if sim >= 0.15 and intersection >= 2:

            # combined weight
            weight = sim + (0.2 * intersection)

            edges.append((
                dx_id,
                prog_id,
                sim,
                intersection,
                weight
            ))

print("N edges:", len(edges))


len(edges)

import pandas as pd
import networkx as nx

B = nx.Graph()

dx_nodes = set()
prog_nodes = set()

for dx, prog, sim, intersection, weight in edges:

    B.add_edge(
        dx,
        prog,
        weight=float(weight),
        cosine=float(sim),
        intersection=int(intersection)
    )

    dx_nodes.add(dx)
    prog_nodes.add(prog)

matching = nx.algorithms.matching.max_weight_matching(
    B,
    maxcardinality=True
)

matches = []

for a, b in matching:

    # ensure direction DX → PROG
    if a in dx_nodes:
        dx, prog = a, b
    else:
        dx, prog = b, a

    matches.append((dx, prog))

df_matches = pd.DataFrame(matches, columns=["DX_PATIENT", "PROGNOS_PATIENT"])

print(df_matches.head())
print(len(df_matches))

dx_icd = final_icd_matrix[final_icd_matrix["SOURCE"] == "DX"].copy()
dx_icd = dx_icd.drop(columns=["SOURCE"])
dx_icd = dx_icd.set_index("PATIENT")
print(dx_icd.shape)
print(dx_icd.head())

prog_icd = final_icd_matrix[final_icd_matrix["SOURCE"] == "PROGNOS"].copy()
prog_icd = prog_icd.drop(columns=["SOURCE"])
prog_icd = prog_icd.set_index("PATIENT")
print(prog_icd.shape)
print(prog_icd.head())

df_matches

df_edges = pd.DataFrame(
    edges,
    columns=["DX_PATIENT", "PROGNOS_PATIENT", "COSINE_SIM", "ICD_INTERSECTION", "WEIGHT"]
)

df_edges

df_matches = df_matches.merge(
    df_edges,
    on=["DX_PATIENT", "PROGNOS_PATIENT"],
    how="left"
)

df_matches['COSINE_SIM'].mean()

df_matches

dx_icd_sets = dx_icd.apply(
    lambda row: set(dx_icd.columns[row > 0]),
    axis=1
).to_dict()

prog_icd_sets = prog_icd.apply(
    lambda row: set(prog_icd.columns[row > 0]),
    axis=1
).to_dict()

df_matches["DX_ICD_SET"] = df_matches["DX_PATIENT"].map(dx_icd_sets)
df_matches["PROGNOS_ICD_SET"] = df_matches["PROGNOS_PATIENT"].map(prog_icd_sets)

df_matches

df_matches["ICD_INTERSECTION_SET"] = df_matches.apply(
    lambda r: r["DX_ICD_SET"] & r["PROGNOS_ICD_SET"]
    if isinstance(r["DX_ICD_SET"], set) and isinstance(r["PROGNOS_ICD_SET"], set)
    else set(),
    axis=1
)

df_matches["ICD_UNION_SET"] = df_matches.apply(
    lambda r: r["DX_ICD_SET"] | r["PROGNOS_ICD_SET"]
    if isinstance(r["DX_ICD_SET"], set) and isinstance(r["PROGNOS_ICD_SET"], set)
    else set(),
    axis=1
)

df_matches

df_matches[df_matches['ICD_INTERSECTION_SET']==df_matches['ICD_UNION_SET']]

df_matches.to_csv('df_matches_igan_tf_idf_all_2026_05_12.txt', index=False, sep=',')


import numpy as np
import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap

# Create custom colormap from #C1E5F5 to #D17C8D
colors = ['#C1E5F5', '#D17C8D']
custom_cmap = LinearSegmentedColormap.from_list('custom', colors, N=256)

# ── jitter (important for discrete ICD counts) ───────────────────
x = df_matches["ICD_INTERSECTION"] + np.random.normal(0, 0.20, len(df_matches))
y = df_matches["COSINE_SIM"] + np.random.normal(0, 0.02, len(df_matches))

# keep bounds clean
y = np.clip(y, 0, 1.1)

# size scaling - wider range for better visual distinction
sizes = 10 + (df_matches["WEIGHT"] - df_matches["WEIGHT"].min()) / (df_matches["WEIGHT"].max() - df_matches["WEIGHT"].min()) * 280

plt.figure(figsize=(8, 7))

sc = plt.scatter(
    x,
    y,
    c=df_matches["WEIGHT"],
    s=sizes,
    alpha=0.6,
    cmap=custom_cmap
)

cbar = plt.colorbar(sc, label="\n Weight")
cbar.outline.set_visible(False)
cbar.ax.yaxis.label.set_fontweight('bold')
cbar.ax.tick_params(width=1.5)

for spine in cbar.ax.spines.values():
    spine.set_visible(False)

plt.xlim(0, 10)
plt.ylim(0, 1.1)

# Bold labels and title
plt.xlabel("\n ICD Intersection [ICD Set Intersection]", fontweight='bold', fontsize=12)
plt.ylabel("Cosine Similarity [ICD Vector Similarity] \n", fontweight='bold', fontsize=12)
plt.title("Symphony Dx - PROGNOS Labs Matching \n", fontweight='bold', fontsize=14, pad=20)

# Bold tick labels
ax = plt.gca()
ax.tick_params(axis='both', which='major', labelsize=10, width=1.5)
for label in ax.get_xticklabels() + ax.get_yticklabels():
    label.set_fontweight('bold')

plt.grid(alpha=0.1, linewidth=0.5)

# Remove spines
ax.spines["top"].set_visible(False)
ax.spines["right"].set_visible(False)
ax.spines["left"].set_visible(False)
ax.spines["bottom"].set_visible(False)

plt.tight_layout()

# Export as SVG
plt.savefig('symphony_matching_plot.svg', format='svg', dpi=300, bbox_inches='tight')
plt.show()

fig, ax = plt.subplots(figsize=(8, 6))

# Calculate proportions (divide by total number of matches)
n_total = len(df_matches)
counts, bins, patches = ax.hist(df_matches['WEIGHT'], bins=30, 
                                 edgecolor='white', linewidth=1.2, 
                                 color='#D17C8D', alpha=0.7,
                                 weights=np.ones(n_total) / n_total)

# Convert to percentage on y-axis
ax.set_ylabel('Proportion of Matches \n', fontweight='bold', fontsize=12)

# Mean and median lines
mean_val = df_matches['WEIGHT'].mean()
median_val = df_matches['WEIGHT'].median()

ax.axvline(mean_val, color='#2c3e50', linestyle='--', 
           linewidth=2.5, label=f'Mean: {mean_val:.3f}')
ax.axvline(median_val, color='#C1E5F5', linestyle='--', 
           linewidth=2.5, label=f'Median: {median_val:.3f}')

# Labels and title
ax.set_xlabel('\n Combined Weight', fontweight='bold', fontsize=12)
ax.set_title('Distribution of Match Weights \n', fontweight='bold', fontsize=14)

# Set axis limits
ax.set_xlim(0, 2.5)
ax.set_ylim(0, 0.10)  # Adjust based on your data max proportion

# Format y-axis as percentages
from matplotlib.ticker import PercentFormatter
ax.yaxis.set_major_formatter(PercentFormatter(1))  # 1 = 100%

# Legend without frame
legend = ax.legend(frameon=False, fontsize=10, loc='upper right')
for text in legend.get_texts():
    text.set_fontweight('bold')

# Remove top and right spines
ax.spines['top'].set_visible(False)
ax.spines['right'].set_visible(False)

# Style remaining spines
ax.spines['left'].set_visible(False)
ax.spines['bottom'].set_visible(False)

# Bold tick labels
ax.tick_params(axis='both', which='major', labelsize=10, width=1.5)
for label in ax.get_xticklabels() + ax.get_yticklabels():
    label.set_fontweight('bold')

# Optional: Add light grid on y-axis
ax.grid(axis='y', alpha=0.3, linestyle=':', linewidth=0.8)
ax.set_axisbelow(True)

plt.tight_layout()
plt.savefig('histogram.svg', format='svg', dpi=300, bbox_inches='tight')

plt.show()

# --- code cell ---
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap

# Create custom colormap from #C1E5F5 to #D17C8D
colors = ['#C1E5F5', '#D17C8D']
custom_cmap = LinearSegmentedColormap.from_list('custom', colors, N=256)

# Create bins
df_matches['sim_bin'] = pd.cut(df_matches['COSINE_SIM'], bins=[0, 0.3, 0.5, 0.7, 1.0], 
                                labels=['Low (<0.3)', 'Medium (0.3-0.5)', 
                                        'High (0.5-0.7)', 'Very High (>0.7)'])
df_matches['int_bin'] = pd.cut(df_matches['ICD_INTERSECTION'], bins=[0, 1, 2, 3, 10], 
                                labels=['1', '2', '3', '4+'])

# Create pivot table
pivot = pd.crosstab(df_matches['sim_bin'], df_matches['int_bin'], 
                     values=df_matches['WEIGHT'], 
                     aggfunc='count', normalize='columns') * 100

fig, ax = plt.subplots(figsize=(7, 5.5))
im = ax.imshow(pivot.values, cmap=custom_cmap, aspect='auto', vmin=0, vmax=100)

# Labels
ax.set_xticks(range(len(pivot.columns)))
ax.set_xticklabels(pivot.columns, fontweight='bold', fontsize=11)
ax.set_yticks(range(len(pivot.index)))
ax.set_yticklabels(pivot.index, fontweight='bold', fontsize=11)
ax.set_xlabel('\n ICD Intersection Size', fontweight='bold', fontsize=12)
ax.set_ylabel('Cosine Similarity \n', fontweight='bold', fontsize=12)
ax.set_title('% of Matches by\nCosine Similarity and ICD Intersection\n', 
             fontweight='bold', fontsize=14, pad=15)

# Add text annotations with improved visibility
for i in range(len(pivot.index)):
    for j in range(len(pivot.columns)):
        val = pivot.values[i, j]
        # Use white text for darker cells, dark text for lighter cells
        text_color = 'white' if val > 50 else '#2c3e50'
        text = ax.text(j, i, f'{val:.0f}%',
                       ha="center", va="center", 
                       color=text_color, fontweight='bold', fontsize=11)

# Customize colorbar
cbar = plt.colorbar(im, label='\n Percentage of matches')
cbar.ax.yaxis.label.set_fontweight('bold')
cbar.ax.yaxis.label.set_fontsize(11)
cbar.ax.tick_params(labelsize=9)
for label in cbar.ax.get_yticklabels():
    label.set_fontweight('bold')
cbar.outline.set_visible(False)

# Remove all grid lines and spines
ax.grid(False)
ax.spines['top'].set_visible(False)
ax.spines['right'].set_visible(False)
ax.spines['left'].set_visible(False)
ax.spines['bottom'].set_visible(False)

# Remove tick lines
ax.tick_params(axis='both', which='both', length=0)

plt.tight_layout()
plt.savefig('crosstab.svg', format='svg', dpi=300, bbox_inches='tight')

plt.show()
