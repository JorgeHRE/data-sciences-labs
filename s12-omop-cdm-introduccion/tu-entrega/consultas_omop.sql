-- consultas_omop.sql — Lab 12 (OMOP CDM v5.4 sobre Synthea)
-- Base: omop_lab12, esquema cdm. Cada sección = una actividad.

-- =====================================================================
-- Actividad 5. Porcentaje de concept_id = 0 por dominio
-- Denominador: TODAS las filas de la tabla (decisión 15).
-- "estandar" = columna del concepto principal; "origen" = *_source_concept_id.
-- =====================================================================
WITH ceros AS (
    SELECT 'person'               AS dominio, 'gender_concept_id'          AS columna, 'estandar' AS tipo,
           count(*) AS filas, count(*) FILTER (WHERE gender_concept_id = 0) AS ceros FROM cdm.person
    UNION ALL SELECT 'person', 'race_concept_id', 'estandar',
           count(*), count(*) FILTER (WHERE race_concept_id = 0) FROM cdm.person
    UNION ALL SELECT 'person', 'ethnicity_concept_id', 'estandar',
           count(*), count(*) FILTER (WHERE ethnicity_concept_id = 0) FROM cdm.person
    UNION ALL SELECT 'visit_occurrence', 'visit_concept_id', 'estandar',
           count(*), count(*) FILTER (WHERE visit_concept_id = 0) FROM cdm.visit_occurrence
    UNION ALL SELECT 'visit_occurrence', 'visit_source_concept_id', 'origen',
           count(*), count(*) FILTER (WHERE visit_source_concept_id = 0) FROM cdm.visit_occurrence
    UNION ALL SELECT 'condition_occurrence', 'condition_concept_id', 'estandar',
           count(*), count(*) FILTER (WHERE condition_concept_id = 0) FROM cdm.condition_occurrence
    UNION ALL SELECT 'condition_occurrence', 'condition_source_concept_id', 'origen',
           count(*), count(*) FILTER (WHERE condition_source_concept_id = 0) FROM cdm.condition_occurrence
    UNION ALL SELECT 'drug_exposure', 'drug_concept_id', 'estandar',
           count(*), count(*) FILTER (WHERE drug_concept_id = 0) FROM cdm.drug_exposure
    UNION ALL SELECT 'drug_exposure', 'drug_source_concept_id', 'origen',
           count(*), count(*) FILTER (WHERE drug_source_concept_id = 0) FROM cdm.drug_exposure
    UNION ALL SELECT 'procedure_occurrence', 'procedure_concept_id', 'estandar',
           count(*), count(*) FILTER (WHERE procedure_concept_id = 0) FROM cdm.procedure_occurrence
    UNION ALL SELECT 'procedure_occurrence', 'procedure_source_concept_id', 'origen',
           count(*), count(*) FILTER (WHERE procedure_source_concept_id = 0) FROM cdm.procedure_occurrence
    UNION ALL SELECT 'measurement', 'measurement_concept_id', 'estandar',
           count(*), count(*) FILTER (WHERE measurement_concept_id = 0) FROM cdm.measurement
    UNION ALL SELECT 'measurement', 'measurement_source_concept_id', 'origen',
           count(*), count(*) FILTER (WHERE measurement_source_concept_id = 0) FROM cdm.measurement
    UNION ALL SELECT 'observation', 'observation_concept_id', 'estandar',
           count(*), count(*) FILTER (WHERE observation_concept_id = 0) FROM cdm.observation
    UNION ALL SELECT 'observation', 'observation_source_concept_id', 'origen',
           count(*), count(*) FILTER (WHERE observation_source_concept_id = 0) FROM cdm.observation
    UNION ALL SELECT 'device_exposure', 'device_concept_id', 'estandar',
           count(*), count(*) FILTER (WHERE device_concept_id = 0) FROM cdm.device_exposure
    UNION ALL SELECT 'device_exposure', 'device_source_concept_id', 'origen',
           count(*), count(*) FILTER (WHERE device_source_concept_id = 0) FROM cdm.device_exposure
)
SELECT dominio, columna, tipo, filas, ceros,
       round(100.0 * ceros / filas, 2) AS pct_ceros
