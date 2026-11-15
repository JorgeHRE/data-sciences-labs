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
    ingrediente_otro     integer NOT NULL,
    inicio_estudio       date             -- NULL = sin fecha de inicio
);
-- Actividad 3c (decisión 9): fecha de inicio del estudio. ADD COLUMN IF NOT
-- EXISTS para bases donde la tabla ya existía sin esta columna.
ALTER TABLE results.cohorte_parametros
    ADD COLUMN IF NOT EXISTS inicio_estudio date;

-- 1701/1702: definición principal, índice desde el 2017-01-01 (el año
-- previo cae ya en el registro detallado, control 0c).
-- 1711/1712: sensibilidad «tal cual», sin fecha de inicio (NULL, no una
-- fecha inventada como 1900-01-01, para no introducir un centinela).
INSERT INTO results.cohorte_parametros VALUES
    (1701, 'nuevos usuarios de lisinopril',                1308216, 1332418, DATE '2017-01-01'),
    (1702, 'nuevos usuarios de amlodipino',                1332418, 1308216, DATE '2017-01-01'),
    (1711, 'lisinopril, sensibilidad sin inicio de estudio', 1308216, 1332418, NULL),
    (1712, 'amlodipino, sensibilidad sin inicio de estudio', 1332418, 1308216, NULL)
ON CONFLICT (cohort_definition_id) DO UPDATE
    SET nombre           = EXCLUDED.nombre,
        ingrediente_exp  = EXCLUDED.ingrediente_exp,
        ingrediente_otro = EXCLUDED.ingrediente_otro,
        inicio_estudio   = EXCLUDED.inicio_estudio;

