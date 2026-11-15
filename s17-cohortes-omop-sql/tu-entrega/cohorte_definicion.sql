-- =====================================================================
-- Lab 17 — Cohorte de nuevo usuario en OMOP con SQL
-- Base: Postgres del lab 12 (lab12-omop-db-1), esquema cdm de solo lectura;
--       la cohorte se escribe en results.cohort (actividad 7).
-- Vocabulario: v5.0 29-AUG-26.
-- Cada consulta va precedida de qué responde y qué se encontró.
-- Orden lógico de un SELECT: FROM → WHERE → GROUP BY → HAVING → SELECT → ORDER BY
-- =====================================================================

-- =====================================================================
-- Controles previos: ¿se puede confiar en OBSERVATION_PERIOD?
-- Por qué: todas las ventanas de la cohorte (observación previa, lavado,
-- criterios, salida) se apoyan en observation_period. Si está mal
-- construido, el SQL corre sin error y la cohorte sale mal.
-- =====================================================================

-- Control 0a. Cobertura y forma de observation_period.
-- Qué mide: cuántas personas tienen periodo, cuántos periodos tiene cada una
-- y cuánto duran. Se compara contra cdm.person para saber si alguien queda
-- sin periodo (esa persona no podría entrar a ninguna cohorte).
-- percentile_cont(0.5) = mediana; la resta de dos date da días (entero).
-- Resultado esperado (2026-11-15), 1 fila:
--   personas 5,904 · con_periodo 5,904 · periodos 5,904 · max_por_persona 1
--   mediana_dias ≈ 11,544 (31.6 años) · desde 1916-06-21 · hasta 2026-10-26
SELECT
    (SELECT count(*) FROM cdm.person)                         AS personas,
    count(DISTINCT op.person_id)                               AS con_periodo,
    count(*)                                                   AS periodos,
    (SELECT max(n) FROM (SELECT count(*) AS n
                         FROM cdm.observation_period
                         GROUP BY person_id) t)                AS max_por_persona,
    percentile_cont(0.5) WITHIN GROUP (
        ORDER BY op.observation_period_end_date
               - op.observation_period_start_date)             AS mediana_dias,
    min(op.observation_period_start_date)                      AS desde,
    max(op.observation_period_end_date)                        AS hasta
FROM cdm.observation_period op;

-- Control 0b. ¿Cuántos eventos caen FUERA de observation_period?
-- Qué mide: en las cuatro tablas de eventos que usará la cohorte (recetas,
-- diagnósticos, visitas, mediciones), cuántas filas tienen fecha de inicio
-- antes del inicio del periodo o después de su fin. Un evento fuera del
-- periodo es una contradicción: la base dice que no estaba mirando a la
-- persona ese día, pero tiene un registro.
-- Por qué un JOIN aquí es seguro: el control 0a mostró max_por_persona = 1,
-- así que cada evento se une con UN solo periodo y no se multiplica. Se
-- comprueba igual: la columna «eventos» debe ser el count(*) de cada tabla
-- (con 2 periodos por persona saldría inflada). Las 5,904 personas tienen
-- periodo (0a), así que el JOIN interno tampoco pierde filas.
-- Orden lógico: FROM eventos JOIN periodo → SELECT con count(*) FILTER.
-- Resultado (2026-11-15), 4 filas (eventos = count(*) de cada tabla → el
-- JOIN no multiplicó; fecha_nula 0 en las cuatro):
--   tabla                   eventos  antes  despues
--   condition_occurrence    101,699    614        0
--   drug_exposure           467,590      0        0
--   measurement           4,008,280      0       76
--   visit_occurrence        385,971      0        0
-- Lectura:
--   · 614 diagnósticos ANTES del inicio: antecedentes con fecha antigua,
--     anteriores a la primera visita. Importa para criterios con ventana
--     (−∞, 0]: «tiene X alguna vez» puede apoyarse en fechas no observadas.
--   · 76 mediciones DESPUÉS del fin, en 37 personas, todas a 1 día exacto:
--     cuestionarios de cribado (PHQ-2, AUDIT-C, depresión) de una visita que
--     empieza dentro del periodo. Artefacto de 1 día del ETL; no afecta a
--     ventanas previas al índice, y la salida (actividad 6) se corta con
--     el fin del periodo de todas formas.
WITH eventos AS (
    SELECT 'condition_occurrence' AS tabla, person_id, condition_start_date AS fecha
    FROM cdm.condition_occurrence
    UNION ALL
    SELECT 'drug_exposure', person_id, drug_exposure_start_date FROM cdm.drug_exposure
    UNION ALL
    SELECT 'visit_occurrence', person_id, visit_start_date FROM cdm.visit_occurrence
    UNION ALL
    SELECT 'measurement', person_id, measurement_date FROM cdm.measurement
)
SELECT e.tabla,
       count(*)                                                         AS eventos,
       count(*) FILTER (WHERE e.fecha < op.observation_period_start_date) AS antes,
       count(*) FILTER (WHERE e.fecha > op.observation_period_end_date)   AS despues,
       count(*) FILTER (WHERE e.fecha IS NULL)                            AS fecha_nula
