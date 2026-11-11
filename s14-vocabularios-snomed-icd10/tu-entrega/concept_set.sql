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
