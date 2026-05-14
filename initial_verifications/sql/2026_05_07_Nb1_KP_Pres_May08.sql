-- =====================================================
-- TARPEYO PATIENT COHORT ANALYSIS - DATA PREPARATION
-- =====================================================


-- =====================================================
-- EXPLORE SOURCE DATA
-- =====================================================

-- Preview drug dimension table
SELECT * FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.LDG_DRUG_DIM LIMIT 100;

-- Count patients in Tarpeyo cohort
SELECT COUNT(*) AS n_patients
FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.KP_TMP_TARPEYO_PATIENTS_VECTOR;

-- Preview filtered Rx claims
SELECT * FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.STG_RX_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR LIMIT 5;

-- Preview filtered diagnosis claims
SELECT FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.STG_DIAGNOSIS_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR LIMIT 5;

-- Show columns in Rx table
SHOW COLUMNS IN TABLE P_CALT_022_ZDH_01.SCH_ANA_DATA.STG_RX_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR;

-- Show columns in Diagnosis table
SHOW COLUMNS IN TABLE P_CALT_022_ZDH_01.SCH_ANA_DATA.STG_DIAGNOSIS_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR;

-- =====================================================
-- CREATE DRUG CLASSIFICATION BASKET
-- =====================================================

CREATE OR REPLACE TABLE P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_drug_basket AS

WITH drug_names AS (
    SELECT DISTINCT
        r.DRUG_ID,
        d.DRUG_NAME AS generic_name
    FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.STG_RX_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR r
    LEFT JOIN P_CALT_022_ZDH_01.SCH_RAW_DATA.LDG_DRUG_DIM d
        ON r.DRUG_ID = d.DRUG_ID
    WHERE r.DRUG_ID IS NOT NULL
)

SELECT
    DRUG_ID,
    generic_name,
    CASE
        -- Tarpeyo (target drug)
        WHEN DRUG_ID = 1593076
            THEN 'Tarpeyo'

        -- Other IgAN treatments
        WHEN generic_name ILIKE '%sparsentan%'
            THEN 'Other IgAN'

        -- ACE inhibitors
        WHEN generic_name ILIKE ANY (
            '%lisinopril%','%ramipril%','%enalapril%','%benazepril%',
            '%captopril%','%fosinopril%','%quinapril%','%perindopril%',
            '%trandolapril%','%moexipril%'
        ) THEN 'ACEi'

        -- Angiotensin receptor blockers
        WHEN generic_name ILIKE ANY (
            '%losartan%','%irbesartan%','%valsartan%','%olmesartan%',
            '%telmisartan%','%candesartan%','%azilsartan%','%eprosartan%'
        ) THEN 'ARB'

        -- SGLT2 inhibitors
        WHEN generic_name ILIKE ANY (
            '%dapagliflozin%','%empagliflozin%','%canagliflozin%',
            '%sotagliflozin%','%ertugliflozin%'
        ) THEN 'SGLT2i'

        -- Immunosuppressants
        WHEN generic_name ILIKE ANY (
            '%mycophenolate%','%azathioprine%','%cyclosporine%',
            '%tacrolimus%','%sirolimus%'
        ) THEN 'Immunosuppressant'

        -- Systemic steroids (excluding Tarpeyo/budesonide)
        WHEN generic_name ILIKE ANY (
            '%prednisone%','%prednisolone%','%methylprednisolone%',
            '%dexamethasone%','%budesonide%'
        ) AND DRUG_ID != 1593076
            THEN 'Systemic steroid'

        -- Omega-3 fatty acids
        WHEN generic_name ILIKE ANY (
            '%omega-3%','%omega 3%','%fish oil%',
            '%icosapent%','%eicosapentaenoic%'
        ) THEN 'Omega-3'

        -- Diuretics and MRAs
        WHEN generic_name ILIKE ANY (
            '%furosemide%','%torsemide%','%bumetanide%',
            '%hydrochlorothiazide%','%chlorthalidone%',
            '%spironolactone%','%eplerenone%'
        ) THEN 'Diuretic / MRA'

        ELSE NULL
    END AS drug_category

