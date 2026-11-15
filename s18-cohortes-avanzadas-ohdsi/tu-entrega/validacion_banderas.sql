-- Validación de las banderas contra results.cohort (lab 17). Se concatena
-- después del bloque de banderas:
--   cat <(sed -n '/^-- \[INICIO banderas\]/,/^-- \[FIN banderas\]/p' atricion.sql) validacion_banderas.sql | psql ...
-- Los mismos conteos no prueban las mismas PERSONAS: se compara la tupla
-- (cohorte, persona, fecha índice) en los dos sentidos con EXCEPT.
-- Qué es EXCEPT: filas del primer SELECT que no están en el segundo.
-- Resultado esperado (2026-11-15), 1701 y 1702: solo_banderas 0, solo_lab17 0,
-- en_ambas = 122 y 81 (el N final de cada cohorte).
, finales AS (
    SELECT cohort_definition_id, person_id, fecha_indice
    FROM banderas
    WHERE f_estudio AND f_obs AND f_lavado AND f_adulto AND f_hta
      AND f_visitas AND f_sin_demencia AND f_sin_otro AND f_sin_combo
),
lab17 AS (
    SELECT cohort_definition_id, subject_id AS person_id, cohort_start_date AS fecha_indice
    FROM results.cohort
    WHERE cohort_definition_id IN (1701, 1702)
)
SELECT c.cohort_definition_id AS cohorte,
       (SELECT count(*) FROM (SELECT * FROM finales f WHERE f.cohort_definition_id = c.cohort_definition_id
                              EXCEPT SELECT * FROM lab17) x) AS solo_banderas,
       (SELECT count(*) FROM (SELECT * FROM lab17 l WHERE l.cohort_definition_id = c.cohort_definition_id
                              EXCEPT SELECT * FROM finales) y) AS solo_lab17,
       (SELECT count(*) FROM (SELECT * FROM finales f WHERE f.cohort_definition_id = c.cohort_definition_id
                              INTERSECT SELECT * FROM lab17) z) AS en_ambas
FROM (VALUES (1701), (1702)) c(cohort_definition_id)
ORDER BY 1;
