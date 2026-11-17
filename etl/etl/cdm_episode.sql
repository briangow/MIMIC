-- -------------------------------------------------------------------
-- @2026, Odysseus Data Services, Inc. All rights reserved
-- MIMIC IV CDM Conversion
-- -------------------------------------------------------------------
-- -------------------------------------------------------------------
-- Populate episode table for microbiology SOP-aligned parallel build
--
-- Dependencies: run after
--      person.sql
--      visit_occurrence.sql
--      lk_microbiology_semantics.sql
-- -------------------------------------------------------------------

--HINT DISTRIBUTE_ON_KEY(person_id)
CREATE OR REPLACE TABLE @etl_project.@etl_dataset.episode
(
  episode_id                INT64     not null ,
  person_id                 INT64     not null ,
  episode_concept_id        INT64     not null ,
  episode_start_date        DATE      not null ,
  episode_start_datetime    DATETIME           ,
  episode_end_date          DATE               ,
  episode_end_datetime      DATETIME           ,
  episode_parent_id         INT64              ,
  episode_number            INT64              ,
  episode_object_concept_id INT64     not null ,
  episode_type_concept_id   INT64     not null ,
  episode_source_value      STRING             ,
  episode_source_concept_id INT64,
  --
  unit_id                   STRING,
  load_table_id             STRING,
  load_row_id               INT64,
  trace_id                  STRING
)
;

INSERT INTO @etl_project.@etl_dataset.episode
SELECT
    src.episode_id                               AS episode_id,
    per.person_id                                AS person_id,
    src.episode_concept_id                       AS episode_concept_id,
    DATE_ADD(CAST(src.start_datetime AS DATE), INTERVAL ds.offset_days DAY) AS episode_start_date,
    DATETIME_ADD(src.start_datetime, INTERVAL ds.offset_days DAY) AS episode_start_datetime,
    DATE_ADD(CAST(src.start_datetime AS DATE), INTERVAL ds.offset_days DAY) AS episode_end_date,
    DATETIME_ADD(src.start_datetime, INTERVAL ds.offset_days DAY) AS episode_end_datetime,
    src.episode_parent_id                        AS episode_parent_id,
    src.episode_number                           AS episode_number,
    src.episode_object_concept_id                AS episode_object_concept_id,
    src.episode_type_concept_id                  AS episode_type_concept_id,
    src.episode_source_value                     AS episode_source_value,
    src.episode_source_concept_id                AS episode_source_concept_id,
    CONCAT('episode.', src.unit_id)              AS unit_id,
    src.load_table_id                            AS load_table_id,
    src.load_row_id                              AS load_row_id,
    src.trace_id                                 AS trace_id
FROM
    @etl_project.@etl_dataset.lk_microbiology_episode_specimen src
INNER JOIN
    @etl_project.@etl_dataset.person per
        ON CAST(src.subject_id AS STRING) = per.person_source_value
LEFT JOIN
    @etl_project.@etl_dataset.person_date_shift_lookup ds
        ON per.person_id = ds.person_id
;

INSERT INTO @etl_project.@etl_dataset.episode
SELECT
    src.episode_id                               AS episode_id,
    per.person_id                                AS person_id,
    src.episode_concept_id                       AS episode_concept_id,
    DATE_ADD(CAST(src.start_datetime AS DATE), INTERVAL ds.offset_days DAY) AS episode_start_date,
    DATETIME_ADD(src.start_datetime, INTERVAL ds.offset_days DAY) AS episode_start_datetime,
    DATE_ADD(CAST(src.start_datetime AS DATE), INTERVAL ds.offset_days DAY) AS episode_end_date,
    DATETIME_ADD(src.start_datetime, INTERVAL ds.offset_days DAY) AS episode_end_datetime,
    src.episode_parent_id                        AS episode_parent_id,
    src.episode_number                           AS episode_number,
    src.episode_object_concept_id                AS episode_object_concept_id,
    src.episode_type_concept_id                  AS episode_type_concept_id,
    src.episode_source_value                     AS episode_source_value,
    src.episode_source_concept_id                AS episode_source_concept_id,
    CONCAT('episode.', src.unit_id)              AS unit_id,
    src.load_table_id                            AS load_table_id,
    src.load_row_id                              AS load_row_id,
    src.trace_id                                 AS trace_id
FROM
    @etl_project.@etl_dataset.lk_microbiology_episode_analysis src
INNER JOIN
    @etl_project.@etl_dataset.person per
        ON CAST(src.subject_id AS STRING) = per.person_source_value
LEFT JOIN
    @etl_project.@etl_dataset.person_date_shift_lookup ds
        ON per.person_id = ds.person_id
;