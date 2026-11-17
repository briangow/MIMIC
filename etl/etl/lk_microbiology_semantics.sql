-- -------------------------------------------------------------------
-- @2026, Odysseus Data Services, Inc. All rights reserved
-- MIMIC IV CDM Conversion
-- -------------------------------------------------------------------
-- -------------------------------------------------------------------
-- Populate microbiology semantic lookup tables for SOP-aligned parallel build
--
-- Dependencies: run after
--      lk_meas_specimen.sql
-- -------------------------------------------------------------------

-- -------------------------------------------------------------------
-- Known issues / Open points:
--
-- Uses placeholder custom concept ids for microbiology episode semantics
-- until approved vocabulary concepts are available.
-- -------------------------------------------------------------------

-- Placeholder custom concepts for local implementation.
-- Replace with approved concepts when available.
CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_microbiology_concepts AS
SELECT 2000005001 AS microbiology_specimen_episode_concept_id,
       2000005002 AS microbiology_analysis_episode_concept_id,
       2000005003 AS organism_identification_observation_concept_id,
       2000005004 AS antimicrobial_susceptibility_observation_concept_id,
       32581      AS episode_type_concept_id
;

-- -------------------------------------------------------------------
-- Parent microbiology specimen episode
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_microbiology_episode_specimen AS
SELECT
    `@etl_project.@etl_dataset`.obf_id_str(CONCAT('micro-episode-spec|', src.trace_id), 64) AS episode_id,
    src.specimen_id                                              AS specimen_id,
    src.subject_id                                               AS subject_id,
    src.hadm_id                                                  AS hadm_id,
    src.start_datetime                                           AS start_datetime,
    CAST(src.start_datetime AS DATE)                             AS date_id,
    cfg.microbiology_specimen_episode_concept_id                 AS episode_concept_id,
    CAST(NULL AS INT64)                                          AS episode_parent_id,
    1                                                            AS episode_number,
    36                                                           AS episode_object_concept_id,
    cfg.episode_type_concept_id                                  AS episode_type_concept_id,
    src.source_code                                              AS episode_source_value,
    src.source_concept_id                                        AS episode_source_concept_id,
    src.unit_id                                                  AS unit_id,
    src.load_table_id                                            AS load_table_id,
    src.load_row_id                                              AS load_row_id,
    src.trace_id                                                 AS trace_id
FROM
    @etl_project.@etl_dataset.lk_specimen_mapped src
CROSS JOIN
    @etl_project.@etl_dataset.lk_microbiology_concepts cfg
;

-- -------------------------------------------------------------------
-- Child microbiology analysis episode
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_microbiology_episode_analysis AS
SELECT DISTINCT
    `@etl_project.@etl_dataset`.obf_id_str(CONCAT('micro-episode-analysis|', org.trace_id), 64) AS episode_id,
    spec.episode_id                                               AS episode_parent_id,
    spec.specimen_id                                              AS specimen_id,
    org.measurement_id                                            AS organism_measurement_id,
    org.subject_id                                                AS subject_id,
    org.hadm_id                                                   AS hadm_id,
    org.start_datetime                                            AS start_datetime,
    CAST(org.start_datetime AS DATE)                              AS date_id,
    cfg.microbiology_analysis_episode_concept_id                  AS episode_concept_id,
    1                                                             AS episode_number,
    21                                                            AS episode_object_concept_id,
    cfg.episode_type_concept_id                                   AS episode_type_concept_id,
    org.source_code                                               AS episode_source_value,
    org.source_concept_id                                         AS episode_source_concept_id,
    org.trace_id_spec                                             AS trace_id_spec,
    org.unit_id                                                   AS unit_id,
    org.load_table_id                                             AS load_table_id,
    org.load_row_id                                               AS load_row_id,
    org.trace_id                                                  AS trace_id
FROM
    @etl_project.@etl_dataset.lk_meas_organism_mapped org
INNER JOIN
    @etl_project.@etl_dataset.lk_microbiology_episode_specimen spec
        ON org.trace_id_spec = spec.trace_id
CROSS JOIN
    @etl_project.@etl_dataset.lk_microbiology_concepts cfg
;

-- -------------------------------------------------------------------
-- Organism observation rows for SOP-aligned parallel build
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_microbiology_observation_organism AS
SELECT
    org.measurement_id                                             AS observation_id,
    ana.episode_id                                                 AS episode_id,
    spec.specimen_id                                               AS specimen_id,
    org.subject_id                                                 AS subject_id,
    org.hadm_id                                                    AS hadm_id,
    org.start_datetime                                             AS start_datetime,
    CAST(org.start_datetime AS DATE)                               AS date_id,
    cfg.organism_identification_observation_concept_id             AS target_concept_id,
    org.type_concept_id                                            AS type_concept_id,
    org.value_as_concept_id                                        AS value_as_concept_id,
    org.value_source_value                                         AS value_source_value,
    org.source_code                                                AS source_code,
    org.source_concept_id                                          AS source_concept_id,
    1147127                                                        AS obs_event_field_concept_id,
    org.unit_id                                                    AS unit_id,
    org.load_table_id                                              AS load_table_id,
    org.load_row_id                                                AS load_row_id,
    org.trace_id                                                   AS trace_id
