-- =====================================================================
-- Actividad 9. Caracterización de la cohorte final (tabla 1).
-- Lee results.cohort (actividad 7), no la cadena de CTE: la cohorte ya
-- está escrita. Solo lectura. Cohortes principales 1701 / 1702.
-- tabla1.py corre estas dos consultas (separadas por el marcador [B]) y
-- calcula con ellas la tabla 1 y la figura. Evita «%» en los comentarios:
-- el driver psycopg2 lo lee como parámetro.
-- =====================================================================

-- [A] Una fila por persona: edad en la fecha índice, sexo y seguimiento.
-- TRAMPA del enunciado: la edad se calcula contra la FECHA ÍNDICE
-- (cohort_start_date), no contra hoy. age(a, b) da el intervalo entre dos
-- fechas y date_part('year', ...) los años CUMPLIDOS. Se usa la fecha de
-- nacimiento completa (año, mes y día; ninguno es NULL, 5,904 personas).
-- edad_por_anio es la versión aproximada (año del índice − year_of_birth), que
-- sobreestima 1 año a quien aún no cumplió años ese año; se deja para medir
-- cuánto cambia (importa en los cortes 45 y 65).
-- Los JOIN con person y concept son por clave primaria: una fila por persona.
-- Seguimiento = fin − inicio en días (resta de date = entero); el fin es
-- inclusivo, así que 1 día de seguimiento = inicio + 1.
SELECT c.cohort_definition_id AS cohorte,
       c.subject_id           AS persona,
       date_part('year', age(c.cohort_start_date,
             make_date(p.year_of_birth, p.month_of_birth, p.day_of_birth)))::int AS edad,
       extract(year FROM c.cohort_start_date)::int - p.year_of_birth AS edad_por_anio,
       g.concept_name         AS sexo,
       c.cohort_end_date - c.cohort_start_date AS seguimiento_dias
FROM results.cohort c
JOIN cdm.person p  ON p.person_id = c.subject_id
JOIN cdm.concept g ON g.concept_id = p.gender_concept_id
WHERE c.cohort_definition_id IN (1701, 1702)
ORDER BY c.cohort_definition_id, c.subject_id;

-- [B] Comorbilidades: una fila por persona y diagnóstico DISTINTO registrado
-- en [−365, 0] respecto a la fecha índice (el día 0 entra: es línea de base,
-- no un criterio de entrada). Solo clase Disorder (decisión 18): se
-- descartan los hallazgos (Clinical Finding: aislamiento social, embarazo
-- normal).
-- TRAMPA: el JOIN con condition_occurrence trae UNA FILA POR REGISTRO; una
-- persona con 12 consultas por gingivitis aparecería 12 veces y inflaría el
-- conteo. DISTINCT (cohorte, persona, diagnóstico) lo vuelve a una fila.
-- Se cuenta personas, no registros. Se comprueba en tabla1.py.
SELECT DISTINCT c.cohort_definition_id AS cohorte,
       c.subject_id                 AS persona,
       co.condition_concept_id      AS concepto,
       cn.concept_name              AS nombre
FROM results.cohort c
JOIN cdm.condition_occurrence co
  ON co.person_id = c.subject_id
 AND co.condition_start_date BETWEEN c.cohort_start_date - 365
                                 AND c.cohort_start_date
JOIN cdm.concept cn ON cn.concept_id = co.condition_concept_id
WHERE c.cohort_definition_id IN (1701, 1702)
  AND cn.concept_class_id = 'Disorder';
