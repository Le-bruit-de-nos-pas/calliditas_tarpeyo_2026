-- =====================================================
-- TARPEYO (BUDESONIDE) PATIENT IDENTIFICATION
-- =====================================================

-- Preview drug dimension table
SELECT * FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.LDG_DRUG_DIM LIMIT 10;

-- Search for Tarpeyo / Budesonide in drug dimension
SELECT *
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.LDG_DRUG_DIM
WHERE LOWER(DRUG_GENERIC_NAME) LIKE '%tarpeyo%'
   OR LOWER(DRUG_GENERIC_NAME) LIKE '%budesonide%'
ORDER BY DRUG_GENERIC_NAME;

-- Get distinct patients with DRUG_ID = 1593076 (Tarpeyo)
SELECT DISTINCT PATIENT_ID
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_RX_CLAIMS
WHERE DRUG_ID = 1593076;

-- Create temp table for Tarpeyo patient list
-- CREATE OR REPLACE TABLE P_CALT_022_ZDH_01.SCH_ANA_DATA.KP_TMP_TARPEYO_PATIENTS_VECTOR (
--     PATIENT_ID VARCHAR
-- );

-- Insert Tarpeyo patients into temp table
INSERT INTO P_CALT_022_ZDH_01.SCH_ANA_DATA.KP_TMP_TARPEYO_PATIENTS_VECTOR
SELECT DISTINCT PATIENT_ID
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_RX_CLAIMS
WHERE DRUG_ID = 1593076;

-- Count Tarpeyo patients
SELECT COUNT(*) AS n_patients
FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.KP_TMP_TARPEYO_PATIENTS_VECTOR;

-- =====================================================
-- CREATE FILTERED TABLES FOR TARPEYO PATIENTS
-- =====================================================

-- Create filtered RX claims table
CREATE OR REPLACE TABLE P_CALT_022_ZDH_01.SCH_ANA_DATA.STG_RX_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR AS
SELECT *
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_RX_CLAIMS
WHERE PATIENT_ID IN (
    SELECT PATIENT_ID
    FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.KP_TMP_TARPEYO_PATIENTS_VECTOR
);

-- Preview filtered RX claims
SELECT * FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.STG_RX_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR LIMIT 10;

-- Create filtered diagnosis claims table
CREATE OR REPLACE TABLE P_CALT_022_ZDH_01.SCH_ANA_DATA.STG_DIAGNOSIS_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR AS
SELECT *
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_DIAGNOSIS_CLAIMS
WHERE PATIENT_ID IN (
    SELECT PATIENT_ID
    FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.KP_TMP_TARPEYO_PATIENTS_VECTOR
);

-- Create filtered procedure claims table
CREATE OR REPLACE TABLE P_CALT_022_ZDH_01.SCH_ANA_DATA.STG_PROCEDURE_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR AS
SELECT *
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_PROCEDURE_CLAIMS
WHERE PATIENT_ID IN (
    SELECT PATIENT_ID
    FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.KP_TMP_TARPEYO_PATIENTS_VECTOR
);

-- Preview filtered diagnosis claims
SELECT * FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.STG_DIAGNOSIS_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR LIMIT 10;

-- Preview filtered procedure claims
SELECT * FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.STG_PROCEDURE_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR LIMIT 10;

-- =====================================================
-- PHYSICIAN DATA
-- =====================================================

-- Preview physician dimension table
SELECT * FROM P_CALT_022_ZDH_01.SCH_DM_DATA.D_PHYSICIAN LIMIT 10;

-- =====================================================
-- CREATE EVENT SPINE WITH PRACTITIONER NPIs
-- =====================================================

-- Create event spine combining RX, DX, and PROC claims with practitioner NPI
CREATE OR REPLACE TABLE P_CALT_022_ZDH_01.SCH_ANA_DATA.KP_TMP_TARPEYO_EVENT_SPINE_PRAC_NPIS AS

