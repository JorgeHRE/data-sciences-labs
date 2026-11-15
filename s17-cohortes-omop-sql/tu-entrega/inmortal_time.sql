-- =====================================================================
-- Actividad 10. ¿Algún criterio usa información POSTERIOR al índice?
-- No corre solo: lee los CTE de cohorte_definicion.sql (hasta [CONTEO]) y
-- añade UN SELECT (un WITH vale para una sola sentencia). Se corre así:
--   sed -n '/^-- \[INICIO cohorte\]/,/^-- \[CONTEO\]/p' cohorte_definicion.sql \
--     | cat - inmortal_time.sql \
--     | docker exec -i lab12-omop-db-1 psql -U omop -d omop_lab12
-- La revisión de las ventanas (qué mira cada criterio) está en
-- cohorte_definicion.md; aquí van las dos comprobaciones con datos:
--  1. «pasan_criterios» (sin_combinacion) debe ser igual a «en_salida»:
--     si el JOIN de la salida con tramo_indice perdiera a alguien, la
--     cohorte dependería de lo que pasa DESPUÉS del índice (el tramo).
--  2. Cuánta gente depende del día 0, que no es «posterior» pero sí
--     ambiguo: el ETL no dice si el diagnóstico se anotó antes o después
--     de la receta del mismo día.
--       hta_solo_dia0      cumple la HTA solo por un registro del día 0
--       hta_en_dia0        tiene algún registro de HTA el día 0
--       demencia_solo_dia0 sale de la cohorte solo por demencia del día 0
--  3. dur_min: el seguimiento empieza el día del índice y nadie dura 0
--     días, así que no hay tiempo «inmortal» entre inicio de cohorte y
--     exposición.
-- EXISTS / NOT EXISTS correlacionados: son ~200 personas por cohorte
-- (las tablas cdm no tienen índice en person_id, pero con tan pocas
-- personas basta).
-- =====================================================================
SELECT a.cohorte, a.pasan_criterios, a.en_salida, a.hta_solo_dia0,
       a.hta_en_dia0, a.dur_min,
       b.excluidos_demencia, b.demencia_solo_dia0
FROM (
    SELECT s.cohort_definition_id AS cohorte,
           (SELECT count(*) FROM sin_combinacion c
            WHERE c.cohort_definition_id = s.cohort_definition_id) AS pasan_criterios,
           count(*) AS en_salida,
           count(*) FILTER (WHERE NOT EXISTS (
               SELECT 1 FROM cdm.condition_occurrence co
               JOIN cdm.concept_ancestor ca
                 ON ca.descendant_concept_id = co.condition_concept_id
               WHERE ca.ancestor_concept_id = 316866
                 AND co.person_id = s.person_id
                 AND co.condition_start_date < s.fecha_indice)) AS hta_solo_dia0,
           count(*) FILTER (WHERE EXISTS (
               SELECT 1 FROM cdm.condition_occurrence co
               JOIN cdm.concept_ancestor ca
                 ON ca.descendant_concept_id = co.condition_concept_id
               WHERE ca.ancestor_concept_id = 316866
                 AND co.person_id = s.person_id
                 AND co.condition_start_date = s.fecha_indice)) AS hta_en_dia0,
           min(s.fecha_salida - s.fecha_indice) AS dur_min
    FROM salida_motivo s
    GROUP BY s.cohort_definition_id
) a
JOIN (
    -- Se mira con_visitas (justo antes de la exclusión por demencia) para
    -- ver a quién quita ese criterio y si es solo por un registro del día 0.
    SELECT v.cohort_definition_id AS cohorte,
           count(*) FILTER (WHERE EXISTS (
               SELECT 1 FROM cdm.condition_occurrence co
               JOIN cdm.concept_ancestor ca
                 ON ca.descendant_concept_id = co.condition_concept_id
               WHERE ca.ancestor_concept_id = 4182210
                 AND co.person_id = v.person_id
                 AND co.condition_start_date <= v.fecha_indice)) AS excluidos_demencia,
           count(*) FILTER (WHERE EXISTS (
               SELECT 1 FROM cdm.condition_occurrence co
               JOIN cdm.concept_ancestor ca
                 ON ca.descendant_concept_id = co.condition_concept_id
               WHERE ca.ancestor_concept_id = 4182210
                 AND co.person_id = v.person_id
                 AND co.condition_start_date = v.fecha_indice)
             AND NOT EXISTS (
               SELECT 1 FROM cdm.condition_occurrence co
               JOIN cdm.concept_ancestor ca
                 ON ca.descendant_concept_id = co.condition_concept_id
               WHERE ca.ancestor_concept_id = 4182210
                 AND co.person_id = v.person_id
                 AND co.condition_start_date < v.fecha_indice)) AS demencia_solo_dia0
    FROM con_visitas v
    GROUP BY v.cohort_definition_id
) b USING (cohorte)
ORDER BY a.cohorte;
