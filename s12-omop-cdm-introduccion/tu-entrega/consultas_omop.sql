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

-- =====================================================================
-- Actividad 6 (parte 1). Personas, sexo y año de nacimiento
-- Siempre con concept_name (nunca un concept_id suelto). El JOIN a concept
-- es N:1 (concept_id es PK), así que NO debe cambiar el número de personas.
-- Orden lógico: FROM person → LEFT JOIN concept → GROUP BY → SELECT → ORDER BY.
-- =====================================================================
-- 6.1a Total de personas y control del JOIN (ambos números deben ser iguales)
SELECT (SELECT count(*) FROM cdm.person)                                   AS personas,
       (SELECT count(DISTINCT person_id) FROM cdm.person)                  AS personas_distintas,
       (SELECT count(*) FROM cdm.person p JOIN cdm.concept c
               ON c.concept_id = p.gender_concept_id)                      AS filas_tras_join;

-- 6.1b Distribución por sexo
SELECT c.concept_name AS sexo, count(*) AS personas,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM cdm.person p
LEFT JOIN cdm.concept c ON c.concept_id = p.gender_concept_id
GROUP BY c.concept_name
ORDER BY personas DESC;

-- 6.1c Año de nacimiento (todos los años; abajo se resume por década para leerlo)
SELECT (year_of_birth / 10) * 10 AS decada, count(*) AS personas,
       min(year_of_birth) AS desde, max(year_of_birth) AS hasta
FROM cdm.person
GROUP BY 1
ORDER BY 1;

-- =====================================================================
-- Actividad 6 (parte 2). Días de observación por persona
-- observation_period tiene 1 fila por persona (5,904 = 5,904), así que no hay
-- que sumar periodos. En este ETL el periodo es min(start) a max(stop) de los
-- encuentros (insert_observation_period.sql): lapso con atención registrada,
-- no edad ni afiliación. percentile_cont interpola (con n par la mediana puede
-- ser x.5); es la mediana estadística usual.
-- =====================================================================
SELECT count(*) AS personas,
       percentile_cont(0.50) WITHIN GROUP (ORDER BY dias) AS mediana_dias,
       round((percentile_cont(0.50) WITHIN GROUP (ORDER BY dias) / 365.25)::numeric, 1) AS mediana_anios,
       percentile_cont(0.25) WITHIN GROUP (ORDER BY dias) AS p25_dias,
       percentile_cont(0.75) WITHIN GROUP (ORDER BY dias) AS p75_dias,
       round(avg(dias)::numeric, 0) AS media_dias,
       count(*) FILTER (WHERE dias = 0) AS con_cero_dias
FROM (SELECT person_id, observation_period_end_date - observation_period_start_date AS dias
      FROM cdm.observation_period) t;

-- =====================================================================
-- Actividad 6 (parte 3). Top 20 diagnósticos (decisión 23, opción A)
-- Se cuenta por condition_concept_id (concepto estándar, SNOMED) y con
-- count(DISTINCT person_id): "cuántas personas tienen el diagnóstico", no
-- "cuántas veces se registró" (una gingivitis crónica se registra en muchas
-- visitas e inflaría el ranking). Se muestran también los registros para ver
-- la diferencia. Solo condition_occurrence: los 129,201 hallazgos/situaciones
-- que el ETL mandó a observation quedan fuera (dominio Observation).
-- Orden lógico: FROM → LEFT JOIN → GROUP BY → SELECT → ORDER BY → LIMIT.
-- =====================================================================
-- 6.3a Control: el JOIN a concept no debe cambiar filas (101,699 = 101,699)
-- y no hay condition_concept_id = 0 (el ETL descarta lo que no mapea; act. 5).
SELECT (SELECT count(*) FROM cdm.condition_occurrence)                     AS filas,
       (SELECT count(*) FROM cdm.condition_occurrence co
          JOIN cdm.concept c ON c.concept_id = co.condition_concept_id)      AS filas_tras_join,
       (SELECT count(DISTINCT person_id) FROM cdm.condition_occurrence)      AS personas_con_condicion,
       (SELECT count(*) FROM cdm.condition_occurrence
         WHERE condition_concept_id = 0)                                     AS concept_id_cero;

-- 6.3b Top 20. El denominador del % es toda la población (5,904), no solo
-- quienes tienen alguna condición (5,826). Desempate por registros.
SELECT co.condition_concept_id,
       c.concept_name                                   AS diagnostico,
       count(DISTINCT co.person_id)                     AS personas,
       round(100.0 * count(DISTINCT co.person_id)
             / (SELECT count(*) FROM cdm.person), 1)    AS pct_poblacion,
       count(*)                                         AS registros
FROM cdm.condition_occurrence co
LEFT JOIN cdm.concept c ON c.concept_id = co.condition_concept_id
GROUP BY co.condition_concept_id, c.concept_name
ORDER BY personas DESC, registros DESC
LIMIT 20;

-- =====================================================================
-- Actividad 6 (parte 4). Visitas por persona, total y por tipo (decisión 24, A)
-- Denominador: TODA la población (5,904). Quien no tiene visitas de un tipo
-- cuenta como 0. Para eso se parte de person (no de visit_occurrence) y se
-- hace LEFT JOIN: si se partiera de visit_occurrence, las personas sin
-- visitas de ese tipo desaparecerían y la media/mediana quedarían infladas.
-- Por tipo se arma la rejilla persona × tipo con CROSS JOIN (5,904 × 3 =
-- 17,712 filas) para que los ceros existan como filas.
-- Orden lógico: FROM/JOIN → GROUP BY (por persona) → agregado externo.
-- =====================================================================
-- 6.4a Control: personas sin visita y visitas huérfanas (esperado 0 y 0)
SELECT (SELECT count(*) FROM cdm.visit_occurrence)                         AS visitas,
       (SELECT count(*) FROM cdm.person p WHERE NOT EXISTS
          (SELECT 1 FROM cdm.visit_occurrence v WHERE v.person_id = p.person_id)) AS personas_sin_visita,
       (SELECT count(*) FROM cdm.visit_occurrence v WHERE NOT EXISTS
          (SELECT 1 FROM cdm.person p WHERE p.person_id = v.person_id))    AS visitas_huerfanas;

-- 6.4b Visitas por persona: total (fila 'Total') y por tipo de visita
WITH tipos AS (SELECT DISTINCT visit_concept_id FROM cdm.visit_occurrence),
por_persona_tipo AS (           -- una fila por persona × tipo, con ceros
    SELECT p.person_id, t.visit_concept_id, count(v.visit_occurrence_id) AS n
    FROM cdm.person p
    CROSS JOIN tipos t
    LEFT JOIN cdm.visit_occurrence v
           ON v.person_id = p.person_id AND v.visit_concept_id = t.visit_concept_id
    GROUP BY p.person_id, t.visit_concept_id),
por_persona AS (                -- total de visitas por persona
    SELECT person_id, NULL::int AS visit_concept_id, sum(n) AS n
    FROM por_persona_tipo GROUP BY person_id)
SELECT coalesce(c.concept_name, 'Total')                        AS tipo_visita,
       count(*)                                                 AS personas_denominador,
       sum(x.n)                                                 AS visitas,
       round(avg(x.n), 1)                                       AS media_por_persona,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY x.n)         AS mediana,
       count(*) FILTER (WHERE x.n = 0)                          AS personas_con_cero
FROM (SELECT * FROM por_persona_tipo UNION ALL SELECT * FROM por_persona) x
LEFT JOIN cdm.concept c ON c.concept_id = x.visit_concept_id
GROUP BY c.concept_name
ORDER BY visitas DESC;
