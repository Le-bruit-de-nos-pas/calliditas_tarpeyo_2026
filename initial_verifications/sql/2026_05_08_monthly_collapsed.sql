-- =====================================================
-- MONTHLY COLLAPSED PATIENT DATA FOR TARPEYO COHORT
-- =====================================================

-- =====================================================
-- VIEW ALL TABLES IN SCH_ANA_DATA WITH SIZES
-- =====================================================

SELECT 
    table_name,
    row_count,
    bytes,
    bytes / POWER(1024, 3) AS gb
FROM P_CALT_022_ZDH_01.INFORMATION_SCHEMA.TABLES
WHERE table_schema = 'SCH_ANA_DATA'
ORDER BY bytes DESC;

-- =====================================================
-- PREVIEW EXISTING TABLES
-- =====================================================

-- Preview IgAN patients distribution
SELECT * FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.KP_DIST_IGAN_PTS LIMIT 10;

-- Preview diagnosis claims for Tarpeyo patients
SELECT * FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.STG_DIAGNOSIS_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR LIMIT 10;

-- Preview procedure claims for Tarpeyo patients
SELECT * FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.STG_PROCEDURE_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR LIMIT 10;

-- Preview Tarpeyo patient vector
SELECT * FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.KP_TMP_TARPEYO_PATIENTS_VECTOR LIMIT 10;

-- Preview Rx claims for Tarpeyo patients
SELECT * FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.STG_RX_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR LIMIT 10;

-- =====================================================
-- DRUG DIMENSION LOOKUP
-- =====================================================

SELECT * FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.LDG_DRUG_DIM LIMIT 100;

-- =====================================================
-- PHYSICIAN NPI LOOKUP
-- =====================================================

SELECT * FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.LDG_PHYSICIAN LIMIT 100;

-- =====================================================
-- PROGNOS DATA EXPLORATION
-- =====================================================

-- Preview STG_PROGNOS table
SELECT * FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_PROGNOS LIMIT 100;

-- Filtered Prognos data for May 2025 with specific DV_TOKEN_1 values
SELECT
    DV_TOKEN_1,
    PATIENT_GENDER,
    PATIENT_YOB,
    ORDERING_PROVIDER_PRIMARY_SPECIALTY,
    TEST_SPECIMEN_DRAW_DATETIME,
    TEST_RESULT_TYPE,
    TEST_RESULT_NUMERIC,
    TEST_RESULT_UNITS
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_PROGNOS
WHERE TO_TIMESTAMP(TEST_SPECIMEN_DRAW_DATETIME) >= '2025-05-01'
  AND TO_TIMESTAMP(TEST_SPECIMEN_DRAW_DATETIME) <  '2025-06-01'
  AND DV_TOKEN_1 IN (
      'NfyggH0UUP5v08UkejZpF82idqQ5hgvDmcH/oLdv8+k=',
      'YLZCfDczRpL4GbLaCk/husnau4WeuJTum2CdSQkD/nU=',
      '+c8DsFgD/xvVNIXgZYA9zMk9mqggH9mYYcxXMmn99Gc='
  );  -- Add all DV_TOKEN_1 values as needed

-- =====================================================
-- PATIENT DEMOGRAPHICS PREVIEW
-- =====================================================

SELECT * FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.D_PAT LIMIT 10;

