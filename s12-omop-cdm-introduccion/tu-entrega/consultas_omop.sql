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
       r0.concept_name AS race_concept_name,   -- 0 = 'No matching concept'
       count(DISTINCT p.person_id) AS personas,
       CASE p.race_source_value WHEN 'hawaiian' THEN 8557   -- Native Hawaiian or Other Pacific Islander
                                WHEN 'native'   THEN 8657   -- American Indian or Alaska Native
                                ELSE NULL END AS concepto_que_le_correspondia,
       c.concept_name
FROM cdm.person p
LEFT JOIN cdm.concept c
       ON c.concept_id = CASE p.race_source_value WHEN 'hawaiian' THEN 8557 WHEN 'native' THEN 8657 END
LEFT JOIN cdm.concept r0 ON r0.concept_id = p.race_concept_id
WHERE p.race_concept_id = 0
GROUP BY p.race_source_value, p.race_concept_id, r0.concept_name, c.concept_name
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
SELECT c.concept_name AS sexo, count(DISTINCT p.person_id) AS personas,
       round(100.0 * count(DISTINCT p.person_id)
             / sum(count(DISTINCT p.person_id)) OVER (), 1) AS pct
FROM cdm.person p
LEFT JOIN cdm.concept c ON c.concept_id = p.gender_concept_id
GROUP BY c.concept_name
ORDER BY personas DESC;

-- 6.1c Año de nacimiento (todos los años; abajo se resume por década para leerlo)
SELECT (year_of_birth / 10) * 10 AS decada, count(DISTINCT person_id) AS personas,
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
SELECT count(DISTINCT person_id) AS personas,   -- = periodos: 1 por persona
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
       count(DISTINCT x.person_id)                              AS personas_denominador,
       sum(x.n)                                                 AS visitas,
       round(avg(x.n), 1)                                       AS media_por_persona,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY x.n)         AS mediana,
       count(DISTINCT x.person_id) FILTER (WHERE x.n = 0)       AS personas_con_cero
FROM (SELECT * FROM por_persona_tipo UNION ALL SELECT * FROM por_persona) x
LEFT JOIN cdm.concept c ON c.concept_id = x.visit_concept_id
GROUP BY c.concept_name
ORDER BY visitas DESC;

-- =====================================================================
-- Actividad 7. Estándar contra origen: Dental caries (decisión 25)
-- Misma condición contada de dos formas. El concepto estándar 133228
-- (SNOMED) agrupa todos los códigos de origen que tienen 'Maps to' hacia él;
-- condition_source_value guarda el código tal como venía de Synthea.
-- =====================================================================
-- 7a Por concepto estándar (una sola cifra)
SELECT c.concept_name, count(*) AS filas, count(DISTINCT co.person_id) AS personas
FROM cdm.condition_occurrence co
JOIN cdm.concept c ON c.concept_id = co.condition_concept_id
WHERE co.condition_concept_id = 133228
GROUP BY c.concept_name;

-- 7b Por código de origen: qué códigos alimentan a 133228 y cuánto aporta
-- cada uno. Si el estándar suma más que cualquier código suelto, es porque
-- varios orígenes (SNOMED-CT e ICD-10 en Synthea) mapean al mismo concepto.
SELECT co.condition_source_value                    AS codigo_origen,
       src.vocabulary_id                            AS vocabulario_origen,
       src.concept_name                             AS nombre_origen,
       count(*)                                     AS filas,
       count(DISTINCT co.person_id)                 AS personas
FROM cdm.condition_occurrence co
LEFT JOIN cdm.concept src ON src.concept_id = co.condition_source_concept_id
WHERE co.condition_concept_id = 133228
GROUP BY 1, 2, 3
ORDER BY filas DESC;

-- 7c Control contra la fuente: ¿se perdió alguna fila de esos códigos?
-- (el ETL descarta lo que no mapea, act. 5). Si cuadra, la diferencia entre
-- 7a y 7b es solo de agrupación, no de pérdida.
SELECT n.code, count(*) AS filas_native,
       (SELECT count(*) FROM cdm.condition_occurrence co
         WHERE co.condition_source_value = n.code)   AS filas_cdm
FROM native.conditions n
WHERE n.code IN ('80967001', 'K02.9')
GROUP BY n.code;

