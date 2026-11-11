-- -------------------------------------------------------------------
-- @2020, Odysseus Data Services, Inc. All rights reserved
-- MIMIC IV CDM Conversion
-- -------------------------------------------------------------------

-- -------------------------------------------------------------------
-- Populate person table
-- 
-- Dependencies: run after st_core.sql
-- on Demo: 12.4 sec
-- -------------------------------------------------------------------

-- -------------------------------------------------------------------
-- Known issues / Open points:
--
-- TRUNCATE TABLE is not supported, organize "create or replace"
-- @etl_project.@etl_dataset.person;
--
-- negative unique id from FARM_FINGERPRINT(GENERATE_UUID())
--
-- loaded custom mapping: 
--      gcpt_ethnicity_to_concept -> mimiciv_per_ethnicity
--
-- Why don't we want to use subject_id as person_id and hadm_id as visit_occurrence_id?
--      ask analysts
-- -------------------------------------------------------------------

-- -------------------------------------------------------------------
-- tmp_subject_ethnicity
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.tmp_subject_ethnicity AS
SELECT DISTINCT
    src.subject_id                      AS subject_id,
    FIRST_VALUE(src.ethnicity) OVER (
        PARTITION BY src.subject_id 
        ORDER BY src.admittime ASC)     AS ethnicity_first
FROM
    @etl_project.@etl_dataset.src_admissions src
;

-- -------------------------------------------------------------------
-- lk_pat_ethnicity_concept
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_pat_ethnicity_concept AS
WITH code_match AS (
    SELECT DISTINCT
        src.ethnicity_first     AS source_code,
        vc.concept_id           AS source_concept_id,
        vc.vocabulary_id        AS source_vocabulary_id,
        vc.domain_id            AS source_domain_id,
        vc1.concept_id          AS target_concept_id,
        vc1.vocabulary_id       AS target_vocabulary_id,
        vc1.domain_id           AS target_domain_id
    FROM
        @etl_project.@etl_dataset.tmp_subject_ethnicity src
    INNER JOIN
        @etl_project.@etl_dataset.voc_concept vc
            ON UPPER(vc.concept_code) = UPPER(src.ethnicity_first)
            AND vc.vocabulary_id = 'MIMIC4'
            AND vc.concept_class_id = 'm4_adm_race'
            AND vc.domain_id IN ('Race', 'Ethnicity')
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept_relationship cr1
            ON  cr1.concept_id_1 = vc.concept_id
            AND cr1.relationship_id = 'Maps to'
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept vc1
            ON  cr1.concept_id_2 = vc1.concept_id
            AND vc1.invalid_reason IS NULL
            AND vc1.standard_concept = 'S'
),
name_match AS (
    SELECT DISTINCT
        src.ethnicity_first     AS source_code,
        vc.concept_id           AS source_concept_id,
        vc.vocabulary_id        AS source_vocabulary_id,
        vc.domain_id            AS source_domain_id,
        vc1.concept_id          AS target_concept_id,
        vc1.vocabulary_id       AS target_vocabulary_id,
        vc1.domain_id           AS target_domain_id
    FROM
        @etl_project.@etl_dataset.tmp_subject_ethnicity src
    INNER JOIN
        @etl_project.@etl_dataset.voc_concept vc
            ON UPPER(vc.concept_name) = UPPER(src.ethnicity_first)
            AND vc.vocabulary_id = 'MIMIC4'
            AND vc.concept_class_id = 'm4_adm_race'
            AND vc.domain_id IN ('Race', 'Ethnicity')
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept_relationship cr1
            ON  cr1.concept_id_1 = vc.concept_id
            AND cr1.relationship_id = 'Maps to'
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept vc1
            ON  cr1.concept_id_2 = vc1.concept_id
            AND vc1.invalid_reason IS NULL
            AND vc1.standard_concept = 'S'
    WHERE NOT EXISTS (
        SELECT 1
        FROM code_match cm
        WHERE cm.source_code = src.ethnicity_first
    )
),
synonym_match AS (
    SELECT DISTINCT
        src.ethnicity_first     AS source_code,
        vc.concept_id           AS source_concept_id,
        vc.vocabulary_id        AS source_vocabulary_id,
        vc.domain_id            AS source_domain_id,
        vc1.concept_id          AS target_concept_id,
        vc1.vocabulary_id       AS target_vocabulary_id,
        vc1.domain_id           AS target_domain_id
    FROM
        @etl_project.@etl_dataset.tmp_subject_ethnicity src
    INNER JOIN
        @etl_project.@etl_dataset.voc_concept_synonym vcs
            ON UPPER(vcs.concept_synonym_name) = UPPER(src.ethnicity_first)
    INNER JOIN
        @etl_project.@etl_dataset.voc_concept vc
            ON  vc.concept_id = vcs.concept_id
            AND vc.vocabulary_id = 'MIMIC4'
            AND vc.concept_class_id = 'm4_adm_race'
            AND vc.domain_id IN ('Race', 'Ethnicity')
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept_relationship cr1
            ON  cr1.concept_id_1 = vc.concept_id
            AND cr1.relationship_id = 'Maps to'
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept vc1
            ON  cr1.concept_id_2 = vc1.concept_id
            AND vc1.invalid_reason IS NULL
            AND vc1.standard_concept = 'S'
    WHERE NOT EXISTS (
        SELECT 1
        FROM code_match cm
        WHERE cm.source_code = src.ethnicity_first
    )
      AND NOT EXISTS (
        SELECT 1
        FROM name_match nm
        WHERE nm.source_code = src.ethnicity_first
    )
)
SELECT * FROM code_match
UNION ALL
SELECT * FROM name_match
UNION ALL
SELECT * FROM synonym_match
;

