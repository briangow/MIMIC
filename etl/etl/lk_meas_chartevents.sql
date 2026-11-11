-- -------------------------------------------------------------------
-- @2020, Odysseus Data Services, Inc. All rights reserved
-- MIMIC IV CDM Conversion
-- -------------------------------------------------------------------
-- -------------------------------------------------------------------
-- Populate lookup tables for measurement table
-- Rule 2
-- Labs from chartevents
-- 
-- Dependencies: run after 
--      st_core.sql,
--      st_hosp.sql,
--      st_icu.sql,
--      lk_meas_units
-- -------------------------------------------------------------------

-- -------------------------------------------------------------------
-- Known issues / Open points:
--
-- to add more measurements from chartevents (see table d_items and analysis for custom mapping)
-- 
-- custom mapping:
--      loaded custom vocab uses MIMIC4 + m4_chart_itemid for itemids and
--      MIMIC4 + m4_chart_value for mapped values/conditions
--          src_chartevents.value = measurement.value_source_value -> value_as_concept_id
-- 
-- -------------------------------------------------------------------

-- -------------------------------------------------------------------
-- Rule 2
-- chartevents
-- chartevents keeps all possible records about events during an ICU stay
-- it repeats labs, but in case of discrepancies labs is the final truth
-- both HR and RR obviously do not repeat labs
-- Saturation probably repeats labs. Compare to Lab with source_value = "Oxygen Saturation | 50817"
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_chartevents_clean AS
SELECT
    src.subject_id                  AS subject_id,
    src.hadm_id                     AS hadm_id,
    src.stay_id                     AS stay_id,
    src.itemid                      AS itemid,
    CAST(src.itemid AS STRING)      AS source_code,
    di.label                        AS source_label,
    src.charttime                   AS start_datetime,
    TRIM(src.value)                 AS value,
    IF(
        REGEXP_EXTRACT(TRIM(src.value), r'^[-]?[\d]+[.]?[\d]*[ ]*[a-z]+$') IS NOT NULL, -- 7.5 mm etc
        CAST(REGEXP_EXTRACT(src.value, r'[-]?[\d]+[.]?[\d]*') AS FLOAT64),
        src.valuenum
    )                               AS valuenum,
    IF(
        REGEXP_EXTRACT(TRIM(src.value), r'^[-]?[\d]+[.]?[\d]*[ ]*[a-z]+$') IS NOT NULL, -- 7.5 mm etc
        REGEXP_EXTRACT(src.value, r'[a-z]+'),
        src.valueuom
    )                               AS valueuom, -- unit of measurement
    --
    'chartevents'           AS unit_id,
    src.load_table_id       AS load_table_id,
    src.load_row_id         AS load_row_id,
    src.trace_id            AS trace_id
FROM
    @etl_project.@etl_dataset.src_chartevents src -- ce
INNER JOIN
    @etl_project.@etl_dataset.src_d_items di
        ON  src.itemid = di.itemid
WHERE
    di.label NOT LIKE '%Temperature'
    OR di.label LIKE '%Temperature' 
        AND IF(valueuom LIKE '%F%', (valuenum - 32) * 5 / 9, valuenum) BETWEEN 25 and 44
    
;

-- -------------------------------------------------------------------
-- tmp_chartevents_code_dist
-- it is a temporary table to collect distinct codes to be mapped
-- we are going to store source_code, source_label, and row_count in the concept lookup table,
-- to provide enough information for a mapping team for possible future mapping
--
-- loaded custom vocabulary -> MIMIC4 + m4_chart_itemid
-- loaded custom vocabulary -> MIMIC4 + m4_chart_value
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.tmp_chartevents_code_dist AS
-- source codes to be mapped
SELECT
    itemid                      AS itemid,
    source_code                 AS source_code,
    source_label                AS source_label,
    'MIMIC4'                    AS source_vocabulary_id,
    'm4_chart_itemid'           AS source_concept_class_id,
    COUNT(*)                    AS row_count
FROM
    @etl_project.@etl_dataset.lk_chartevents_clean
GROUP BY
    itemid,
    source_code,
    source_label
UNION ALL
-- values to be mapped
SELECT
    CAST(NULL AS INT64)                 AS itemid,
    value                               AS source_code,
    value                               AS source_label,
    'MIMIC4'                            AS source_vocabulary_id,
    'm4_chart_value'                    AS source_concept_class_id, -- both obs values and conditions
    COUNT(*)                            AS row_count
FROM
    @etl_project.@etl_dataset.lk_chartevents_clean
GROUP BY
    source_code,
    source_label
;

