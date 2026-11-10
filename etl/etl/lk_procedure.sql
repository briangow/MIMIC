-- -------------------------------------------------------------------
-- @2020, Odysseus Data Services, Inc. All rights reserved
-- MIMIC IV CDM Conversion
-- -------------------------------------------------------------------
-- -------------------------------------------------------------------
-- Populate lookups for procedure_occurrence table
-- 
-- Dependencies: run after 
--      st_core.sql,
--      st_hosp.sql,
--
-- -------------------------------------------------------------------

-- -------------------------------------------------------------------
-- Known issues / Open points:
--
-- TRUNCATE TABLE is not supported, organize create or replace
--
-- remove dots from ICD codes
-- to review "custom mapping" from d_icd_procedures: domain_id = 'd_icd_procedures' AND vocabulary_id = 'MIMIC Local Codes'
-- to review relationship_id IN ('CPT4 - SNOMED eq','Maps to')
-- datetimeevents: to summarize count of duplicated rows or to use charttime instead of value?
-- Rule 1
--      add more custom mapping for CPT4 if needed
-- -------------------------------------------------------------------


DROP TABLE IF EXISTS @etl_project.@etl_dataset.lk_datetimeevents_concept;
DROP TABLE IF EXISTS @etl_project.@etl_dataset.lk_proc_event_clean;
DROP TABLE IF EXISTS @etl_project.@etl_dataset.lk_datetimeevents_clean;
DROP TABLE IF EXISTS @etl_project.@etl_dataset.lk_proc_d_items_clean;

-- -------------------------------------------------------------------
-- lk_hcpcsevents_clean
-- Rule 1, HCPCS mapping
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_hcpcsevents_clean AS
 SELECT
    src.subject_id      AS subject_id,
    src.hadm_id         AS hadm_id,
    adm.dischtime       AS start_datetime,
    src.seq_num         AS seq_num, --- procedure_type as in condtion_occurrence
    src.hcpcs_cd                            AS hcpcs_cd,
    src.short_description                   AS short_description,
    --
    src.load_table_id                   AS load_table_id,
    src.load_row_id                     AS load_row_id,
    src.trace_id                        AS trace_id
FROM
    @etl_project.@etl_dataset.src_hcpcsevents src
INNER JOIN
    @etl_project.@etl_dataset.src_admissions adm
        ON src.hadm_id = adm.hadm_id
;

-- -------------------------------------------------------------------
-- lk_procedures_icd_clean
-- Rule 2, ICD mapping
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_procedures_icd_clean AS
SELECT
    src.subject_id                              AS subject_id,
    src.hadm_id                                 AS hadm_id,
    adm.dischtime                               AS start_datetime,
    src.icd_code                                AS source_code,
    src.icd_version                             AS icd_version,
    CASE
        WHEN src.icd_version = 9 THEN 'ICD9Proc'
        WHEN src.icd_version = 10 THEN 'ICD10PCS'
    END                                         AS source_vocabulary_id,
    --
    src.load_table_id                           AS load_table_id,
    src.load_row_id                             AS load_row_id,
    src.trace_id                                AS trace_id
FROM
    @etl_project.@etl_dataset.src_procedures_icd src
INNER JOIN
    @etl_project.@etl_dataset.src_admissions adm
        ON src.hadm_id = adm.hadm_id
;

-- -------------------------------------------------------------------
-- lk_proc_d_items_clean from procedureevents
-- Rule 3, d_items custom mapping
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_proc_event_clean AS
SELECT
    src.subject_id                      AS subject_id,
    src.hadm_id                         AS hadm_id,
    src.starttime                       AS start_datetime,
    src.itemid                          AS itemid,
    CAST(src.itemid AS STRING)          AS source_code,
    d_items.label                       AS source_label,
    src.value                           AS quantity,
    --
    'procedureevents'                   AS unit_id,
    src.load_table_id                   AS load_table_id,
    src.load_row_id                     AS load_row_id,
    src.trace_id                        AS trace_id
FROM
    @etl_project.@etl_dataset.src_procedureevents src
