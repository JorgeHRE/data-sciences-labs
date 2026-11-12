-- =====================================================================
-- Concept set: exposición a metformina, versión C (B sin iSGLT2)
-- =====================================================================
-- Qué define:   productos con metformina (versión B) EXCEPTO los que además
--               contienen un inhibidor de SGLT2. Es la versión elegida para
--               estudiar el efecto de la metformina sobre la función renal.
-- Vocabulario:  RxNorm 20260601 y ATC 2026-02-01 (release OMOP v5.0
--               29-AUG-26), Postgres del lab 12, esquema cdm. Construido y
--               verificado el 2026-11-12.
-- Devuelve:     249 conceptos estándar (400 − 151 con iSGLT2). En la base:
--               231 pacientes.
-- Construcción: por jerarquía, en dos ramas:
--               B = descendientes de metformin (1503297);
--               excluidos = descendientes de los ingredientes RxNorm que
--               cuelgan de la clase ATC A10BK (iSGLT2).
-- Decisiones (DECISIONES.md, 6 y 13):
--   - Los iSGLT2 tienen efecto nefroprotector propio: mezclarían dos
--     exposiciones sobre el mismo desenlace.
--   - Se excluye por la CLASE ATC y no por nombres: recoge sola los iSGLT2
--     nuevos (sotagliflozina, bexagliflozina).
--   - Se conservan las combinaciones con iDPP-4, sulfonilureas, etc. (sin
--     efecto renal propio comparable) y la combinación obsoleta con ropinirol.
--   - Limitación: no ve los iSGLT2 tomados en pastillas separadas; eso exige
--     comparar fechas de exposición (sesión 17).
-- =====================================================================
WITH b AS (
    SELECT c.concept_id, c.concept_name, c.concept_class_id
    FROM cdm.concept_ancestor a
    JOIN cdm.concept c ON c.concept_id = a.descendant_concept_id
    WHERE a.ancestor_concept_id = 1503297       -- metformin (RxCUI 6809)
      AND c.standard_concept = 'S'
),
isglt2 AS (     -- todo lo que desciende de un ingrediente de ATC A10BK
    SELECT DISTINCT a2.descendant_concept_id AS concept_id
    FROM cdm.concept atc
    JOIN cdm.concept_ancestor a1 ON a1.ancestor_concept_id = atc.concept_id
    JOIN cdm.concept i ON i.concept_id = a1.descendant_concept_id
                      AND i.vocabulary_id = 'RxNorm' AND i.concept_class_id = 'Ingredient'
    JOIN cdm.concept_ancestor a2 ON a2.ancestor_concept_id = i.concept_id
    WHERE atc.vocabulary_id = 'ATC' AND atc.concept_code = 'A10BK'
)
SELECT b.concept_id, b.concept_name, b.concept_class_id
FROM b
WHERE b.concept_id NOT IN (SELECT concept_id FROM isglt2)
ORDER BY b.concept_class_id, b.concept_name;
