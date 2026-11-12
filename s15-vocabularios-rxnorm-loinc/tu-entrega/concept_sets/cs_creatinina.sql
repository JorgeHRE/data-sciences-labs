-- =====================================================================
-- Concept set: creatinina (Creatinine), medición puntual cuantitativa en sangre o suero/plasma
-- =====================================================================
-- Qué define:   todo código LOINC de creatinina medida en una muestra puntual,
--               como valor numérico, en sangre total o en suero/plasma, sea
--               en masa/volumen o en moles/volumen.
-- Vocabulario:  LOINC 2.82 (release OMOP v5.0 29-AUG-26), Postgres del lab 12,
--               esquema cdm. Construido y verificado el 2026-11-12.
-- Devuelve:     5 conceptos estándar. En uso en la base: 38483-4 (sangre, 69,106) y 2160-0 (suero/plasma, 49,484)
--               = 118,590 mediciones (24,827 persona-días tienen ambos).
-- Construcción: por regla sobre los ejes LOINC (concept_relationship «Has …»):
--               Component = Creatinine, System ∈ {Blood, Serum or Plasma},
--               Time = Point in time, Scale = Qn, clase Lab Test.
-- Decisiones (DECISIONES.md, 9 y 13):
--   - Entran ambos System, como en la auditoría de la actividad 7: un
--     analista que dice «creatinina» junta los dos códigos en uso.
--   - Entran los códigos en moles/volumen: misma cantidad, se convierten con
--     un factor. ANTES de promediar: 14682-9, 59826-8 y 103616-9 (µmol/L; el último por LC/MS/MS): mg/dL = µmol/L ÷ 88.4.
--   - Ojo al analizar: 38483-4 es bimodal por ERC (no por unidades) y tiene
--     232 valores ≥ 40 mg/dL implausibles (auditoria_unidades.md); los dos
--     códigos en uso se comportan como variables distintas en Synthea.
-- =====================================================================
WITH ejes AS (      -- 1 fila por código LOINC con sus ejes pivotados (como 5a)
    SELECT c.concept_id, c.concept_code, c.concept_name,
           max(e.concept_name) FILTER (WHERE r.relationship_id = 'Has component')   AS component,
           max(e.concept_name) FILTER (WHERE r.relationship_id = 'Has property')    AS property,
           max(e.concept_name) FILTER (WHERE r.relationship_id = 'Has time aspect') AS time_aspect,
           max(e.concept_name) FILTER (WHERE r.relationship_id = 'Has system')      AS system,
           max(e.concept_name) FILTER (WHERE r.relationship_id = 'Has scale type')  AS scale
    FROM cdm.concept c
    JOIN cdm.concept_relationship r ON r.concept_id_1 = c.concept_id
                                   AND r.relationship_id LIKE 'Has %'
                                   AND r.invalid_reason IS NULL
    JOIN cdm.concept e ON e.concept_id = r.concept_id_2
    WHERE c.vocabulary_id = 'LOINC'
      AND c.standard_concept = 'S'
      AND c.invalid_reason IS NULL
      AND c.concept_class_id = 'Lab Test'
    GROUP BY c.concept_id, c.concept_code, c.concept_name
)
SELECT concept_id, concept_code, concept_name, property, system
FROM ejes
WHERE component = 'Creatinine'
  AND system IN ('Blood', 'Serum or Plasma')
  AND time_aspect = 'Point in time (spot)'
  AND scale = 'Qn'
  AND concept_name NOT LIKE '%--%'      -- sin desafíos ni momentos posdosis
ORDER BY property, system, concept_code;
