-- =====================================================================
-- Concept set: glucosa (Glucose), medición puntual cuantitativa en sangre o suero/plasma
-- =====================================================================
-- Qué define:   todo código LOINC de glucosa medida en una muestra puntual,
--               como valor numérico, en sangre total o en suero/plasma, sea
--               en masa/volumen o en moles/volumen.
-- Vocabulario:  LOINC 2.82 (release OMOP v5.0 29-AUG-26), Postgres del lab 12,
--               esquema cdm. Construido y verificado el 2026-11-12.
-- Devuelve:     4 conceptos estándar. En uso en la base: 2339-0 (sangre, 69,106) y 2345-7 (suero/plasma, 49,484)
--               = 118,590 mediciones (24,827 persona-días tienen ambos).
-- Construcción: por regla sobre los ejes LOINC (concept_relationship «Has …»):
--               Component = Glucose, System ∈ {Blood, Serum or Plasma},
--               Time = Point in time, Scale = Qn, clase Lab Test.
-- Decisiones (DECISIONES.md, 9 y 13):
--   - Entran ambos System, como en la auditoría de la actividad 7: un
--     analista que dice «glucosa» junta los dos códigos en uso.
--   - Entran los códigos en moles/volumen: misma cantidad, se convierten con
--     un factor. ANTES de promediar: 14749-6 y 15074-8 (mmol/L): mg/dL = mmol/L · 18.016.
--   - Se excluyen los códigos con desafío o momento posdosis, que LOINC
--     marca en el nombre con «--» (aquí: 102019-7, glucosa 1.5 h tras
--     glucagón): son pruebas de estímulo, no glucosa basal. Se excluye por
--     regla sobre el nombre, no por id, y se revisó a mano que solo atrapa ese.
--   - Ojo al analizar: en datos reales la glucosa en sangre total da ~11 %
--     menos que en plasma; no promediar ambos System sin decidirlo.
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
WHERE component = 'Glucose'
  AND system IN ('Blood', 'Serum or Plasma')
  AND time_aspect = 'Point in time (spot)'
  AND scale = 'Qn'
  AND concept_name NOT LIKE '%--%'      -- sin desafíos ni momentos posdosis
ORDER BY property, system, concept_code;