-- -------------------------------------------------------------------
-- lk_chartevents_concept
-- collect the mapping and keep source_code, source_label, and row_count
-- for possible future mapping. Follow staged code/name/synonym matching
-- per ETL guidance, using MIMIC4 plus concept_class_id.
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_chartevents_concept AS
WITH source_candidates AS (
    SELECT
        src.itemid                  AS itemid,
        src.source_code             AS source_code,
        src.source_label            AS source_label,
        src.source_vocabulary_id    AS source_vocabulary_id,
        src.source_concept_class_id AS source_concept_class_id,
        src.row_count               AS row_count,
        1                           AS class_priority
    FROM
        @etl_project.@etl_dataset.tmp_chartevents_code_dist src

    UNION ALL

    SELECT
        src.itemid                  AS itemid,
        src.source_code             AS source_code,
        src.source_label            AS source_label,
        src.source_vocabulary_id    AS source_vocabulary_id,
        'm4_ditem_label'            AS source_concept_class_id,
        src.row_count               AS row_count,
        2                           AS class_priority
    FROM
        @etl_project.@etl_dataset.tmp_chartevents_code_dist src
    WHERE
        src.itemid IS NOT NULL
        AND src.source_vocabulary_id = 'MIMIC4'
        AND src.source_concept_class_id = 'm4_chart_itemid'
),
code_match AS (
    SELECT
        src.itemid                  AS itemid,
        src.source_code             AS source_code,
        src.source_label            AS source_label,
        src.source_vocabulary_id    AS source_vocabulary_id,
        src.source_concept_class_id AS source_concept_class_id,
        vc.domain_id                AS source_domain_id,
        vc.concept_id               AS source_concept_id,
        vc.concept_name             AS source_concept_name,
        src.row_count               AS row_count,
        src.class_priority          AS class_priority
    FROM
        source_candidates src
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept vc
            ON  vc.concept_code = src.source_code
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
        COALESCE(cm.source_concept_name, vc.concept_name)  AS source_concept_name,
        cm.row_count                AS row_count,
        cm.class_priority           AS class_priority
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
        COALESCE(cm.source_concept_name, vc.concept_name)  AS source_concept_name,
        cm.row_count                AS row_count,
        cm.class_priority           AS class_priority
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
        src.itemid                   AS itemid,
        src.source_code              AS source_code,
        src.source_label             AS source_label,
        src.source_vocabulary_id     AS source_vocabulary_id,
        src.source_concept_class_id  AS source_concept_class_id,
        CAST(NULL AS STRING)         AS source_domain_id,
        CAST(NULL AS INT64)          AS source_concept_id,
        CAST(NULL AS STRING)         AS source_concept_name,
        CAST(NULL AS STRING)         AS target_domain_id,
        CAST(NULL AS INT64)          AS target_concept_id,
        src.row_count                AS row_count,
        IF(src.source_concept_class_id = 'm4_chart_itemid', 1, 2) AS class_priority
    FROM
        source_candidates src
    WHERE NOT EXISTS (
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
      AND NOT EXISTS (
        SELECT 1
        FROM synonym_match sm
        WHERE sm.source_code = src.source_code
          AND sm.source_vocabulary_id = src.source_vocabulary_id
          AND sm.source_concept_id IS NOT NULL
    )
),
resolved_matches AS (
    SELECT
        itemid,
        source_code,
        source_label,
        source_vocabulary_id,
        source_concept_class_id,
        source_domain_id,
        source_concept_id,
        source_concept_name,
        row_count,
        class_priority
    FROM code_match
    WHERE source_concept_id IS NOT NULL

    UNION ALL

    SELECT
        itemid,
        source_code,
        source_label,
        source_vocabulary_id,
        source_concept_class_id,
        source_domain_id,
        source_concept_id,
        source_concept_name,
        row_count,
        class_priority
    FROM name_match
    WHERE source_concept_id IS NOT NULL

    UNION ALL

    SELECT
        itemid,
        source_code,
        source_label,
        source_vocabulary_id,
        source_concept_class_id,
        source_domain_id,
        source_concept_id,
        source_concept_name,
        row_count,
        class_priority
    FROM synonym_match
    WHERE source_concept_id IS NOT NULL
),
best_resolved_match AS (
    SELECT
        itemid,
        source_code,
        source_label,
        source_vocabulary_id,
        source_concept_class_id,
        source_domain_id,
        source_concept_id,
        source_concept_name,
        row_count
    FROM resolved_matches
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY source_code, source_vocabulary_id
        ORDER BY class_priority, source_concept_id
    ) = 1
)
SELECT
    brm.itemid                  AS itemid,
    brm.source_code             AS source_code,
    brm.source_label            AS source_label,
    brm.source_vocabulary_id    AS source_vocabulary_id,
    brm.source_concept_class_id AS source_concept_class_id,
    -- source concept
    brm.source_domain_id        AS source_domain_id,
    brm.source_concept_id       AS source_concept_id,
    -- target concept
    vc2.domain_id               AS target_domain_id,
    vc2.concept_id              AS target_concept_id,
    brm.row_count               AS row_count
FROM
    best_resolved_match brm
LEFT JOIN
    @etl_project.@etl_dataset.voc_concept_relationship vcr
        ON  brm.source_concept_id = vcr.concept_id_1
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
    uf.target_domain_id         AS target_domain_id,
    uf.target_concept_id        AS target_concept_id,
    uf.row_count                AS row_count
