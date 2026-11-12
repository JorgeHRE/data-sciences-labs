-- =====================================================================
-- Concept set: exposición a metformina, versión B (combinaciones incluidas)
-- =====================================================================
-- Qué define:   todo producto que contiene metformina, solo o combinado con
--               otros ingredientes.
-- Vocabulario:  RxNorm 20260601 (release OMOP v5.0 29-AUG-26), Postgres del
--               lab 12, esquema cdm. Construido y verificado el 2026-11-12.
-- Devuelve:     400 conceptos estándar. En la base: 231 pacientes (un solo
--               producto en uso, 24 HR metformin 500 MG ER, monocomponente).
-- Construcción: por jerarquía: descendientes del ingrediente RxNorm metformin
--               (concept_id 1503297, RxCUI 6809) en concept_ancestor.
-- Decisiones (DECISIONES.md, 6 y 13):
--   - Solo conceptos estándar ('S'): los Clinical Dose Group ('C') son
--     agrupadores de clasificación y no aparecen en drug_exposure.
--   - El nivel 0 de concept_ancestor (el propio ingrediente) se incluye: hay
--     registros que apuntan directo a un Ingredient (decisión 4).
--   - Es la versión de sensibilidad: incluye las combinaciones con iSGLT2,
--     que la versión C excluye.
-- =====================================================================
SELECT c.concept_id, c.concept_name, c.concept_class_id
FROM cdm.concept_ancestor a
JOIN cdm.concept c ON c.concept_id = a.descendant_concept_id
WHERE a.ancestor_concept_id = 1503297          -- metformin (RxCUI 6809)
  AND c.standard_concept = 'S'
ORDER BY c.concept_class_id, c.concept_name;
