-- -------------------------------------------------------------------
-- @2020, Odysseus Data Services, Inc. All rights reserved
-- MIMIC IV CDM Conversion
-- -------------------------------------------------------------------
-- -------------------------------------------------------------------
-- Populate lookups for observation table
-- 
-- Dependencies: run after 
--      st_core.sql,
--      st_hosp.sql
-- -------------------------------------------------------------------

-- -------------------------------------------------------------------
-- Known issues / Open points:
--
-- TRUNCATE TABLE is not supported, organize create or replace
--
-- Cost containment drgcode should be in cost table apparently.... 
--      http://forums.ohdsi.org/t/most-appropriate-omop-table-to-house-drg-information/1591/9,
-- observation.proc.* (Achilless Heel report)
--      value_as_string IS NULL AND value_as_number IS NULL AND COALESCE(value_as_concept_id, 0) = 0
--      review custom mapping. if ok, use value_as_concept_id = 4188539 'Yes'?
-- -------------------------------------------------------------------

-- on demo: 1585 rows
-- -------------------------------------------------------------------
-- lk_observation_clean from admissions
-- rules 1-3
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_observation_clean AS
-- rule 1, insurance
SELECT
    src.subject_id                  AS subject_id,
    src.hadm_id                     AS hadm_id,
    'Insurance'                     AS source_code,
    46235654                        AS target_concept_id, -- Primary insurance,
    src.admittime                   AS start_datetime,
    src.insurance                   AS value_as_string,
    'mimiciv_obs_insurance'         AS source_vocabulary_id,
    --
    'admissions.insurance'          AS unit_id,
    src.load_table_id               AS load_table_id,
    src.load_row_id                 AS load_row_id,
    src.trace_id                    AS trace_id
FROM
    @etl_project.@etl_dataset.src_admissions src -- adm
WHERE
    src.insurance IS NOT NULL

UNION ALL
-- rule 2, marital_status
SELECT
    src.subject_id                  AS subject_id,
    src.hadm_id                     AS hadm_id,
    'Marital status'                AS source_code,
    40766231                        AS target_concept_id, -- Marital status,
    src.admittime                   AS start_datetime,
    src.marital_status              AS value_as_string,
    'mimiciv_obs_marital'           AS source_vocabulary_id,
    --
    'admissions.marital_status'     AS unit_id,
    src.load_table_id               AS load_table_id,
    src.load_row_id                 AS load_row_id,
    src.trace_id                    AS trace_id
FROM
    @etl_project.@etl_dataset.src_admissions src -- adm
WHERE
    src.marital_status IS NOT NULL

UNION ALL
-- rule 3, language
SELECT
    src.subject_id                  AS subject_id,
    src.hadm_id                     AS hadm_id,
    'Language'                      AS source_code,
    40758030                        AS target_concept_id, -- Preferred language
    src.admittime                   AS start_datetime,
    src.language                    AS value_as_string,
    'mimiciv_obs_language'          AS source_vocabulary_id,
    --
    'admissions.language'           AS unit_id,
    src.load_table_id               AS load_table_id,
    src.load_row_id                 AS load_row_id,
    src.trace_id                    AS trace_id
FROM
    @etl_project.@etl_dataset.src_admissions src -- adm
WHERE
    src.language IS NOT NULL
;

-- -------------------------------------------------------------------
-- lk_observation_clean
-- Rule 4, drgcodes
-- -------------------------------------------------------------------

INSERT INTO @etl_project.@etl_dataset.lk_observation_clean
SELECT
    src.subject_id                  AS subject_id,
    src.hadm_id                     AS hadm_id,
    -- 'DRG code' AS source_code,
    src.drg_code                    AS source_code,
    4296248                         AS target_concept_id, -- Cost containment
    COALESCE(adm.edregtime, adm.admittime)  AS start_datetime,
    src.description                 AS value_as_string,
    'mimiciv_obs_drgcodes'          AS source_vocabulary_id,
    --
    'drgcodes.description'          AS unit_id,
    src.load_table_id               AS load_table_id,
    src.load_row_id                 AS load_row_id,
    src.trace_id                    AS trace_id