-- 7d Ampliación (no la pide el enunciado): toda la caries, padre + descendientes.
-- 7a solo cuenta filas con condition_concept_id = 133228 exacto; los subtipos
-- (p. ej. 45757234 'penetrating into dentin') se guardan con su propio ID.
-- concept_ancestor trae la jerarquía; incluye el par (133228, 133228) con
-- distancia 0, así que el padre entra sin OR. Equivale a "include
-- descendants" de un concept set en ATLAS. Esperado: 5,482 filas, 3,636
-- personas, 9 conceptos (frente a 4,721 / 3,297 / 1 de 7a).
SELECT count(*)                               AS filas,
       count(DISTINCT co.person_id)           AS personas,
       count(DISTINCT co.condition_concept_id) AS conceptos
FROM cdm.condition_occurrence co
JOIN cdm.concept_ancestor ca ON ca.descendant_concept_id = co.condition_concept_id
WHERE ca.ancestor_concept_id = 133228;

-- =====================================================================
-- Actividad 8. Respetar OBSERVATION_PERIOD (decisión 26, opción A)
-- "Dentro" = condition_start_date BETWEEN inicio AND fin del periodo, regla
-- estricta de ATLAS y del Data Quality Dashboard. Se usa LEFT JOIN para que
-- un evento de una persona sin periodo no desaparezca: contaría como fuera.
-- observation_period tiene 1 fila por persona (act. 6), así que el JOIN no
-- multiplica filas (control: total = 101,699).
-- =====================================================================
-- 8a Sin filtrar, dentro, fuera y % de diferencia
SELECT count(*)                                                       AS sin_filtrar,
       count(*) FILTER (WHERE co.condition_start_date
             BETWEEN op.observation_period_start_date
                 AND op.observation_period_end_date)                  AS dentro,
       count(*) FILTER (WHERE co.condition_start_date
             < op.observation_period_start_date)                      AS antes_del_inicio,
       count(*) FILTER (WHERE co.condition_start_date
             > op.observation_period_end_date)                        AS despues_del_fin,
       count(*) FILTER (WHERE op.person_id IS NULL)                   AS sin_periodo,
       -- % fuera = (total - dentro) / total. No se usa NOT BETWEEN: con un
       -- periodo NULL daría NULL y ese evento no contaría como fuera.
       round(100.0 * (count(*) - count(*) FILTER (WHERE co.condition_start_date
             BETWEEN op.observation_period_start_date
                 AND op.observation_period_end_date)) / count(*), 2)  AS pct_fuera
FROM cdm.condition_occurrence co
LEFT JOIN cdm.observation_period op ON op.person_id = co.person_id;

-- 8b Diagnóstico de los que quedan fuera: ¿cuántos días antes y en qué
-- visita? Si todos son 1 día antes y en la primera visita, apunta al
-- desfase de zona horaria de Synthea (encuentros en UTC, condiciones en
-- fecha local); la columna tolerancia_1_dia es el control de esa causa.
SELECT op.observation_period_start_date - co.condition_start_date      AS dias_antes,
       count(*)                                                       AS filas,
       count(DISTINCT co.person_id)                                   AS personas,
       count(*) FILTER (WHERE v.visit_start_date
                              = op.observation_period_start_date)     AS en_primera_visita,
       (SELECT count(*) FROM cdm.condition_occurrence c2
          JOIN cdm.observation_period o2 ON o2.person_id = c2.person_id
         WHERE c2.condition_start_date BETWEEN o2.observation_period_start_date - 1
                                           AND o2.observation_period_end_date) AS tolerancia_1_dia
FROM cdm.condition_occurrence co
JOIN cdm.observation_period op ON op.person_id = co.person_id
LEFT JOIN cdm.visit_occurrence v ON v.visit_occurrence_id = co.visit_occurrence_id
WHERE co.condition_start_date < op.observation_period_start_date
GROUP BY 1
ORDER BY 1;