INNER JOIN
    @etl_project.@etl_dataset.src_d_items d_items
        ON src.itemid = d_items.itemid
WHERE
    src.cancelreason = 0 -- not cancelled
;

-- -------------------------------------------------------------------
-- lk_datetimeevents_clean
-- Rule 4, d_items custom mapping
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_datetimeevents_clean AS
SELECT
    src.subject_id                      AS subject_id,
    src.hadm_id                         AS hadm_id,
    src.charttime                       AS start_datetime,
    src.itemid                          AS itemid,
    d_items.label                       AS source_code,
    d_items.label                       AS source_label,
    CAST(1 AS FLOAT64)                  AS quantity,
    --
    'datetimeevents'                    AS unit_id,
    src.load_table_id                   AS load_table_id,
    src.load_row_id                     AS load_row_id,
    src.trace_id                        AS trace_id
FROM
    @etl_project.@etl_dataset.src_datetimeevents src
INNER JOIN
    @etl_project.@etl_dataset.src_d_items d_items
        ON src.itemid = d_items.itemid
;

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_proc_d_items_clean AS
SELECT
    src.subject_id                      AS subject_id,
    src.hadm_id                         AS hadm_id,
    src.start_datetime                  AS start_datetime,
    src.itemid                          AS itemid,
    src.source_code                     AS source_code,
    src.source_label                    AS source_label,
    src.quantity                        AS quantity,
    'MIMIC4'                            AS source_vocabulary_id,
    'm4_proc_itemid'                    AS source_concept_class_id,
    src.unit_id                         AS unit_id,
    src.load_table_id                   AS load_table_id,
    src.load_row_id                     AS load_row_id,
    src.trace_id                        AS trace_id
FROM @etl_project.@etl_dataset.lk_proc_event_clean src
UNION ALL
SELECT
    src.subject_id                      AS subject_id,
    src.hadm_id                         AS hadm_id,
    src.start_datetime                  AS start_datetime,
    src.itemid                          AS itemid,
    src.source_code                     AS source_code,
    src.source_label                    AS source_label,
    src.quantity                        AS quantity,
    'MIMIC4'                            AS source_vocabulary_id,
    'm4_datetime_item'                  AS source_concept_class_id,
    src.unit_id                         AS unit_id,
    src.load_table_id                   AS load_table_id,
    src.load_row_id                     AS load_row_id,
    src.trace_id                        AS trace_id
FROM @etl_project.@etl_dataset.lk_datetimeevents_clean src
;

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_proc_d_items_distinct AS
SELECT DISTINCT
    itemid,
    source_code,
    source_label,
    source_vocabulary_id,
    source_concept_class_id
FROM
    @etl_project.@etl_dataset.lk_proc_d_items_clean
;

-- -------------------------------------------------------------------
-- lk_icd_proc_concept
-- Rule 2, ICD mapping
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_icd_proc_concept AS
SELECT
    vc.concept_code                         AS source_code,
    vc.vocabulary_id                        AS source_vocabulary_id,
    vc.domain_id                            AS source_domain_id,
    vc.concept_id                           AS source_concept_id,
    vc2.domain_id                           AS target_domain_id,
    vc2.concept_id                          AS target_concept_id
FROM
    @etl_project.@etl_dataset.voc_concept vc
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
    vc.vocabulary_id IN ('ICD9Proc', 'ICD10PCS')
;