WITH rx AS (
    SELECT
        PATIENT_ID,
        TRY_TO_DATE(RX_FILL_DATE) AS EVENT_DATE,
        PRACTITIONER_ID
    FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.STG_RX_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR
    WHERE PATIENT_ID IS NOT NULL
      AND RX_FILL_DATE IS NOT NULL
      AND PRACTITIONER_ID IS NOT NULL
),

dx AS (
    SELECT
        PATIENT_ID,
        TRY_TO_DATE(SERVICE_DATE) AS EVENT_DATE,
        PRACTITIONER_ID
    FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.STG_DIAGNOSIS_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR
    WHERE PATIENT_ID IS NOT NULL
      AND SERVICE_DATE IS NOT NULL
      AND PRACTITIONER_ID IS NOT NULL
),

proc AS (
    SELECT
        PATIENT_ID,
        TRY_TO_DATE(PROCEDURE_DATE) AS EVENT_DATE,
        PRACTITIONER_ID
    FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.STG_PROCEDURE_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR
    WHERE PATIENT_ID IS NOT NULL
      AND PROCEDURE_DATE IS NOT NULL
      AND PRACTITIONER_ID IS NOT NULL
),

unioned AS (
    SELECT * FROM rx
    UNION ALL
    SELECT * FROM dx
    UNION ALL
    SELECT * FROM proc
)

SELECT
    u.PATIENT_ID,
    u.EVENT_DATE,
    u.PRACTITIONER_ID,
    p.NPI
FROM unioned u
LEFT JOIN P_CALT_022_ZDH_01.SCH_DM_DATA.D_PHYSICIAN p
    ON u.PRACTITIONER_ID = p.PRAC_ID;

-- Preview event spine
SELECT * FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.KP_TMP_TARPEYO_EVENT_SPINE_PRAC_NPIS LIMIT 10;

-- Count distinct patient-practitioner pairs
SELECT COUNT(DISTINCT PATIENT_ID, PRACTITIONER_ID) 
FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.KP_TMP_TARPEYO_EVENT_SPINE_PRAC_NPIS;

-- Count distinct patient-NPI pairs
SELECT COUNT(DISTINCT PATIENT_ID, NPI) 
FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.KP_TMP_TARPEYO_EVENT_SPINE_PRAC_NPIS;

-- =====================================================
-- LIST ALL TABLES IN SCH_ANA_DATA
-- =====================================================

SELECT table_name
FROM P_CALT_022_ZDH_01.INFORMATION_SCHEMA.TABLES
WHERE table_schema = 'SCH_ANA_DATA' 
ORDER BY table_name;

-- =====================================================
-- PROGNOS DATA EXPLORATION
-- =====================================================

-- Preview STG_PROGNOS table
SELECT * FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_PROGNOS LIMIT 10;

-- Monthly distribution of STG_PROGNOS records
SELECT
    TO_CHAR(TRY_TO_DATE(TEST_SPECIMEN_DRAW_DATETIME), 'YYYYMM') AS year_month,
    COUNT(*) AS n_rows
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_PROGNOS
WHERE TEST_SPECIMEN_DRAW_DATETIME IS NOT NULL
GROUP BY TO_CHAR(TRY_TO_DATE(TEST_SPECIMEN_DRAW_DATETIME), 'YYYYMM')
ORDER BY year_month;

-- Preview Prognos fields for bridging
SELECT
    DV_TOKEN_1,
    ORDERING_PROVIDER_NPI AS NPI,
    TRY_TO_DATE(TEST_SPECIMEN_DRAW_DATETIME) AS EVENT_DATE
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_PROGNOS LIMIT 10;

-- =====================================================
-- CREATE PROGNOS BRIDGE TABLE (Symphony <-> Prognos)
-- =====================================================

-- Bridge table linking Symphony events to Prognos data by NPI and date
CREATE OR REPLACE TABLE P_CALT_022_ZDH_01.SCH_ANA_DATA.KP_TMP_TARPEYO_PROGNOS_BRIDGE AS

