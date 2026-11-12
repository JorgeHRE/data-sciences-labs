-- =====================================================================
-- Concept set: HbA1c (hemoglobina glucosilada)
-- =====================================================================
-- Qué define:   todo código LOINC que mide la fracción de HbA1c sobre la
--               hemoglobina total, sea cual sea el método o la escala
--               (%, mmol/mol IFCC, fracción decimal).
-- Vocabulario:  LOINC 2.82 (release OMOP v5.0 29-AUG-26), Postgres del lab 12,
--               esquema cdm. Construido y verificado el 2026-11-12.
-- Devuelve:     8 conceptos estándar. En la base solo 4548-4 tiene datos
--               (58,969 mediciones, 2,565 pacientes).
-- Construcción: por regla sobre los ejes LOINC (concept_relationship
--               'Has component'), no con una lista de ids:
--               Component que empieza por «Hemoglobin A1c/Hemoglobin.total»
--               + clase Lab Test.
-- Decisiones (DECISIONES.md, 8 y 13):
--   - Entran las variantes por método (HPLC 17856-6, electroforesis 4549-2,
--     JDS/JSCC 62388-4), calculada (17855-8) y gota seca (96595-4).
--   - Entran 59261-8 (IFCC, mmol/mol) y 71875-9 (decimal): misma cantidad en
--     otra escala; ANTES de promediar convertir a %:
--       NGSP % = 0.0915 · IFCC + 2.15      ;      % = decimal · 100
--   - Queda fuera 41995-2 (masa/volumen): la regla la excluye sola porque su
--     Component es «Hemoglobin A1c» sin «/Hemoglobin.total»; depende de la Hb
--     total y no se puede convertir a %.
--   - Queda fuera 86910-7 (meta o goal de HbA1c): la excluye la clase, es
--     Clinical Observation, no una medición.
--   - Se descartó el LOINC Group LG51070-7: solo agrupa 4 de los 8.
-- =====================================================================
SELECT c.concept_id, c.concept_code, c.concept_name, comp.concept_name AS component
FROM cdm.concept c
JOIN cdm.concept_relationship r ON r.concept_id_1 = c.concept_id
                               AND r.relationship_id = 'Has component'
                               AND r.invalid_reason IS NULL
JOIN cdm.concept comp ON comp.concept_id = r.concept_id_2
WHERE c.vocabulary_id = 'LOINC'
  AND c.standard_concept = 'S'
  AND c.invalid_reason IS NULL
  AND c.concept_class_id = 'Lab Test'
  AND comp.concept_name ILIKE 'Hemoglobin A1c/Hemoglobin.total%'
ORDER BY c.concept_code;