-- -------------------------------------------------------------------
-- mapping
-- Rule 2, 4 
-- can be optimized by including Specimen mapping to lk_itemid_concept
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_itemid_concept AS
WITH code_match AS (
    SELECT
        src.itemid                      AS itemid,
        src.source_code                 AS source_code,
        src.source_label                AS source_label,
        src.source_vocabulary_id        AS source_vocabulary_id,
        src.source_concept_class_id     AS source_concept_class_id,
        vc.domain_id                    AS source_domain_id,
        vc.concept_id                   AS source_concept_id,
        vc.concept_name                 AS source_concept_name
    FROM
        @etl_project.@etl_dataset.lk_proc_d_items_distinct src
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept vc
            ON vc.concept_code = src.source_code
            AND vc.vocabulary_id = src.source_vocabulary_id
            AND vc.concept_class_id = src.source_concept_class_id
),
name_match AS (
    SELECT
        cm.itemid                   AS itemid,
        cm.source_code              AS source_code,
        cm.source_label             AS source_label,
        cm.source_vocabulary_id     AS source_vocabulary_id,
        cm.source_concept_class_id  AS source_concept_class_id,
        COALESCE(cm.source_domain_id, vc.domain_id)        AS source_domain_id,
        COALESCE(cm.source_concept_id, vc.concept_id)      AS source_concept_id,
        COALESCE(cm.source_concept_name, vc.concept_name)  AS source_concept_name
    FROM
        code_match cm
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept vc
            ON cm.source_concept_id IS NULL
            AND cm.source_label = vc.concept_name
            AND vc.vocabulary_id = cm.source_vocabulary_id
            AND vc.concept_class_id = cm.source_concept_class_id
    WHERE
        cm.source_concept_id IS NULL
        AND NOT EXISTS (
            SELECT 1
            FROM code_match prior
            WHERE prior.source_code = cm.source_code
              AND prior.source_vocabulary_id = cm.source_vocabulary_id
              AND prior.source_concept_class_id = cm.source_concept_class_id
              AND prior.source_concept_id IS NOT NULL
        )
),
synonym_match AS (
    SELECT
        cm.itemid                   AS itemid,
        cm.source_code              AS source_code,
        cm.source_label             AS source_label,
        cm.source_vocabulary_id     AS source_vocabulary_id,
        cm.source_concept_class_id  AS source_concept_class_id,
        COALESCE(cm.source_domain_id, vc.domain_id)        AS source_domain_id,
        COALESCE(cm.source_concept_id, vc.concept_id)      AS source_concept_id,
        COALESCE(cm.source_concept_name, vc.concept_name)  AS source_concept_name
    FROM
        code_match cm
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept_synonym vcs
            ON cm.source_concept_id IS NULL
            AND cm.source_label = vcs.concept_synonym_name
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept vc
            ON vcs.concept_id = vc.concept_id
            AND vc.vocabulary_id = cm.source_vocabulary_id
            AND vc.concept_class_id = cm.source_concept_class_id
    WHERE
        cm.source_concept_id IS NULL
        AND NOT EXISTS (
            SELECT 1
            FROM code_match prior
            WHERE prior.source_code = cm.source_code
              AND prior.source_vocabulary_id = cm.source_vocabulary_id
              AND prior.source_concept_class_id = cm.source_concept_class_id
              AND prior.source_concept_id IS NOT NULL
        )
        AND NOT EXISTS (
            SELECT 1
            FROM name_match prior
            WHERE prior.source_code = cm.source_code
              AND prior.source_vocabulary_id = cm.source_vocabulary_id
              AND prior.source_concept_class_id = cm.source_concept_class_id
              AND prior.source_concept_id IS NOT NULL
        )
),
unmapped_fallback AS (
    SELECT
                src.itemid                     AS itemid,
                src.source_code                AS source_code,
                src.source_label               AS source_label,
                src.source_vocabulary_id       AS source_vocabulary_id,
                src.source_concept_class_id    AS source_concept_class_id,
        CAST(NULL AS STRING)           AS source_domain_id,
        CAST(NULL AS INT64)            AS source_concept_id,
        CAST(NULL AS STRING)           AS target_domain_id,
        CAST(NULL AS INT64)            AS target_concept_id
    FROM
        @etl_project.@etl_dataset.lk_proc_d_items_distinct src
    WHERE
        NOT EXISTS (
            SELECT 1
            FROM code_match cm
            WHERE cm.itemid = src.itemid
              AND cm.source_vocabulary_id = src.source_vocabulary_id
              AND cm.source_concept_class_id = src.source_concept_class_id
              AND cm.source_concept_id IS NOT NULL
        )
        AND NOT EXISTS (
            SELECT 1
            FROM name_match nm
            WHERE nm.itemid = src.itemid
              AND nm.source_vocabulary_id = src.source_vocabulary_id
              AND nm.source_concept_class_id = src.source_concept_class_id
              AND nm.source_concept_id IS NOT NULL
        )
        AND NOT EXISTS (
            SELECT 1
            FROM synonym_match sm
            WHERE sm.itemid = src.itemid
              AND sm.source_vocabulary_id = src.source_vocabulary_id
              AND sm.source_concept_class_id = src.source_concept_class_id
              AND sm.source_concept_id IS NOT NULL
        )
)
SELECT
    cm.itemid                           AS itemid,
    cm.source_code                      AS source_code,
    cm.source_label                     AS source_label,
    cm.source_vocabulary_id             AS source_vocabulary_id,
    cm.source_concept_class_id          AS source_concept_class_id,
    cm.source_domain_id                 AS source_domain_id,
    cm.source_concept_id                AS source_concept_id,
    vc2.domain_id                       AS target_domain_id,
    vc2.concept_id                      AS target_concept_id
