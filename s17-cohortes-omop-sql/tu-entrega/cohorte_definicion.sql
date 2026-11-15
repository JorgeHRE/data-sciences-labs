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

-- =====================================================================
-- Actividad 2. Evento inicial: primera receta del fármaco, una fila por persona.
-- =====================================================================

-- Actividad 2a. Tabla de parámetros: una fila por cohorte (decisión 6).
-- Por qué una tabla: la lógica de la cohorte es la misma para lisinopril y
-- amlodipino; solo cambian los fármacos. Con los fármacos en una tabla, el
-- mismo SQL construye las dos cohortes a la vez (cada CTE lleva
-- cohort_definition_id) y una tercera cohorte sería una fila nueva, no un
-- archivo nuevo (bono 1 del enunciado).
--   ingrediente_exp  = ingrediente que define la fecha índice.
--   ingrediente_otro = el otro fármaco del par; se usa en la exclusión de la
--                      actividad 5 (uso en (−∞, 0], incluido el mismo día).
-- Se guarda el INGREDIENTE (clase Ingredient de RxNorm), no los productos:
-- los productos se obtienen con concept_ancestor, como en los labs 13-15.
-- Re-ejecutable: CREATE ... IF NOT EXISTS + INSERT ... ON CONFLICT DO UPDATE
-- (si la fila existe, se sobrescribe con estos valores; nunca se duplica,
-- porque cohort_definition_id es la clave primaria).
CREATE TABLE IF NOT EXISTS results.cohorte_parametros (
    cohort_definition_id integer PRIMARY KEY,
    nombre               text    NOT NULL,
    ingrediente_exp      integer NOT NULL,
    ingrediente_otro     integer NOT NULL
);

INSERT INTO results.cohorte_parametros VALUES
    (1701, 'nuevos usuarios de lisinopril', 1308216, 1332418),
    (1702, 'nuevos usuarios de amlodipino', 1332418, 1308216)
ON CONFLICT (cohort_definition_id) DO UPDATE
    SET nombre           = EXCLUDED.nombre,
        ingrediente_exp  = EXCLUDED.ingrediente_exp,
        ingrediente_otro = EXCLUDED.ingrediente_otro;

-- Control 2a. Los parámetros apuntan a lo que creemos: ingredientes RxNorm
-- estándar y vigentes. Un id mal tecleado no daría error: daría una cohorte
-- vacía o de otro fármaco. Por eso se muestra el nombre desde concept.
-- Los dos JOIN a concept son por clave primaria (concept_id): 1 fila por
-- parámetro, no multiplican (2 filas antes, 2 después).
-- Resultado (2026-11-15), 2 filas:
--   1701 lisinopril → exp lisinopril, otro amlodipine
--   1702 amlodipino → exp amlodipine, otro lisinopril
--   los dos: clase Ingredient, standard_concept 'S', invalid_reason NULL.
-- Segunda corrida: «relation already exists, skipping» + INSERT 0 2 y la
-- tabla sigue con 2 filas → re-ejecutable.
SELECT p.cohort_definition_id, p.nombre,
       ce.concept_name AS exp,  ce.concept_class_id AS clase_exp,
       ce.standard_concept AS std_exp, ce.invalid_reason AS inv_exp,
       co.concept_name AS otro, co.concept_class_id AS clase_otro
FROM results.cohorte_parametros p
JOIN cdm.concept ce ON ce.concept_id = p.ingrediente_exp
JOIN cdm.concept co ON co.concept_id = p.ingrediente_otro
ORDER BY p.cohort_definition_id;

-- [INICIO cohorte] =====================================================
-- Construcción de la cohorte (actividades 2-7): UNA sentencia WITH que
-- crece; cada actividad añade un CTE a la cadena (decisión 7).
-- El SELECT final cuenta cada paso, una fila por paso y cohorte: es la
-- tabla de atrición que se va formando (actividad 8).
-- Para correr solo este bloque (los marcadores van anclados con ^ para
-- que esta línea de comentario no los active):
--   sed -n '/^-- \[INICIO cohorte\]/,/^-- \[FIN cohorte\]/p' \
--     cohorte_definicion.sql | docker exec -i lab12-omop-db-1 psql ...
-- Orden de los CTE: cada uno lee SOLO del anterior, así una persona que
-- sale en un paso no puede volver a entrar en otro.
-- =====================================================================
WITH
-- Actividad 2b. recetas: todas las recetas del fármaco de cada cohorte.
-- concept_ancestor expande el ingrediente a todos sus productos (tabletas,
-- combinaciones). Cada producto aparece UNA vez por ingrediente en
-- concept_ancestor, así que el JOIN no duplica recetas: se comprueba en el
-- SELECT final (filas = drug_exposure_id distintos).
-- drug_type_concept_id = 32838 (EHR prescription): solo recetas; las
-- vacunas (32827) quedan fuera, igual que en el lab 13.
recetas AS (
    SELECT p.cohort_definition_id,
           d.drug_exposure_id,
           d.person_id,
           d.drug_concept_id,
           d.drug_exposure_start_date AS inicio,
           d.drug_exposure_end_date   AS fin
    FROM results.cohorte_parametros p
    JOIN cdm.concept_ancestor ca ON ca.ancestor_concept_id = p.ingrediente_exp
    JOIN cdm.drug_exposure d     ON d.drug_concept_id = ca.descendant_concept_id
    WHERE d.drug_type_concept_id = 32838
),
-- Actividad 2b. evento_inicial: la PRIMERA receta de toda la historia.
-- GROUP BY cohorte y persona + min(inicio) → una fila por persona y
-- cohorte. Orden lógico: FROM recetas → GROUP BY → SELECT min().
-- Una misma persona puede estar en las dos cohortes (usa los dos
-- fármacos); la exclusión del «otro» fármaco llega en la actividad 5.
evento_inicial AS (
    SELECT cohort_definition_id,
           person_id,
           min(inicio) AS fecha_indice
    FROM recetas
    GROUP BY cohort_definition_id, person_id
)
-- Resultado (2026-11-15), 4 filas, < 1 s; filas = distintos en todas:
--   paso                    1701 lisinopril   1702 amlodipino
--   0 recetas del fármaco        42,085            34,475
--   1 evento inicial              1,522             1,104
-- 42,085 ≠ 42,002 de results.lisinopril_exposicion (lab 13): la diferencia
-- son las 83 recetas con fin < inicio (days_supply negativo, mínimo −6),
-- que el lab 13 excluyó. Aquí se conservan porque su fecha de INICIO es
-- válida: comprobado que excluirlas no cambia la fecha índice de nadie
-- (0 en las dos cohortes). Amlodipino tiene 64 (36 personas). Pendiente
-- para la actividad 6, donde sí importa la duración. Sin fin NULL; fin =
-- inicio en 1,772 y 1,201 recetas («en curso» del ETL, lab 13).
-- Conteo de cada paso. «filas» y «distintos» deben coincidir:
--   recetas:        distintos = drug_exposure_id distintos (JOIN sin duplicar)
--   evento_inicial: distintos = person_id distintos (trampa del enunciado)
SELECT '0 recetas del fármaco' AS paso, cohort_definition_id,
       count(*) AS filas, count(DISTINCT drug_exposure_id) AS distintos