FROM
    @etl_project.@etl_dataset.src_drgcodes src -- drg
INNER JOIN
    @etl_project.@etl_dataset.src_admissions adm
        ON src.hadm_id = adm.hadm_id
WHERE
    src.description IS NOT NULL
;


-- on demo: 270 rows
-- -------------------------------------------------------------------
-- lk_obs_admissions_concept
-- Rules 1-4
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_obs_admissions_concept AS
WITH obs_source AS (
    SELECT DISTINCT
        src.value_as_string         AS source_code,
        src.source_vocabulary_id    AS source_vocabulary_id
    FROM
        @etl_project.@etl_dataset.lk_observation_clean src
),
code_match AS (
    SELECT DISTINCT
        src.source_code             AS source_code,
        src.source_vocabulary_id    AS source_vocabulary_id,
        vc.domain_id                AS source_domain_id,
        vc.concept_id               AS source_concept_id,
        vc2.domain_id               AS target_domain_id,
        vc2.concept_id              AS target_concept_id
    FROM
        obs_source src
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept vc
            ON src.source_code = vc.concept_code
            AND vc.vocabulary_id = 'MIMIC4'
            AND vc.domain_id IN ('Observation', 'Language', 'Meas Value')
            AND (
                    (src.source_vocabulary_id = 'mimiciv_obs_drgcodes' AND vc.concept_class_id = 'm4_drg_desc')
                    OR (src.source_vocabulary_id = 'mimiciv_obs_insurance' AND vc.concept_class_id = 'm4_insurance')
                    OR (src.source_vocabulary_id = 'mimiciv_obs_language' AND vc.concept_class_id = 'm4_language')
                    OR (src.source_vocabulary_id = 'mimiciv_obs_marital' AND vc.concept_class_id = 'm4_marital_status')
                )
            -- valid period should be used to map drg_code, but due to the date shift it is not applicable
            -- AND src.start_datetime BETWEEN vc.valid_start_date AND vc.valid_end_date
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept_relationship vcr
            ON  vc.concept_id = vcr.concept_id_1
            AND vcr.relationship_id = 'Maps to'
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept vc2
            ON vc2.concept_id = vcr.concept_id_2
            AND vc2.standard_concept = 'S'
            AND vc2.invalid_reason IS NULL
),
name_match AS (
    SELECT DISTINCT
        src.source_code             AS source_code,
        src.source_vocabulary_id    AS source_vocabulary_id,
        vc.domain_id                AS source_domain_id,
        vc.concept_id               AS source_concept_id,
        vc2.domain_id               AS target_domain_id,
        vc2.concept_id              AS target_concept_id
    FROM
        obs_source src
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept vc
            ON src.source_code = vc.concept_name
            AND vc.vocabulary_id = 'MIMIC4'
            AND vc.domain_id IN ('Observation', 'Language', 'Meas Value')
            AND (
                    (src.source_vocabulary_id = 'mimiciv_obs_drgcodes' AND vc.concept_class_id = 'm4_drg_desc')
                    OR (src.source_vocabulary_id = 'mimiciv_obs_insurance' AND vc.concept_class_id = 'm4_insurance')
                    OR (src.source_vocabulary_id = 'mimiciv_obs_language' AND vc.concept_class_id = 'm4_language')
                    OR (src.source_vocabulary_id = 'mimiciv_obs_marital' AND vc.concept_class_id = 'm4_marital_status')
                )
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept_relationship vcr
            ON  vc.concept_id = vcr.concept_id_1
            AND vcr.relationship_id = 'Maps to'
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept vc2
            ON vc2.concept_id = vcr.concept_id_2
            AND vc2.standard_concept = 'S'
            AND vc2.invalid_reason IS NULL
    WHERE
        NOT EXISTS (
            SELECT 1
            FROM code_match cm
            WHERE cm.source_code = src.source_code
              AND cm.source_vocabulary_id = src.source_vocabulary_id
              AND cm.source_concept_id IS NOT NULL
        )
),
synonym_match AS (
    SELECT DISTINCT
        src.source_code             AS source_code,
        src.source_vocabulary_id    AS source_vocabulary_id,
        vc.domain_id                AS source_domain_id,
        vc.concept_id               AS source_concept_id,
        vc2.domain_id               AS target_domain_id,
        vc2.concept_id              AS target_concept_id
    FROM
        obs_source src
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept_synonym vcs
            ON src.source_code = vcs.concept_synonym_name
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept vc
            ON vc.concept_id = vcs.concept_id
            AND vc.vocabulary_id = 'MIMIC4'
            AND vc.domain_id IN ('Observation', 'Language', 'Meas Value')
            AND (
                    (src.source_vocabulary_id = 'mimiciv_obs_drgcodes' AND vc.concept_class_id = 'm4_drg_desc')
                    OR (src.source_vocabulary_id = 'mimiciv_obs_insurance' AND vc.concept_class_id = 'm4_insurance')
                    OR (src.source_vocabulary_id = 'mimiciv_obs_language' AND vc.concept_class_id = 'm4_language')
                    OR (src.source_vocabulary_id = 'mimiciv_obs_marital' AND vc.concept_class_id = 'm4_marital_status')
                )
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept_relationship vcr
            ON  vc.concept_id = vcr.concept_id_1
            AND vcr.relationship_id = 'Maps to'
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept vc2
            ON vc2.concept_id = vcr.concept_id_2
            AND vc2.standard_concept = 'S'
            AND vc2.invalid_reason IS NULL
    WHERE
        NOT EXISTS (
            SELECT 1
            FROM code_match cm
            WHERE cm.source_code = src.source_code
              AND cm.source_vocabulary_id = src.source_vocabulary_id
              AND cm.source_concept_id IS NOT NULL
        )
        AND NOT EXISTS (
            SELECT 1
            FROM name_match nm
            WHERE nm.source_code = src.source_code
              AND nm.source_vocabulary_id = src.source_vocabulary_id
              AND nm.source_concept_id IS NOT NULL
        )
)
SELECT * FROM code_match
UNION ALL
SELECT * FROM name_match
UNION ALL
SELECT * FROM synonym_match
;

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_obs_admissions_concept_dedup AS
SELECT
    source_code,
    source_vocabulary_id,
    source_domain_id,
    source_concept_id,
    target_domain_id,
    target_concept_id