FROM drug_names;



-- Verify drug classification counts
SELECT drug_category, COUNT(*) AS n_drugs
FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_drug_basket
GROUP BY drug_category
ORDER BY drug_category;

-- View all classified drugs
SELECT * FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_drug_basket;

-- =====================================================
-- CREATE COHORT TABLE
-- =====================================================

CREATE OR REPLACE TABLE P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_cohort AS

WITH tarpeyo_fills AS (
    SELECT
        PATIENT_ID,
        MIN(RX_FILL_DATE) AS first_tarpeyo_fill,
        MAX(RX_FILL_DATE) AS last_tarpeyo_fill,
        COUNT(*) AS n_tarpeyo_fills
    FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.STG_RX_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR
    WHERE DRUG_ID = 1593076
      AND RX_FILL_DATE IS NOT NULL
    GROUP BY PATIENT_ID
)

SELECT
    p.PATIENT_ID,
    t.first_tarpeyo_fill,
    t.last_tarpeyo_fill,
    COALESCE(t.n_tarpeyo_fills, 0) AS n_tarpeyo_fills,

    -- 24-month pre-Tarpeyo observation window
    DATEADD('month', -24, t.first_tarpeyo_fill) AS pre_window_start,
    t.first_tarpeyo_fill AS pre_window_end

FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.KP_TMP_TARPEYO_PATIENTS_VECTOR p
LEFT JOIN tarpeyo_fills t
    ON t.PATIENT_ID = p.PATIENT_ID;

-- Check cohort size and date ranges
SELECT COUNT(*) AS n_patients FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_cohort;

-- Sanity check - all patients should have first fill date
SELECT
    COUNT(*) AS n_patients,
    COUNT(first_tarpeyo_fill) AS n_with_fill_date,
    MIN(first_tarpeyo_fill) AS earliest_fill,
    MAX(first_tarpeyo_fill) AS latest_fill
FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_cohort;

-- =====================================================
-- CREATE RAW RX TABLE WITH TIMING
-- =====================================================

CREATE OR REPLACE TABLE P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_rx_raw AS
SELECT
    r.PATIENT_ID,
    r.RX_FILL_DATE AS fill_date,
    LEAST(COALESCE(r.DAYS_SUPPLY, 30), 180) AS days_supply,
    DATEADD('day',
        LEAST(COALESCE(r.DAYS_SUPPLY, 30), 180) - 1,
        r.RX_FILL_DATE) AS end_date,

    b.generic_name,
    b.drug_category,
    b.DRUG_ID,

    CASE
        WHEN r.RX_FILL_DATE < c.first_tarpeyo_fill THEN 'pre-Tarpeyo'
        WHEN r.DRUG_ID = 1593076 THEN 'Tarpeyo'
        ELSE 'concurrent'
    END AS timing_relative_to_tarpeyo

FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.STG_RX_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR r
JOIN P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_cohort c
    ON c.PATIENT_ID = r.PATIENT_ID
JOIN P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_drug_basket b
    ON b.DRUG_ID = r.DRUG_ID
WHERE r.RX_FILL_DATE BETWEEN '2020-01-01' AND '2026-01-01'
  AND b.drug_category IS NOT NULL
  AND COALESCE(r.DAYS_SUPPLY, 1) >= 1;

-- Summary by category and timing
SELECT drug_category, timing_relative_to_tarpeyo,
       COUNT(DISTINCT PATIENT_ID) AS n_patients, 
       COUNT(*) AS n_fills
FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_rx_raw
GROUP BY drug_category, timing_relative_to_tarpeyo
ORDER BY drug_category, timing_relative_to_tarpeyo;

-- =====================================================
-- CREATE RX EPISODES (CONTINUOUS TREATMENT PERIODS)
-- =====================================================
-- Combines consecutive fills with gaps <= 60 days into episodes

