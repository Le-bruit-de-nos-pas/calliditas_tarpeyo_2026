-- =====================================================
-- DATABASE EXPLORATION & TABLE SIZING
-- =====================================================

-- Available databases
SHOW DATABASES;

-- Available schemas in target database
USE DATABASE P_CALT_022_ZDH_01;
SHOW SCHEMAS;

-- Check grants on schema SCH_ANA_DATA
SHOW GRANTS ON SCHEMA P_CALT_022_ZDH_01.SCH_ANA_DATA;

-- Check grants on schema SCH_DM_DATA
SHOW GRANTS ON SCHEMA P_CALT_022_ZDH_01.SCH_DM_DATA;

-- Test write attempt 
-- CREATE TABLE P_CALT_022_ZDH_01.SCH_DM_DATA.TEST_WRITE AS SELECT 1 AS col;

-- Query all schemata information
SELECT * FROM INFORMATION_SCHEMA.SCHEMATA;

-- =====================================================
-- TABLE SIZES IN SCH_RAW_DATA (rows and GB)
-- =====================================================
SELECT 
    table_name,
    row_count,
    bytes,
    bytes / POWER(1024, 3) AS gb
FROM P_CALT_022_ZDH_01.INFORMATION_SCHEMA.TABLES
WHERE table_schema = 'SCH_RAW_DATA'
ORDER BY bytes DESC;

-- =====================================================
-- TABLE SIZES IN SCH_DM_DATA (rows and GB)
-- =====================================================
SELECT 
    table_name,
    row_count,
    bytes,
    bytes / POWER(1024, 3) AS gb
FROM P_CALT_022_ZDH_01.INFORMATION_SCHEMA.TABLES
WHERE table_schema = 'SCH_DM_DATA'
ORDER BY bytes DESC;

-- =====================================================
-- STG_DIAGNOSIS_CLAIMS - Key Figures
-- =====================================================

-- Unique patients count
SELECT COUNT(DISTINCT PATIENT_ID) AS unique_patients
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_DIAGNOSIS_CLAIMS;

-- Sample data preview
SELECT * FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_DIAGNOSIS_CLAIMS LIMIT 20;

-- Date range coverage
SELECT
    MIN(TO_TIMESTAMP(SERVICE_DATE)) AS start_date,
    MAX(TO_TIMESTAMP(SERVICE_DATE)) AS end_date
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_DIAGNOSIS_CLAIMS;

-- Unique patients per year (approx)
SELECT
    YEAR(TO_TIMESTAMP(SERVICE_DATE)) AS year,
    APPROX_COUNT_DISTINCT(PATIENT_ID) AS approx_unique_patients
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_DIAGNOSIS_CLAIMS
WHERE SERVICE_DATE IS NOT NULL
GROUP BY year
ORDER BY year;

-- Most frequent diagnosis codes
SELECT 
    DIAGNOSIS_CODE,
    COUNT(*) AS row_count
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_DIAGNOSIS_CLAIMS
GROUP BY DIAGNOSIS_CODE
ORDER BY row_count DESC;

-- Distribution of number of distinct service dates per patient
WITH patient_date_counts AS (
    SELECT
        PATIENT_ID,
        COUNT(DISTINCT DATE(SERVICE_DATE)) AS n_dates
    FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_DIAGNOSIS_CLAIMS
    WHERE PATIENT_ID IS NOT NULL
      AND DATE(SERVICE_DATE) IS NOT NULL
    GROUP BY PATIENT_ID
),
dist AS (
    SELECT
        n_dates,
        COUNT(*) AS n_patients
    FROM patient_date_counts
    GROUP BY n_dates
)
SELECT
    n_dates,
    n_patients,
    n_patients * 100.0 / SUM(n_patients) OVER () AS pct_patients
FROM dist
ORDER BY n_dates;

-- =====================================================
-- STG_RX_CLAIMS - Key Figures
-- =====================================================

