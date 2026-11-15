-- =====================================================================
-- Lab 18 — Actividad 1. Factibilidad a posteriori de la cohorte del lab 17
-- Base: Postgres del lab 12 (lab12-omop-db-1). Solo lectura: lee
-- results.cohort (lab 17) y cdm.*. Cada consulta corre sola:
--   docker exec -i lab12-omop-db-1 psql -U $POSTGRES_USER -d $POSTGRES_DB < factibilidad.sql
-- Orden lógico de un SELECT: FROM → WHERE → GROUP BY → HAVING → SELECT → ORDER BY
-- =====================================================================

-- Conteos 1 y 2. ¿Cuántos pacientes entraron y cuánto seguimiento tienen?
-- Qué mide: una fila por cohorte. «Seguimiento» = días entre la fecha índice
-- (cohort_start_date) y la salida de la cohorte (cohort_end_date): es el
-- tiempo en que el desenlace SÍ se habría podido registrar. La salida ya
-- incluye la persistencia de 30 días y el corte por el otro fármaco (lab 17,
-- decisiones 13 y 14), así que no es el tiempo restante de observation_period.
-- Control: filas = personas distintas (una fila por persona y cohorte); si no
-- coincidieran, algún JOIN del lab 17 habría duplicado a alguien.
-- percentile_cont(ARRAY[.25,.5,.75]) da los tres cuartiles en un solo paso;
-- una resta de dos date da días (entero).
-- Resultado esperado (2026-11-15), 2 filas:
--   1701: 122 · 122 · 30 / 927.5 / 1,869 días · 373.3 años-persona
--   1702:  81 ·  81 · 30 / 401   / 1,514 días · 216.3 años-persona
SELECT cohort_definition_id                                   AS cohorte,
       count(*)                                               AS filas,
       count(DISTINCT subject_id)                             AS personas,
       percentile_cont(0.25) WITHIN GROUP (
           ORDER BY cohort_end_date - cohort_start_date)      AS q1_dias,
       percentile_cont(0.50) WITHIN GROUP (
           ORDER BY cohort_end_date - cohort_start_date)      AS mediana_dias,
       percentile_cont(0.75) WITHIN GROUP (
           ORDER BY cohort_end_date - cohort_start_date)      AS q3_dias,
       round(sum(cohort_end_date - cohort_start_date) / 365.25, 1) AS anios_persona
FROM results.cohort
WHERE cohort_definition_id IN (1701, 1702)
GROUP BY cohort_definition_id
ORDER BY cohort_definition_id;

-- Conteo 3. ¿Cuántas veces ocurre el desenlace en ese seguimiento?  (el que decide)
-- Desenlace = primer diagnóstico de demencia (4182210 «Dementia» y
-- descendientes) DESPUÉS del índice, como en el lab 17. Ventana de evento:
-- (índice, salida], es decir fecha > índice y fecha ≤ salida. El día 0 no
-- cuenta: el criterio de exclusión del lab 17 miraba (−∞, 0], así que una
-- demencia del día 0 habría sacado a la persona; aquí, por eso, previa = 0.
-- Por qué concept_ancestor: el concept set es el ingrediente + todos sus
-- descendientes (lab 14). Cada descendiente aparece UNA vez por ancestro, así
-- que el JOIN no multiplica filas; DISTINCT subject_id cuenta personas, no
-- registros (alguien con 3 códigos de Alzheimer es 1 persona con evento).
-- Orden lógico: FROM cohorte JOIN condición → WHERE ventana → GROUP BY.
-- Se usa LEFT JOIN desde la cohorte para que una cohorte con 0 eventos salga
-- con 0 y no desaparezca del resultado (un INNER JOIN dejaría 0 filas y
-- «no hay filas» se confunde con «no se midió»).
-- Resultado esperado (2026-11-15), 2 filas:
--   1701: 122 personas · 0 con evento · 0 registros · previa 0 · 373.3 años
--   1702:  81 personas · 0 con evento · 0 registros · previa 0 · 216.3 años
SELECT c.cohort_definition_id                                        AS cohorte,
       count(DISTINCT c.subject_id)                                  AS personas,
       count(DISTINCT c.subject_id) FILTER (
           WHERE co.condition_start_date >  c.cohort_start_date
             AND co.condition_start_date <= c.cohort_end_date)       AS con_evento,
       count(*) FILTER (
           WHERE co.condition_start_date >  c.cohort_start_date
             AND co.condition_start_date <= c.cohort_end_date)       AS registros_evento,
       count(DISTINCT c.subject_id) FILTER (
           WHERE co.condition_start_date <= c.cohort_start_date)     AS con_previa