FROM ceros
ORDER BY dominio, tipo DESC, columna;

-- =====================================================================
-- Actividad 5 (parte 2). Completitud: ¿a dónde va cada fila de native.conditions?
-- Los ceros no miden pérdida: ETL-Synthea DESCARTA lo que no mapea.
-- Se clasifica por CÓDIGO distinto (un JOIN directo multiplicaría filas
-- de los códigos con varios destinos) y se ponderan por sus filas.
-- Orden lógico: CTE por_codigo (FROM native → GROUP BY code) → CTE destino
-- (LEFT JOIN al mapa → GROUP BY code) → SELECT final agrupado por destino.
-- =====================================================================
WITH por_codigo AS (                      -- 1 fila por (sistema, código) con su nº de filas
    SELECT system, code, count(*) AS filas
    FROM native.conditions
    GROUP BY system, code
),
destino AS (                              -- destinos ESTÁNDAR y vigentes de cada código
    SELECT p.system, p.code, p.filas,
           string_agg(DISTINCT m.target_domain_id, '+' ORDER BY m.target_domain_id) AS dominios
    FROM por_codigo p
    LEFT JOIN cdm.source_to_standard_vocab_map m
           ON m.source_code = p.code
          AND m.source_vocabulary_id = CASE p.system WHEN 'SNOMED-CT' THEN 'SNOMED'
                                                      WHEN 'ICD10'     THEN 'ICD10CM' END
          AND m.target_standard_concept = 'S'
          AND m.target_invalid_reason IS NULL
    GROUP BY p.system, p.code, p.filas
)
SELECT system, coalesce(dominios, 'SIN DESTINO') AS destino,
       count(*) AS codigos, sum(filas) AS filas,
       round(100.0 * sum(filas) / sum(sum(filas)) OVER (), 2) AS pct_del_total
FROM destino
GROUP BY system, dominios
ORDER BY system, filas DESC;

-- =====================================================================
-- Actividad 5 (parte 3). Casos peores: códigos de conditions SIN destino estándar
-- NOT EXISTS (anti-join) en lugar de LEFT JOIN ... IS NULL: no multiplica filas
-- y expresa directo "no hay ningún destino estándar vigente".
-- =====================================================================
SELECT c.system, c.code, max(c.description) AS descripcion, count(*) AS filas,
       count(DISTINCT c.patient) AS pacientes
FROM native.conditions c
WHERE NOT EXISTS (
    SELECT 1 FROM cdm.source_to_standard_vocab_map m
    WHERE m.source_code = c.code
      AND m.source_vocabulary_id = CASE c.system WHEN 'SNOMED-CT' THEN 'SNOMED'
                                                 WHEN 'ICD10'     THEN 'ICD10CM' END
      AND m.target_standard_concept = 'S'
      AND m.target_invalid_reason IS NULL)
GROUP BY c.system, c.code
ORDER BY filas DESC;

