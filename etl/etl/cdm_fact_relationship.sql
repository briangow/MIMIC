-- -------------------------------------------------------------------
-- @2020, Odysseus Data Services, Inc. All rights reserved
-- MIMIC IV CDM Conversion
-- -------------------------------------------------------------------
-- -------------------------------------------------------------------
-- Populate observation table
-- 
-- Dependencies: run after 
--      lk_meas_specimen
-- -------------------------------------------------------------------


CREATE OR REPLACE TABLE @etl_project.@etl_dataset.fact_relationship
(
    domain_concept_id_1     INT64     not null ,
    fact_id_1               INT64     not null ,
    domain_concept_id_2     INT64     not null ,
    fact_id_2               INT64     not null ,
    relationship_concept_id INT64     not null ,
    -- 
    unit_id                       STRING  
)
;