-- Control 2a. Los parámetros apuntan a lo que creemos: ingredientes RxNorm
-- estándar y vigentes. Un id mal tecleado no daría error: daría una cohorte
-- vacía o de otro fármaco. Por eso se muestra el nombre desde concept.
-- Los dos JOIN a concept son por clave primaria (concept_id): 1 fila por
-- parámetro, no multiplican (2 filas antes, 2 después).
-- Resultado (2026-11-15), 4 filas (2 hasta la actividad 3c):
--   1701 y 1711 → exp lisinopril, otro amlodipine
--   1702 y 1712 → exp amlodipine, otro lisinopril
--   todos: clase Ingredient, standard_concept 'S', invalid_reason NULL;
--   inicio_estudio 2017-01-01 en 1701/1702 y NULL en 1711/1712.
-- Segunda corrida: «relation already exists, skipping», INSERT 0 4 y la
-- tabla sigue con 4 filas → re-ejecutable.
SELECT p.cohort_definition_id, p.nombre, p.inicio_estudio,
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
),
-- Actividad 3c. periodo_estudio: la fecha índice cae desde el inicio del
-- estudio de cada cohorte (decisión 9). 1701/1702: desde 2017-01-01, porque
-- antes de 2016 la base «observa» sin datos (control 0c) y las primeras
-- recetas hacen pico en 2015-2016: usuarios que ya lo tomaban y aparecen
-- como nuevos cuando empieza el registro detallado (figura 3b).
-- 1711/1712 (sensibilidad): inicio_estudio NULL → no filtra.
-- Va DESPUÉS de evento_inicial a propósito: primero la primera receta de
-- TODA la historia, luego se exige que caiga en el periodo. Al revés
-- (filtrar recetas desde 2017 y tomar la primera) alguien que empezó en
-- 2015 entraría como «nuevo» en 2018. Medido: con el orden al revés serían
-- 1,233 / 934 personas en vez de 346 / 238 (887 / 696 usuarios previos).
-- El JOIN con parámetros es por clave primaria: 1 fila por cohorte, no
-- multiplica.
periodo_estudio AS (
    SELECT e.*
    FROM evento_inicial e
    JOIN results.cohorte_parametros p USING (cohort_definition_id)
    WHERE p.inicio_estudio IS NULL
       OR e.fecha_indice >= p.inicio_estudio
),
-- Actividad 3a. obs_previa: la base observaba a la persona al menos 365
-- días antes del índice, sin interrupciones (decisión 8).
-- Las DOS condiciones van sobre el MISMO periodo (trampa 1 del enunciado):
-- el periodo empieza ≤ índice − 365 Y termina ≥ índice. Con dos periodos
-- separados, mirar «el inicio más antiguo» y «el fin más reciente» de
-- periodos distintos aprobaría a alguien con un hueco en medio.
-- Por qué JOIN y no EXISTS: se necesita op_fin (fin del periodo) para la
-- censura de la actividad 6. No multiplica: los periodos de una persona no
-- se solapan (convención OMOP), así que como mucho UNO contiene la fecha
-- índice. Se comprueba en el SELECT final: filas = personas distintas.
-- Es un JOIN interno: quien no tiene un periodo así desaparece aquí, que
-- es justo el filtro.
-- Resta de fechas: date − integer = date (365 días antes).
obs_previa AS (
    SELECT e.cohort_definition_id,
           e.person_id,
           e.fecha_indice,
           op.observation_period_start_date AS op_inicio,
           op.observation_period_end_date   AS op_fin
    FROM periodo_estudio e
    JOIN cdm.observation_period op
      ON op.person_id = e.person_id
     AND op.observation_period_start_date <= e.fecha_indice - 365
     AND op.observation_period_end_date   >= e.fecha_indice
),
-- Actividad 4. lavado: CERO exposición al fármaco en los 365 días previos
-- al índice, ventana [−365, −1] (decisión 10). Es un filtro distinto de
-- obs_previa: aquel dice «te estábamos viendo», este dice «y no lo tenías».
-- NOT EXISTS (anti-semi-join): deja pasar a quien no tiene NINGUNA receta
-- que cumpla; no trae columnas ni puede multiplicar filas.
-- «Exposición en la ventana» = receta que empezó ANTES del índice
-- (inicio < índice: el día 0 es el propio índice, no cuenta) y que NO
-- terminó antes de la ventana (fin ≥ índice − 365). Mirar solo la fecha de
-- inicio sería un error: una receta que empezó hace 2 años y dura 3 sigue
-- activa en la ventana (medido: 779 / 609 usuarios previos se colarían).
-- greatest(fin, inicio): 83 / 64 recetas tienen fin < inicio (act. 2b);
-- así su duración nunca es negativa.
-- Con índice = primera receta de TODA la historia (act. 2b) no existe
-- ninguna receta anterior: el filtro quita 0 por construcción. Se deja
-- explícito para que la definición lo diga, y porque protege si algún día
-- se relaja el evento inicial (control 4a, fuera del bloque).
lavado AS (
    SELECT o.*
    FROM obs_previa o
    WHERE NOT EXISTS (
        SELECT 1
        FROM recetas r
        WHERE r.cohort_definition_id = o.cohort_definition_id
          AND r.person_id = o.person_id
          AND r.inicio < o.fecha_indice
          AND greatest(r.fin, r.inicio) >= o.fecha_indice - 365
    )
),
-- Actividad 5 (decisiones 11 y 12). Criterios clínicos: cada uno lee SOLO
-- del anterior, así que los conteos del SELECT final son una atrición
-- secuencial (lo que quita cada criterio DESPUÉS de los previos; el orden
-- cambia el reparto, no el resultado final).
-- Dos diferencias entre EXISTS y JOIN, para no confundirlas:
--   EXISTS / NOT EXISTS: pregunta «¿hay al menos una fila?», sale en cuanto
--     encuentra una y nunca multiplica filas. Una persona con 12
--     diagnósticos de HTA sigue siendo UNA fila (trampa del enunciado).
--   JOIN: trae las filas de la otra tabla; si hay 12, la persona sale 12
--     veces. Solo se usa cuando se necesita CONTAR (criterio ≥ N, abajo).
--
-- 5a. Inclusión: edad ≥ 18 en la fecha índice. Aproximación por año
-- (año del índice − year_of_birth): se desconoce la fecha exacta de
-- nacimiento para todos. JOIN con person por su clave primaria: 1 fila por
-- persona, no multiplica. Se espera que quite 0 (control 5a).
mayores AS (
    SELECT l.*
    FROM lavado l
    JOIN cdm.person pe USING (person_id)
    WHERE extract(year FROM l.fecha_indice) - pe.year_of_birth >= 18
),
-- 5b. Inclusión: hipertensión (316866 «Hypertensive disorder» y todos sus
-- descendientes) en (−∞, 0]: cualquier fecha hasta el día índice, incluido.
-- Ventana abierta hacia atrás porque la HTA es crónica y se registra una
-- sola vez al diagnosticarse (339 de 346 tienen < 2 registros, así que
-- tampoco sirve para un criterio «≥ N»). Con el inicio de estudio 2017,
-- (−∞, 0] y [−365, 0] casi coinciden (26 vs 36 que no cumplen).
con_hta AS (
    SELECT m.*
    FROM mayores m
    WHERE EXISTS (
        SELECT 1
        FROM cdm.condition_occurrence co
        JOIN cdm.concept_ancestor ca
          ON ca.descendant_concept_id = co.condition_concept_id
        WHERE ca.ancestor_concept_id = 316866
          AND co.person_id = m.person_id
          AND co.condition_start_date <= m.fecha_indice
    )
),
-- 5c. Inclusión, tipo «al menos N en la ventana W» (decisión 11): ≥ 2
-- visitas en [−365, −1]. EXISTS no sabe contar: dice «hay una», no «hay
-- dos». Aquí sí se necesita el JOIN para tener una fila por visita, y
-- GROUP BY + HAVING para contarlas por persona. Orden lógico: FROM
-- (persona ⨝ visitas de la ventana) → GROUP BY persona → HAVING count ≥ 2.
-- El JOIN multiplica a propósito (una fila por visita); el GROUP BY lo
-- vuelve a dejar en una fila por persona, y la persona se une de vuelta
-- al CTE por su clave (cohorte, persona), único en cada lado.
-- Ventana hasta −1: el día 0 es la visita donde se receta, no evidencia
-- de contacto previo. Quien no tiene ninguna visita no aparece en el JOIN
-- interno y sale, que es lo que se quiere.
con_visitas AS (
    SELECT h.*
    FROM con_hta h
    JOIN (
        SELECT h2.cohort_definition_id, h2.person_id
        FROM con_hta h2
        JOIN cdm.visit_occurrence v
          ON v.person_id = h2.person_id
         AND v.visit_start_date BETWEEN h2.fecha_indice - 365
                                    AND h2.fecha_indice - 1
        GROUP BY h2.cohort_definition_id, h2.person_id
        HAVING count(*) >= 2
    ) ok USING (cohort_definition_id, person_id)
),
-- 5d. Exclusión: demencia (4182210 «Dementia» y descendientes) en (−∞, 0].
-- Sin esto el desenlace no sería incidente. Va en (−∞, 0] y no solo en el
-- año previo: la demencia no desaparece, y un diagnóstico de hace 3 años
-- sigue excluyendo. NOT EXISTS: deja pasar a quien no tiene ninguna.
sin_demencia AS (
    SELECT v.*
    FROM con_visitas v
    WHERE NOT EXISTS (
        SELECT 1
        FROM cdm.condition_occurrence co
        JOIN cdm.concept_ancestor ca
          ON ca.descendant_concept_id = co.condition_concept_id
        WHERE ca.ancestor_concept_id = 4182210
          AND co.person_id = v.person_id
          AND co.condition_start_date <= v.fecha_indice
    )
),
-- 5e. Exclusión: ya usa (o empieza el mismo día) el OTRO fármaco, en
-- (−∞, 0]. Mismo concept_ancestor que `recetas`, pero con el ingrediente
-- del otro fármaco. Incluye el día 0: quien inicia los dos a la vez no es
-- nuevo usuario de uno solo (507 casos antes del lavado y del inicio de
-- estudio). No se limita a 365 días: el filtro es «nuevo usuario de UNO».
-- Tener el otro fármaco después del índice NO excluye (eso es la salida,
-- actividad 6).
sin_otro_farmaco AS (
    SELECT d.*
    FROM sin_demencia d
    WHERE NOT EXISTS (
        SELECT 1
        FROM results.cohorte_parametros p
        JOIN cdm.concept_ancestor ca ON ca.ancestor_concept_id = p.ingrediente_otro
        JOIN cdm.drug_exposure de    ON de.drug_concept_id = ca.descendant_concept_id
        WHERE p.cohort_definition_id = d.cohort_definition_id
          AND de.person_id = d.person_id
          AND de.drug_type_concept_id = 32838
          AND de.drug_exposure_start_date <= d.fecha_indice
    )
),
-- 5f. Exclusión: el producto del índice es una combinación (decisión 12).
-- Un producto con más de un ingrediente (lisinopril/HCTZ, amlodipino/
-- benazepril, Tribenzor) inicia DOS clases a la vez, aunque la otra no sea
-- el comparador. Se cuenta ingredientes distintos en drug_strength. Las
-- recetas consideradas son las del día índice (inicio = fecha_indice).
sin_combinacion AS (
    SELECT o.*
    FROM sin_otro_farmaco o
    WHERE NOT EXISTS (
        SELECT 1
        FROM recetas r
        WHERE r.cohort_definition_id = o.cohort_definition_id
          AND r.person_id = o.person_id
          AND r.inicio = o.fecha_indice
          AND r.drug_concept_id IN (
              SELECT drug_concept_id
              FROM cdm.drug_strength
              GROUP BY drug_concept_id
              HAVING count(DISTINCT ingredient_concept_id) > 1)
    )
),
-- Actividad 6 (decisiones 13 y 14). Estrategia de salida: fin de la
-- exposición continua con gap de 30 días (gaps and islands, lab 11).
-- Idea: ordenar las recetas de cada persona por inicio y marcar «corte»
-- cuando una receta empieza más de 30 días después del fin más tardío de
-- TODAS las anteriores; la suma acumulada de los cortes numera las islas
-- (tramos de exposición continua). Cada isla es un tramo sin huecos > 30.
--
-- 6a. tramos: las recetas de las personas que llegaron hasta aquí, con el
-- número de isla. Dos precauciones heredadas:
--  · fin máximo acumulado (no LAG): con recetas solapadas, el fin de la
--    receta inmediatamente anterior puede ser menor que el de una más
--    antigua y partiría un tramo continuo en dos (lab 11, decisión 3).
--  · greatest(fin, inicio): 83 / 64 recetas tienen fin < inicio; así su
--    duración nunca es negativa (igual que en el lavado, actividad 4).
-- Un hueco de exactamente 30 días NO corta (inicio − fin_previo > 30),
-- convención de DRUG_ERA de OMOP. Resta de dos date = días (entero).
-- El JOIN con sin_combinacion es por (cohorte, persona), única en ese
-- lado: cada receta sale una vez (se comprueba más abajo contando filas).
tramos AS (
    SELECT r.cohort_definition_id, r.person_id, r.inicio,
           greatest(r.fin, r.inicio) AS fin,
           sum(CASE WHEN fin_previo IS NULL OR r.inicio - fin_previo > 30
                    THEN 1 ELSE 0 END)
               OVER (PARTITION BY r.cohort_definition_id, r.person_id
                     ORDER BY r.inicio, r.fin
                     ROWS UNBOUNDED PRECEDING) AS isla
    FROM (
        SELECT r.*,
               max(greatest(r.fin, r.inicio))
                   OVER (PARTITION BY r.cohort_definition_id, r.person_id
                         ORDER BY r.inicio, r.fin
                         ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)
                   AS fin_previo
        FROM recetas r
        JOIN sin_combinacion s USING (cohort_definition_id, person_id)
    ) r
),
-- 6b. tramo_indice: el tramo que contiene la fecha índice. Como el índice es
-- la primera receta de la historia (actividad 2b), ese tramo es el primero
-- (isla = 1) y empieza en el índice. Su fin es el fin más tardío de las
-- recetas del tramo. Los tramos posteriores (quien volvió tras un hueco
-- > 30 días) no cuentan: la salida es el FIN DE LA EXPOSICIÓN CONTINUA
-- desde el índice. GROUP BY → una fila por persona y cohorte.
tramo_indice AS (
    SELECT cohort_definition_id, person_id, max(fin) AS fin_tramo
    FROM tramos
    WHERE isla = 1
    GROUP BY cohort_definition_id, person_id
),
-- 6c. otro_post: el primer día que la persona empieza el OTRO fármaco
-- después del índice (decisión 14). El día del índice no cuenta: quien lo
-- empezó antes o ese día ya quedó fuera en la actividad 5. Mismo
-- concept_ancestor que el criterio 5e, pero con inicio > fecha_indice.
-- LEFT JOIN al final: la mayoría nunca lo empieza → NULL, y NULL no
-- recorta nada (least() ignora los NULL en Postgres).
otro_post AS (
    SELECT s.cohort_definition_id, s.person_id,
           min(de.drug_exposure_start_date) AS fecha_otro
    FROM sin_combinacion s
    JOIN results.cohorte_parametros p USING (cohort_definition_id)
    JOIN cdm.concept_ancestor ca ON ca.ancestor_concept_id = p.ingrediente_otro
    JOIN cdm.drug_exposure de    ON de.drug_concept_id = ca.descendant_concept_id
    WHERE de.person_id = s.person_id
      AND de.drug_type_concept_id = 32838
      AND de.drug_exposure_start_date > s.fecha_indice
    GROUP BY s.cohort_definition_id, s.person_id
),
-- 6d. salida: la fecha de salida es el MÍNIMO de tres fechas (trampa del
-- enunciado: nunca seguir a nadie más allá de donde llegan los datos):
--   1. fin del tramo + 30 días de persistencia (decisión 13)
--   2. fin del periodo de observación (op_fin, que viene de obs_previa)
--   3. inicio del otro fármaco (decisión 14), si lo hay
-- least() en Postgres ignora NULL (a diferencia de otros motores), así que
-- fecha_otro NULL simplemente no participa. Una fecha NULL en greatest/least
-- en SQL Server o Oracle daría NULL: cuidado al portar.
-- motivo: cuál de las tres fue la que ganó; en un empate gana la primera de
-- la lista (otro fármaco > fin de observación > fin de exposición).
salida AS (
    SELECT s.cohort_definition_id, s.person_id, s.fecha_indice, s.op_fin,
           t.fin_tramo, o.fecha_otro,
           least(t.fin_tramo + 30, s.op_fin, o.fecha_otro) AS fecha_salida
    FROM sin_combinacion s
    JOIN tramo_indice t USING (cohort_definition_id, person_id)
    LEFT JOIN otro_post o USING (cohort_definition_id, person_id)
),
salida_motivo AS (
    SELECT *,
           CASE WHEN fecha_salida = fecha_otro THEN 'otro fármaco'
                WHEN fecha_salida = op_fin     THEN 'fin de observación'
                ELSE 'fin de exposición + 30 d' END AS motivo
    FROM salida
)
-- Resultado (2026-11-15), 48 filas (12 pasos × 4 cohortes), ~18 s;
-- filas = distintos en todas:
--   paso                         1701    1702  |  1711    1712 (sensibilidad)
--   0 recetas del fármaco      42,085  34,475  | 42,085  34,475
--   1 evento inicial            1,522   1,104  |  1,522   1,104
--   2 índice en periodo estudio   346     238  |  1,522   1,104
--   3 + 365 días de observación   346     238  |  1,522   1,104  (pérdida 0)
--   4 + lavado 365 días           346     238  |  1,522   1,104  (pérdida 0)
--   5a + edad ≥ 18                346     238  |  1,522   1,104  (pérdida 0)
--   5b + hipertensión (−∞, 0]     320     237  |  1,447   1,102
--   5c + ≥ 2 visitas [−365, −1]   173     165  |    421     340
--   5d − demencia previa          172     164  |    409     329
--   5e − otro fármaco previo      122      81  |    246     131
--   5f − combinación en índice    122      81  |    242     131
--   6 con fecha de salida         122      81  |    242     131  (una por persona)
-- Actividad 5 (decisiones 11 y 12). Cohorte final de la definición
-- principal: 122 lisinopril y 81 amlodipino (35 % y 34 % de las 346 / 238).
-- Pérdida de cada criterio en secuencia (lisinopril / amlodipino):
--   HTA 26 / 1 · visitas 147 / 72 · demencia 1 / 1 · otro fármaco 50 / 83 ·
--   combinación 0 / 0 · edad 0 / 0.
-- Solo, cada criterio quita más o igual que en secuencia (HTA 26/1, visitas
-- 147/72, demencia 4/1, otro fármaco 63/102): en secuencia los que ya
-- salieron antes no se cuentan otra vez. El orden reparte la pérdida, no
-- cambia la cohorte final. El criterio de visitas es el más costoso en
-- lisinopril (42 % de lo que le llega); el del otro fármaco, en amlodipino
-- (51 % de lo que le llega).
-- 5f quita 0 en 1701/1702 por una razón comprobada, no por un error: las dos
-- personas que sobrevivían a HTA y visitas con un producto combinado (4289:
-- lisinopril/HCTZ; 4506: amlodipino/benazepril) ya tomaban el otro fármaco
-- y salen en 5e. El criterio sí funciona: en la sensibilidad (1711) quita 4.
-- Actividad 6 (decisiones 13 y 14). Salida = mínimo entre fin del tramo + 30,
-- fin de la observación y primer día del otro fármaco. La distribución está
-- en distribucion_salida.sql; duración en días desde el índice:
--   cohorte  motivo                     personas  mediana  [q1 – q3]
--   1701     todos                          122      928   30 – 1,869
--            fin de observación              61    1,853   1,127 – 2,597
--            fin de exposición + 30 d        21    1,143   30 – 2,256
--            otro fármaco                    40       30   30 – 60
--   1702     todos                           81      401   30 – 1,514
--            fin de observación              36    1,476   723 – 2,123
--            fin de exposición + 30 d        19    1,484   202 – 2,226
--            otro fármaco                    26       30   30 – 30
--   (1711 / 1712, sensibilidad: mediana 2,629 / 1,505; 42 / 30 por otro fármaco)
--   Validaciones: 0 salidas antes del índice y 0 después del fin de la
--   observación en las cuatro cohortes; todos los tramos empiezan en el
--   índice. Contraste independiente: sin el corte por otro fármaco, la
--   mediana de la salida da 1,514 / 1,484 (1701 / 1702) y 2,964 / 2,226
--   (1711 / 1712), igual que una consulta de islas escrita aparte.
--   Lectura: el 33 % (lisinopril) y el 32 % (amlodipino) salen por empezar
--   el otro fármaco, con una mediana de exactamente 30 días: es el
--   añadido en la primera renovación, no un cambio tardío. Esas 66 personas
--   aportan 98 días o menos de seguimiento. Solo el 57 % y 56 % superan un
--   año (69 de 122 y 45 de 81).
-- Las visitas se cuentan por fila, no por día distinto. Contar días
-- distintos cambia 0 personas en 1701/1702 (173 y 165 en ambos) y quita 9 y
-- 1 en la sensibilidad 1711/1712 (421 → 412, 340 → 339): no afecta a la
-- definición principal.
-- Actividad 3c: el inicio de estudio quita 1,176 (77.3 %) y 866 (78.4 %);
-- incluye los 665 / 545 del pico de 2016. Costo: demencias incidentes antes
-- de los demás criterios 3 / 2 (60 / 38 sin el filtro) → con esta base no
-- se puede estudiar el desenlace; se reporta, no se afloja (decisión 9).
-- Actividad 3a: no quita a nadie, y no por poco: días de observación
-- antes del índice, mínimo 371 / 772 y mediana 13,548 / 13,661 (~37 años);
-- solo 2 personas con menos de 2 años. Es el periodo de décadas de los
-- controles 0a-0c: el filtro se cumple siempre, sin probar observación
-- real (antes de 2016 solo ~1 de cada 4 «observados» tiene visitas).
-- Actividad 4: el lavado quita 0 por construcción (índice = 1.ª receta de la
-- historia: no hay recetas anteriores). El control 4a (fuera del bloque)
-- prueba que el criterio no es vacío: aplicado a un índice más flojo quita
-- 777 / 609 de 1,125 / 847 (decisión 10).
-- 42,085 ≠ 42,002 de results.lisinopril_exposicion (lab 13): la diferencia
-- son las 83 recetas con fin < inicio (days_supply negativo, mínimo −6),
-- que el lab 13 excluyó. Aquí se conservan porque su fecha de INICIO es
-- válida: comprobado que excluirlas no cambia la fecha índice de nadie
-- (0 en las dos cohortes). Amlodipino tiene 64 (36 personas). Pendiente
-- para la actividad 6, donde sí importa la duración. Sin fin NULL; fin =
-- inicio en 1,772 y 1,201 recetas («en curso» del ETL, lab 13).
-- [CONTEO] Los scripts de figuras cortan el bloque en esta línea y añaden
-- su propio SELECT: así usan exactamente los mismos CTE.
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
UNION ALL
SELECT '2 índice en el periodo de estudio', cohort_definition_id,
       count(*), count(DISTINCT person_id)