-- =====================================================================
-- Actividad 9. Los tres conceptos más usados, vistos desde la base local
-- (decisiones 27-28). Sirve para comparar contra ATHENA: la base solo tiene
-- los vocabularios descargados, ATHENA tiene todos (p. ej. OMOP Extension y
-- SNOMED Veterinary no están aquí). "Hijos" = descendientes estándar a
-- distancia 1 en concept_ancestor; también todos los descendientes (nivel > 0,
-- se excluye el propio concepto, que está a distancia 0).
-- =====================================================================
SELECT c.concept_id, c.concept_name, c.vocabulary_id, c.domain_id,
       c.concept_class_id, c.standard_concept,
       (SELECT count(*) FROM cdm.concept_ancestor a
         WHERE a.ancestor_concept_id = c.concept_id
           AND a.min_levels_of_separation = 1)                    AS hijos_directos,
       (SELECT count(*) FROM cdm.concept_ancestor a
         WHERE a.ancestor_concept_id = c.concept_id
           AND a.min_levels_of_separation > 0)                    AS descendientes,
       -- códigos de origen con 'Maps to' hacia el concepto (sin el
       -- auto-mapeo del propio concepto estándar), agrupados por vocabulario
       (SELECT string_agg(s.vocabulary_id || ' ' || s.concept_code, ', '
                          ORDER BY s.vocabulary_id, s.concept_code)
          FROM cdm.concept_relationship r
          JOIN cdm.concept s ON s.concept_id = r.concept_id_1
         WHERE r.concept_id_2 = c.concept_id
           AND r.relationship_id = 'Maps to'
           AND r.invalid_reason IS NULL
           AND r.concept_id_1 <> r.concept_id_2)                  AS origenes_maps_to
FROM cdm.concept c
WHERE c.concept_id IN (133228, 320128, 4281516)
ORDER BY c.concept_id;

-- =====================================================================
-- Actividad 10. Comparación con dos CDM de referencia (decisiones 30-32)
-- ref_gibleed: GiBleed 5.3 (Synthea vía ETL-Synthea, 2019, recortado).
-- ref_mimic:   MIMIC-IV demo 5.3 (100 pacientes reales de UCI, fechas
--              desplazadas a los 2100 para anonimizar).
-- Carga: referencia/cargar_referencia.sh. Son las consultas de la act. 6,
-- pero con una columna `base` y las tres bases apiladas con UNION ALL, para
-- obtener la tabla comparativa de una vez. Los nombres salen siempre de
-- cdm.concept (decisión 31): el concept de MIMIC solo trae conceptos locales.
-- =====================================================================
-- 10a Personas, sexo y año de nacimiento
WITH personas AS (
    SELECT 'lab' AS base, person_id, gender_concept_id, year_of_birth FROM cdm.person
    UNION ALL
    SELECT 'gibleed', person_id, gender_concept_id, year_of_birth FROM ref_gibleed.person
    UNION ALL
    SELECT 'mimic', person_id, gender_concept_id, year_of_birth FROM ref_mimic.person)
SELECT p.base,
       count(*)                                                     AS filas,   -- control: = personas
       count(DISTINCT p.person_id)                                  AS personas,
       round(100.0 * count(DISTINCT p.person_id) FILTER (WHERE c.concept_name = 'FEMALE')
             / count(DISTINCT p.person_id), 1)                      AS pct_mujeres,
       count(*) FILTER (WHERE c.concept_id IS NULL)                 AS sexo_sin_nombre,
       min(p.year_of_birth)                                         AS nac_min,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY p.year_of_birth) AS nac_mediana,
       max(p.year_of_birth)                                         AS nac_max
FROM personas p
LEFT JOIN cdm.concept c ON c.concept_id = p.gender_concept_id
GROUP BY p.base
ORDER BY personas DESC;

-- 10b Días de observación por periodo (como 6.2). En GiBleed hay 2,649
-- periodos de personas que no existen en person (decisión 30): se muestran
-- las dos versiones, todos los periodos y solo los de personas existentes.
WITH periodos AS (
    SELECT 'lab' AS base, op.person_id, observation_period_end_date - observation_period_start_date AS dias,
           EXISTS (SELECT 1 FROM cdm.person p WHERE p.person_id = op.person_id) AS persona_existe
      FROM cdm.observation_period op
    UNION ALL
    SELECT 'gibleed', op.person_id, observation_period_end_date - observation_period_start_date,
           EXISTS (SELECT 1 FROM ref_gibleed.person p WHERE p.person_id = op.person_id)
      FROM ref_gibleed.observation_period op
    UNION ALL
    SELECT 'mimic', op.person_id, observation_period_end_date - observation_period_start_date,
           EXISTS (SELECT 1 FROM ref_mimic.person p WHERE p.person_id = op.person_id)
      FROM ref_mimic.observation_period op)