FROM (
    SELECT
        src.*,
        ROW_NUMBER() OVER (
            PARTITION BY src.source_code, src.source_vocabulary_id
            ORDER BY
                IF(src.target_concept_id IS NOT NULL, 0, 1),
                IF(src.source_concept_id IS NOT NULL, 0, 1),
                src.source_code
        ) AS row_num
    FROM
        @etl_project.@etl_dataset.lk_obs_admissions_concept src
)
WHERE
    row_num = 1
;

-- -------------------------------------------------------------------
-- lk_observation_mapped
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_observation_mapped AS
SELECT
    src.hadm_id                             AS hadm_id, -- to visit
    src.subject_id                          AS subject_id, -- to person
    COALESCE(src.target_concept_id, 0)      AS target_concept_id,
    src.start_datetime                      AS start_datetime,
    32817                                   AS type_concept_id, -- OMOP4976890 EHR, -- Rules 1-4
    src.source_code                         AS source_code,
    -- # BG: updated relative to the old design to carry forward the joined custom
    -- # BG: source concept from lk_obs_admissions_concept when available, rather
    -- # BG: than hard-coding source_concept_id to 0.
    COALESCE(lc.source_concept_id, 0)       AS source_concept_id,
    src.value_as_string                     AS value_as_string,
    lc.target_concept_id                    AS value_as_concept_id,
    'Observation'                           AS target_domain_id, -- to join on src.target_concept_id?
    --
    src.unit_id                     AS unit_id,
    src.load_table_id               AS load_table_id,
    src.load_row_id                 AS load_row_id,
    src.trace_id                    AS trace_id
FROM
    @etl_project.@etl_dataset.lk_observation_clean src
LEFT JOIN
    @etl_project.@etl_dataset.lk_obs_admissions_concept_dedup lc
        ON src.value_as_string = lc.source_code
        AND src.source_vocabulary_id = lc.source_vocabulary_id
;
