-- -------------------------------------------------------------------
-- @2020, Odysseus Data Services, Inc. All rights reserved
-- MIMIC IV CDM Conversion
-- -------------------------------------------------------------------
-- -------------------------------------------------------------------
-- Populate drug_exposure table
-- 
-- Dependencies: run after 
--      st_core.sql
--      st_hosp.sql
-- -------------------------------------------------------------------

-- -------------------------------------------------------------------
-- Known issues / Open points:
--
-- open points: 
--      source table pharmacy - it is not here yet
--      mimiciv_drug_ndc.concept_class_id = 'Prescription Drug' - is it right?
--      TODO: one distinct list of codes, then one join to vocabulary tables (1.42GB per vocab join)
-- -------------------------------------------------------------------


-- -------------------------------------------------------------------
-- lk_prescriptions_clean 
-- Rule 1
-- -------------------------------------------------------------------
CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_prescriptions_clean AS
SELECT
    -- -- 'drug:['                || COALESCE(drug, drug_name_poe, drug_name_generic,'') || ']'||
    -- 'drug:['                || COALESCE(drug,'') || ']'||
    -- 'prod_strength:['       || COALESCE(prod_strength,'') || ']'||
    -- 'drug_type:['           || COALESCE(drug_type,'') || ']'||
    -- -- 'formulary_drug_cd:['   || COALESCE(formulary_drug_cd,'') || ']' ||
    --  'dose_unit_rx:['       || COALESCE(dose_unit_rx,'') || ']' 
    --                                                                     AS concept_name,
    src.subject_id              AS subject_id,
    src.hadm_id                 AS hadm_id,
    src.dose_val_rx             AS dose_val_rx,
    src.starttime               AS start_datetime,
    COALESCE(src.stoptime, src.starttime) AS end_datetime,
    src.route                   AS route_source_code,
    'MIMIC4'                    AS route_source_vocabulary,
    'm4_rx_route'               AS route_source_concept_class_id,
    src.form_unit_disp          AS dose_unit_source_code,
    CAST(src.ndc AS STRING)     AS ndc_source_code,
    'NDC'                       AS ndc_source_vocabulary,
    src.form_val_disp           AS form_val_disp,
    CAST(REGEXP_EXTRACT(src.form_val_disp, r'[-]?[\d]+[.]?[\d]*') AS FLOAT64)  AS quantity,
    -- COALESCE(
    --     -- src.drug, src.drug_name_poe, src.drug_name_generic,'')
    --     src.drug, '')
    --     || ' ' || COALESCE(src.prod_strength, '')               
    TRIM(COALESCE(
        IF(src.drug IN ('Bag', 'Vial', 'Syringe', 'Syringe.', 
                        'Syringe (Neonatal)', 'Syringe (Chemo)', 'Soln', 'Soln.',
                        'Sodium Chloride 0.9%  Flush'), 
            pharm.medication, src.drug), '') || 
                ' ' || COALESCE(src.prod_strength, ''))  AS custom_source_code,
    'MIMIC4'                                            AS custom_source_vocabulary,
    'gcpt_drug_ndc'                                     AS custom_source_concept_class_id,
    src.pharmacy_id                             AS pharmacy_id,
    -- 
    'prescriptions'                 AS unit_id,
    src.load_table_id               AS load_table_id,
    src.load_row_id                 AS load_row_id,
    src.trace_id                    AS trace_id

FROM
    @etl_project.@etl_dataset.src_prescriptions src -- pr
LEFT JOIN 
    @etl_project.@etl_dataset.src_pharmacy pharm
        ON src.pharmacy_id = pharm.pharmacy_id
WHERE
    src.starttime IS NOT NULL
    AND src.drug IS NOT NULL
;

-- -------------------------------------------------------------------
-- lk_pr_ndc_concept
-- Rule 1
-- mapping is 85% done from gsn coding
-- -------------------------------------------------------------------
CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_pr_ndc_concept AS
SELECT DISTINCT
    src.ndc_source_code     AS source_code,
    vc.domain_id            AS source_domain_id,
    vc.concept_id           AS source_concept_id,
    vc2.domain_id           AS target_domain_id,
    vc2.concept_id          AS target_concept_id
FROM
    @etl_project.@etl_dataset.lk_prescriptions_clean src -- pr
LEFT JOIN
    @etl_project.@etl_dataset.voc_concept vc
        ON  vc.concept_code = src.ndc_source_code
        AND vc.vocabulary_id = src.ndc_source_vocabulary
LEFT JOIN
    @etl_project.@etl_dataset.voc_concept_relationship vcr
        ON  vc.concept_id = vcr.concept_id_1 
        and vcr.relationship_id = 'Maps to'
LEFT JOIN
    @etl_project.@etl_dataset.voc_concept vc2
        ON vc2.concept_id = vcr.concept_id_2
        AND vc2.standard_concept = 'S'
        AND vc2.invalid_reason IS NULL --covers 71% of rxnorm standards concepts