-- =====================================================================
-- Actividad 5 (parte 4). Diagnóstico: ¿qué relaciones tienen los 27 códigos sin destino?
-- Se parte de concept (código→concept_id) y se cuentan las relaciones SALIENTES
-- vigentes por tipo. Si 'Maps to' no aparece, el hueco está en la descarga/vocabulario.
-- =====================================================================
WITH sin_destino AS (
    SELECT DISTINCT c.system, c.code
    FROM native.conditions c
    WHERE NOT EXISTS (
        SELECT 1 FROM cdm.source_to_standard_vocab_map m
        WHERE m.source_code = c.code
          AND m.source_vocabulary_id = CASE c.system WHEN 'SNOMED-CT' THEN 'SNOMED'
                                                     WHEN 'ICD10'     THEN 'ICD10CM' END
          AND m.target_standard_concept = 'S' AND m.target_invalid_reason IS NULL)
),
conceptos AS (
    SELECT s.system, s.code, k.concept_id
    FROM sin_destino s
    JOIN cdm.concept k ON k.concept_code = s.code
     AND k.vocabulary_id = CASE s.system WHEN 'SNOMED-CT' THEN 'SNOMED' WHEN 'ICD10' THEN 'ICD10CM' END
)
SELECT c.system, coalesce(r.relationship_id, '(ninguna relación)') AS relacion,
       count(DISTINCT c.code) AS codigos_con_relacion, count(*) AS pares
FROM conceptos c
LEFT JOIN cdm.concept_relationship r
       ON r.concept_id_1 = c.concept_id AND r.invalid_reason IS NULL
GROUP BY c.system, r.relationship_id
ORDER BY c.system, codigos_con_relacion DESC;

-- =====================================================================
-- Actividad 5 (parte 5). Completitud de native.medications
-- Se filtra source_vocabulary_id = 'RxNorm': varios source_code numéricos
-- chocan con códigos OSM (Geography) y, sin el filtro, el JOIN los mezclaría.
-- Mismo patrón que conditions: clasificar por código distinto y ponderar por filas.
-- =====================================================================
WITH por_codigo AS (
    SELECT code, count(*) AS filas FROM native.medications GROUP BY code
),
destino AS (
    SELECT p.code, p.filas,
           count(m.target_concept_id) AS n_destinos,          -- >1 = multi-mapeo (duplica filas en el CDM)
           string_agg(DISTINCT m.target_domain_id, '+') AS dominios
    FROM por_codigo p
    LEFT JOIN cdm.source_to_standard_vocab_map m
           ON m.source_code = p.code
          AND m.source_vocabulary_id = 'RxNorm'
          AND m.target_standard_concept = 'S'
          AND m.target_invalid_reason IS NULL
    GROUP BY p.code, p.filas
)
SELECT coalesce(dominios, 'SIN DESTINO') AS destino, n_destinos,
       count(*) AS codigos, sum(filas) AS filas_origen,
       sum(filas * greatest(n_destinos, 1)) AS filas_esperadas_cdm
FROM destino
GROUP BY dominios, n_destinos
ORDER BY filas_origen DESC;

-- =====================================================================
-- Actividad 5 (parte 6). Completitud de native.immunizations, por código
-- Se compara contra drug_exposure de tipo 32827 (el ETL marca así las vacunas).
-- Aquí el mapa por sí solo NO predice la pérdida: ETL-Synthea exige además
-- target_vocabulary_id = 'CVX' (insert_drug_exposure.sql, v540, línea 127).
-- =====================================================================
WITH o AS (SELECT code, max(description) AS descr, count(*) AS filas_origen
           FROM native.immunizations GROUP BY code),
     c AS (SELECT drug_source_value AS code, count(*) AS filas_cdm
           FROM cdm.drug_exposure WHERE drug_type_concept_id = 32827 GROUP BY 1)
SELECT o.code, left(o.descr, 45) AS descr, o.filas_origen, coalesce(c.filas_cdm, 0) AS filas_cdm,
       o.filas_origen - coalesce(c.filas_cdm, 0) AS perdidas,
       round(100.0 * (o.filas_origen - coalesce(c.filas_cdm, 0)) / o.filas_origen, 1) AS pct
FROM o LEFT JOIN c USING (code)
ORDER BY perdidas DESC;

-- =====================================================================
-- Actividad 5 (parte 7). Completitud de native.procedures
-- ETL-Synthea solo lee procedures en insert_procedure_occurrence.sql (dominio
-- Procedure) e insert_measurement.sql (dominio Measurement). Cualquier otro
-- destino (Observation, Drug, Device, Condition) o la ausencia de destino = fila perdida.
-- =====================================================================
WITH por_codigo AS (SELECT code, max(description) AS descr, count(*) AS filas
                    FROM native.procedures GROUP BY code),
