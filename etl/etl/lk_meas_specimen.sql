-- -------------------------------------------------------------------
-- @2020, Odysseus Data Services, Inc. All rights reserved
-- MIMIC IV CDM Conversion
-- -------------------------------------------------------------------
-- -------------------------------------------------------------------
-- Populate lookup tables for specimen and measurement tables
-- 
-- Dependencies: run after 
--      st_hosp
--      
-- -------------------------------------------------------------------

-- -------------------------------------------------------------------
-- Known issues / Open points:
--
--
-- -------------------------------------------------------------------

-- -------------------------------------------------------------------
-- lk_micro_cross_ref
-- group microevent_id = trace_id for each type of records
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_micro_cross_ref AS
SELECT
    trace_id                                    AS trace_id_ab, -- for antibiotics
    FIRST_VALUE(src.trace_id) OVER (
        PARTITION BY
            src.subject_id,
            src.hadm_id,
            COALESCE(src.charttime, src.chartdate),
            src.spec_itemid,
            src.test_itemid,
            src.org_itemid
        ORDER BY src.trace_id
    )                                           AS trace_id_org, -- for test-organism pairs
    FIRST_VALUE(src.trace_id) OVER (
        PARTITION BY
            src.subject_id,
            src.hadm_id,
            COALESCE(src.charttime, src.chartdate),
            src.spec_itemid
        ORDER BY src.trace_id
    )                                           AS trace_id_spec, -- for specimen
    subject_id                                  AS subject_id,    -- to pick additional hadm_id from admissions
    hadm_id                                     AS hadm_id,
    COALESCE(src.charttime, src.chartdate)      AS start_datetime -- just to do coalesce once
FROM
    @etl_project.@etl_dataset.src_microbiologyevents src -- mbe
;

-- -------------------------------------------------------------------
-- lk_micro_hadm_id
-- pick additional hadm_id by event start_datetime
-- row_num is added to select the earliest if more than one hadm_ids are found
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_micro_hadm_id AS
SELECT
    src.trace_id_ab                     AS event_trace_id,
    adm.hadm_id                         AS hadm_id,
    ROW_NUMBER() OVER (
        PARTITION BY src.trace_id_ab
        ORDER BY adm.start_datetime
    )                                   AS row_num
FROM  
    @etl_project.@etl_dataset.lk_micro_cross_ref src
INNER JOIN 
    @etl_project.@etl_dataset.lk_admissions_clean adm
        ON adm.subject_id = src.subject_id
        AND src.start_datetime BETWEEN adm.start_datetime AND adm.end_datetime
WHERE
    src.hadm_id IS NULL
;

-- -------------------------------------------------------------------
-- Part 2 of microbiology: test taken and organisms grown in the material of the test
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_meas_organism_clean AS
SELECT DISTINCT
    src.subject_id                              AS subject_id,
    src.hadm_id                                 AS hadm_id,
    cr.start_datetime                           AS start_datetime,
    src.spec_itemid                             AS spec_itemid, -- d_micro.itemid, type of specimen taken
    src.test_itemid                             AS test_itemid, -- d_micro.itemid, test taken from the specimen
    src.org_itemid                              AS org_itemid, -- d_micro.itemid, organism which has grown
    cr.trace_id_spec                            AS trace_id_spec, -- to link org and spec in fact_relationship
    -- 
    'micro.organism'                AS unit_id,
    src.load_table_id               AS load_table_id,
    0                               AS load_row_id,
    cr.trace_id_org                 AS trace_id         -- trace_id for test-organism
FROM
    @etl_project.@etl_dataset.src_microbiologyevents src -- mbe
INNER JOIN
    @etl_project.@etl_dataset.lk_micro_cross_ref cr
        ON src.trace_id = cr.trace_id_org
;

-- -------------------------------------------------------------------
-- Part 1 of microbiology: specimen
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_specimen_clean AS
SELECT DISTINCT
    src.subject_id                              AS subject_id,
    src.hadm_id                                 AS hadm_id,
    src.start_datetime                          AS start_datetime,
    src.spec_itemid                             AS spec_itemid, -- d_micro.itemid, type of specimen taken
    -- 
    'micro.specimen'                AS unit_id,
    src.load_table_id               AS load_table_id,
    0                               AS load_row_id,
    cr.trace_id_spec                AS trace_id         -- trace_id for specimen
FROM
    @etl_project.@etl_dataset.lk_meas_organism_clean src -- mbe
INNER JOIN
    @etl_project.@etl_dataset.lk_micro_cross_ref cr
        ON src.trace_id = cr.trace_id_spec
;