;

-- -------------------------------------------------------------------
-- lk_pr_custom_concept
-- Rule 1
-- -------------------------------------------------------------------
CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_pr_custom_concept AS
WITH code_match AS (
    SELECT DISTINCT
        src.custom_source_code  AS source_code,
        vc.domain_id            AS source_domain_id,
        vc.concept_id           AS source_concept_id,
        vc2.domain_id           AS target_domain_id,
        vc2.concept_id          AS target_concept_id
    FROM
        @etl_project.@etl_dataset.lk_prescriptions_clean src -- pr
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept vc
            ON  vc.concept_code = src.custom_source_code
            AND vc.vocabulary_id = src.custom_source_vocabulary
            AND vc.concept_class_id = src.custom_source_concept_class_id
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept_relationship vcr
            ON  vc.concept_id = vcr.concept_id_1 
            and vcr.relationship_id = 'Maps to'
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept vc2
            ON vc2.concept_id = vcr.concept_id_2
            AND vc2.standard_concept = 'S'
            AND vc2.invalid_reason IS NULL
),
name_match AS (
    SELECT DISTINCT
        src.custom_source_code  AS source_code,
        vc.domain_id            AS source_domain_id,
        vc.concept_id           AS source_concept_id,
        vc2.domain_id           AS target_domain_id,
        vc2.concept_id          AS target_concept_id
    FROM
        @etl_project.@etl_dataset.lk_prescriptions_clean src -- pr
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept vc
            ON  vc.concept_name = src.custom_source_code
            AND vc.vocabulary_id = src.custom_source_vocabulary
            AND vc.concept_class_id = src.custom_source_concept_class_id
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept_relationship vcr
            ON  vc.concept_id = vcr.concept_id_1 
            and vcr.relationship_id = 'Maps to'
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept vc2
            ON vc2.concept_id = vcr.concept_id_2
            AND vc2.standard_concept = 'S'
            AND vc2.invalid_reason IS NULL
    WHERE NOT EXISTS (
        SELECT 1
        FROM code_match cm
        WHERE cm.source_code = src.custom_source_code
          AND cm.source_concept_id IS NOT NULL
    )
),
synonym_match AS (
    SELECT DISTINCT
        src.custom_source_code  AS source_code,
        vc.domain_id            AS source_domain_id,
        vc.concept_id           AS source_concept_id,
        vc2.domain_id           AS target_domain_id,
        vc2.concept_id          AS target_concept_id
    FROM
        @etl_project.@etl_dataset.lk_prescriptions_clean src -- pr
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept_synonym vcs
            ON vcs.concept_synonym_name = src.custom_source_code
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept vc
            ON  vc.concept_id = vcs.concept_id
            AND vc.vocabulary_id = src.custom_source_vocabulary
            AND vc.concept_class_id = src.custom_source_concept_class_id
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept_relationship vcr
            ON  vc.concept_id = vcr.concept_id_1 
            and vcr.relationship_id = 'Maps to'
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept vc2
            ON vc2.concept_id = vcr.concept_id_2
            AND vc2.standard_concept = 'S'
            AND vc2.invalid_reason IS NULL
    WHERE NOT EXISTS (
        SELECT 1
        FROM code_match cm
        WHERE cm.source_code = src.custom_source_code
          AND cm.source_concept_id IS NOT NULL
    )
      AND NOT EXISTS (
        SELECT 1
        FROM name_match nm
        WHERE nm.source_code = src.custom_source_code
          AND nm.source_concept_id IS NOT NULL
    )
)
SELECT * FROM code_match
UNION ALL
SELECT * FROM name_match
UNION ALL
SELECT * FROM synonym_match
;