-- Unique patients count
SELECT COUNT(DISTINCT PATIENT_ID) AS unique_patients
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_RX_CLAIMS;

-- Sample data preview
SELECT * FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_RX_CLAIMS LIMIT 20;

-- Date range coverage
SELECT
    MIN(TO_TIMESTAMP(RX_FILL_DATE)) AS start_date,
    MAX(TO_TIMESTAMP(RX_FILL_DATE)) AS end_date
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_RX_CLAIMS;

-- Unique patients per year (approx)
SELECT
    YEAR(TO_TIMESTAMP(RX_FILL_DATE)) AS year,
    APPROX_COUNT_DISTINCT(PATIENT_ID) AS approx_unique_patients
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_RX_CLAIMS
WHERE RX_FILL_DATE IS NOT NULL
GROUP BY year
ORDER BY year;

-- Most frequent drugs
SELECT 
    DRUG_ID,
    COUNT(*) AS row_count
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_RX_CLAIMS
GROUP BY DRUG_ID
ORDER BY row_count DESC;

-- Distribution of number of distinct fill dates per patient
WITH patient_date_counts AS (
    SELECT
        PATIENT_ID,
        COUNT(DISTINCT DATE(RX_FILL_DATE)) AS n_dates
    FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_RX_CLAIMS
    WHERE PATIENT_ID IS NOT NULL
      AND DATE(RX_FILL_DATE) IS NOT NULL
    GROUP BY PATIENT_ID
),
dist AS (
    SELECT
        n_dates,
        COUNT(*) AS n_patients
    FROM patient_date_counts
    GROUP BY n_dates
)
SELECT
    n_dates,
    n_patients,
    n_patients * 100.0 / SUM(n_patients) OVER () AS pct_patients
FROM dist
ORDER BY n_dates;

-- =====================================================
-- STG_PROCEDURE_CLAIMS - Key Figures
-- =====================================================

-- Unique patients count
SELECT COUNT(DISTINCT PATIENT_ID) AS unique_patients
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_PROCEDURE_CLAIMS;

-- Sample data preview
SELECT * FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_PROCEDURE_CLAIMS LIMIT 20;

-- Date range coverage
SELECT
    MIN(TO_TIMESTAMP(PROCEDURE_DATE)) AS start_date,
    MAX(TO_TIMESTAMP(PROCEDURE_DATE)) AS end_date
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_PROCEDURE_CLAIMS;

-- Unique patients per year (approx)
SELECT
    YEAR(TO_TIMESTAMP(PROCEDURE_DATE)) AS year,
    APPROX_COUNT_DISTINCT(PATIENT_ID) AS approx_unique_patients
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_PROCEDURE_CLAIMS
WHERE PROCEDURE_DATE IS NOT NULL
GROUP BY year
ORDER BY year;

-- Most frequent procedure codes
SELECT 
    PROCEDURE_CODE,
    COUNT(*) AS row_count
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_PROCEDURE_CLAIMS
GROUP BY PROCEDURE_CODE
ORDER BY row_count DESC;

-- Distribution of claim line items
SELECT 
    CLAIM_LINE_ITEM,
    COUNT(*) AS row_count
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_PROCEDURE_CLAIMS
GROUP BY CLAIM_LINE_ITEM
ORDER BY row_count DESC;

-- Distribution of number of distinct procedure dates per patient
WITH patient_date_counts AS (
    SELECT
        PATIENT_ID,
        COUNT(DISTINCT DATE(PROCEDURE_DATE)) AS n_dates
    FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_PROCEDURE_CLAIMS
    WHERE PATIENT_ID IS NOT NULL
      AND DATE(PROCEDURE_DATE) IS NOT NULL
    GROUP BY PATIENT_ID
),
dist AS (
    SELECT
        n_dates,
        COUNT(*) AS n_patients
    FROM patient_date_counts
    GROUP BY n_dates
)
SELECT
    n_dates,
    n_patients,
    n_patients * 100.0 / SUM(n_patients) OVER () AS pct_patients
