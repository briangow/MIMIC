CREATE OR REPLACE TABLE `@etl_project`.@etl_dataset.lk_inputevents AS
SELECT
    src.subject_id                  AS subject_id,
    src.hadm_id                     AS hadm_id,
    src.stay_id                     AS stay_id,
    src.itemid                      AS itemid,
    CAST(src.itemid AS STRING)      AS source_code,
    di.label                        AS source_label,
    src.starttime                   AS start_datetime,
    COALESCE(src.endtime, src.starttime) AS end_datetime,
    src.amount                      AS amount,
    src.amountuom                   AS amountuom,
    src.rate                        AS rate,
    src.rateuom                     AS rateuom,
    src.ordercategoryname           AS ordercategoryname,
    src.ordercategorydescription    AS ordercategorydescription,
    src.statusdescription           AS statusdescription,
    src.patientweight               AS patientweight,
    src.totalamount                 AS totalamount,
    src.totalamountuom              AS totalamountuom,
    'inputevents'                   AS unit_id,
    src.load_table_id               AS load_table_id,
    src.load_row_id                 AS load_row_id,
    src.trace_id                    AS trace_id
FROM
    `@etl_project`.@etl_dataset.src_inputevents src
INNER JOIN
    `@etl_project`.@etl_dataset.src_d_items di
        ON src.itemid = di.itemid
;

CREATE OR REPLACE TABLE `@etl_project`.@etl_dataset.lk_inputevents_concept AS
WITH code_match AS (
    SELECT
        src.itemid                  AS itemid,
        src.source_code             AS source_code,
        src.source_label            AS source_label,
        'MIMIC4'                    AS source_vocabulary_id,
        'm4_input_itemid'           AS source_concept_class_id,
        vc.domain_id                AS source_domain_id,
        vc.concept_id               AS source_concept_id,
        vc.concept_name             AS source_concept_name
    FROM
        `@etl_project`.@etl_dataset.lk_inputevents src
    LEFT JOIN `@etl_project`.@etl_dataset.voc_concept vc
        ON src.source_code = vc.concept_code
        AND vc.vocabulary_id = 'MIMIC4'
        AND vc.concept_class_id = 'm4_input_itemid'
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
    LEFT JOIN `@etl_project`.@etl_dataset.voc_concept vc
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
    LEFT JOIN `@etl_project`.@etl_dataset.voc_concept_synonym vcs
        ON cm.source_concept_id IS NULL
        AND cm.source_label = vcs.concept_synonym_name
    LEFT JOIN `@etl_project`.@etl_dataset.voc_concept vc
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
        src.itemid                  AS itemid,
        src.source_code             AS source_code,
        src.source_label            AS source_label,
        'MIMIC4'                    AS source_vocabulary_id,
        'm4_input_itemid'           AS source_concept_class_id,
        CAST(NULL AS STRING)        AS source_domain_id,
        CAST(NULL AS INT64)         AS source_concept_id,
        CAST(NULL AS STRING)        AS source_concept_name,
        CAST(NULL AS STRING)        AS target_domain_id,
        CAST(NULL AS INT64)         AS target_concept_id
    FROM
        `@etl_project`.@etl_dataset.lk_inputevents src
    WHERE NOT EXISTS (
        SELECT 1
        FROM code_match cm
        WHERE cm.itemid = src.itemid
          AND cm.source_concept_id IS NOT NULL
    )
      AND NOT EXISTS (
        SELECT 1
        FROM name_match nm
        WHERE nm.itemid = src.itemid
          AND nm.source_concept_id IS NOT NULL
    )
      AND NOT EXISTS (
        SELECT 1
        FROM synonym_match sm
        WHERE sm.itemid = src.itemid
          AND sm.source_concept_id IS NOT NULL
    )
)
SELECT
    cm.itemid                   AS itemid,
    cm.source_code              AS source_code,
    cm.source_label             AS source_label,
    cm.source_vocabulary_id     AS source_vocabulary_id,
    cm.source_concept_class_id  AS source_concept_class_id,
    cm.source_domain_id         AS source_domain_id,
    cm.source_concept_id        AS source_concept_id,
    vc2.domain_id               AS target_domain_id,
    vc2.concept_id              AS target_concept_id
FROM
    code_match cm
LEFT JOIN `@etl_project`.@etl_dataset.voc_concept_relationship cr
    ON  cm.source_concept_id = cr.concept_id_1
    AND cr.relationship_id = 'Maps to'
LEFT JOIN `@etl_project`.@etl_dataset.voc_concept vc2
    ON cr.concept_id_2 = vc2.concept_id
    AND vc2.standard_concept = 'S'
    AND vc2.invalid_reason IS NULL
WHERE
    cm.source_concept_id IS NOT NULL
UNION ALL
SELECT
    nm.itemid                   AS itemid,
    nm.source_code              AS source_code,
    nm.source_label             AS source_label,
    nm.source_vocabulary_id     AS source_vocabulary_id,
    nm.source_concept_class_id  AS source_concept_class_id,
    nm.source_domain_id         AS source_domain_id,
    nm.source_concept_id        AS source_concept_id,
    vc2.domain_id               AS target_domain_id,
    vc2.concept_id              AS target_concept_id
FROM
    name_match nm
LEFT JOIN `@etl_project`.@etl_dataset.voc_concept_relationship cr
    ON  nm.source_concept_id = cr.concept_id_1
    AND cr.relationship_id = 'Maps to'
