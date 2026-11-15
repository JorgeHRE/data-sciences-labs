-- =====================================================================
-- Lab 18 — Actividad 5. Incidencia de entrada por año calendario y por edad
-- Base: Postgres del lab 12. Solo lectura: lee results.cohort,
-- results.cohorte_parametros y cdm.*. Cada consulta corre sola:
--   docker exec -i lab12-omop-db-1 psql -U $POSTGRES_USER -d $POSTGRES_DB < incidencia.sql
-- Orden lógico de un SELECT: FROM → WHERE → GROUP BY → HAVING → SELECT → ORDER BY
-- Una incidencia = entradas / tiempo en que la gente podía entrar. Aquí se
-- devuelven numeradores y denominadores crudos; la tasa por 1,000 personas-año
-- se calcula en figura_incidencia.py (así los dos denominadores se ven lado a lado).
-- =====================================================================

-- [A] Por año calendario (2005-2026), cohorte 1701 (lisinopril).
-- Numeradores (decisión 11):
--   primeras = primera receta de lisinopril de toda la historia (evento inicial,
--              antes de cualquier criterio; los 1,522 del lab 17). Es donde se
--              ve el pico artificial, porque la cohorte final lo excluye (índice ≥ 2017).
--   n_1711   = cohorte 1711: todos los criterios clínicos, SIN inicio de estudio.
--   n_1701   = cohorte final (índice ≥ 2017-01-01).
-- Denominadores (dos, decisión 12), ambos por año:
--   py_op        = personas-año observadas según observation_period. Se suma el
--                  traslape de cada periodo con el año: min(fin+1, 1-ene del año
--                  siguiente) − max(inicio, 1-ene), en días / 365.25. Si no hay
--                  traslape el resultado sería negativo: greatest(0, ...).
--   pers_visita  = personas distintas con ≥ 1 visita en el año.
--   fraccion     = parte del año que los datos cubren: 1 salvo en el último año,
--                  que termina en la fecha de corte (el fin de periodo más tardío:
--                  2026-10-26). La tasa con visitas divide entre pers_visita ×
--                  fraccion: sin eso el año parcial parecería tener menos casos
--                  por persona de los reales (observación de 10 meses, no 12).
-- Los JOIN de cada denominador/numerador son por año (una fila por año en cada
-- lado), así que no multiplican filas: 22 años antes y después.
-- Resultado esperado (2026-11-15), 22 filas; por ejemplo:
--   2005: py_op 3,545 · visita 966 · primeras 7 · 1711 0 · 1701 0
--   2016: py_op 4,449 · visita 3,868 · primeras 665 · 1711 61 · 1701 0
--   2026: py_op 2,285 · visita 4,383 · fracción 0.82 · primeras 33 · 1711 8 · 1701 8
WITH anios AS (SELECT generate_series(2005, 2026) AS anio),
corte AS (SELECT max(observation_period_end_date) AS fecha FROM cdm.observation_period),
py AS (
    SELECT a.anio,
           sum(greatest(0, least(op.observation_period_end_date + 1, make_date(a.anio + 1, 1, 1))
                           - greatest(op.observation_period_start_date, make_date(a.anio, 1, 1)))) / 365.25 AS py_op
    FROM anios a
    CROSS JOIN cdm.observation_period op
    GROUP BY a.anio
),
visitas AS (
    SELECT extract(year FROM visit_start_date)::int AS anio, count(DISTINCT person_id) AS pers_visita
    FROM cdm.visit_occurrence
    GROUP BY 1
),
primeras AS (
    SELECT extract(year FROM f.fecha)::int AS anio, count(*) AS primeras
    FROM (SELECT d.person_id, min(d.drug_exposure_start_date) AS fecha
          FROM results.cohorte_parametros p
          JOIN cdm.concept_ancestor ca ON ca.ancestor_concept_id = p.ingrediente_exp
          JOIN cdm.drug_exposure d     ON d.drug_concept_id = ca.descendant_concept_id
          WHERE p.cohort_definition_id = 1701 AND d.drug_type_concept_id = 32838
          GROUP BY d.person_id) f
    GROUP BY 1
),
cohortes AS (
    SELECT extract(year FROM cohort_start_date)::int AS anio,
           count(*) FILTER (WHERE cohort_definition_id = 1711) AS n_1711,
           count(*) FILTER (WHERE cohort_definition_id = 1701) AS n_1701
    FROM results.cohort
    WHERE cohort_definition_id IN (1701, 1711)
    GROUP BY 1
)
SELECT a.anio,
       round(py.py_op::numeric, 1)                                       AS py_op,
       coalesce(v.pers_visita, 0)                                        AS pers_visita,
       round(least(1.0, (c.fecha - make_date(a.anio, 1, 1) + 1) / 365.25)::numeric, 3) AS fraccion,
       coalesce(pr.primeras, 0)                                          AS primeras,
       coalesce(co.n_1711, 0)                                            AS n_1711,
       coalesce(co.n_1701, 0)                                            AS n_1701