WITH prognos AS (
    SELECT
        DV_TOKEN_1,
        ORDERING_PROVIDER_NPI AS NPI,
        TRY_TO_DATE(TEST_SPECIMEN_DRAW_DATETIME) AS EVENT_DATE
    FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_PROGNOS
    WHERE ORDERING_PROVIDER_NPI IS NOT NULL
      AND TEST_SPECIMEN_DRAW_DATETIME IS NOT NULL
)

SELECT
    s.PATIENT_ID,
    p.DV_TOKEN_1,
    COALESCE(s.NPI, p.NPI) AS NPI,
    COALESCE(s.EVENT_DATE, p.EVENT_DATE) AS EVENT_DATE,

    -- flags indicating data source presence
    CASE WHEN s.PATIENT_ID IS NOT NULL THEN 1 ELSE 0 END AS has_symphony,
    CASE WHEN p.DV_TOKEN_1 IS NOT NULL THEN 1 ELSE 0 END AS has_prognos

FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.KP_TMP_TARPEYO_EVENT_SPINE_PRAC_NPIS s

FULL OUTER JOIN prognos p
    ON s.NPI = p.NPI
   AND s.EVENT_DATE = p.EVENT_DATE;

-- Summary of bridge table overlap
SELECT
    has_symphony,
    has_prognos,
    COUNT(*) AS n_rows
FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.KP_TMP_TARPEYO_PROGNOS_BRIDGE
GROUP BY has_symphony, has_prognos
ORDER BY has_symphony DESC, has_prognos DESC;

-- Count distinct Symphony patients
SELECT COUNT(DISTINCT PATIENT_ID) AS n_symphony_patients
FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.KP_TMP_TARPEYO_PROGNOS_BRIDGE
WHERE has_symphony = 1;

-- Count distinct Prognos tokens
SELECT COUNT(DISTINCT DV_TOKEN_1) AS n_prognos_tokens
FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.KP_TMP_TARPEYO_PROGNOS_BRIDGE
WHERE has_prognos = 1;

-- Count patients with overlap (both Symphony and Prognos)
SELECT COUNT(DISTINCT PATIENT_ID) AS n_patients_with_prognos_overlap
FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.KP_TMP_TARPEYO_PROGNOS_BRIDGE
WHERE has_symphony = 1
  AND has_prognos = 1;

-- Preview bridge table
SELECT * FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.KP_TMP_TARPEYO_PROGNOS_BRIDGE LIMIT 10;

-- Monthly patient counts from bridge table
SELECT
    TO_CHAR(EVENT_DATE, 'YYYYMM') AS year_month,
    COUNT(DISTINCT PATIENT_ID) AS n_patients
FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.KP_TMP_TARPEYO_PROGNOS_BRIDGE
WHERE PATIENT_ID IS NOT NULL
  AND EVENT_DATE IS NOT NULL
GROUP BY TO_CHAR(EVENT_DATE, 'YYYYMM')
ORDER BY year_month;

-- =====================================================
-- PATIENT DEMOGRAPHICS
-- =====================================================

-- Preview patient dimension table
SELECT * FROM P_CALT_022_ZDH_01.SCH_DM_DATA.D_PAT LIMIT 10;

-- Get column information for LDG_DRUG_DIM
SELECT column_name, ordinal_position
FROM P_CALT_022_ZDH_01.INFORMATION_SCHEMA.COLUMNS
WHERE table_catalog = 'P_CALT_022_ZDH_01'
  AND table_schema  = 'SCH_RAW_DATA'
  AND table_name    = 'LDG_DRUG_DIM'
ORDER BY ordinal_position;

-- =====================================================
-- DIAGNOSIS CODE ANALYSIS FOR TARPEYO PATIENTS
-- =====================================================

-- Basic counts on filtered diagnosis claims
SELECT COUNT(DISTINCT PATIENT_ID) FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.STG_DIAGNOSIS_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR;
SELECT COUNT(DISTINCT DIAGNOSIS_CODE) FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.STG_DIAGNOSIS_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR;

-- All distinct diagnosis codes
SELECT DISTINCT DIAGNOSIS_CODE 
FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.STG_DIAGNOSIS_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR  
ORDER BY DIAGNOSIS_CODE;