FROM
    unmapped_fallback uf
;

DROP TABLE IF EXISTS @etl_project.@etl_dataset.tmp_chartevents_code_dist;

-- -------------------------------------------------------------------
-- lk_chartevents_mapped
-- src_chartevents to measurement and measurement value
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_chartevents_mapped AS
WITH lk_chartevents_item_concept AS (
    SELECT
        itemid,
        source_code,
        source_label,
        source_vocabulary_id,
        source_concept_class_id,
        source_domain_id,
        source_concept_id,
        target_domain_id,
        target_concept_id,
        row_count
    FROM
        @etl_project.@etl_dataset.lk_chartevents_concept
    WHERE
        itemid IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY itemid, source_code, source_vocabulary_id
        ORDER BY
            CASE source_concept_class_id
                WHEN 'm4_chart_itemid' THEN 1
                WHEN 'm4_ditem_label' THEN 2
                ELSE 3
            END,
            CASE WHEN source_concept_id IS NOT NULL THEN 0 ELSE 1 END,
            source_concept_id,
            target_concept_id
    ) = 1
)
SELECT
    `@etl_project.@etl_dataset`.obf_id_str(src.trace_id, 64)  AS measurement_id,
    src.subject_id                                            AS subject_id,
    src.hadm_id                                               AS hadm_id,
    src.stay_id                                               AS stay_id,
    src.start_datetime                                        AS start_datetime,
    32817                                                     AS type_concept_id,  -- OMOP4976890 EHR
    src.itemid                                                AS itemid,
    src.source_code                                           AS source_code,
    src.source_label                                          AS source_label,
    c_main.source_vocabulary_id                               AS source_vocabulary_id,
    c_main.source_concept_class_id                            AS source_concept_class_id,
    c_main.source_domain_id                                   AS source_domain_id,
    c_main.source_concept_id                                  AS source_concept_id,
    c_main.target_domain_id                                   AS target_domain_id,
    c_main.target_concept_id                                  AS target_concept_id,
    src.value                                                 AS value_source_value,
    IF(
        IF(src.valuenum IS NULL, src.value, NULL) IS NOT NULL,
        COALESCE(c_value.target_concept_id, 0), 
        NULL
    )                                                         AS value_as_concept_id,
    src.valuenum                                              AS value_as_number,
    src.valueuom                                              AS unit_source_value, -- unit of measurement
    IF(src.valueuom IS NOT NULL, 
        COALESCE(uc.target_concept_id, 0), NULL)              AS unit_concept_id,
    --
    CONCAT('meas.', src.unit_id)                              AS unit_id,
    src.load_table_id                                         AS load_table_id,
    src.load_row_id                                           AS load_row_id,
    src.trace_id                                              AS trace_id
FROM
    @etl_project.@etl_dataset.lk_chartevents_clean src -- ce
LEFT JOIN
    lk_chartevents_item_concept c_main -- main
        ON c_main.source_code = src.source_code 
        AND c_main.source_vocabulary_id = 'MIMIC4'
LEFT JOIN
    @etl_project.@etl_dataset.lk_chartevents_concept c_value -- values for main
        ON c_value.source_code = src.value
        AND c_value.source_vocabulary_id = 'MIMIC4'
        AND c_value.source_concept_class_id = 'm4_chart_value'
        AND c_value.target_domain_id = 'Meas Value'
LEFT JOIN 
    @etl_project.@etl_dataset.lk_meas_unit_concept uc
        ON uc.source_code = src.valueuom
;


-- -------------------------------------------------------------------
-- lk_chartevents_condition_mapped
-- src_chartevents to condition
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_chartevents_condition_mapped AS
SELECT
    src.subject_id                              AS subject_id,
    src.hadm_id                                 AS hadm_id,
    src.stay_id                                 AS stay_id,
    src.start_datetime                          AS start_datetime,
    32817                                       AS type_concept_id,  -- OMOP4976890 EHR
    src.value                                   AS source_code,
    c_main.source_vocabulary_id                 AS source_vocabulary_id,
    c_main.source_concept_class_id              AS source_concept_class_id,
    c_main.source_concept_id                    AS source_concept_id,
    c_main.target_domain_id                     AS target_domain_id,
    c_main.target_concept_id                    AS target_concept_id,
    --
    CONCAT('cond.', src.unit_id)                AS unit_id,
    src.load_table_id       AS load_table_id,
    src.load_row_id         AS load_row_id,
    src.trace_id            AS trace_id
FROM
    @etl_project.@etl_dataset.lk_chartevents_clean src -- ce
INNER JOIN
    @etl_project.@etl_dataset.lk_chartevents_concept c_main -- condition domain from values, mapped
        ON c_main.source_code = src.value
        AND c_main.source_vocabulary_id = 'MIMIC4'
        AND c_main.source_concept_class_id = 'm4_chart_value'
        AND c_main.target_domain_id = 'Condition'
;