destino AS (
    SELECT p.code, p.descr, p.filas,
           string_agg(DISTINCT m.target_domain_id, '+' ORDER BY m.target_domain_id) AS dominios
    FROM por_codigo p
    LEFT JOIN cdm.source_to_standard_vocab_map m
           ON m.source_code = p.code AND m.source_vocabulary_id = 'SNOMED'
          AND m.target_standard_concept = 'S' AND m.target_invalid_reason IS NULL
    GROUP BY p.code, p.descr, p.filas
)
SELECT coalesce(dominios, 'SIN DESTINO') AS destino, code, left(descr, 55) AS descripcion, filas
FROM destino
WHERE dominios IS DISTINCT FROM 'Procedure' AND dominios IS DISTINCT FROM 'Measurement'
ORDER BY filas DESC
LIMIT 15;

-- =====================================================================
-- Actividad 5 (parte 8). Completitud de native.devices
-- El INSERT del ETL exige destino Device/SNOMED estándar vigente
-- (insert_device_exposure.sql, líneas 46-52). Se listan los códigos sin ese destino.
-- =====================================================================
SELECT d.code, max(d.description) AS descripcion, count(*) AS filas
FROM native.devices d
WHERE NOT EXISTS (
    SELECT 1 FROM cdm.source_to_standard_vocab_map m
    WHERE m.source_code = d.code AND m.source_vocabulary_id = 'SNOMED'
      AND m.target_domain_id = 'Device' AND m.target_vocabulary_id = 'SNOMED'
      AND m.target_standard_concept = 'S' AND m.target_invalid_reason IS NULL)
GROUP BY d.code
ORDER BY filas DESC;

-- =====================================================================
-- Actividad 5 (parte 9). Completitud de native.observations
-- Destinos escritos: Measurement (LOINC) -> measurement; Observation (LOINC) -> observation.
-- Perdidas: SIN DESTINO y destinos Note / Procedure (ningún INSERT los lee).
-- Control de cuadratura: measurement(CDM) - 246,598 de procedures = esperadas; igual para observation.
-- =====================================================================
SELECT o.category, o.code, max(left(o.description, 50)) AS descripcion, count(*) AS filas
FROM native.observations o
WHERE NOT EXISTS (
    SELECT 1 FROM cdm.source_to_standard_vocab_map m
    WHERE m.source_code = o.code AND m.source_vocabulary_id = 'LOINC'
      AND m.target_standard_concept = 'S' AND m.target_invalid_reason IS NULL)
GROUP BY o.category, o.code
ORDER BY filas DESC
LIMIT 12;

-- =====================================================================
-- Actividad 5 (parte 10). Los 165 ceros de race_concept_id
-- insert_person.sql codifica la raza a mano: solo WHITE/BLACK/ASIAN tienen
-- concepto; todo lo demás va a 0. Se cruza con la categoría OMB que le correspondería.
-- =====================================================================
SELECT p.race_source_value, p.race_concept_id,
       count(*) AS personas,
       CASE p.race_source_value WHEN 'hawaiian' THEN 8557   -- Native Hawaiian or Other Pacific Islander
                                WHEN 'native'   THEN 8657   -- American Indian or Alaska Native
                                ELSE NULL END AS concepto_que_le_correspondia,
       c.concept_name
FROM cdm.person p
LEFT JOIN cdm.concept c
       ON c.concept_id = CASE p.race_source_value WHEN 'hawaiian' THEN 8557 WHEN 'native' THEN 8657 END
WHERE p.race_concept_id = 0
GROUP BY p.race_source_value, p.race_concept_id, c.concept_name
ORDER BY personas DESC;
