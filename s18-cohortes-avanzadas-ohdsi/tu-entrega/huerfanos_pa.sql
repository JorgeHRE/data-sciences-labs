-- Impacto del candidato «presión arterial elevada sin diagnóstico» en la cohorte.
-- Se pega después del bloque de banderas de atricion.sql:
--   cat <(sed -n '/^-- \[INICIO banderas\]/,/^-- \[FIN banderas\]/p' atricion.sql) huerfanos_pa.sql | psql ...
-- Población: las personas que pasan TODOS los criterios menos el de hipertensión
-- (son las únicas a quienes un criterio alterno de PA cambiaría la cohorte final).
-- Para cada umbral de presión y número mínimo de fechas elevadas (hasta el día
-- índice, inclusive) cuenta cuántas de ellas lo cumplen. Tomas: una fila por
-- persona y fecha con la sistólica y la diastólica del día (máximo si hay
-- varias tomas); «elevada» = sistólica ≥ s O diastólica ≥ d.
-- Los umbrales se prueban para ver CUÁNTO cambia el N: si el resultado depende
-- mucho del umbral, el criterio es arbitrario. LEFT JOIN a tomas: una persona
-- sin ninguna toma elevada queda con 0 fechas (count FILTER sobre NULL = 0).
-- Resultado (2026-11-15), 3 filas (1701; en 1702 nadie falla solo el criterio de
-- hipertensión, así que no hay filas). De las 22 que fallan solo hipertensión,
-- con ≥ 1 / ≥ 2 / ≥ 3 fechas elevadas:
--   130/80: 8 / 7 / 7   140/90: 4 / 3 / 2   160/100: 1 / 0 / 0
-- Con ≥ 2 fechas, la cohorte final pasaría de 122 a 129, 125 o 122 según el umbral.
, tomas AS (
    SELECT m.person_id, m.measurement_date AS fecha,
           max(m.value_as_number) FILTER (WHERE m.measurement_concept_id = 3004249) AS sis,
           max(m.value_as_number) FILTER (WHERE m.measurement_concept_id = 3012888) AS dia
    FROM cdm.measurement m
    WHERE m.measurement_concept_id IN (3004249, 3012888)
    GROUP BY m.person_id, m.measurement_date
),
umbrales(sis, dia) AS (VALUES (130, 80), (140, 90), (160, 100)),
solo_hta AS (
    SELECT * FROM banderas
    WHERE f_estudio AND f_obs AND f_lavado AND f_adulto AND f_visitas
      AND f_sin_demencia AND f_sin_otro AND f_sin_combo AND NOT f_hta
),
cuenta AS (
    SELECT s.cohort_definition_id, u.sis AS u_sis, u.dia AS u_dia, s.person_id,
           count(*) FILTER (WHERE t.sis >= u.sis OR t.dia >= u.dia) AS fechas
    FROM solo_hta s
    CROSS JOIN umbrales u
    LEFT JOIN tomas t ON t.person_id = s.person_id AND t.fecha <= s.fecha_indice
    GROUP BY s.cohort_definition_id, u.sis, u.dia, s.person_id
)
SELECT cohort_definition_id AS cohorte,
       u_sis || '/' || u_dia                AS umbral,
       count(*)                             AS fallan_solo_hta,
       count(*) FILTER (WHERE fechas >= 1)  AS con_1_o_mas_fechas,
       count(*) FILTER (WHERE fechas >= 2)  AS con_2_o_mas_fechas,
       count(*) FILTER (WHERE fechas >= 3)  AS con_3_o_mas_fechas
FROM cuenta
GROUP BY cohort_definition_id, u_sis, u_dia
ORDER BY cohort_definition_id, u_sis;
