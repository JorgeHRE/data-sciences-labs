-- Impacto del intruso «Pre-eclampsia» (439393) en la cohorte. Se pega después
-- del bloque de banderas de atricion.sql (mismo uso que huerfanos_pa.sql).
-- Cuenta, entre quienes cumplen el criterio de hipertensión, a los que lo cumplen
-- SOLO por pre-eclampsia: su primera «Essential hypertension» (320128) es
-- posterior al índice o no existe. Se mira en tres puestos: entre las primeras
-- recetas, con índice desde 2017 y en la cohorte final.
-- min() FILTER por persona: una fila por persona, así el JOIN no multiplica
-- (1,522 / 1,104 antes y después).
-- Además, el huérfano «Eclampsia in pregnancy» (137613, 120 personas en la base,
-- fuera del set): cuántas de las personas que fallan SOLO el criterio de
-- hipertensión (las únicas a quienes incluirlo cambiaría la cohorte) tienen ese
-- código hasta el índice. Misma forma que hx: una fila por persona.
-- Resultado esperado (2026-11-15), 2 filas: todo 0 en 1701 y 1702.
, ecl AS (
    SELECT person_id, min(condition_start_date) AS f_eclampsia
    FROM cdm.condition_occurrence
    WHERE condition_concept_id = 137613
    GROUP BY person_id
),
hx AS (
    SELECT co.person_id,
           min(co.condition_start_date) FILTER (WHERE co.condition_concept_id = 320128) AS f_esencial
    FROM cdm.condition_occurrence co
    JOIN cdm.concept_ancestor ca ON ca.descendant_concept_id = co.condition_concept_id
                                AND ca.ancestor_concept_id = 316866
    GROUP BY co.person_id
)
SELECT b.cohort_definition_id AS cohorte,
       count(*) AS primeras_recetas,
       count(*) FILTER (WHERE b.f_hta) AS cumplen_hta,
       count(*) FILTER (WHERE b.f_hta AND (h.f_esencial IS NULL OR h.f_esencial > b.fecha_indice)) AS solo_preeclampsia,
       count(*) FILTER (WHERE b.f_hta AND b.f_estudio
                          AND (h.f_esencial IS NULL OR h.f_esencial > b.fecha_indice)) AS solo_preeclampsia_desde_2017,
       count(*) FILTER (WHERE b.f_estudio AND b.f_obs AND b.f_lavado AND b.f_adulto AND b.f_hta
                          AND b.f_visitas AND b.f_sin_demencia AND b.f_sin_otro AND b.f_sin_combo
                          AND (h.f_esencial IS NULL OR h.f_esencial > b.fecha_indice)) AS en_cohorte_final,
       count(*) FILTER (WHERE b.f_estudio AND b.f_obs AND b.f_lavado AND b.f_adulto AND NOT b.f_hta
                          AND b.f_visitas AND b.f_sin_demencia AND b.f_sin_otro AND b.f_sin_combo
                          AND e.f_eclampsia <= b.fecha_indice) AS solo_hta_con_eclampsia
FROM banderas b
LEFT JOIN hx h USING (person_id)
LEFT JOIN ecl e USING (person_id)
GROUP BY b.cohort_definition_id
ORDER BY b.cohort_definition_id;
