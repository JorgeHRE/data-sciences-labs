-- Caracterización de las variantes (actividad 9). Se ejecuta DESPUÉS de
-- variantes.sql, en la misma sesión (usa la tabla temporal `variantes`).
-- Misma definición que la tabla 1 del lab 17 (caracterizacion.sql): edad
-- cumplida en la fecha índice, sexo, seguimiento = salida − índice, y
-- comorbilidades = diagnósticos DISTINCT de clase Disorder en [−365, 0].
-- Evita «%» en los comentarios: el driver psycopg2 lo lee como parámetro.
-- Cuatro «variantes»: W180, W365, W730 (tabla `variantes`) y `sin_inicio`
-- (cohortes 1711 / 1712 del lab 17: sin fecha de inicio de estudio), que se
-- trae de results.cohort con cohort_definition_id − 10 para igualar la cohorte.

-- [A] Una fila por persona y variante: edad, sexo, seguimiento.
-- Los JOIN con person y concept son por clave primaria: no multiplican filas.
WITH base AS (
    SELECT 'W' || w AS variante, c AS cohorte, pid AS persona, idx AS inicio, salida AS fin FROM variantes
    UNION ALL
    SELECT 'sin_inicio', cohort_definition_id - 10, subject_id, cohort_start_date, cohort_end_date
    FROM results.cohort WHERE cohort_definition_id IN (1711, 1712)
)
SELECT b.variante, b.cohorte, b.persona,
       date_part('year', age(b.inicio, make_date(p.year_of_birth, p.month_of_birth, p.day_of_birth)))::int AS edad,
       g.concept_name AS sexo,
       b.fin - b.inicio AS seguimiento_dias
FROM base b
JOIN cdm.person p  ON p.person_id = b.persona
JOIN cdm.concept g ON g.concept_id = p.gender_concept_id
ORDER BY b.variante, b.cohorte, b.persona;

-- [B] Comorbilidades: una fila por persona y diagnóstico DISTINTO en [−365, 0].
-- TRAMPA: el JOIN con condition_occurrence trae una fila por registro; DISTINCT la
-- vuelve a una por persona y diagnóstico (se cuentan personas, no registros).
WITH base AS (
    SELECT 'W' || w AS variante, c AS cohorte, pid AS persona, idx AS inicio FROM variantes
    UNION ALL
    SELECT 'sin_inicio', cohort_definition_id - 10, subject_id, cohort_start_date
    FROM results.cohort WHERE cohort_definition_id IN (1711, 1712)
)
SELECT DISTINCT b.variante, b.cohorte, b.persona, co.condition_concept_id AS concepto, cn.concept_name AS nombre
FROM base b
JOIN cdm.condition_occurrence co
  ON co.person_id = b.persona
 AND co.condition_start_date BETWEEN b.inicio - 365 AND b.inicio
JOIN cdm.concept cn ON cn.concept_id = co.condition_concept_id
WHERE cn.concept_class_id = 'Disorder';
