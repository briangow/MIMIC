-- -------------------------------------------------------------------
-- @2026, Odysseus Data Services, Inc. All rights reserved
-- MIMIC IV CDM Conversion
-- -------------------------------------------------------------------
-- -------------------------------------------------------------------
-- Populate episode_event table for microbiology SOP-aligned parallel build
--
-- Dependencies: run after
--      cdm_episode.sql
--      cdm_specimen.sql
--      cdm_measurement.sql
--      cdm_observation.sql
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.episode_event
(
  episode_id                     INT64     not null ,
  event_id                       INT64     not null ,
  episode_event_field_concept_id INT64     not null,
  --
  unit_id                        STRING
)
;

-- Parent specimen episode -> specimen
INSERT INTO @etl_project.@etl_dataset.episode_event
SELECT
    src.episode_id                               AS episode_id,
    src.specimen_id                              AS event_id,
    1147304                                      AS episode_event_field_concept_id,
    'episode_event.micro.specimen'               AS unit_id
FROM
    @etl_project.@etl_dataset.lk_microbiology_episode_specimen src
;

-- Analysis episode -> organism observation
INSERT INTO @etl_project.@etl_dataset.episode_event
SELECT
    src.episode_id                               AS episode_id,
    src.observation_id                           AS event_id,
    1147127                                      AS episode_event_field_concept_id,
    'episode_event.micro.organism_observation'   AS unit_id
FROM
    @etl_project.@etl_dataset.lk_microbiology_observation_organism src
;

-- Analysis episode -> AST observation
INSERT INTO @etl_project.@etl_dataset.episode_event
SELECT
    src.episode_id                               AS episode_id,
    src.observation_id                           AS event_id,
    1147127                                      AS episode_event_field_concept_id,
    'episode_event.micro.ast_observation'        AS unit_id
FROM
    @etl_project.@etl_dataset.lk_microbiology_observation_ast src
;

-- Analysis episode -> AST MIC / dilution measurement
INSERT INTO @etl_project.@etl_dataset.episode_event
SELECT
    src.episode_id                               AS episode_id,
    src.measurement_id                           AS event_id,
    1147127                                      AS episode_event_field_concept_id,
    'episode_event.micro.ast_measurement'        AS unit_id
FROM
    @etl_project.@etl_dataset.lk_microbiology_measurement_ast src
;