FROM
    @etl_project.@etl_dataset.lk_meas_organism_mapped org
INNER JOIN
    @etl_project.@etl_dataset.lk_microbiology_episode_analysis ana
        ON org.trace_id = ana.trace_id
INNER JOIN
    @etl_project.@etl_dataset.lk_microbiology_episode_specimen spec
        ON ana.episode_parent_id = spec.episode_id
CROSS JOIN
    @etl_project.@etl_dataset.lk_microbiology_concepts cfg
;

-- -------------------------------------------------------------------
-- AST interpretation observation rows for SOP-aligned parallel build
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_microbiology_observation_ast AS
SELECT
    ab.measurement_id                                              AS observation_id,
    ana.episode_id                                                 AS episode_id,
    ana.organism_measurement_id                                    AS organism_measurement_id,
    spec.specimen_id                                               AS specimen_id,
    ab.subject_id                                                  AS subject_id,
    ab.hadm_id                                                     AS hadm_id,
    ab.start_datetime                                              AS start_datetime,
    CAST(ab.start_datetime AS DATE)                                AS date_id,
    cfg.antimicrobial_susceptibility_observation_concept_id        AS target_concept_id,
    ab.type_concept_id                                             AS type_concept_id,
    ab.value_as_concept_id                                         AS value_as_concept_id,
    ab.value_source_value                                          AS value_source_value,
    ab.source_code                                                 AS source_code,
    ab.source_concept_id                                           AS source_concept_id,
    1147127                                                        AS obs_event_field_concept_id,
    ab.unit_id                                                     AS unit_id,
    ab.load_table_id                                               AS load_table_id,
    ab.load_row_id                                                 AS load_row_id,
    ab.trace_id                                                    AS trace_id
FROM
    @etl_project.@etl_dataset.lk_meas_ab_mapped ab
INNER JOIN
    @etl_project.@etl_dataset.lk_meas_organism_mapped org
        ON ab.trace_id_org = org.trace_id
INNER JOIN
    @etl_project.@etl_dataset.lk_microbiology_episode_analysis ana
        ON org.trace_id = ana.trace_id
INNER JOIN
    @etl_project.@etl_dataset.lk_microbiology_episode_specimen spec
        ON ana.episode_parent_id = spec.episode_id
CROSS JOIN
    @etl_project.@etl_dataset.lk_microbiology_concepts cfg
;

-- -------------------------------------------------------------------
-- AST MIC / dilution measurement rows for SOP-aligned parallel build
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_microbiology_measurement_ast AS
SELECT
    ab.measurement_id                                              AS measurement_id,
    ana.episode_id                                                 AS episode_id,
    ana.organism_measurement_id                                    AS organism_measurement_id,
    spec.specimen_id                                               AS specimen_id,
    ab.subject_id                                                  AS subject_id,
    ab.hadm_id                                                     AS hadm_id,
    ab.start_datetime                                              AS start_datetime,
    CAST(ab.start_datetime AS DATE)                                AS date_id,
    ab.target_concept_id                                           AS target_concept_id,
    ab.type_concept_id                                             AS type_concept_id,
    ab.operator_concept_id                                         AS operator_concept_id,
    ab.value_as_number                                             AS value_as_number,
    ab.source_code                                                 AS source_code,
    ab.source_concept_id                                           AS source_concept_id,
    ab.value_source_value                                          AS value_source_value,
    1147127                                                        AS meas_event_field_concept_id,
    'micro.ast_measurement'                                        AS unit_id,
    ab.load_table_id                                               AS load_table_id,
    ab.load_row_id                                                 AS load_row_id,
    ab.trace_id                                                    AS trace_id
FROM
    @etl_project.@etl_dataset.lk_meas_ab_mapped ab
INNER JOIN
    @etl_project.@etl_dataset.lk_meas_organism_mapped org
        ON ab.trace_id_org = org.trace_id
INNER JOIN
    @etl_project.@etl_dataset.lk_microbiology_episode_analysis ana
        ON org.trace_id = ana.trace_id
INNER JOIN
    @etl_project.@etl_dataset.lk_microbiology_episode_specimen spec
        ON ana.episode_parent_id = spec.episode_id
WHERE
    ab.value_as_number IS NOT NULL
       OR ab.operator_concept_id IS NOT NULL
;