-- -------------------------------------------------------------------
-- Part 3 of microbiology: antibiotics tested on organisms
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_meas_ab_clean AS
SELECT
    src.subject_id                              AS subject_id,
    src.hadm_id                                 AS hadm_id,
    cr.start_datetime                           AS start_datetime,
    src.ab_itemid                               AS ab_itemid, -- antibiotic tested
    src.dilution_comparison                     AS dilution_comparison, -- operator sign
    src.dilution_value                          AS dilution_value, -- numeric dilution value
    src.interpretation                          AS interpretation, -- degree of resistance
    cr.trace_id_org                             AS trace_id_org, -- to link org to ab in fact_relationship
    -- 
    'micro.antibiotics'             AS unit_id,
    src.load_table_id               AS load_table_id,
    0                               AS load_row_id,
    src.trace_id                    AS trace_id         -- trace_id for antibiotics, no groupping is needed
FROM
    @etl_project.@etl_dataset.src_microbiologyevents src
INNER JOIN
    @etl_project.@etl_dataset.lk_micro_cross_ref cr
        ON src.trace_id = cr.trace_id_ab
WHERE
    src.ab_itemid IS NOT NULL
;

-- -------------------------------------------------------------------
-- lk_d_micro_clean
-- add resistance source codes to all microbiology source codes
-- source_label for organism: test name plus specimen name
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_d_micro_clean AS
SELECT
    dm.itemid                                       AS itemid,
    CAST(dm.itemid AS STRING)                       AS source_code,
    CASE LOWER(dm.category)
        WHEN 'specimen' THEN CONCAT('microbiologyevents.spec_itemid||', CAST(dm.itemid AS STRING))
        ELSE CAST(NULL AS STRING)
    END                                             AS alt_source_code,
    dm.label                                        AS source_label, -- for organism_mapped: test name plus specimen name
    'MIMIC4'                                        AS source_vocabulary_id,
    CASE LOWER(dm.category)
        WHEN 'specimen' THEN 'm4_micro_spec'
        WHEN 'microtest' THEN 'm4_micro_test'
        WHEN 'organism' THEN 'm4_micro_org'
        WHEN 'antibiotic' THEN 'm4_micro_ab'
    END                                             AS source_concept_class_id,
FROM
    @etl_project.@etl_dataset.src_d_micro dm
UNION ALL
SELECT DISTINCT
    CAST(NULL AS INT64)                             AS itemid,
    src.interpretation                              AS source_code,
    CAST(NULL AS STRING)                            AS alt_source_code,
    src.interpretation                              AS source_label,
    'MIMIC4'                                        AS source_vocabulary_id,
    'm4_micro_interp'                               AS source_concept_class_id
FROM
    @etl_project.@etl_dataset.lk_meas_ab_clean src
WHERE
    src.interpretation IS NOT NULL
;