FROM recetas GROUP BY cohort_definition_id
UNION ALL
SELECT '1 evento inicial', cohort_definition_id,
       count(*), count(DISTINCT person_id)
FROM evento_inicial GROUP BY cohort_definition_id
ORDER BY paso, cohort_definition_id;
-- [FIN cohorte] ========================================================

-- Control 2c. ¿Con qué producto entra cada persona, y hay empates el día índice?
-- Qué mide: las recetas del fármaco con inicio = fecha índice. Si una persona
-- tiene 2 ese día, el min() del evento inicial ya dio una sola fila (no hay
-- duplicado), pero «el producto del índice» sería ambiguo.
-- Va FUERA del bloque de construcción: es un diagnóstico, no un componente.
-- Repite a propósito la expansión del concept set (no puede leer los CTE de
-- otra sentencia). El JOIN recetas ↔ índice es por (cohorte, persona,
-- fecha): da una fila por receta del día índice, que es justo lo que se
-- quiere contar aquí.
-- Resultado (2026-11-15), 13 filas (9 productos de lisinopril, 4 de
-- amlodipino); personas suman 1,522 y 1,104 → una fila por persona:
--   1701: lisinopril 10 MG 1,415 · 20 MG 64 · 5 MG 15 · 40 MG 9 · 2.5 MG 3
--         · 30 MG 2 · combinaciones con HIDROCLOROTIAZIDA 14 (10 + 2 + 2)
--   1702: amlodipine 2.5 MG 1,101 · amlodipino/benazepril 2 · Tribenzor
--         (amlodipino/HCTZ/olmesartán) 1
--   Con 2 productos distintos el día índice: 0 en las dos cohortes → el
--   producto del índice no es ambiguo.
--   Con 2 recetas del MISMO producto ese día: 175 (1701) y 85 (1702). No
--   son filas duplicadas: en toda la historia hay 187 / 89 pares así, y
--   168 / 82 son una receta de 0 días (fin = inicio, «en curso» del ETL)
--   junto a la receta con duración; solo 19 / 7 pares tienen el mismo fin.
--   No afectan al índice (min() colapsa el día) ni a los tramos de la
--   actividad 6 (se usa el fin máximo).
-- Hallazgo para la actividad 5: 14 personas empiezan lisinopril con una
-- combinación con HCTZ y 3 empiezan amlodipino con una combinación con otro
-- antihipertensivo: inician DOS clases a la vez, como las 507 del inicio
-- lisinopril + amlodipino. Decidir si se excluyen con el mismo criterio.
WITH recetas AS (
    SELECT p.cohort_definition_id, d.person_id, d.drug_concept_id,
           d.drug_exposure_start_date AS inicio
    FROM results.cohorte_parametros p
    JOIN cdm.concept_ancestor ca ON ca.ancestor_concept_id = p.ingrediente_exp
    JOIN cdm.drug_exposure d     ON d.drug_concept_id = ca.descendant_concept_id
    WHERE d.drug_type_concept_id = 32838
),
indice AS (
    SELECT cohort_definition_id, person_id, min(inicio) AS fecha_indice
    FROM recetas GROUP BY 1, 2
),
del_dia AS (               -- recetas del día índice, por persona
    SELECT r.cohort_definition_id, r.person_id,
           count(*)                          AS recetas,
           count(DISTINCT r.drug_concept_id) AS productos,
           min(r.drug_concept_id)            AS un_producto
    FROM recetas r
    JOIN indice i ON i.cohort_definition_id = r.cohort_definition_id
                 AND i.person_id = r.person_id
                 AND r.inicio = i.fecha_indice
    GROUP BY 1, 2
)
SELECT dd.cohort_definition_id,
       c.concept_name                         AS producto_indice,
       count(*)                               AS personas,
       count(*) FILTER (WHERE dd.recetas > 1)   AS con_2_recetas_ese_dia,
       count(*) FILTER (WHERE dd.productos > 1) AS con_2_productos_ese_dia
FROM del_dia dd
JOIN cdm.concept c ON c.concept_id = dd.un_producto
GROUP BY 1, 2
ORDER BY 1, 3 DESC;