FROM periodo_estudio GROUP BY cohort_definition_id
UNION ALL
SELECT '3 + 365 días de observación', cohort_definition_id,
       count(*), count(DISTINCT person_id)
FROM obs_previa GROUP BY cohort_definition_id
UNION ALL
SELECT '4 + lavado 365 días', cohort_definition_id,
       count(*), count(DISTINCT person_id)
FROM lavado GROUP BY cohort_definition_id
UNION ALL
SELECT '5a + edad ≥ 18', cohort_definition_id,
       count(*), count(DISTINCT person_id)
FROM mayores GROUP BY cohort_definition_id
UNION ALL
SELECT '5b + hipertensión (−∞, 0]', cohort_definition_id,
       count(*), count(DISTINCT person_id)
FROM con_hta GROUP BY cohort_definition_id
UNION ALL
SELECT '5c + ≥ 2 visitas en [−365, −1]', cohort_definition_id,
       count(*), count(DISTINCT person_id)
FROM con_visitas GROUP BY cohort_definition_id
UNION ALL
SELECT '5d − demencia previa', cohort_definition_id,
       count(*), count(DISTINCT person_id)
FROM sin_demencia GROUP BY cohort_definition_id
UNION ALL
SELECT '5e − otro fármaco previo', cohort_definition_id,
       count(*), count(DISTINCT person_id)
