-- =====================================================================
-- Lab 16 — Jerarquías en acción: concept_relationship y concept_ancestor
-- Base: Postgres del lab 12 (lab12-omop-db-1), esquema cdm de solo lectura.
-- Vocabulario: v5.0 29-AUG-26 (SNOMED, RxNorm, ATC, LOINC de ATHENA).
-- Motor de los EXPLAIN ANALYZE (actividad 8): PostgreSQL.
-- Cada consulta va precedida de qué responde y qué se encontró.
-- Orden lógico de un SELECT: FROM → WHERE → GROUP BY → HAVING → SELECT → ORDER BY
-- =====================================================================

-- Control 0. ¿Están las cuatro tablas que pide el lab, y con qué índices?
-- Por qué: si concept_ancestor o relationship estuvieran vacías, las
-- actividades 2 y 3 «funcionarían» con 0 filas sin dar error. Los índices
-- se anotan ahora porque la actividad 8 compara planes y hay que saber
-- de qué índices se partía antes de crear ninguno.
-- Se usa count(*) real (no la estimación de pg_class) porque hay que
-- comparar contra cifras exactas; tarda ~1 s por los 12 M de concept_ancestor.
-- Resultado (2026-11-13), 4 filas, ~1.5 s:
--   concept               2,028,013 · concept_relationship  14,138,100
--   concept_ancestor     12,077,497 · relationship                  724
SELECT 'concept' AS tabla, count(*) AS filas FROM cdm.concept
UNION ALL SELECT 'concept_relationship', count(*) FROM cdm.concept_relationship
UNION ALL SELECT 'concept_ancestor', count(*) FROM cdm.concept_ancestor
UNION ALL SELECT 'relationship', count(*) FROM cdm.relationship;

-- Control 0b. Índices de las tablas que usará el lab.
-- Resultado: 7 filas. concept_ancestor indexada por ancestro y por
-- descendiente; concept_relationship por concept_id_2, relationship_id y
-- su PK (concept_id_1, concept_id_2, relationship_id), que empieza por
-- concept_id_1 y por eso también sirve para subir con 'Is a' (actividad 1);
-- condition_occurrence SOLO su PK: no hay índice en condition_concept_id.
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'cdm'
  AND tablename IN ('concept_ancestor', 'concept_relationship',
                    'relationship', 'condition_occurrence')
ORDER BY tablename, indexname;
