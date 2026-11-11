-- =====================================================================
-- Lab 14 — Construir y defender un concept set (SNOMED CT e ICD-10-CM)
-- Base: Postgres del lab 12 (contenedor lab12-omop-db-1, BD omop_lab12).
-- El esquema cdm es de solo lectura: este archivo no modifica nada.
-- Ejecutar completo:
--   docker exec -i lab12-omop-db-1 psql -U <usuario> -d omop_lab12 \
--     -v ON_ERROR_STOP=1 < concept_set.sql
-- Recordatorio del orden lógico de ejecución de un SELECT:
--   FROM → WHERE → GROUP BY → HAVING → SELECT → ORDER BY
-- =====================================================================

-- Paso 0a. Tamaño del vocabulario. Por qué: un vocabulario cargado a
-- medias produce concept sets que parecen correctos y no lo son.
-- Esperado: concept_relationship 14,138,100 · concept_ancestor 12,077,497 ·
-- SNOMED 1,106,309 (356,613 estándar) · ICD10CM 100,273 (0 estándar).
SELECT 'concept_relationship' AS objeto, count(*) AS filas, NULL::bigint AS estandar
FROM cdm.concept_relationship
UNION ALL SELECT 'concept_ancestor', count(*), NULL FROM cdm.concept_ancestor
UNION ALL
SELECT 'concept ' || vocabulary_id, count(*),
       count(*) FILTER (WHERE standard_concept = 'S')
FROM cdm.concept
WHERE vocabulary_id IN ('SNOMED', 'ICD10CM')
GROUP BY vocabulary_id;

-- Paso 0b. ¿concept_ancestor está completo? Por qué: el tamaño no basta.
-- Cada arista directa «Is a» entre dos SNOMED estándar debe tener su
-- pareja ancestro-descendiente en concept_ancestor. Esperado: 587,392
-- aristas y 0 sin pareja. El LEFT JOIN deja a la vista las que faltan
-- (quedarían con NULL); con un JOIN normal desaparecerían sin avisar.
SELECT count(*)                                         AS aristas_is_a,
       count(*) FILTER (WHERE ca.ancestor_concept_id IS NULL) AS sin_pareja
FROM cdm.concept_relationship r
JOIN cdm.concept hijo  ON hijo.concept_id  = r.concept_id_1
                      AND hijo.vocabulary_id  = 'SNOMED' AND hijo.standard_concept  = 'S'
JOIN cdm.concept padre ON padre.concept_id = r.concept_id_2
                      AND padre.vocabulary_id = 'SNOMED' AND padre.standard_concept = 'S'
LEFT JOIN cdm.concept_ancestor ca
       ON ca.ancestor_concept_id   = r.concept_id_2
      AND ca.descendant_concept_id = r.concept_id_1
WHERE r.relationship_id = 'Is a';

-- =====================================================================
-- Actividad 1. Condición elegida: diabetes mellitus tipo 2 (SNOMED 201826).
-- Antes de comprometerse: ¿hay suficientes pacientes (≥ ~50)?
-- Por qué pacientes distintos y no filas: un diabético con 30 visitas
-- genera 30 filas en condition_occurrence, pero es UN paciente.
-- Se cuenta el concepto exacto y con descendientes (concept_ancestor
-- incluye la semilla a distancia 0) para ver ya si la jerarquía añade
-- pacientes. Orden lógico: FROM → WHERE → SELECT.
-- =====================================================================
SELECT 'exacto' AS alcance,
       count(*)                     AS filas,
       count(DISTINCT co.person_id) AS pacientes
FROM cdm.condition_occurrence co
WHERE co.condition_concept_id = 201826
UNION ALL
SELECT 'con descendientes',
       count(*),
       count(DISTINCT co.person_id)
FROM cdm.condition_occurrence co
-- IN (subconsulta) y no JOIN: solo pregunta "¿está en la lista?", así que
-- no puede duplicar filas aunque la lista tuviera repetidos.
WHERE co.condition_concept_id IN (SELECT descendant_concept_id
                                  FROM cdm.concept_ancestor
                                  WHERE ancestor_concept_id = 201826);

-- =====================================================================
-- Actividad 2a. Las banderas de la semilla 201826.
-- Por qué: el concepto tiene que ser estándar ('S'), de dominio Condition
-- (si no, sus pacientes no están en condition_occurrence) y vigente
-- (invalid_reason NULL y valid_end_date en el futuro, típico 2099-12-31).
-- =====================================================================
SELECT concept_id, concept_name, domain_id, vocabulary_id, concept_class_id,
       standard_concept, invalid_reason, concept_code,
       valid_start_date, valid_end_date
FROM cdm.concept
WHERE concept_id = 201826;

-- Actividad 2b. Un nivel arriba y un nivel abajo.
-- min_levels_of_separation = 1 → padre o hijo directo. En SNOMED un
-- concepto puede tener VARIOS padres: más de una fila no es un error.
-- Esperado: 1 padre (201820 Diabetes mellitus) y 12 hijos directos.
SELECT 'padre' AS sentido, c.concept_id, c.concept_name
FROM cdm.concept_ancestor a
JOIN cdm.concept c ON c.concept_id = a.ancestor_concept_id
WHERE a.descendant_concept_id = 201826 AND a.min_levels_of_separation = 1
UNION ALL
SELECT 'hijo', c.concept_id, c.concept_name
FROM cdm.concept_ancestor a
JOIN cdm.concept c ON c.concept_id = a.descendant_concept_id
WHERE a.ancestor_concept_id = 201826 AND a.min_levels_of_separation = 1
ORDER BY sentido DESC, concept_name;

-- Actividad 2c. Número total de descendientes (cualquier distancia).
-- Se excluye la propia semilla, que es su ancestro a distancia 0.
-- Esperado: 14 (12 hijos + 2 nietos).
SELECT count(*) AS descendientes
FROM cdm.concept_ancestor
WHERE ancestor_concept_id = 201826
  AND descendant_concept_id <> 201826;