FROM
    code_match cm
LEFT JOIN
    @etl_project.@etl_dataset.voc_concept_relationship vcr
        ON  cm.source_concept_id = vcr.concept_id_1
        AND vcr.relationship_id = 'Maps to'
LEFT JOIN
    @etl_project.@etl_dataset.voc_concept vc2
        ON vc2.concept_id = vcr.concept_id_2
        AND vc2.standard_concept = 'S'
        AND vc2.invalid_reason IS NULL
WHERE
    cm.source_concept_id IS NOT NULL
UNION ALL
SELECT
    nm.itemid                           AS itemid,
    nm.source_code                      AS source_code,
    nm.source_label                     AS source_label,
    nm.source_vocabulary_id             AS source_vocabulary_id,
    nm.source_concept_class_id          AS source_concept_class_id,
    nm.source_domain_id                 AS source_domain_id,
    nm.source_concept_id                AS source_concept_id,
    vc2.domain_id                       AS target_domain_id,
    vc2.concept_id                      AS target_concept_id
FROM
    name_match nm
LEFT JOIN
    @etl_project.@etl_dataset.voc_concept_relationship vcr
        ON  nm.source_concept_id = vcr.concept_id_1
        AND vcr.relationship_id = 'Maps to'
LEFT JOIN
    @etl_project.@etl_dataset.voc_concept vc2
        ON vc2.concept_id = vcr.concept_id_2
        AND vc2.standard_concept = 'S'
        AND vc2.invalid_reason IS NULL
UNION ALL
SELECT
    sm.itemid                           AS itemid,
    sm.source_code                      AS source_code,
    sm.source_label                     AS source_label,
    sm.source_vocabulary_id             AS source_vocabulary_id,
    sm.source_concept_class_id          AS source_concept_class_id,
    sm.source_domain_id                 AS source_domain_id,
    sm.source_concept_id                AS source_concept_id,
    vc2.domain_id                       AS target_domain_id,
    vc2.concept_id                      AS target_concept_id
FROM
    synonym_match sm
LEFT JOIN
    @etl_project.@etl_dataset.voc_concept_relationship vcr
        ON  sm.source_concept_id = vcr.concept_id_1
        AND vcr.relationship_id = 'Maps to'
LEFT JOIN
    @etl_project.@etl_dataset.voc_concept vc2
        ON vc2.concept_id = vcr.concept_id_2
        AND vc2.standard_concept = 'S'
        AND vc2.invalid_reason IS NULL
UNION ALL
SELECT
    uf.itemid                           AS itemid,
    uf.source_code                      AS source_code,
    uf.source_label                     AS source_label,
    uf.source_vocabulary_id             AS source_vocabulary_id,
    uf.source_concept_class_id          AS source_concept_class_id,
    uf.source_domain_id                 AS source_domain_id,
    uf.source_concept_id                AS source_concept_id,
    uf.target_domain_id                 AS target_domain_id,
    uf.target_concept_id                AS target_concept_id
FROM
    unmapped_fallback uf
;

-- -------------------------------------------------------------------
-- lk_procedure_mapped
-- -------------------------------------------------------------------