FROM anios a
CROSS JOIN corte c
JOIN py USING (anio)
LEFT JOIN visitas v   USING (anio)
LEFT JOIN primeras pr USING (anio)
LEFT JOIN cohortes co USING (anio)
ORDER BY a.anio;

-- [B] Por grupo de edad, 2017-2026 (el periodo de la cohorte final), cohorte 1701.
-- Edad = año calendario − year_of_birth, TANTO en el numerador (año del índice)
-- COMO en el denominador (cada año observado): la misma aproximación en los
-- dos lados mantiene consistente la tasa. (El lab 17 usó edad exacta en la
-- tabla 1; difiere en 58 de 203 personas, 1 cambia de grupo.)
-- Se cuentan solo adultos (≥ 18): el criterio de la cohorte los exige, así que
-- los menores no están en riesgo de entrar y no deben estar en el denominador.
--   py_op     = personas-año de observation_period en el grupo, 2017-2026.
--   py_visita = personas-año con ≥ 1 visita (cada persona-año cuenta 1, o la
--               fracción de año cubierta por los datos en 2026).
--   entradas  = personas de 1701 cuyo índice cae en el grupo.
-- Un JOIN por persona (person tiene 1 fila por persona) y por grupo (cada edad
-- cae en UN grupo): no multiplica filas. Control: suma de entradas = 122.
-- Resultado esperado (2026-11-15), 6 filas (entradas 34 · 24 · 21 · 19 · 16 · 8):
--   18-29: py_op 7,384 · 30-39: 5,848 · 40-49: 6,752 · 50-59: 6,567
--   60-69: 4,383 · 70+: 4,440
WITH grupos(grupo, lo, hi, orden) AS (
    VALUES ('18-29', 18, 29, 1), ('30-39', 30, 39, 2), ('40-49', 40, 49, 3),
           ('50-59', 50, 59, 4), ('60-69', 60, 69, 5), ('70+', 70, 200, 6)
),
anios AS (SELECT generate_series(2017, 2026) AS anio),
corte AS (SELECT max(observation_period_end_date) AS fecha FROM cdm.observation_period),
py AS (
    SELECT g.grupo,
           sum(greatest(0, least(op.observation_period_end_date + 1, make_date(a.anio + 1, 1, 1))
                           - greatest(op.observation_period_start_date, make_date(a.anio, 1, 1)))) / 365.25 AS py_op
    FROM anios a
    CROSS JOIN cdm.observation_period op
    JOIN cdm.person p USING (person_id)
    JOIN grupos g ON a.anio - p.year_of_birth BETWEEN g.lo AND g.hi
    GROUP BY g.grupo
),
visitas AS (
    SELECT g.grupo, sum(least(1.0, (c.fecha - make_date(x.anio, 1, 1) + 1) / 365.25)) AS py_visita
    FROM (SELECT DISTINCT person_id, extract(year FROM visit_start_date)::int AS anio
          FROM cdm.visit_occurrence) x
    CROSS JOIN corte c
    JOIN cdm.person p USING (person_id)
    JOIN grupos g ON x.anio - p.year_of_birth BETWEEN g.lo AND g.hi
    WHERE x.anio BETWEEN 2017 AND 2026
    GROUP BY g.grupo
),
entradas AS (
    SELECT g.grupo, count(*) AS entradas
    FROM results.cohort c
    JOIN cdm.person p ON p.person_id = c.subject_id
    JOIN grupos g ON extract(year FROM c.cohort_start_date) - p.year_of_birth BETWEEN g.lo AND g.hi
    WHERE c.cohort_definition_id = 1701
    GROUP BY g.grupo
)
SELECT g.grupo,
       round(py.py_op::numeric, 1)      AS py_op,
       round(v.py_visita::numeric, 1)   AS py_visita,
       coalesce(e.entradas, 0)          AS entradas
FROM grupos g
JOIN py USING (grupo)
LEFT JOIN visitas v USING (grupo)
LEFT JOIN entradas e USING (grupo)
ORDER BY g.orden;
