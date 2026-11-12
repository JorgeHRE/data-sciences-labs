-- =====================================================================
-- Concept set: exposición a metformina, versión A (un solo ingrediente)
-- =====================================================================
-- Qué define:   productos cuyo ÚNICO ingrediente es metformina. «Un solo
--               ingrediente» describe la pastilla, no al paciente: quien toma
--               metformina y otro fármaco en pastillas separadas sigue en A.
-- Vocabulario:  RxNorm 20260601 (release OMOP v5.0 29-AUG-26), Postgres del
--               lab 12, esquema cdm. Construido y verificado el 2026-11-12.
-- Devuelve:     83 conceptos estándar. En la base: 231 pacientes.
-- Construcción: por jerarquía: descendientes estándar de metformin (1503297,
--               como en cs_metformina_b.sql) que tienen exactamente UN ancestro
--               de clase Ingredient en RxNorm.
-- Decisiones (DECISIONES.md, 6 y 13):
--   - Contar ancestros Ingredient (y no buscar «/» en el nombre) es la forma
--     robusta de detectar combinaciones: no depende del texto.
-- =====================================================================
WITH b AS (
    SELECT c.concept_id
    FROM cdm.concept_ancestor a
    JOIN cdm.concept c ON c.concept_id = a.descendant_concept_id
    WHERE a.ancestor_concept_id = 1503297       -- metformin (RxCUI 6809)
      AND c.standard_concept = 'S'
)
SELECT c.concept_id, c.concept_name, c.concept_class_id
FROM b
JOIN cdm.concept_ancestor a ON a.descendant_concept_id = b.concept_id
JOIN cdm.concept i ON i.concept_id = a.ancestor_concept_id
                  AND i.vocabulary_id = 'RxNorm' AND i.concept_class_id = 'Ingredient'
JOIN cdm.concept c ON c.concept_id = b.concept_id
GROUP BY c.concept_id, c.concept_name, c.concept_class_id
HAVING count(*) = 1                             -- un solo ingrediente
ORDER BY c.concept_class_id, c.concept_name;