-- Cleaned diagnosis codes (first letter + up to 3 alphanumeric)
SELECT DISTINCT
    REGEXP_SUBSTR(
        REPLACE(DIAGNOSIS_CODE, '.', ''),
        '^[A-Z][A-Z0-9]{0,3}'
    ) AS CLEAN_DIAGNOSIS_CODE
FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.STG_DIAGNOSIS_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR
WHERE DIAGNOSIS_CODE IS NOT NULL
ORDER BY CLEAN_DIAGNOSIS_CODE;

-- =====================================================
-- KIDNEY/COMORBIDITY ICD CODES LOOKUP
-- =====================================================

-- List of relevant ICD codes for kidney disease and related conditions
-- Note: This is a lookup/reference list
/*
ICD Codes of interest:
- N02B, N028, N029, N020-N027, N02A: Glomerular diseases
- N181-N186, N189, N19: Chronic kidney disease
- N040-N049: Nephritic syndrome
- R800-R809: Proteinuria
- R310-R319: Hematuria
- I10, I120, I129, I130-I132: Hypertension related
- Z992, Z911, Z940, T861: Kidney transplant/procedures
- E112, E119, E116, E102, E109: Diabetes with renal complications
- I502, I503, I509: Heart failure
- E780, E781, E782, E785: Lipid disorders
*/

-- Find matching diagnosis codes from filtered data against lookup list
WITH CLEANED AS (
    SELECT DISTINCT
        REGEXP_SUBSTR(REPLACE(DIAGNOSIS_CODE, '.', ''), '^[A-Z][A-Z0-9]{0,3}') AS CODE
    FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.STG_DIAGNOSIS_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR
    WHERE DIAGNOSIS_CODE IS NOT NULL
),
LOOKUP AS (
    SELECT COLUMN1 AS CODE FROM VALUES
    ('N02B'), ('N028'), ('N029'), ('N020'), ('N021'), ('N022'), ('N023'), ('N024'), ('N025'), ('N026'), ('N027'), ('N02A'),
    ('N181'), ('N182'), ('N183'), ('N184'), ('N185'), ('N186'), ('N189'), ('N19'),
    ('N040'), ('N041'), ('N042'), ('N043'), ('N044'), ('N045'), ('N046'), ('N047'), ('N048'), ('N049'),
    ('R800'), ('R801'), ('R802'), ('R803'), ('R808'), ('R809'),
    ('R310'), ('R311'), ('R312'), ('R319'),
    ('I10'), ('I120'), ('I129'), ('I130'), ('I131'), ('I132'),
    ('Z992'), ('Z911'), ('Z940'), ('T861'),
    ('E112'), ('E119'), ('E116'), ('E102'), ('E109'),
    ('I502'), ('I503'), ('I509'),
    ('E780'), ('E781'), ('E782'), ('E785')
)
SELECT DISTINCT c.CODE
FROM CLEANED c
JOIN LOOKUP l
    ON c.CODE LIKE l.CODE || '%'
    OR l.CODE LIKE c.CODE || '%'
ORDER BY c.CODE;

-- Patient-month-diagnosis for longitudinal analysis
SELECT DISTINCT 
    PATIENT_ID, 
    SERVICE_DATE, 
    DIAGNOSIS_CODE 
FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.STG_DIAGNOSIS_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR;

-- Monthly aggregated diagnosis codes for kidney/comorbidity tracking
WITH base AS (
    SELECT DISTINCT
        PATIENT_ID,
        TO_VARCHAR(
            DATE_TRUNC('MONTH', TO_DATE(SERVICE_DATE)),
            'YYYY-MM'
        ) AS SERVICE_MONTH,
        UPPER(REPLACE(DIAGNOSIS_CODE, '.', '')) AS DIAG_CODE_NORM
    FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.STG_DIAGNOSIS_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR
),