-- -------------------------------------------------------------------
-- person
-- -------------------------------------------------------------------

--HINT DISTRIBUTE_ON_KEY(person_id)
CREATE OR REPLACE TABLE @etl_project.@etl_dataset.person
(
    person_id                   INT64     not null ,
    gender_concept_id           INT64     not null ,
    year_of_birth               INT64     not null ,
    month_of_birth              INT64              ,
    day_of_birth                INT64              ,
    birth_datetime              DATETIME           ,
    race_concept_id             INT64     not null,
    ethnicity_concept_id        INT64     not null,
    location_id                 INT64              ,
    provider_id                 INT64              ,
    care_site_id                INT64              ,
    person_source_value         STRING             ,
    gender_source_value         STRING             ,
    gender_source_concept_id    INT64              ,
    race_source_value           STRING             ,
    race_source_concept_id      INT64              ,
    ethnicity_source_value      STRING             ,
    ethnicity_source_concept_id INT64              ,
    -- 
    unit_id                       STRING,
    load_table_id                 STRING,
    load_row_id                   INT64,
    trace_id                      STRING
)
;

INSERT INTO @etl_project.@etl_dataset.person
SELECT
    `@etl_project.@etl_dataset`.obf_id(p.subject_id, 32)    AS person_id,
    CASE 
        WHEN p.gender = 'F' THEN 8532 -- FEMALE
        WHEN p.gender = 'M' THEN 8507 -- MALE
        ELSE 0
    END                                                     AS gender_concept_id,
    EXTRACT(YEAR FROM DATE_ADD(DATE(p.anchor_year, 1, 1), INTERVAL d.offset_days DAY)) - p.anchor_age AS year_of_birth,
    CAST(NULL AS INT64)                                     AS month_of_birth,
    CAST(NULL AS INT64)                                     AS day_of_birth,
    CAST(NULL AS DATETIME)                                  AS birth_datetime,
    COALESCE(map_eth.target_concept_id, 0)                  AS race_concept_id,
    CASE
        WHEN eth.ethnicity_first IS NULL
            THEN 0
        WHEN REGEXP_CONTAINS(UPPER(eth.ethnicity_first), r'HISPANIC OR LATINO|HISPANIC/LATINO')
            THEN 38003563
        ELSE 0
    END                                                     AS ethnicity_concept_id,
    CAST(NULL AS INT64)                                     AS location_id,
    CAST(NULL AS INT64)                                     AS provider_id,
    CAST(NULL AS INT64)                                     AS care_site_id,
    CAST(p.subject_id AS STRING)                            AS person_source_value,
    p.gender                                                AS gender_source_value,
    0                                                       AS gender_source_concept_id,
    eth.ethnicity_first                                     AS race_source_value,
    COALESCE(map_eth.source_concept_id, 0)                  AS race_source_concept_id,
    --
    eth.ethnicity_first                                     AS ethnicity_source_value,
    map_eth.source_concept_id                               AS ethnicity_source_concept_id,
    'person.patients'                                       AS unit_id,
    p.load_table_id                                         AS load_table_id,
    p.load_row_id                                           AS load_row_id,
    p.trace_id                                              AS trace_id
FROM 
    @etl_project.@etl_dataset.src_patients p
LEFT JOIN 
    @etl_project.@etl_dataset.tmp_subject_ethnicity eth 
        ON  p.subject_id = eth.subject_id
LEFT JOIN
    @etl_project.@etl_dataset.lk_pat_ethnicity_concept map_eth
        ON  eth.ethnicity_first = map_eth.source_code
LEFT JOIN 
    @etl_project.@etl_dataset.date_shift_lookup d
    ON CAST(p.subject_id AS INT64) = d.subject_id
;


-- -------------------------------------------------------------------
-- cleanup
-- -------------------------------------------------------------------

-- DROP TABLE IF EXISTS @etl_project.@etl_dataset.tmp_subject_ethnicity;