FROM eventos e
JOIN cdm.observation_period op ON op.person_id = e.person_id
GROUP BY e.tabla
ORDER BY e.tabla;

-- Control 0c. ¿El periodo refleja observación real? Visitas por año.
-- Qué mide: por cada año desde 2005, cuántas personas tienen su periodo
-- abierto ese año («observadas» según la base) y cuántas tuvieron al menos
-- una visita. Si el periodo fuera fiel, casi todas las observadas tendrían
-- alguna visita. Un hueco grande = años que el periodo «cubre» sin datos:
-- ahí la ausencia de una receta NO prueba que no la hubo (afecta al lavado).
-- generate_series(2005, 2026) crea una fila por año (tabla de calendario).
-- Por qué desde 2005: antes hay pocas visitas por año y la tabla se haría
-- larga sin cambiar la conclusión; el corte es solo de presentación.
-- Por qué personas DISTINTAS: una persona con 10 visitas en un año cuenta 1.
-- El JOIN años × periodos da como máximo una fila por persona y año
-- (un periodo por persona, control 0a), así que no hay duplicados.
-- Orden lógico: FROM anios JOIN periodos → GROUP BY anio → SELECT.
-- Resultado (2026-11-15), 22 filas (2005-2026), sin años con 0 visitas:
--   anio  observadas  con_visita  %      visitas
--   2005       3,586        966  26.9     4,034
--   2010       3,864      1,160  30.0     4,661
--   2013       4,062      1,528  37.6     4,251
--   2014       4,160      2,368  56.9     6,631
--   2015       4,305      2,436  56.6     6,395
--   2016       4,627      3,868  83.6    11,713
--   2017       4,830      4,541  94.0    24,293
--   2017-2026: entre 93.7 % y 99.9 % cada año
-- Lectura: hasta 2013, de cada 4 personas «observadas» solo 1 tiene alguna
-- visita en el año; desde 2017, más del 93 %. El periodo empieza en la
-- primera visita y se extiende décadas, pero el registro detallado empieza
-- en 2016-2017 (escalón 2014 y 2016). Consecuencia para la cohorte: antes de
-- 2016, «no hay receta en los 365 días previos» no garantiza que no la
-- hubiera → el lavado y la observación previa son débiles en esos años.
WITH anios AS (
    SELECT generate_series(2005, 2026) AS anio
),
observadas AS (            -- personas con el periodo abierto algún día del año
    SELECT a.anio, count(*) AS personas_observadas
    FROM anios a
    JOIN cdm.observation_period op
      ON op.observation_period_start_date <= make_date(a.anio, 12, 31)
     AND op.observation_period_end_date   >= make_date(a.anio, 1, 1)
    GROUP BY a.anio
),
con_visita AS (            -- visitas y personas distintas con visita, por año
    SELECT extract(year FROM visit_start_date)::int AS anio,
           count(*)                  AS visitas,
           count(DISTINCT person_id) AS personas_con_visita
    FROM cdm.visit_occurrence
    WHERE visit_start_date >= DATE '2005-01-01'
    GROUP BY 1
)
SELECT o.anio, o.personas_observadas,
       coalesce(v.personas_con_visita, 0) AS personas_con_visita,
       round(100.0 * coalesce(v.personas_con_visita, 0)
             / o.personas_observadas, 1)  AS pct_con_visita,
       coalesce(v.visitas, 0)             AS visitas
FROM observadas o
LEFT JOIN con_visita v ON v.anio = o.anio   -- LEFT: un año sin visitas sale con 0
ORDER BY o.anio;
