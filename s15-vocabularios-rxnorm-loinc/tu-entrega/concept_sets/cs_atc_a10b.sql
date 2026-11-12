-- =====================================================================
-- Concept set: fármacos de la clase ATC A10B (hipoglucemiantes no insulínicos)
-- =====================================================================
-- Qué define:   todo producto que contiene algún ingrediente de la clase ATC
--               A10B «Blood glucose lowering drugs, excl. insulins», solo o
--               combinado (incluidas combinaciones con insulina).
-- Vocabulario:  ATC 2026-02-01 y RxNorm 20260601 (release OMOP v5.0
--               29-AUG-26), Postgres del lab 12, esquema cdm. Construido y
--               verificado el 2026-11-12.
-- Devuelve:     1,467 conceptos estándar, que cuelgan de 42 ingredientes.
--               En la base: 2 productos en uso (metformina ER 500 mg y
--               liraglutida), 231 pacientes.
-- Construcción: por jerarquía, en dos saltos de concept_ancestor:
--               ATC A10B → ingredientes RxNorm → sus descendientes estándar.
-- Decisiones (DECISIONES.md, 5, 14 y 13):
--   - A10B tal como la define ATC: incluye los GLP-1 inyectables (liraglutida,
--     semaglutida), aunque el enunciado hable de «orales» (decisión 5).
--   - Vía ingredientes y no por descendencia directa del ATC (que da 1,437):
--     la pregunta es de exposición. Entran así Xultophy y Soliqua (insulina +
--     GLP-1, que ATC clasifica como insulinas A10AE) (decisión 14).
--   - Limitación: entra la tolbutamida inyectable de uso diagnóstico
--     (prueba de insulinoma), que no es tratamiento.
--   - 22 de los 365 productos de la base no tienen ningún ancestro ATC
--     (19 vacunas CVX + 3 RxNorm): ninguna selección por ATC los ve (act. 3).
-- =====================================================================
WITH a10b_ingr AS (
    SELECT DISTINCT i.concept_id
    FROM cdm.concept atc
    JOIN cdm.concept_ancestor a ON a.ancestor_concept_id = atc.concept_id
    JOIN cdm.concept i          ON i.concept_id = a.descendant_concept_id
    WHERE atc.vocabulary_id = 'ATC' AND atc.concept_code = 'A10B'
      AND i.vocabulary_id = 'RxNorm' AND i.concept_class_id = 'Ingredient'
)
-- DISTINCT: una combinación de dos ingredientes de A10B (p. ej. metformina +
-- sitagliptina) cuelga de ambos y saldría dos veces.
SELECT DISTINCT c.concept_id, c.concept_name, c.concept_class_id
FROM a10b_ingr g
JOIN cdm.concept_ancestor a ON a.ancestor_concept_id = g.concept_id
JOIN cdm.concept c          ON c.concept_id = a.descendant_concept_id
WHERE c.standard_concept = 'S'
ORDER BY c.concept_class_id, c.concept_name;