SELECT base,
       CASE WHEN persona_existe THEN 'persona existe' ELSE 'huérfano' END AS periodo,
       count(*)                                                    AS periodos,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY dias)           AS mediana_dias,
       round((percentile_cont(0.5) WITHIN GROUP (ORDER BY dias) / 365.25)::numeric, 1) AS mediana_anios,
       percentile_cont(0.25) WITHIN GROUP (ORDER BY dias)          AS p25_dias,
       percentile_cont(0.75) WITHIN GROUP (ORDER BY dias)          AS p75_dias,
       count(*) FILTER (WHERE dias = 0)                            AS con_cero_dias
FROM periodos
GROUP BY base, persona_existe
ORDER BY base, periodo DESC;

-- 10c Top 20 de diagnósticos por base (como 6.3: personas distintas por
-- concepto estándar, % sobre toda la población de esa base). row_number()
-- numera dentro de cada base (PARTITION BY) y se filtra después: el filtro
-- sobre una ventana necesita una subconsulta porque WHERE se evalúa antes.
WITH cond AS (
    SELECT 'lab' AS base, person_id, condition_concept_id FROM cdm.condition_occurrence
    UNION ALL SELECT 'gibleed', person_id, condition_concept_id FROM ref_gibleed.condition_occurrence
    UNION ALL SELECT 'mimic',   person_id, condition_concept_id FROM ref_mimic.condition_occurrence),
pob AS (
    SELECT 'lab' AS base, count(DISTINCT person_id) AS n FROM cdm.person
    UNION ALL SELECT 'gibleed', count(DISTINCT person_id) FROM ref_gibleed.person
    UNION ALL SELECT 'mimic',   count(DISTINCT person_id) FROM ref_mimic.person),
ranking AS (
    SELECT c.base, c.condition_concept_id,
           count(DISTINCT c.person_id) AS personas, count(*) AS registros,
           row_number() OVER (PARTITION BY c.base
                              ORDER BY count(DISTINCT c.person_id) DESC, count(*) DESC) AS puesto
    FROM cond c
    GROUP BY c.base, c.condition_concept_id)
SELECT r.base, r.puesto, k.concept_name AS diagnostico, r.personas,
       round(100.0 * r.personas / p.n, 1) AS pct_poblacion, r.registros
FROM ranking r
JOIN pob p ON p.base = r.base
LEFT JOIN cdm.concept k ON k.concept_id = r.condition_concept_id
WHERE r.puesto <= 20
ORDER BY r.base, r.puesto;

-- 10d Visitas por persona y por tipo (como 6.4): rejilla persona × tipo de
-- su propia base con LEFT JOIN, para que los ceros cuenten; denominador =
-- todas las personas de la base. Se cuenta visit_occurrence_id, no filas.
WITH personas AS (
    SELECT 'lab' AS base, person_id FROM cdm.person
    UNION ALL SELECT 'gibleed', person_id FROM ref_gibleed.person
    UNION ALL SELECT 'mimic',   person_id FROM ref_mimic.person),
visitas AS (
    SELECT 'lab' AS base, person_id, visit_concept_id, visit_occurrence_id FROM cdm.visit_occurrence
    UNION ALL SELECT 'gibleed', person_id, visit_concept_id, visit_occurrence_id FROM ref_gibleed.visit_occurrence
    UNION ALL SELECT 'mimic',   person_id, visit_concept_id, visit_occurrence_id FROM ref_mimic.visit_occurrence),
tipos AS (SELECT DISTINCT base, visit_concept_id FROM visitas),
rejilla AS (
    SELECT p.base, p.person_id, t.visit_concept_id, count(v.visit_occurrence_id) AS n
    FROM personas p
    JOIN tipos t ON t.base = p.base
    LEFT JOIN visitas v ON v.base = p.base AND v.person_id = p.person_id
                       AND v.visit_concept_id = t.visit_concept_id
    GROUP BY p.base, p.person_id, t.visit_concept_id)
SELECT r.base, coalesce(k.concept_name, r.visit_concept_id::text) AS tipo_visita,
       count(DISTINCT r.person_id) AS personas_denominador, sum(r.n) AS visitas,
       round(avg(r.n), 2) AS media_por_persona,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY r.n) AS mediana,
       count(DISTINCT r.person_id) FILTER (WHERE r.n = 0) AS personas_con_cero
FROM rejilla r
LEFT JOIN cdm.concept k ON k.concept_id = r.visit_concept_id
GROUP BY r.base, k.concept_name, r.visit_concept_id
ORDER BY r.base, visitas DESC;