-- Rule 1, HCPCS

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_procedure_mapped AS
SELECT
    src.subject_id                          AS subject_id, -- to person
    src.hadm_id                             AS hadm_id, -- to visit
    src.start_datetime                      AS start_datetime,
    32821                                   AS type_concept_id, -- OMOP4976894 EHR billing record
    CAST(1 AS FLOAT64)                      AS quantity,
    CAST(NULL AS INT64)                     AS itemid,
    src.hcpcs_cd                            AS source_code,
    CAST(NULL AS STRING)                    AS source_label,
    lc.source_vocabulary_id                 AS source_vocabulary_id,
    lc.source_domain_id                     AS source_domain_id,
    COALESCE(lc.source_concept_id, 0)       AS source_concept_id,
    lc.target_domain_id                     AS target_domain_id,
    COALESCE(lc.target_concept_id, 0)       AS target_concept_id,
    --
    'proc.hcpcsevents'              AS unit_id,
    src.load_table_id               AS load_table_id,
    src.load_row_id                 AS load_row_id,
    src.trace_id                    AS trace_id
FROM
    @etl_project.@etl_dataset.lk_hcpcsevents_clean src
LEFT JOIN
    @etl_project.@etl_dataset.lk_hcpcs_concept lc
        ON src.hcpcs_cd = lc.source_code
;

-- Rule 2, ICD

INSERT INTO @etl_project.@etl_dataset.lk_procedure_mapped
SELECT
    src.subject_id                          AS subject_id, -- to person
    src.hadm_id                             AS hadm_id, -- to visit
    src.start_datetime                      AS start_datetime,
    32821                                   AS type_concept_id, -- OMOP4976894 EHR billing record
    1                                       AS quantity,
    CAST(NULL AS INT64)                     AS itemid,
    src.source_code                         AS source_code,
    CAST(NULL AS STRING)                    AS source_label,
    src.source_vocabulary_id                AS source_vocabulary_id,
    lc.source_domain_id                     AS source_domain_id,
    COALESCE(lc.source_concept_id, 0)       AS source_concept_id,
    lc.target_domain_id                     AS target_domain_id,
    COALESCE(lc.target_concept_id, 0)       AS target_concept_id,
    --
    'proc.procedures_icd'           AS unit_id,
    src.load_table_id               AS load_table_id,
    src.load_row_id                 AS load_row_id,
    src.trace_id                    AS trace_id
FROM
    @etl_project.@etl_dataset.lk_procedures_icd_clean src
LEFT JOIN
    @etl_project.@etl_dataset.lk_icd_proc_concept lc
        ON  src.source_code = lc.source_code
        AND src.source_vocabulary_id = lc.source_vocabulary_id
;

-- rule 3, "procedureevents" and itemid custom mapping
-- rule 4, "datetimeevents" and itemid custom mapping

INSERT INTO @etl_project.@etl_dataset.lk_procedure_mapped
SELECT
    src.subject_id                          AS subject_id, -- to person
    src.hadm_id                             AS hadm_id, -- to visit
    src.start_datetime                      AS start_datetime,
    32833                                   AS type_concept_id, -- OMOP4976906 EHR order
    src.quantity                            AS quantity,
    src.itemid                              AS itemid,
    src.source_code                         AS source_code,
    src.source_label                        AS source_label,
    lc.source_vocabulary_id                 AS source_vocabulary_id,
    lc.source_domain_id                     AS source_domain_id,
    COALESCE(lc.source_concept_id, 0)       AS source_concept_id,
    lc.target_domain_id                     AS target_domain_id,
    COALESCE(lc.target_concept_id, 0)       AS target_concept_id,
    --
    CONCAT('proc.', src.unit_id)    AS unit_id,
    src.load_table_id               AS load_table_id,
    src.load_row_id                 AS load_row_id,
    src.trace_id                    AS trace_id
FROM
    @etl_project.@etl_dataset.lk_proc_d_items_clean src
LEFT JOIN
    @etl_project.@etl_dataset.lk_itemid_concept lc
        ON src.itemid = lc.itemid
        AND src.source_vocabulary_id = lc.source_vocabulary_id
        AND src.source_concept_class_id = lc.source_concept_class_id
;