-- -------------------------------------------------------------------
-- lk_d_micro_concept
-- staged microbiology concept matching using MIMIC4 + concept_class_id
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_d_micro_concept AS
WITH code_match AS (
    SELECT
        dm.itemid                   AS itemid,
        dm.source_code              AS source_code,
        dm.alt_source_code          AS alt_source_code,
        dm.source_label             AS source_label,
        dm.source_vocabulary_id     AS source_vocabulary_id,
        dm.source_concept_class_id  AS source_concept_class_id,
        vc.domain_id                AS source_domain_id,
        vc.concept_id               AS source_concept_id,
        vc.concept_name             AS source_concept_name
    FROM
        @etl_project.@etl_dataset.lk_d_micro_clean dm
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept vc
            ON (dm.source_code = vc.concept_code OR dm.alt_source_code = vc.concept_code)
            AND vc.vocabulary_id = dm.source_vocabulary_id
            AND vc.concept_class_id = dm.source_concept_class_id
),
name_match AS (
    SELECT
        cm.itemid                   AS itemid,
        cm.source_code              AS source_code,
        cm.alt_source_code          AS alt_source_code,
        cm.source_label             AS source_label,
        cm.source_vocabulary_id     AS source_vocabulary_id,
        cm.source_concept_class_id  AS source_concept_class_id,
        COALESCE(cm.source_domain_id, vc.domain_id)            AS source_domain_id,
        COALESCE(cm.source_concept_id, vc.concept_id)          AS source_concept_id,
        COALESCE(cm.source_concept_name, vc.concept_name)      AS source_concept_name
    FROM
        code_match cm
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept vc
            ON cm.itemid IS NOT NULL
            AND cm.source_concept_id IS NULL
            AND cm.source_label = vc.concept_name
            AND vc.vocabulary_id = cm.source_vocabulary_id
            AND vc.concept_class_id = cm.source_concept_class_id
    WHERE
        cm.source_concept_id IS NULL
        AND
        vc.concept_id IS NOT NULL
        AND NOT EXISTS (
            SELECT 1
            FROM code_match prior
            WHERE prior.source_code = cm.source_code
              AND prior.source_vocabulary_id = cm.source_vocabulary_id
              AND prior.source_concept_class_id = cm.source_concept_class_id
              AND prior.itemid IS NOT DISTINCT FROM cm.itemid
        )
),
synonym_match AS (
    SELECT
        cm.itemid                   AS itemid,
        cm.source_code              AS source_code,
        cm.alt_source_code          AS alt_source_code,
        cm.source_label             AS source_label,
        cm.source_vocabulary_id     AS source_vocabulary_id,
        cm.source_concept_class_id  AS source_concept_class_id,
        COALESCE(cm.source_domain_id, vc.domain_id)            AS source_domain_id,
        COALESCE(cm.source_concept_id, vc.concept_id)          AS source_concept_id,
        COALESCE(cm.source_concept_name, vc.concept_name)      AS source_concept_name
    FROM
        code_match cm
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept_synonym vcs
            ON cm.itemid IS NOT NULL
            AND cm.source_concept_id IS NULL
            AND cm.source_label = vcs.concept_synonym_name
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept vc
            ON vcs.concept_id = vc.concept_id
            AND vc.vocabulary_id = cm.source_vocabulary_id
            AND vc.concept_class_id = cm.source_concept_class_id
    WHERE
        cm.source_concept_id IS NULL
        AND
        vc.concept_id IS NOT NULL
        AND NOT EXISTS (
            SELECT 1
            FROM code_match prior
            WHERE prior.source_code = cm.source_code
              AND prior.source_vocabulary_id = cm.source_vocabulary_id
              AND prior.source_concept_class_id = cm.source_concept_class_id
              AND prior.itemid IS NOT DISTINCT FROM cm.itemid
        )
        AND NOT EXISTS (
            SELECT 1
            FROM name_match prior
            WHERE prior.source_code = cm.source_code
              AND prior.source_vocabulary_id = cm.source_vocabulary_id
              AND prior.source_concept_class_id = cm.source_concept_class_id
              AND prior.itemid IS NOT DISTINCT FROM cm.itemid
        )
),
unmapped_fallback AS (
        -- Preserve microbiology source rows even when vocabulary resolution fails.
        -- This keeps downstream specimen / organism events from disappearing solely
        -- because a source concept or target mapping is unavailable.
        SELECT
                dm.itemid                   AS itemid,
                dm.source_code              AS source_code,
                dm.source_label             AS source_label,
                dm.source_vocabulary_id     AS source_vocabulary_id,
                dm.source_concept_class_id  AS source_concept_class_id,
                CAST(NULL AS STRING)        AS source_domain_id,
                CAST(NULL AS INT64)         AS source_concept_id,
                CAST(NULL AS STRING)        AS source_concept_name,
                CAST(NULL AS STRING)        AS target_vocabulary_id,
                CAST(NULL AS STRING)        AS target_domain_id,
                CAST(NULL AS INT64)         AS target_concept_id,
                CAST(NULL AS STRING)        AS target_concept_name,
                CAST(NULL AS STRING)        AS target_standard_concept
        FROM
                @etl_project.@etl_dataset.lk_d_micro_clean dm
        WHERE NOT EXISTS (
                SELECT 1
                FROM code_match prior
                WHERE prior.source_code = dm.source_code
                    AND prior.source_vocabulary_id = dm.source_vocabulary_id
                    AND prior.source_concept_class_id = dm.source_concept_class_id
                    AND prior.itemid IS NOT DISTINCT FROM dm.itemid
        )
            AND NOT EXISTS (
                SELECT 1
                FROM name_match prior
                WHERE prior.source_code = dm.source_code
                    AND prior.source_vocabulary_id = dm.source_vocabulary_id
                    AND prior.source_concept_class_id = dm.source_concept_class_id
                    AND prior.itemid IS NOT DISTINCT FROM dm.itemid
        )
            AND NOT EXISTS (
                SELECT 1
                FROM synonym_match prior
                WHERE prior.source_code = dm.source_code
                    AND prior.source_vocabulary_id = dm.source_vocabulary_id
                    AND prior.source_concept_class_id = dm.source_concept_class_id
                    AND prior.itemid IS NOT DISTINCT FROM dm.itemid
        )
)
SELECT
    cm.itemid                   AS itemid,
    cm.source_code              AS source_code, -- itemid
    cm.source_label             AS source_label, -- symbolic information in case more mapping is required
    cm.source_vocabulary_id     AS source_vocabulary_id,
    cm.source_concept_class_id  AS source_concept_class_id,
    -- source_concept
    cm.source_domain_id         AS source_domain_id,
    cm.source_concept_id        AS source_concept_id,
    cm.source_concept_name      AS source_concept_name,
    -- target concept
    vc2.vocabulary_id           AS target_vocabulary_id,
    vc2.domain_id               AS target_domain_id,
    vc2.concept_id              AS target_concept_id,
    vc2.concept_name            AS target_concept_name,
    vc2.standard_concept        AS target_standard_concept
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
    nm.itemid                   AS itemid,
    nm.source_code              AS source_code, -- itemid
    nm.source_label             AS source_label, -- symbolic information in case more mapping is required
    nm.source_vocabulary_id     AS source_vocabulary_id,
    nm.source_concept_class_id  AS source_concept_class_id,
    -- source_concept
    nm.source_domain_id         AS source_domain_id,
    nm.source_concept_id        AS source_concept_id,
    nm.source_concept_name      AS source_concept_name,
    -- target concept
    vc2.vocabulary_id           AS target_vocabulary_id,
    vc2.domain_id               AS target_domain_id,
    vc2.concept_id              AS target_concept_id,
    vc2.concept_name            AS target_concept_name,
    vc2.standard_concept        AS target_standard_concept
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
    sm.itemid                   AS itemid,
    sm.source_code              AS source_code, -- itemid
    sm.source_label             AS source_label, -- symbolic information in case more mapping is required
    sm.source_vocabulary_id     AS source_vocabulary_id,
    sm.source_concept_class_id  AS source_concept_class_id,
    -- source_concept
    sm.source_domain_id         AS source_domain_id,
    sm.source_concept_id        AS source_concept_id,
    sm.source_concept_name      AS source_concept_name,
    -- target concept
    vc2.vocabulary_id           AS target_vocabulary_id,
    vc2.domain_id               AS target_domain_id,
    vc2.concept_id              AS target_concept_id,
    vc2.concept_name            AS target_concept_name,
    vc2.standard_concept        AS target_standard_concept
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
    uf.itemid                   AS itemid,
    uf.source_code              AS source_code,
    uf.source_label             AS source_label,
    uf.source_vocabulary_id     AS source_vocabulary_id,
    uf.source_concept_class_id  AS source_concept_class_id,
    uf.source_domain_id         AS source_domain_id,
    uf.source_concept_id        AS source_concept_id,
    uf.source_concept_name      AS source_concept_name,
    uf.target_vocabulary_id     AS target_vocabulary_id,
    uf.target_domain_id         AS target_domain_id,
    uf.target_concept_id        AS target_concept_id,
    uf.target_concept_name      AS target_concept_name,
    uf.target_standard_concept  AS target_standard_concept