FROM dist
ORDER BY n_dates;

-- =====================================================
-- STG_LABS - Key Figures
-- =====================================================

-- Unique patients count (using PATIENT_GID)
SELECT COUNT(DISTINCT PATIENT_GID) AS unique_patients
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_LABS;

-- Sample data preview
SELECT * FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_LABS LIMIT 20;

-- Date range coverage
SELECT
    MIN(TO_TIMESTAMP(DATE_COLLECTED)) AS start_date,
    MAX(TO_TIMESTAMP(DATE_COLLECTED)) AS end_date
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_LABS;

-- Unique patients per year (approx)
SELECT
    YEAR(TO_TIMESTAMP(DATE_COLLECTED)) AS year,
    APPROX_COUNT_DISTINCT(PATIENT_GID) AS approx_unique_patients
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_LABS
WHERE DATE_COLLECTED IS NOT NULL
GROUP BY year
ORDER BY year;

-- Most frequent lab result names
SELECT 
    RESULT_NAME,
    COUNT(*) AS row_count
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_LABS
WHERE 
    (RESULT_VALUE IS NOT NULL AND RESULT_VALUE <> '')
GROUP BY RESULT_NAME
ORDER BY row_count DESC;

-- Distinct lab result names
SELECT DISTINCT(RESULT_NAME)
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_LABS
ORDER BY RESULT_NAME;

-- Distinct lab IDs
SELECT DISTINCT(LAB_ID)
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_LABS
ORDER BY LAB_ID;

-- Distribution of number of distinct collection dates per patient
WITH patient_date_counts AS (
    SELECT
        PATIENT_GID,
        COUNT(DISTINCT DATE(DATE_COLLECTED)) AS n_dates
    FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_LABS
    WHERE PATIENT_GID IS NOT NULL
      AND DATE(DATE_COLLECTED) IS NOT NULL
    GROUP BY PATIENT_GID
),
dist AS (
    SELECT
        n_dates,
        COUNT(*) AS n_patients
    FROM patient_date_counts
    GROUP BY n_dates
)
SELECT
    n_dates,
    n_patients,
    n_patients * 100.0 / SUM(n_patients) OVER () AS pct_patients
FROM dist
ORDER BY n_dates;

-- =====================================================
-- STG_PROGNOS - Key Figures
-- =====================================================

-- Approximate distinct tokens/patients
SELECT APPROX_COUNT_DISTINCT(DV_TOKEN_1)
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_PROGNOS;

-- Non-null counts across token columns
SELECT
    COUNT(*) AS total_rows,
    COUNT(DV_TOKEN_1) AS token1_non_null,
    COUNT(DV_TOKEN_2) AS token2_non_null,
    COUNT(DV_TOKEN_3) AS token3_non_null
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_PROGNOS;

-- Sample data preview
SELECT * FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_PROGNOS LIMIT 10;

-- Distinct test result types
SELECT DISTINCT(TEST_RESULT_TYPE)
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_PROGNOS
ORDER BY TEST_RESULT_TYPE;

-- Test result type frequency
SELECT 
    TEST_RESULT_TYPE,
    COUNT(*) AS row_count
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_PROGNOS
WHERE 
    (TEST_RESULT_NUMERIC IS NOT NULL AND TEST_RESULT_NUMERIC <> '')
    OR
    (TEST_RESULT_NON_NUMERIC IS NOT NULL AND TEST_RESULT_NON_NUMERIC <> '')
GROUP BY TEST_RESULT_TYPE
ORDER BY row_count DESC;

-- Date range (ESTIMATED_PATIENT_TEST_PERFORMED_DATETIME)
SELECT
    MIN(TO_TIMESTAMP(ESTIMATED_PATIENT_TEST_PERFORMED_DATETIME)) AS start_date,
    MAX(TO_TIMESTAMP(ESTIMATED_PATIENT_TEST_PERFORMED_DATETIME)) AS end_date
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_PROGNOS;