FROM sin_otro_farmaco GROUP BY cohort_definition_id
UNION ALL
SELECT '5f − combinación en el índice', cohort_definition_id,
       count(*), count(DISTINCT person_id)
FROM sin_combinacion GROUP BY cohort_definition_id
UNION ALL
SELECT '6 con fecha de salida', cohort_definition_id,
       count(*), count(DISTINCT person_id)
FROM salida_motivo GROUP BY cohort_definition_id
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
      -- 1711/1712 tienen los mismos fármacos: se omiten para no duplicar.
      -- Describe el evento inicial (antes del periodo de estudio).
      AND p.cohort_definition_id IN (1701, 1702)
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

-- Control 4a. ¿El lavado hace algo, o es un filtro vacío?
-- Con índice = 1.ª receta de la historia quita 0 por construcción, así que
-- no se puede saber si el criterio está bien escrito. Prueba: aplicarlo a un
-- índice MÁS FLOJO, cualquier receta desde 2017 (cada receta es un
-- candidato), donde SÍ debe quitar gente. Es un diagnóstico, no la cohorte.
-- Funciones de ventana en vez de NOT EXISTS por candidato: la versión
-- correlacionada (una subconsulta por cada una de las ~40,000 recetas)
-- pasó de 2 minutos; esta corre en segundos. Ventana: las recetas de la
-- misma persona ordenadas por inicio; RANGE con intervalos mira por FECHA
-- (no por posición), así que las recetas del mismo día no se cuentan
-- entre sí (la ventana termina 1 día antes: «inicio < índice»).
--   n_inicio_vent : recetas con INICIO en [−365, −1]
--   max_fin_prev  : fin más tardío de todas las recetas anteriores
-- Tres cuentas de personas por cohorte (con ≥ 1 candidato que pasa):
--   solo_inicio : lavado mirando solo fechas de inicio (n_inicio_vent = 0)
--   activa      : lavado de la cohorte (max_fin_prev < índice − 365 o NULL)
--   historia    : cohorte real (candidato = 1.ª receta de toda la historia)
-- Resultado (2026-11-15): 1701 → 1,125 / 348 / 346; 1702 → 847 / 238 / 238.
--   El lavado por inicio deja 779 / 609 usuarios previos cuya receta
--   anterior sigue vigente (duran años). El de exposición activa los quita
--   casi todos y difiere de la cohorte real en 2 personas (1701): reinician
--   tras más de 365 días sin fármaco; no son «nuevas» (decisión 10).
WITH recetas AS (
    SELECT p.cohort_definition_id AS c, d.person_id,
           d.drug_exposure_start_date AS inicio,
           greatest(d.drug_exposure_end_date,
                    d.drug_exposure_start_date) AS fin   -- fin < inicio: 83/64
    FROM results.cohorte_parametros p
    JOIN cdm.concept_ancestor ca ON ca.ancestor_concept_id = p.ingrediente_exp
    JOIN cdm.drug_exposure d     ON d.drug_concept_id = ca.descendant_concept_id
    WHERE d.drug_type_concept_id = 32838
      AND p.cohort_definition_id IN (1701, 1702)
),
con_pasado AS (
    SELECT c, person_id, inicio,
           count(*) OVER w365 AS n_inicio_vent,
           max(fin) OVER wprev AS max_fin_prev,
           min(inicio) OVER (PARTITION BY c, person_id) AS primera
    FROM recetas
    WINDOW w365  AS (PARTITION BY c, person_id ORDER BY inicio
                     RANGE BETWEEN INTERVAL '365 days' PRECEDING
                               AND INTERVAL '1 day' PRECEDING),
           wprev AS (PARTITION BY c, person_id ORDER BY inicio
                     RANGE BETWEEN UNBOUNDED PRECEDING
                               AND INTERVAL '1 day' PRECEDING)
)
SELECT c AS cohorte,
       count(DISTINCT person_id) FILTER (WHERE n_inicio_vent = 0)  AS solo_inicio,
       count(DISTINCT person_id) FILTER (WHERE max_fin_prev IS NULL
                                    OR max_fin_prev < inicio - 365) AS activa,
       count(DISTINCT person_id) FILTER (WHERE inicio = primera)   AS historia
FROM con_pasado
WHERE inicio >= DATE '2017-01-01'
GROUP BY c ORDER BY c;

-- Control 5a. ¿Los conceptos de los criterios son lo que creemos, y year_of_birth
-- sirve para la edad? Un id mal tecleado no daría error: daría un criterio vacío.
-- Resultado (2026-11-15):
--   316866  Hypertensive disorder · Condition · Disorder · S · vigente
--   4182210 Dementia              · Condition · Disorder · S · vigente
--   person: 5,904 filas, year_of_birth NULL 0 (rango 1916-2026; el 2026 no es
--   un adulto, pero ninguno entra a la cohorte: el criterio 5a quita 0).
SELECT concept_id, concept_name, domain_id, concept_class_id,
       standard_concept, invalid_reason
FROM cdm.concept
WHERE concept_id IN (316866, 4182210)
ORDER BY concept_id;

SELECT count(*) AS personas,
       count(*) FILTER (WHERE year_of_birth IS NULL) AS yob_nulo,
       min(year_of_birth) AS min_yob, max(year_of_birth) AS max_yob
FROM cdm.person;