FROM
    unmapped_fallback uf
;

-- -------------------------------------------------------------------
-- lk_specimen_mapped
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_specimen_mapped AS
SELECT
    `@etl_project.@etl_dataset`.obf_id_str(src.trace_id, 32)    AS specimen_id,
    src.subject_id                                              AS subject_id,
    COALESCE(src.hadm_id, hadm.hadm_id)                         AS hadm_id,
    CAST(src.start_datetime AS DATE)                            AS date_id,
    32856                                                       AS type_concept_id, -- Lab
    src.start_datetime                                          AS start_datetime,
    src.spec_itemid                                             AS spec_itemid,
    mc.source_code                                              AS source_code,
    mc.source_vocabulary_id                                     AS source_vocabulary_id,
    mc.source_concept_id                                        AS source_concept_id,
    COALESCE(mc.target_domain_id, 'Specimen')                   AS target_domain_id,
    mc.target_concept_id                                        AS target_concept_id,
    -- 
    src.unit_id                                                 AS unit_id,
    src.load_table_id                                           AS load_table_id,
    src.load_row_id                                             AS load_row_id,
    src.trace_id                                                AS trace_id
FROM
    @etl_project.@etl_dataset.lk_specimen_clean src
INNER JOIN
    @etl_project.@etl_dataset.lk_d_micro_concept mc
        ON src.spec_itemid = mc.itemid
LEFT JOIN
    @etl_project.@etl_dataset.lk_micro_hadm_id hadm
        ON hadm.event_trace_id = src.trace_id
        AND hadm.row_num = 1
;