CREATE OR REPLACE TABLE P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_rx_episodes AS
WITH
deduped AS (
    SELECT DISTINCT
        PATIENT_ID, fill_date, end_date,
        generic_name, drug_category, DRUG_ID,
        timing_relative_to_tarpeyo
    FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_rx_raw
),
lagged AS (
    SELECT *,
        LAG(end_date) OVER (
            PARTITION BY PATIENT_ID, drug_category, generic_name
            ORDER BY fill_date
        ) AS prev_end_date
    FROM deduped
),
episode_starts AS (
    SELECT *,
        CASE
            WHEN prev_end_date IS NULL THEN 1
            WHEN DATEDIFF('day', prev_end_date, fill_date) > 60 THEN 1
            ELSE 0
        END AS is_new_episode
    FROM lagged
),
numbered AS (
    SELECT *,
        SUM(is_new_episode) OVER (
            PARTITION BY PATIENT_ID, drug_category, generic_name
            ORDER BY fill_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS episode_id
    FROM episode_starts
),
collapsed AS (
    SELECT
        PATIENT_ID,
        drug_category,
        generic_name,
        DRUG_ID,
        episode_id,
        MIN(fill_date) AS episode_start,
        MAX(end_date)  AS episode_end,
        COUNT(*) AS n_fills,
        SUM(DATEDIFF('day', fill_date, end_date) + 1) AS total_covered_days,
        MODE(timing_relative_to_tarpeyo) AS episode_timing
    FROM numbered
    GROUP BY PATIENT_ID, drug_category, generic_name, DRUG_ID, episode_id
)
SELECT
    c.*,
    DATEDIFF('day', c.episode_start, c.episode_end) + 1 AS episode_span_days,
    coh.first_tarpeyo_fill,
    coh.last_tarpeyo_fill
FROM collapsed c
JOIN P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_cohort coh
    ON coh.PATIENT_ID = c.PATIENT_ID
ORDER BY c.PATIENT_ID, c.episode_start;

-- =====================================================
-- CREATE DIAGNOSIS EVENTS TABLE
-- =====================================================

CREATE OR REPLACE TABLE P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_dx_events AS
SELECT
    d.PATIENT_ID,
    d.SERVICE_DATE AS event_date,
    d.DIAGNOSIS_CODE AS icd_code,
    CASE
        -- IgAN specific code
        WHEN d.DIAGNOSIS_CODE ILIKE 'N02.B%'
            THEN 'IgAN (specific)'
        -- IgAN proxy codes
        WHEN d.DIAGNOSIS_CODE IN ('N02.8','N02.9')
            THEN 'IgAN (proxy)'
        -- Recurrent hematuria
        WHEN d.DIAGNOSIS_CODE ILIKE 'N02.%'
            THEN 'Recurrent hematuria'
        -- CKD stages
        WHEN d.DIAGNOSIS_CODE IN ('N18.5','N18.6')
            THEN 'CKD stage 5 / ESRD'
        WHEN d.DIAGNOSIS_CODE = 'N18.4'
            THEN 'CKD stage 4'
        WHEN d.DIAGNOSIS_CODE IN ('N18.3','N18.31','N18.32')
            THEN 'CKD stage 3'
        WHEN d.DIAGNOSIS_CODE = 'N18.2'
            THEN 'CKD stage 2'
        WHEN d.DIAGNOSIS_CODE = 'N18.1'
            THEN 'CKD stage 1'
        WHEN d.DIAGNOSIS_CODE = 'N18.9'
            THEN 'CKD unspecified'
        -- Nephrotic syndrome
        WHEN d.DIAGNOSIS_CODE ILIKE 'N04%'
            THEN 'Nephrotic syndrome'
        -- Proteinuria
        WHEN d.DIAGNOSIS_CODE ILIKE 'R80%'
            THEN 'Proteinuria'
        -- Comorbidities
        WHEN d.DIAGNOSIS_CODE = 'I10'
            THEN 'Hypertension'
        WHEN d.DIAGNOSIS_CODE ILIKE 'E11%'
            THEN 'Type 2 diabetes'
        WHEN d.DIAGNOSIS_CODE ILIKE 'Z99.2%'
            THEN 'Dependence on dialysis'
        ELSE NULL
    END AS dx_category,
    CASE
        WHEN d.DIAGNOSIS_CODE IN ('N18.5','N18.6') THEN 5
        WHEN d.DIAGNOSIS_CODE = 'N18.4' THEN 4
        WHEN d.DIAGNOSIS_CODE IN ('N18.3','N18.31','N18.32') THEN 3
        WHEN d.DIAGNOSIS_CODE = 'N18.2' THEN 2
        WHEN d.DIAGNOSIS_CODE = 'N18.1' THEN 1
        ELSE NULL
    END AS ckd_severity_rank
FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.STG_DIAGNOSIS_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR d
JOIN P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_cohort c
    ON c.PATIENT_ID = d.PATIENT_ID
WHERE d.DIAGNOSIS_CODE ILIKE ANY (
    'N02%','N04%','N18%','R80%','I10','E11%','Z99.2%'
)
  AND d.SERVICE_DATE BETWEEN '2020-01-01' AND '2026-01-01';

-- =====================================================
-- CREATE PROCEDURE EVENTS TABLE
-- =====================================================

CREATE OR REPLACE TABLE P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_proc_events AS
SELECT
    p.PATIENT_ID,
    p.PROCEDURE_DATE AS event_date,
    p.PROCEDURE_CODE,
    CASE
        WHEN p.PROCEDURE_CODE IN ('50200','50205')
            THEN 'Kidney biopsy'
        WHEN p.PROCEDURE_CODE IN ('90935','90937','90945','90947','90940','G0257')
            THEN 'Dialysis'
        WHEN p.PROCEDURE_CODE IN ('50360','50365','50380')
            THEN 'Kidney transplant'
        ELSE 'Other renal procedure'
    END AS proc_category
FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.STG_PROCEDURE_CLAIMS_KP_TMP_TARPEYO_PATIENTS_VECTOR p
JOIN P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_cohort c
    ON c.PATIENT_ID = p.PATIENT_ID
WHERE p.PROCEDURE_CODE IN (
    '50200','50205',
    '90935','90937','90945','90947','90940','G0257',
    '50360','50365','50380'
)
  AND p.PROCEDURE_DATE BETWEEN '2020-01-01' AND '2026-01-01';

-- Preview procedure events
SELECT * FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_proc_events;

-- =====================================================
-- CREATE PRE-TARPEYO TRAJECTORY TABLE
-- =====================================================
-- Summarizes patient characteristics and medication use in the 24 months
-- prior to first Tarpeyo fill

CREATE OR REPLACE TABLE P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_pre_trajectory AS

WITH pre_rx AS (
    SELECT
        r.PATIENT_ID,
        r.drug_category,
        r.generic_name,
        r.fill_date,
        c.first_tarpeyo_fill,
        DATEDIFF('month', r.fill_date, c.first_tarpeyo_fill) AS months_before_tarpeyo
    FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_rx_raw r
    JOIN P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_cohort c
        ON c.PATIENT_ID = r.PATIENT_ID
    WHERE r.timing_relative_to_tarpeyo = 'pre-Tarpeyo'
      AND r.drug_category IS NOT NULL
      AND r.drug_category != 'Tarpeyo'
),

first_per_cat AS (
    SELECT
        PATIENT_ID,
        drug_category,
        MIN(fill_date) AS first_fill_in_window,
        MAX(fill_date) AS last_fill_in_window,
        COUNT(DISTINCT fill_date) AS n_fills_pre,
        MIN(months_before_tarpeyo) AS closest_months_before,
        MIN(fill_date) AS category_initiation_date
    FROM pre_rx
    GROUP BY PATIENT_ID, drug_category
),

wide AS (
    SELECT
        p.PATIENT_ID,
        p.first_tarpeyo_fill,
        p.n_tarpeyo_fills,

        -- ACEi
        MAX(CASE WHEN f.drug_category = 'ACEi' THEN 1 ELSE 0 END) AS had_acei,
        MAX(CASE WHEN f.drug_category = 'ACEi' THEN f.closest_months_before END) AS acei_months_before,

        -- ARB
        MAX(CASE WHEN f.drug_category = 'ARB' THEN 1 ELSE 0 END) AS had_arb,
        MAX(CASE WHEN f.drug_category = 'ARB' THEN f.closest_months_before END) AS arb_months_before,

        -- SGLT2i
        MAX(CASE WHEN f.drug_category = 'SGLT2i' THEN 1 ELSE 0 END) AS had_sglt2i,
        MAX(CASE WHEN f.drug_category = 'SGLT2i' THEN f.closest_months_before END) AS sglt2i_months_before,

        -- Immunosuppressant
        MAX(CASE WHEN f.drug_category = 'Immunosuppressant' THEN 1 ELSE 0 END) AS had_immuno,
        MAX(CASE WHEN f.drug_category = 'Immunosuppressant' THEN f.closest_months_before END) AS immuno_months_before,

        -- Systemic steroid
        MAX(CASE WHEN f.drug_category = 'Systemic steroid' THEN 1 ELSE 0 END) AS had_steroid,
        MAX(CASE WHEN f.drug_category = 'Systemic steroid' THEN f.closest_months_before END) AS steroid_months_before,

        -- Diuretic / MRA
        MAX(CASE WHEN f.drug_category = 'Diuretic / MRA' THEN 1 ELSE 0 END) AS had_diuretic,

        -- Other IgAN treatments
        MAX(CASE WHEN f.drug_category = 'Other IgAN' THEN 1 ELSE 0 END) AS had_other_igan,

        -- Omega-3
        MAX(CASE WHEN f.drug_category = 'Omega-3' THEN 1 ELSE 0 END) AS had_omega3,

        -- Total distinct drug categories pre-Tarpeyo
        COUNT(DISTINCT f.drug_category) AS n_drug_categories_pre

    FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_cohort p
    LEFT JOIN first_per_cat f
        ON f.PATIENT_ID = p.PATIENT_ID
    GROUP BY p.PATIENT_ID, p.first_tarpeyo_fill, p.n_tarpeyo_fills
),

latest_ckd AS (
    SELECT
        d.PATIENT_ID,
        MAX(d.ckd_severity_rank) AS max_ckd_stage_pre
    FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_dx_events d
    JOIN P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_cohort c
        ON c.PATIENT_ID = d.PATIENT_ID
    WHERE d.ckd_severity_rank IS NOT NULL
      AND d.event_date < c.first_tarpeyo_fill
    GROUP BY d.PATIENT_ID
),

had_igan_dx AS (
    SELECT DISTINCT PATIENT_ID
    FROM P_CALT_022_ZDH_01.SCH_ANA_DATA.kp_tarp_dx_events
    WHERE dx_category IN ('IgAN (specific)', 'IgAN (proxy)')
)

SELECT
    w.*,
    COALESCE(k.max_ckd_stage_pre, 0) AS max_ckd_stage_pre,
    CASE WHEN i.PATIENT_ID IS NOT NULL THEN 1 ELSE 0 END AS had_igan_dx

FROM wide w
LEFT JOIN latest_ckd k
    ON k.PATIENT_ID = w.PATIENT_ID
LEFT JOIN had_igan_dx i
    ON i.PATIENT_ID = w.PATIENT_ID;

-- =====================================================
-- FINAL TABLE SIZES
-- =====================================================

SELECT 
    table_name, 
    row_count,
    ROUND(bytes / 1e6, 1) AS mb
FROM P_CALT_022_ZDH_01.information_schema.tables
WHERE table_schema = 'SCH_ANA_DATA'
  AND table_name ILIKE 'KP_TARP_%'
ORDER BY bytes DESC;