codes AS (
    SELECT COLUMN1 AS CODE
    FROM VALUES
        ('N02B'), ('N028'), ('N029'), ('N020'), ('N021'), ('N022'), ('N023'),
        ('N024'), ('N025'), ('N026'), ('N027'), ('N02A'), ('N181'), ('N182'),
        ('N183'), ('N184'), ('N185'), ('N186'), ('N189'), ('N19'), ('N040'),
        ('N041'), ('N042'), ('N043'), ('N044'), ('N045'), ('N046'), ('N047'),
        ('N048'), ('N049'), ('R800'), ('R801'), ('R802'), ('R803'), ('R808'),
        ('R809'), ('R310'), ('R311'), ('R312'), ('R319'), ('I10'), ('I120'),
        ('I129'), ('I130'), ('I131'), ('I132'), ('Z992'), ('Z911'), ('Z940'),
        ('T861'), ('E112'), ('E119'), ('E116'), ('E102'), ('E109'), ('I502'),
        ('I503'), ('I509'), ('E780'), ('E781'), ('E782'), ('E785')
)

SELECT DISTINCT
    b.PATIENT_ID,
    b.SERVICE_MONTH,
    b.DIAG_CODE_NORM AS DIAGNOSIS_CODE
FROM base b
JOIN codes c
    ON  b.DIAG_CODE_NORM LIKE '%' || c.CODE || '%'
    OR  c.CODE LIKE '%' || b.DIAG_CODE_NORM || '%';

-- =====================================================
-- NOTE: Python visualization code for diagnosis timeline
-- =====================================================

/*
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.dates as mdates

df = dataframe_42

df["SERVICE_MONTH"] = pd.to_datetime(df["SERVICE_MONTH"], errors="coerce")

result = (
    df.groupby("PATIENT_ID")["SERVICE_MONTH"]
    .nunique()
    .reset_index(name="unique_date_count")
)

filtered_result = result[result["unique_date_count"] > 24]
df_filtered = df[df["PATIENT_ID"].isin(filtered_result["PATIENT_ID"])]

# ICD category color mapping
ICD_COLORS = {
    "E": "#328cc1",   # Endocrine
    "I": "#0b3c5d",   # Circulatory
    "N": "#c66f80",   # Genitourinary
    "R": "#1c1c1c",   # Symptoms
    "Z": "#9faa74",   # Factors influencing health
}

def get_color(dx):
    return ICD_COLORS.get(str(dx)[0], "black")

# Sample one random patient with >24 unique dates
patient_id = np.random.choice(df_filtered["PATIENT_ID"].unique())
df_p = df_filtered[df_filtered["PATIENT_ID"] == patient_id].copy()

df_p["SERVICE_MONTH"] = pd.to_datetime(df_p["SERVICE_MONTH"], errors="coerce")
df_p = df_p.dropna(subset=["SERVICE_MONTH"])
df_p["MONTH"] = df_p["SERVICE_MONTH"].dt.to_period("M").dt.to_timestamp()

dx_list = sorted(df_p["DIAGNOSIS_CODE"].astype(str).unique())
dx_to_y = {dx: i for i, dx in enumerate(dx_list)}

fig, ax = plt.subplots()

for dx in dx_list:
    df_dx = df_p[df_p["DIAGNOSIS_CODE"].astype(str) == dx]
    ax.scatter(
        df_dx["MONTH"],
        [dx_to_y[dx]] * len(df_dx),
        color=get_color(dx),
        marker="s",
        s=30,
        alpha=0.8
    )

ax.set_yticks(list(dx_to_y.values()))
ax.set_yticklabels(dx_list)
ax.xaxis.set_major_locator(mdates.YearLocator())
ax.xaxis.set_major_formatter(mdates.DateFormatter("%Y"))
ax.set_title(f"Patient {patient_id} — Diagnosis Event Timeline (ICD letter colored)")
ax.set_xlabel("Time (Month)")
ax.set_ylabel("Diagnosis Code")
ax.grid(axis="x", linestyle="--", alpha=0.3)

for spine in ax.spines.values():
    spine.set_visible(False)

plt.tight_layout()
ax.set_xlim(pd.to_datetime("2020-01-01"), pd.to_datetime("2025-12-01"))
plt.show()
*/