-- -------------------------------------------------------------------
-- lk_meas_organism_mapped
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_meas_organism_mapped AS
SELECT
    `@etl_project.@etl_dataset`.obf_id_str(src.trace_id, 64)    AS measurement_id,
    src.subject_id                                              AS subject_id,
    COALESCE(src.hadm_id, hadm.hadm_id)                         AS hadm_id,
    CAST(src.start_datetime AS DATE)                            AS date_id,
    32856                                                       AS type_concept_id, -- Lab
    src.start_datetime                                          AS start_datetime,
    src.test_itemid                                             AS test_itemid,
    src.spec_itemid                                             AS spec_itemid,
    src.org_itemid                                              AS org_itemid,
    CONCAT(tc.source_code, '|', sc.source_code)                 AS source_code, -- test itemid plus specimen itemid
    tc.source_vocabulary_id                                     AS source_vocabulary_id,
    tc.source_concept_id                                        AS source_concept_id,
    COALESCE(tc.target_domain_id, 'Measurement')                AS target_domain_id,
    tc.target_concept_id                                        AS target_concept_id,
    oc.source_code                                              AS value_source_value,
    oc.target_concept_id                                        AS value_as_concept_id,
    -- fields to link to specimen and test-organism
    src.trace_id_spec                                           AS trace_id_spec,
    --
    src.unit_id                                                 AS unit_id,
    src.load_table_id                                           AS load_table_id,
    src.load_row_id                                             AS load_row_id,
    src.trace_id                                                AS trace_id
FROM
    @etl_project.@etl_dataset.lk_meas_organism_clean src
INNER JOIN
    @etl_project.@etl_dataset.lk_d_micro_concept tc
        ON src.test_itemid = tc.itemid
INNER JOIN
    @etl_project.@etl_dataset.lk_d_micro_concept sc
        ON src.spec_itemid = sc.itemid
LEFT JOIN
    @etl_project.@etl_dataset.lk_d_micro_concept oc
        ON src.org_itemid = oc.itemid
LEFT JOIN
    @etl_project.@etl_dataset.lk_micro_hadm_id hadm
        ON hadm.event_trace_id = src.trace_id
        AND hadm.row_num = 1
;

-- -------------------------------------------------------------------
-- lk_meas_ab_mapped
--
--      (gcpt) brand new vocab -> mimiciv_micro_resistance
--          mbe.interpretation -> source_code -> 4 rows for resistance degrees.
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_meas_ab_mapped AS
SELECT
    `@etl_project.@etl_dataset`.obf_id_str(src.trace_id, 64)    AS measurement_id,
    src.subject_id                                              AS subject_id,
    COALESCE(src.hadm_id, hadm.hadm_id)                         AS hadm_id,
    CAST(src.start_datetime AS DATE)                            AS date_id,
    32856                                                       AS type_concept_id, -- Lab
    src.start_datetime                                          AS start_datetime,
    src.ab_itemid                                               AS ab_itemid,
    ac.source_code                                              AS source_code,
    COALESCE(ac.target_concept_id, 0)                           AS target_concept_id,
    COALESCE(ac.source_concept_id, 0)                           AS source_concept_id,
    rc.target_concept_id                                        AS value_as_concept_id,
    src.interpretation                                          AS value_source_value,
    src.dilution_value                                          AS value_as_number,
    src.dilution_comparison                                     AS operator_source_value,
    opc.target_concept_id                                       AS operator_concept_id,
    COALESCE(ac.target_domain_id, 'Measurement')                AS target_domain_id,
    -- fields to link test-organism and antibiotics
    src.trace_id_org                                            AS trace_id_org,
    -- 
    src.unit_id                                                 AS unit_id,
    src.load_table_id                                           AS load_table_id,
    src.load_row_id                                             AS load_row_id,
    src.trace_id                                                AS trace_id
FROM
    @etl_project.@etl_dataset.lk_meas_ab_clean src
INNER JOIN
    @etl_project.@etl_dataset.lk_d_micro_concept ac
        ON src.ab_itemid = ac.itemid
LEFT JOIN
    @etl_project.@etl_dataset.lk_d_micro_concept rc
        ON src.interpretation = rc.source_code
        AND rc.source_vocabulary_id = 'MIMIC4'
        AND rc.source_concept_class_id = 'm4_micro_interp'
LEFT JOIN
    @etl_project.@etl_dataset.lk_meas_operator_concept opc -- see lk_meas_labevents.sql
        ON src.dilution_comparison = opc.source_code
LEFT JOIN
    @etl_project.@etl_dataset.lk_micro_hadm_id hadm
        ON hadm.event_trace_id = src.trace_id
        AND hadm.row_num = 1
;