-- Date range (TEST_OBSERVATION_DATETIME)
SELECT
    MIN(TO_TIMESTAMP(TEST_OBSERVATION_DATETIME)) AS start_date,
    MAX(TO_TIMESTAMP(TEST_OBSERVATION_DATETIME)) AS end_date
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_PROGNOS;

-- Unique patients per year (by ESTIMATED_PATIENT_TEST_PERFORMED_DATETIME)
SELECT
    YEAR(TO_TIMESTAMP(ESTIMATED_PATIENT_TEST_PERFORMED_DATETIME)) AS year,
    APPROX_COUNT_DISTINCT(DV_TOKEN_1) AS approx_unique_patients
FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_PROGNOS
WHERE ESTIMATED_PATIENT_TEST_PERFORMED_DATETIME IS NOT NULL
GROUP BY year
ORDER BY year;

-- First seen year per patient
WITH first_seen AS (
    SELECT
        DV_TOKEN_1,
        MIN(TO_TIMESTAMP(ESTIMATED_PATIENT_TEST_PERFORMED_DATETIME)) AS first_date
    FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_PROGNOS
    WHERE ESTIMATED_PATIENT_TEST_PERFORMED_DATETIME IS NOT NULL
    GROUP BY DV_TOKEN_1
)
SELECT
    YEAR(first_date) AS first_year,
    APPROX_COUNT_DISTINCT(DV_TOKEN_1) AS patients
FROM first_seen
GROUP BY first_year
ORDER BY first_year;

-- Distribution of rows per token (patient)
WITH token_counts AS (
    SELECT
        DV_TOKEN_1,
        COUNT(*) AS n_rows
    FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_PROGNOS
    WHERE DV_TOKEN_1 IS NOT NULL
    GROUP BY DV_TOKEN_1
)
SELECT
    n_rows,
    COUNT(*) AS n_tokens
FROM token_counts
GROUP BY n_rows
ORDER BY n_rows;

-- Distribution of rows per token with percentages
WITH token_counts AS (
    SELECT
        DV_TOKEN_1,
        COUNT(*) AS n_rows
    FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_PROGNOS
    WHERE DV_TOKEN_1 IS NOT NULL
    GROUP BY DV_TOKEN_1
),
dist AS (
    SELECT
        n_rows,
        COUNT(*) AS n_tokens
    FROM token_counts
    GROUP BY n_rows
)
SELECT
    n_rows,
    n_tokens,
    n_tokens * 1.0 / SUM(n_tokens) OVER () AS pct_tokens
FROM dist
ORDER BY n_rows;

-- Distribution of distinct dates per token
WITH token_date_counts AS (
    SELECT
        DV_TOKEN_1,
        COUNT(DISTINCT DATE(TRY_TO_TIMESTAMP(ESTIMATED_PATIENT_TEST_PERFORMED_DATETIME))) AS n_dates
    FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_PROGNOS
    WHERE DV_TOKEN_1 IS NOT NULL
      AND TRY_TO_TIMESTAMP(ESTIMATED_PATIENT_TEST_PERFORMED_DATETIME) IS NOT NULL
    GROUP BY DV_TOKEN_1
),
dist AS (
    SELECT
        n_dates,
        COUNT(*) AS n_tokens
    FROM token_date_counts
    GROUP BY n_dates
)
SELECT
    n_dates,
    n_tokens,
    n_tokens * 100.0 / SUM(n_tokens) OVER () AS pct_tokens
FROM dist
ORDER BY n_dates;

-- =====================================================
-- PATIENT OVERLAP ACROSS DATA SOURCES (Full dataset)
-- =====================================================
-- Note: The dataset is heavily dominated by full overlap (111)
-- ~28 million patients have all three sources