LEFT JOIN `@etl_project`.@etl_dataset.voc_concept vc2
    ON cr.concept_id_2 = vc2.concept_id
    AND vc2.standard_concept = 'S'
    AND vc2.invalid_reason IS NULL
UNION ALL
SELECT
    sm.itemid                   AS itemid,
    sm.source_code              AS source_code,
    sm.source_label             AS source_label,
    sm.source_vocabulary_id     AS source_vocabulary_id,
    sm.source_concept_class_id  AS source_concept_class_id,
    sm.source_domain_id         AS source_domain_id,
    sm.source_concept_id        AS source_concept_id,
    vc2.domain_id               AS target_domain_id,
    vc2.concept_id              AS target_concept_id
FROM
    synonym_match sm
LEFT JOIN `@etl_project`.@etl_dataset.voc_concept_relationship cr
    ON  sm.source_concept_id = cr.concept_id_1
    AND cr.relationship_id = 'Maps to'
LEFT JOIN `@etl_project`.@etl_dataset.voc_concept vc2
    ON cr.concept_id_2 = vc2.concept_id
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
    uf.target_concept_id        AS target_concept_id
FROM
    unmapped_fallback uf
;

CREATE OR REPLACE TABLE `@etl_project`.@etl_dataset.lk_inputevents_mapped AS
WITH inputevents_concept_dedup AS (
    SELECT * EXCEPT(row_num)
    FROM (
        SELECT
            c.*,
            ROW_NUMBER() OVER (
                PARTITION BY c.itemid
                ORDER BY
                    IF(c.target_concept_id IS NOT NULL, 0, 1),
                    IF(c.source_concept_id IS NOT NULL, 0, 1),
                    c.target_concept_id,
                    c.source_concept_id
            ) AS row_num
        FROM `@etl_project`.@etl_dataset.lk_inputevents_concept c
    )
    WHERE row_num = 1
),
meas_unit_concept_dedup AS (
    SELECT * EXCEPT(row_num)
    FROM (
        SELECT
            uc.*,
            ROW_NUMBER() OVER (
                PARTITION BY uc.source_code
                ORDER BY
                    IF(uc.target_concept_id IS NOT NULL, 0, 1),
                    uc.target_concept_id,
                    uc.source_concept_id
            ) AS row_num
        FROM `@etl_project`.@etl_dataset.lk_meas_unit_concept uc
    )
    WHERE row_num = 1
),
route_concept_dedup AS (
    SELECT * EXCEPT(row_num)
    FROM (
        SELECT
            rc.*,
            ROW_NUMBER() OVER (
                PARTITION BY rc.source_code
                ORDER BY
                    IF(rc.target_concept_id IS NOT NULL, 0, 1),
                    rc.target_concept_id,
                    rc.source_concept_id
            ) AS row_num
        FROM `@etl_project`.@etl_dataset.lk_pr_route_concept rc
    )
    WHERE row_num = 1
)
SELECT
    `@etl_project.@etl_dataset`.obf_id_str(CONCAT(
        src.trace_id, '|',
        CAST(COALESCE(c.target_concept_id, 0) AS STRING)
    ), 64)                                                    AS inputevent_id,
    src.subject_id                                            AS subject_id,
    src.hadm_id                                               AS hadm_id,
    src.stay_id                                               AS stay_id,
    src.start_datetime                                        AS start_datetime,
    CASE
        WHEN src.end_datetime < src.start_datetime THEN src.start_datetime
        ELSE src.end_datetime
    END                                                       AS end_datetime,
    src.itemid                                                AS itemid,
    src.source_code                                           AS source_code,
    src.source_label                                          AS source_label,
    c.source_vocabulary_id                                    AS source_vocabulary_id,
    c.source_concept_class_id                                 AS source_concept_class_id,
    c.source_domain_id                                        AS source_domain_id,
    c.source_concept_id                                       AS source_concept_id,
    c.target_domain_id                                        AS target_domain_id,
    c.target_concept_id                                       AS target_concept_id,
    32818                                                     AS type_concept_id,
    src.amount                                                AS quantity,
    src.amountuom                                             AS quantity_source_value,
    src.rate                                                  AS rate,
    src.rateuom                                               AS rateuom,
    src.ordercategoryname                                     AS ordercategoryname,
    src.ordercategorydescription                              AS ordercategorydescription,
    src.statusdescription                                     AS statusdescription,
    src.patientweight                                         AS patientweight,
    src.totalamount                                           AS totalamount,
    src.totalamountuom                                        AS totalamountuom,
    IF(src.amountuom IS NOT NULL,
        COALESCE(uc.target_concept_id, 0), NULL)              AS unit_concept_id,
    COALESCE(rc.target_concept_id, 0)                         AS route_concept_id,
    CAST(NULL AS STRING)                                      AS route_source_code,
    src.amountuom                                             AS dose_unit_source_code,
    CONCAT('drug.', src.unit_id)                              AS unit_id,
    src.load_table_id                                         AS load_table_id,
    src.load_row_id                                           AS load_row_id,
    src.trace_id                                              AS trace_id
FROM
    `@etl_project`.@etl_dataset.lk_inputevents src
LEFT JOIN inputevents_concept_dedup c
    ON src.itemid = c.itemid
LEFT JOIN meas_unit_concept_dedup uc
    ON src.amountuom = uc.source_code
LEFT JOIN route_concept_dedup rc
    ON FALSE
;