-- =====================================================
-- PYTHON DATA PROCESSING CODE
-- =====================================================
/*

import pandas as pd
import numpy as np
import re

df_STG_DIAGNOSIS_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR = dataframe_14
df_STG_PROCEDURE_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR = dataframe_17
df_STG_RX_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR = dataframe_15
df_KP_TMP_TARPEYO_PATIENTS_VECTOR = dataframe_16


# =============================================================================
# Collapse diagnosis data to patient-month level
# =============================================================================

cols = ["PATIENT_ID", "SERVICE_DATE", "DIAGNOSIS_CODE", "PRACTITIONER_ID"]

df_tarpeyo_dx = df_STG_DIAGNOSIS_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR[cols].drop_duplicates()

# Clean diagnosis code (remove dots)
def clean_dx(code):
    if pd.isna(code):
        return None
    code = str(code).replace(".", "")  # remove dots
    match = re.match(r"([A-Za-z])([A-Za-z0-9]{0,3})", code)
    return (match.group(1) + match.group(2)) if match else code

df_tarpeyo_dx["DIAGNOSIS_CODE"] = df_tarpeyo_dx["DIAGNOSIS_CODE"].apply(clean_dx)

# Keep only month-year
df_tarpeyo_dx["SERVICE_DATE"] = pd.to_datetime(df_tarpeyo_dx["SERVICE_DATE"])
df_tarpeyo_dx["SERVICE_DATE"] = df_tarpeyo_dx["SERVICE_DATE"].dt.to_period("M").astype(str)

# Group into vectors at month level
df_tarpeyo_dx = df_tarpeyo_dx.dropna(subset=["DIAGNOSIS_CODE", "PRACTITIONER_ID"])

df_tarpeyo_dx = (
    df_tarpeyo_dx.groupby(["PATIENT_ID", "SERVICE_DATE"])
      .agg({
          "DIAGNOSIS_CODE": lambda x: list(pd.unique(x.dropna())),
          "PRACTITIONER_ID": lambda x: list(pd.unique(x.dropna()))
      })
      .reset_index()
)

print(df_tarpeyo_dx.head())


# =============================================================================
# Load drug lookup and collapse prescription data
# =============================================================================

drugs_lookup = dataframe_18  # LDG_DRUG_DIM table
print(drugs_lookup.head())

cols = ["PATIENT_ID", "DRUG_ID", "RX_FILL_DATE", "PRACTITIONER_ID", "PHARMACY_ZIP_3"]

df_tarpeyo_rx = df_STG_RX_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR[cols].drop_duplicates()

df_tarpeyo_rx["DRUG_ID"] = df_tarpeyo_rx["DRUG_ID"].astype(str)
drugs_lookup["DRUG_ID"] = drugs_lookup["DRUG_ID"].astype(str)

# Merge with drug lookup
df_tarpeyo_rx = df_tarpeyo_rx.merge(
    drugs_lookup[["DRUG_ID", "BB_USC_NAME", "DRUG_GENERIC_NAME"]],
    on="DRUG_ID",
    how="left"
)

# Clean date → month
df_tarpeyo_rx["RX_FILL_DATE"] = pd.to_datetime(df_tarpeyo_rx["RX_FILL_DATE"])
df_tarpeyo_rx["YEAR_MONTH"] = df_tarpeyo_rx["RX_FILL_DATE"].dt.to_period("M").astype(str)

# Collapse per patient-month
df_tarpeyo_rx = (
    df_tarpeyo_rx.groupby(["PATIENT_ID", "YEAR_MONTH"])
    .agg(
        DRUGS=("DRUG_GENERIC_NAME", lambda x: sorted(set(x.dropna()))),
        ZIP3=("PHARMACY_ZIP_3", lambda x: sorted(set(x.dropna().astype(str)))),
        PRACT=("PRACTITIONER_ID", lambda x: sorted(set(x.dropna())))
    )
    .reset_index()
)

print(df_tarpeyo_rx.head())


# =============================================================================
# Collapse procedure data to patient-month level
# =============================================================================

cols = ["PATIENT_ID", "PROCEDURE_CODE", "PROCEDURE_DATE", "REFERRING_PRACTITIONER_ID"]

df_tarpeyo_px = df_STG_PROCEDURE_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR[cols].drop_duplicates()

df_tarpeyo_px["PROCEDURE_DATE"] = pd.to_datetime(df_tarpeyo_px["PROCEDURE_DATE"])
df_tarpeyo_px["YEAR_MONTH"] = (
    df_tarpeyo_px["PROCEDURE_DATE"]
    .dt.to_period("M")
    .astype(str)
)

# Aggregate per patient-month
df_tarpeyo_px = (
    df_tarpeyo_px.groupby(["PATIENT_ID", "YEAR_MONTH"])
    .agg(
        PROCEDURES=(
            "PROCEDURE_CODE",
            lambda x: sorted(set(
                v for v in x.dropna().astype(str)
                if v != "None"
            ))
        ),
        PRACTITIONERS=(
            "REFERRING_PRACTITIONER_ID",
            lambda x: sorted(set(
                v for v in x.dropna().astype(str)
                if v != "None"
            ))
        )
    )
    .reset_index()
)

print(df_tarpeyo_px)


# =============================================================================
# Normalize column names for merging
# =============================================================================

# Normalize date column names
df_tarpeyo_dx = df_tarpeyo_dx.rename(
    columns={"SERVICE_DATE": "YEAR_MONTH"}
)

df_tarpeyo_dx = df_tarpeyo_dx.rename(
    columns={"PRACTITIONER_ID": "DX_PRACTITIONERS"}
)

df_tarpeyo_rx = df_tarpeyo_rx.rename(
    columns={"PRACT": "RX_PRACTITIONERS"}
)

df_tarpeyo_px = df_tarpeyo_px.rename(
    columns={"PRACTITIONERS": "PX_PRACTITIONERS"}
)


# =============================================================================
# Full outer join all three data sources
# =============================================================================

df_patient_month = (
    
    df_tarpeyo_dx.merge(
        df_tarpeyo_rx,
        on=["PATIENT_ID", "YEAR_MONTH"],
        how="outer"
    )
    
    .merge(
        df_tarpeyo_px,
        on=["PATIENT_ID", "YEAR_MONTH"],
        how="outer"
    )
)

# Sort nicely
df_patient_month = df_patient_month.sort_values(
    ["PATIENT_ID", "YEAR_MONTH"]
).reset_index(drop=True)

# Replace NaN lists with empty lists
list_cols = [
    "DIAGNOSIS_CODE",
    "DX_PRACTITIONERS",
    "DRUGS",
    "ZIP3",
    "RX_PRACTITIONERS",
    "PROCEDURES",
    "PX_PRACTITIONERS"
]

for c in list_cols:
    df_patient_month[c] = df_patient_month[c].apply(
        lambda x: x if isinstance(x, list) else []
    )

print(df_patient_month.head())
print(df_patient_month.columns)


# =============================================================================
# Process PROGNOS data
# =============================================================================

df_STG_PROGNOS = dataframe_5
df_STG_PROGNOS = df_STG_PROGNOS[['DV_TOKEN_1', 'ORDERING_PROVIDER_NPI', 
                                  'TEST_SPECIMEN_DRAW_DATETIME', 'TEST_RESULT_TYPE', 
                                  'ICD10_BILLABLES_VALIDATED']]

# Year-month extraction
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

df_STG_PROGNOS = df_STG_PROGNOS.drop_duplicates().copy()

# Split ICD strings into lists
def extract_unique_icd_codes(series):
    codes = set()
    for val in series.dropna():
        for c in str(val).split("|"):
            c = c.strip()
            if c and c != "None":
                codes.add(c)
    return sorted(codes)

# Aggregate by patient, NPI, month, and test type
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

# Further collapse ignoring TEST_RESULT_TYPE
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

print(df_STG_PROGNOS.head())

# Filter to May 2025 only
df_STG_PROGNOS = df_STG_PROGNOS[
    df_STG_PROGNOS["YEAR_MONTH"] == "2025-05"
]
df_STG_PROGNOS


# =============================================================================
# Map practitioner IDs to NPIs for diagnosis data
# =============================================================================

physician_npis = dataframe_1  # LDG_PHYSICIAN table
physician_npis = physician_npis[['PRACTITIONER_ID', 'NPI']]
print(physician_npis.head())

cols = ["PATIENT_ID", "SERVICE_DATE", "DIAGNOSIS_CODE", "PRACTITIONER_ID"]

df_tarpeyo_dx_simplified = df_STG_DIAGNOSIS_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR[cols].drop_duplicates()

df_tarpeyo_dx_simplified = df_tarpeyo_dx_simplified.merge(
    physician_npis[
        ["PRACTITIONER_ID", "NPI"]
    ].drop_duplicates(),
    on="PRACTITIONER_ID",
    how="left"
)

# Drop practitioner id
df_tarpeyo_dx_simplified = df_tarpeyo_dx_simplified.drop(
    columns=["PRACTITIONER_ID"]
)

# Clean diagnosis code (remove dots only, no regex truncation)
def clean_dx(code):
    if pd.isna(code):
        return None
    return str(code).replace(".", "")

df_tarpeyo_dx_simplified["DIAGNOSIS_CODE"] = df_tarpeyo_dx_simplified["DIAGNOSIS_CODE"].apply(clean_dx)

# Keep only month-year
df_tarpeyo_dx_simplified["SERVICE_DATE"] = pd.to_datetime(df_tarpeyo_dx_simplified["SERVICE_DATE"])
df_tarpeyo_dx_simplified["SERVICE_DATE"] = df_tarpeyo_dx_simplified["SERVICE_DATE"].dt.to_period("M").astype(str)

# Filter to 2025 only
df_tarpeyo_dx_simplified = df_tarpeyo_dx_simplified[
    df_tarpeyo_dx_simplified["SERVICE_DATE"].astype(str).str.contains("2025")
]

# Group into vectors by patient and NPI
df_tarpeyo_dx_simplified = df_tarpeyo_dx_simplified.dropna(subset=["DIAGNOSIS_CODE", "NPI"])

df_tarpeyo_dx_simplified = (
    df_tarpeyo_dx_simplified.groupby(["PATIENT_ID", "NPI"])
      .agg({
          "DIAGNOSIS_CODE": lambda x: list(pd.unique(x.dropna()))
      })
      .reset_index()
)

print(df_tarpeyo_dx_simplified.head())

*/



-- =====================================================
-- ALTERNATIVE SQL APPROACH FOR MONTHLY COLLAPSE
-- =====================================================
--  Snowflake supports ARRAY_AGG.
-- Example for diagnosis data :


CREATE OR REPLACE TABLE P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_dx_monthly AS
SELECT 
    PATIENT_ID,
    DATE_TRUNC('MONTH', SERVICE_DATE) AS year_month,
    ARRAY_AGG(DISTINCT DIAGNOSIS_CODE) AS diagnosis_codes,
    ARRAY_AGG(DISTINCT PRACTITIONER_ID) AS practitioners
FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.STG_DIAGNOSIS_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR
WHERE SERVICE_DATE BETWEEN '2020-01-01' AND '2026-01-01'
GROUP BY PATIENT_ID, DATE_TRUNC('MONTH', SERVICE_DATE)
ORDER BY PATIENT_ID, year_month;