WITH rx AS (
    SELECT DISTINCT PATIENT_ID
    FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_RX_CLAIMS
),
dx AS (
    SELECT DISTINCT PATIENT_ID
    FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_DIAGNOSIS_CLAIMS
),
proc AS (
    SELECT DISTINCT PATIENT_ID
    FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_PROCEDURE_CLAIMS
),
base AS (
    SELECT
        COALESCE(r.PATIENT_ID, d.PATIENT_ID, p.PATIENT_ID) AS PATIENT_ID,
        CASE WHEN r.PATIENT_ID IS NOT NULL THEN 1 ELSE 0 END AS has_rx,
        CASE WHEN d.PATIENT_ID IS NOT NULL THEN 1 ELSE 0 END AS has_dx,
        CASE WHEN p.PATIENT_ID IS NOT NULL THEN 1 ELSE 0 END AS has_proc
    FROM rx r
    FULL OUTER JOIN dx d ON r.PATIENT_ID = d.PATIENT_ID
    FULL OUTER JOIN proc p ON COALESCE(r.PATIENT_ID, d.PATIENT_ID) = p.PATIENT_ID
)
SELECT
    CONCAT(has_rx, has_dx, has_proc) AS pattern,
    COUNT(*) AS n_patients
FROM base
GROUP BY pattern
ORDER BY n_patients DESC;

-- =====================================================
-- PATIENT OVERLAP ACROSS DATA SOURCES (Per year)
-- =====================================================

WITH rx AS (
    SELECT DISTINCT
        PATIENT_ID,
        YEAR(TRY_TO_DATE(RX_FILL_DATE)) AS yr
    FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_RX_CLAIMS
    WHERE RX_FILL_DATE IS NOT NULL
),
dx AS (
    SELECT DISTINCT
        PATIENT_ID,
        YEAR(TRY_TO_DATE(SERVICE_DATE)) AS yr
    FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_DIAGNOSIS_CLAIMS
    WHERE SERVICE_DATE IS NOT NULL
),
proc AS (
    SELECT DISTINCT
        PATIENT_ID,
        YEAR(TRY_TO_DATE(PROCEDURE_DATE)) AS yr
    FROM P_CALT_022_ZDH_01.SCH_RAW_DATA.STG_PROCEDURE_CLAIMS
    WHERE PROCEDURE_DATE IS NOT NULL
),
years AS (
    SELECT 2020 AS yr UNION ALL
    SELECT 2021 UNION ALL
    SELECT 2022 UNION ALL
    SELECT 2023 UNION ALL
    SELECT 2024 UNION ALL
    SELECT 2025 UNION ALL
    SELECT 2026
),
base AS (
    SELECT
        y.yr,
        COALESCE(r.PATIENT_ID, d.PATIENT_ID, p.PATIENT_ID) AS PATIENT_ID,
        CASE WHEN r.PATIENT_ID IS NOT NULL THEN 1 ELSE 0 END AS has_rx,
        CASE WHEN d.PATIENT_ID IS NOT NULL THEN 1 ELSE 0 END AS has_dx,
        CASE WHEN p.PATIENT_ID IS NOT NULL THEN 1 ELSE 0 END AS has_proc
    FROM years y
    LEFT JOIN rx r ON r.yr = y.yr
    FULL OUTER JOIN dx d ON r.PATIENT_ID = d.PATIENT_ID AND r.yr = y.yr
    FULL OUTER JOIN proc p ON COALESCE(r.PATIENT_ID, d.PATIENT_ID) = p.PATIENT_ID
        AND COALESCE(r.yr, d.yr, y.yr) = p.yr
)
SELECT
    yr,
    CONCAT(has_rx, has_dx, has_proc) AS pattern,
    COUNT(*) AS n_patients
FROM base
GROUP BY yr, pattern
ORDER BY yr, n_patients DESC;

