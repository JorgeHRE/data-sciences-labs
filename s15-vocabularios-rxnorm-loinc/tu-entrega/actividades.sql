-- =====================================================================
-- Lab 15 — Consultas de exploración por actividad
-- Base: Postgres del lab 12 (lab12-omop-db-1, BD omop_lab12), solo lectura.
-- Vocabulario: v5.0 29-AUG-26 · RxNorm 20260601 · ATC 2026-02-01 · LOINC 2.82
-- Los concept sets finales van en concept_sets/ (actividad 9).
-- Orden lógico de un SELECT: FROM → WHERE → GROUP BY → HAVING → SELECT → ORDER BY
-- =====================================================================

-- Actividad 1b. Los conteos de RxNav (SCDF y BN), pero en nuestra base.
-- RxCUI = concept.concept_code. Desde el ingrediente:
--   'RxNorm ing of'  → sus formas clínicas (SCDF, clase Clinical Drug Form)
--   'Has brand name' → sus marcas (BN, clase Brand Name; no estándar)
-- Combinación = el SCDF o la marca está ligado a MÁS DE UN ingrediente.
-- Se cuenta con una subconsulta (cuántos IN apuntan a ese concepto) y no
-- con un JOIN a los ingredientes, que daría una fila por ingrediente y
-- contaría dos veces cada combinación (Trampa 2 de la actividad 2).
-- Esperado: 6 filas (RxNav del 2026-11-11 entre corchetes):
--   metformina     SCDF 26 [21] (4 solas / 22 comb.) · BN 23 [14] (7 / 16)
--   lisinopril     SCDF  3 [3]  (2 / 1)              · BN  8 [4]  (4 / 4)
--   empagliflozina SCDF  5 [5]  (1 / 4)              · BN  4 [4]  (1 / 3)
-- La base tiene más porque conserva productos que RxNorm ya marcó como
-- Obsolete (retirados del mercado de EE. UU.; p. ej. Fortamet, Avandamet).
WITH ingr AS (
    SELECT concept_id, concept_code AS rxcui, concept_name
    FROM cdm.concept
    WHERE vocabulary_id = 'RxNorm' AND concept_class_id = 'Ingredient'
      AND concept_code IN ('6809', '29046', '1545653')
),
ligados AS (           -- una fila por (ingrediente, SCDF o marca)
    SELECT i.concept_name AS ingrediente, i.rxcui, c.concept_id,
           c.concept_class_id,
           (SELECT count(*)                       -- ¿cuántos IN lo comparten?
            FROM cdm.concept_relationship r2
            JOIN cdm.concept i2 ON i2.concept_id = r2.concept_id_1
            WHERE r2.concept_id_2 = c.concept_id
              AND r2.relationship_id = r.relationship_id
              -- solo flechas que salen de un Ingredient: a una marca
              -- también apuntan con 'Has brand name' todos sus productos
              -- (Synjardy: 24 flechas, solo 2 de ingredientes)
              AND i2.concept_class_id = 'Ingredient') AS n_ingr
    FROM ingr i
    JOIN cdm.concept_relationship r ON r.concept_id_1 = i.concept_id
     AND r.relationship_id IN ('RxNorm ing of', 'Has brand name')
    JOIN cdm.concept c ON c.concept_id = r.concept_id_2
     AND c.concept_class_id IN ('Clinical Drug Form', 'Brand Name')
)
SELECT ingrediente, rxcui, concept_class_id,
       count(*)                            AS total,
       count(*) FILTER (WHERE n_ingr = 1)  AS un_ingrediente,
       count(*) FILTER (WHERE n_ingr > 1)  AS combinaciones
FROM ligados
GROUP BY ingrediente, rxcui, concept_class_id
ORDER BY ingrediente, concept_class_id DESC;