FROM results.cohort c
LEFT JOIN cdm.concept_ancestor ca ON ca.ancestor_concept_id = 4182210
LEFT JOIN cdm.condition_occurrence co
       ON co.person_id = c.subject_id
      AND co.condition_concept_id = ca.descendant_concept_id
WHERE c.cohort_definition_id IN (1701, 1702)
GROUP BY c.cohort_definition_id
ORDER BY c.cohort_definition_id;

-- Control 3b. ¿El 0 es porque no hay demencia o porque la salida corta antes?
-- Qué mide: de las personas de la cohorte, cuántas tienen demencia DESPUÉS del
-- índice sin límite de salida (hasta el fin de los datos). Si fuera > 0, el 0
-- del conteo 3 lo causaría el corte de seguimiento (persistencia, otro
-- fármaco); si es 0, simplemente no hay demencia en estas personas.
-- Resultado (2026-11-15): solo 1701 aparece (el JOIN interno omite a quien no
-- tiene demencia en ningún momento; 1702 no sale = 0 personas):
--   1701: 2 personas con demencia tras el índice, las 2 DESPUÉS de la salida.
-- Lectura: el 0 del conteo 3 es en parte el corte de seguimiento (las 2
-- salieron por empezar amlodipino a los 30 y 91 días y tuvieron demencia 9 y
-- 3 años después, a los 61 y 74 años).
SELECT c.cohort_definition_id AS cohorte,
       count(DISTINCT c.subject_id) AS personas,
       count(DISTINCT c.subject_id) FILTER (
           WHERE co.condition_start_date > c.cohort_start_date)      AS demencia_despues_del_indice,
       count(DISTINCT c.subject_id) FILTER (
           WHERE co.condition_start_date > c.cohort_end_date)        AS demencia_despues_de_la_salida
FROM results.cohort c
JOIN cdm.concept_ancestor ca ON ca.ancestor_concept_id = 4182210
JOIN cdm.condition_occurrence co
  ON co.person_id = c.subject_id AND co.condition_concept_id = ca.descendant_concept_id
WHERE c.cohort_definition_id IN (1701, 1702)
GROUP BY c.cohort_definition_id
ORDER BY c.cohort_definition_id;