-- -------------------------------------------------------------------
-- lk_pr_route_concept
-- Rule 1
-- -------------------------------------------------------------------
CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_pr_route_concept AS
WITH code_match AS (
    SELECT DISTINCT
        src.route_source_code   AS source_code,
        vc.domain_id            AS source_domain_id,
        vc.concept_id           AS source_concept_id,
        vc2.domain_id           AS target_domain_id,
        vc2.concept_id          AS target_concept_id
    FROM
        @etl_project.@etl_dataset.lk_prescriptions_clean src -- pr
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept vc
            ON  vc.concept_code = src.route_source_code
            AND vc.vocabulary_id = src.route_source_vocabulary
            AND vc.concept_class_id = src.route_source_concept_class_id
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept_relationship vcr
            ON  vc.concept_id = vcr.concept_id_1 
            and vcr.relationship_id = 'Maps to'
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept vc2
            ON vc2.concept_id = vcr.concept_id_2
            AND vc2.standard_concept = 'S'
            AND vc2.invalid_reason IS NULL
),
name_match AS (
    SELECT DISTINCT
        src.route_source_code   AS source_code,
        vc.domain_id            AS source_domain_id,
        vc.concept_id           AS source_concept_id,
        vc2.domain_id           AS target_domain_id,
        vc2.concept_id          AS target_concept_id
    FROM
        @etl_project.@etl_dataset.lk_prescriptions_clean src -- pr
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept vc
            ON  vc.concept_name = src.route_source_code
            AND vc.vocabulary_id = src.route_source_vocabulary
            AND vc.concept_class_id = src.route_source_concept_class_id
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept_relationship vcr
            ON  vc.concept_id = vcr.concept_id_1 
            and vcr.relationship_id = 'Maps to'
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept vc2
            ON vc2.concept_id = vcr.concept_id_2
            AND vc2.standard_concept = 'S'
            AND vc2.invalid_reason IS NULL
    WHERE NOT EXISTS (
        SELECT 1
        FROM code_match cm
        WHERE cm.source_code = src.route_source_code
          AND cm.source_concept_id IS NOT NULL
    )
),
synonym_match AS (
    SELECT DISTINCT
        src.route_source_code   AS source_code,
        vc.domain_id            AS source_domain_id,
        vc.concept_id           AS source_concept_id,
        vc2.domain_id           AS target_domain_id,
        vc2.concept_id          AS target_concept_id
    FROM
        @etl_project.@etl_dataset.lk_prescriptions_clean src -- pr
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept_synonym vcs
            ON vcs.concept_synonym_name = src.route_source_code
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept vc
            ON  vc.concept_id = vcs.concept_id
            AND vc.vocabulary_id = src.route_source_vocabulary
            AND vc.concept_class_id = src.route_source_concept_class_id
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept_relationship vcr
            ON  vc.concept_id = vcr.concept_id_1 
            and vcr.relationship_id = 'Maps to'
    LEFT JOIN
        @etl_project.@etl_dataset.voc_concept vc2
            ON vc2.concept_id = vcr.concept_id_2
            AND vc2.standard_concept = 'S'
            AND vc2.invalid_reason IS NULL
    WHERE NOT EXISTS (
        SELECT 1
        FROM code_match cm
        WHERE cm.source_code = src.route_source_code
          AND cm.source_concept_id IS NOT NULL
    )
      AND NOT EXISTS (
        SELECT 1
        FROM name_match nm
        WHERE nm.source_code = src.route_source_code
          AND nm.source_concept_id IS NOT NULL
    )
)
SELECT * FROM code_match
UNION ALL
SELECT * FROM name_match
UNION ALL
SELECT * FROM synonym_match
;

-- -------------------------------------------------------------------
-- lk_drug_mapped
-- -------------------------------------------------------------------

CREATE OR REPLACE TABLE @etl_project.@etl_dataset.lk_drug_mapped AS
SELECT
    src.hadm_id                                     AS hadm_id,
    src.subject_id                                  AS subject_id,
    COALESCE(vc_ndc.target_concept_id, vc_custom.target_concept_id, 0)    AS target_concept_id,
    COALESCE(vc_ndc.target_domain_id, vc_custom.target_domain_id, 'Drug') AS target_domain_id,
    src.start_datetime                                                  AS start_datetime,
    CASE
        WHEN src.end_datetime < src.start_datetime THEN src.start_datetime
        ELSE src.end_datetime
    END                                             AS end_datetime,
    32838                                           AS type_concept_id, -- OMOP4976911 EHR prescription
    src.quantity                                    AS quantity,
    COALESCE(vc_route.target_concept_id, 0)                             AS route_concept_id,
    COALESCE(vc_ndc.source_code, vc_custom.source_code, src.custom_source_code) AS source_code,
    COALESCE(vc_ndc.source_concept_id, vc_custom.source_concept_id, 0)    AS source_concept_id,
    src.route_source_code                                               AS route_source_code,
    src.dose_unit_source_code                       AS dose_unit_source_code,
    src.form_val_disp                               AS quantity_source_value,
    src.pharmacy_id                                 AS pharmacy_id, -- to investigate pharmacy.medication
    -- 
    CONCAT('drug.', src.unit_id)    AS unit_id,
    src.load_table_id               AS load_table_id,
    src.load_row_id                 AS load_row_id,
    src.trace_id                    AS trace_id
FROM
    @etl_project.@etl_dataset.lk_prescriptions_clean src
LEFT JOIN
    @etl_project.@etl_dataset.lk_pr_ndc_concept vc_ndc
        ON  src.ndc_source_code = vc_ndc.source_code
        AND vc_ndc.target_concept_id IS NOT NULL
LEFT JOIN
    @etl_project.@etl_dataset.lk_pr_custom_concept vc_custom
        ON  src.custom_source_code = vc_custom.source_code
        AND vc_custom.target_concept_id IS NOT NULL
LEFT JOIN
    @etl_project.@etl_dataset.lk_pr_route_concept vc_route
        ON src.route_source_code = vc_route.source_code
        AND vc_route.target_concept_id IS NOT NULL
;