-- Tabla exploratoria 3c (NO sustituye al desenlace principal, decisión 4).
-- Qué mide: con cuántos eventos incidentes contaría la cohorte 1701 si la
-- pregunta fuera otra. «Incidente» = evento en (índice, salida] en personas SIN
-- el mismo diagnóstico en (−∞, índice]: sin esa exclusión se contarían
-- diagnósticos repetidos de una enfermedad ya presente (cada visita de ERC
-- registra de nuevo el código). max_vars = eventos / 10 (regla de Peduzzi,
-- redondeo hacia abajo): cuántas variables soportaría un modelo.
-- Los conceptos son los de la exploración del plan: ERC 46271022, DM2 201826,
-- IAM 4329847, ACV 381316 y demencia 4182210 (referencia).
-- Orden lógico: FROM cohorte × desenlaces → JOIN condiciones → GROUP BY.
-- Resultado (2026-11-15), 5 filas (incidentes / variables que soportaría):
--   ERC 13 / 1 · DM2 2 / 0 · infarto de miocardio 1 / 0 · ACV 0 / 0 · demencia 0 / 0
WITH desenlaces(concepto, nombre) AS (
    VALUES (4182210,  'Demencia (principal)'),
           (46271022, 'Enfermedad renal crónica'),
           (201826,   'Diabetes tipo 2'),
           (4329847,  'Infarto de miocardio'),
           (381316,   'Accidente cerebrovascular')
), registros AS (
    SELECT c.subject_id, d.nombre, co.condition_start_date AS fecha,
           c.cohort_start_date AS ini, c.cohort_end_date AS fin
    FROM results.cohort c
    CROSS JOIN desenlaces d
    JOIN cdm.concept_ancestor ca ON ca.ancestor_concept_id = d.concepto
    JOIN cdm.condition_occurrence co
      ON co.person_id = c.subject_id AND co.condition_concept_id = ca.descendant_concept_id
    WHERE c.cohort_definition_id = 1701
)
SELECT d.nombre,
       count(DISTINCT r.subject_id) FILTER (
           WHERE r.fecha > r.ini AND r.fecha <= r.fin
             AND NOT EXISTS (SELECT 1 FROM registros p
                             WHERE p.subject_id = r.subject_id AND p.nombre = r.nombre
                               AND p.fecha <= p.ini))                AS eventos_incidentes,
       floor(count(DISTINCT r.subject_id) FILTER (
           WHERE r.fecha > r.ini AND r.fecha <= r.fin
             AND NOT EXISTS (SELECT 1 FROM registros p
                             WHERE p.subject_id = r.subject_id AND p.nombre = r.nombre
                               AND p.fecha <= p.ini)) / 10.0)        AS max_variables
FROM desenlaces d
LEFT JOIN registros r ON r.nombre = d.nombre
GROUP BY d.nombre
ORDER BY eventos_incidentes DESC, d.nombre;

-- Contraste 3d. ¿Cambiaría el veredicto sin cortar al empezar el otro fármaco?
-- Qué mide: seguimiento y eventos de demencia si cada persona se siguiera
-- hasta el FIN de su observation_period (como un análisis «por intención de
-- tratar» sin censura por el otro fármaco). NO es la definición del lab 17
-- (decisión 14: as-treated); solo muestra cuánto pesa ese corte.
-- JOIN con observation_period: 1 periodo por persona (lab 17, control 0a), no
-- multiplica filas (122 y 81 personas antes y después).
-- Resultado (2026-11-15), 2 filas:
--   1701: 122 · mediana 1,569 d · 559.0 años-persona · 2 con demencia
--   1702:  81 · mediana 1,484 d · 329.2 años-persona · 0 con demencia
SELECT c.cohort_definition_id AS cohorte,
       count(*) AS personas,
       percentile_cont(0.5) WITHIN GROUP (
           ORDER BY op.observation_period_end_date - c.cohort_start_date) AS mediana_dias_a_fin_op,
       round(sum(op.observation_period_end_date - c.cohort_start_date) / 365.25, 1) AS anios_persona,
       count(DISTINCT c.subject_id) FILTER (WHERE EXISTS (
           SELECT 1 FROM cdm.condition_occurrence co
           JOIN cdm.concept_ancestor ca ON ca.descendant_concept_id = co.condition_concept_id
                                       AND ca.ancestor_concept_id = 4182210
           WHERE co.person_id = c.subject_id
             AND co.condition_start_date > c.cohort_start_date)) AS con_demencia
FROM results.cohort c
JOIN cdm.observation_period op ON op.person_id = c.subject_id
WHERE c.cohort_definition_id IN (1701, 1702)
GROUP BY c.cohort_definition_id ORDER BY 1;

-- Dato de contexto usado en diagnostico_cohorte.md (2026-11-15): personas de
-- toda la base con algún diagnóstico de demencia (4182210 y descendientes).
-- Resultado: 170 de 5,904 (2.9 %).
SELECT count(DISTINCT co.person_id) AS personas_con_demencia,
       (SELECT count(*) FROM cdm.person) AS personas_totales
FROM cdm.condition_occurrence co
JOIN cdm.concept_ancestor ca ON ca.descendant_concept_id = co.condition_concept_id
                            AND ca.ancestor_concept_id = 4182210;
