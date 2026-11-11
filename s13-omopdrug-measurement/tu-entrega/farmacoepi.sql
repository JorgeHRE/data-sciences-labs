-- =====================================================================
-- Lab 13 — Farmacoepidemiología y calidad de mediciones en OMOP CDM
-- Base: Postgres del lab 12 (contenedor lab12-omop-db-1, puerto 5433,
--       BD omop_lab12). Esquema cdm = solo lectura; lo propio va a results.
-- Ejecutar completo:
--   docker exec -i lab12-omop-db-1 psql -U <usuario> -d omop_lab12 \
--     -v ON_ERROR_STOP=1 < farmacoepi.sql
-- Recordatorio del orden lógico de ejecución de un SELECT:
--   FROM → WHERE → GROUP BY → HAVING → SELECT → ORDER BY
-- =====================================================================

-- Paso 0. Esquema propio: separa los resultados del lab de las tablas
-- del CDM, para no tocar nunca lo que generó el ETL.
CREATE SCHEMA IF NOT EXISTS results;

-- Paso 0. Control de punto de partida: deben coincidir con el lab 12
-- (drug_exposure 467,590 · measurement 4,008,280 · observation 1,929,625 ·
--  drug_era 50,407 · condition_era 100,233 · concept_ancestor 12,077,497).
SELECT 'drug_exposure' AS tabla, count(*) AS filas FROM cdm.drug_exposure
UNION ALL SELECT 'measurement',      count(*) FROM cdm.measurement
UNION ALL SELECT 'observation',      count(*) FROM cdm.observation
UNION ALL SELECT 'drug_era',         count(*) FROM cdm.drug_era
UNION ALL SELECT 'condition_era',    count(*) FROM cdm.condition_era
UNION ALL SELECT 'concept_ancestor', count(*) FROM cdm.concept_ancestor;

-- =====================================================================
-- Actividad 1. ¿Qué tipo de exposición tenemos? (drug_type_concept_id)
-- Por qué: el tipo dice qué tan cerca está el registro de la toma real
-- (prescripción < dispensación < administración). Hay que saberlo ANTES de
-- interpretar cualquier conteo de "pacientes expuestos".
-- Orden lógico: FROM/JOIN → GROUP BY → SELECT (ventana sobre el agregado)
-- → ORDER BY.
-- =====================================================================
SELECT
    de.drug_type_concept_id,
    ct.concept_name                         AS tipo_exposicion,
    -- Vocabulario del fármaco: separa RxNorm (medicamentos) de CVX (vacunas).
    cd.vocabulary_id                        AS vocabulario_farmaco,
    count(*)                                AS filas,
    count(DISTINCT de.person_id)            AS personas,
    round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct_filas
FROM cdm.drug_exposure de
-- LEFT JOIN: si un tipo no existiera en el vocabulario, la fila no se pierde
-- (saldría con nombre NULL y lo veríamos). concept_id es clave primaria de
-- concept, así que estos JOIN no pueden multiplicar filas.
LEFT JOIN cdm.concept ct ON ct.concept_id = de.drug_type_concept_id
LEFT JOIN cdm.concept cd ON cd.concept_id = de.drug_concept_id
GROUP BY de.drug_type_concept_id, ct.concept_name, cd.vocabulary_id
ORDER BY filas DESC;

-- Control: la suma de las categorías debe ser igual al total de la tabla
-- (467,590). Si difiere, algún JOIN duplicó o perdió filas.
SELECT
    (SELECT count(*) FROM cdm.drug_exposure)                  AS total_tabla,
    (SELECT count(*) FROM cdm.drug_exposure de
       LEFT JOIN cdm.concept ct ON ct.concept_id = de.drug_type_concept_id
       LEFT JOIN cdm.concept cd ON cd.concept_id = de.drug_concept_id) AS total_tras_join,
    (SELECT count(*) FROM cdm.drug_exposure
      WHERE drug_type_concept_id IS NULL OR drug_type_concept_id = 0) AS tipo_nulo_o_cero;

-- =====================================================================
-- Actividad 2a. Top 20 de ingredientes por pacientes distintos
-- Decisión 3: producto → ingrediente vía concept_ancestor (cubre 346/346
-- productos; drug_strength solo 335). Solo prescripciones (decisión 2).
-- Ojo: un producto con varios ingredientes (55 productos) genera una fila
-- por ingrediente → el JOIN multiplica filas A PROPÓSITO; por eso se cuenta
-- count(DISTINCT person_id), nunca count(*).
-- Orden lógico: FROM/JOIN → WHERE → GROUP BY → SELECT → ORDER BY → LIMIT
-- =====================================================================
WITH receta_ingrediente AS (
    SELECT de.drug_exposure_id, de.person_id,
           ing.concept_id   AS ingrediente_id,
           ing.concept_name AS ingrediente
    FROM cdm.drug_exposure de
    JOIN cdm.concept_ancestor ca ON ca.descendant_concept_id = de.drug_concept_id
    JOIN cdm.concept ing         ON ing.concept_id = ca.ancestor_concept_id
                                AND ing.concept_class_id = 'Ingredient'
                                AND ing.standard_concept = 'S'
    WHERE de.drug_type_concept_id = 32838          -- solo prescripciones
)
SELECT ingrediente_id, ingrediente,
       count(DISTINCT person_id)  AS pacientes,
       count(*)                   AS recetas
FROM receta_ingrediente
GROUP BY ingrediente_id, ingrediente
ORDER BY pacientes DESC, ingrediente
LIMIT 20;

-- Control del JOIN: filas antes (recetas) vs después (pares receta-ingrediente)
-- y recetas que se quedaron sin ingrediente (deberían ser 0).
SELECT
    (SELECT count(*) FROM cdm.drug_exposure WHERE drug_type_concept_id = 32838) AS recetas_antes,
    count(*)                              AS pares_receta_ingrediente,
    count(DISTINCT de.drug_exposure_id)   AS recetas_con_ingrediente
FROM cdm.drug_exposure de
JOIN cdm.concept_ancestor ca ON ca.descendant_concept_id = de.drug_concept_id
JOIN cdm.concept ing ON ing.concept_id = ca.ancestor_concept_id
                    AND ing.concept_class_id = 'Ingredient' AND ing.standard_concept = 'S'
WHERE de.drug_type_concept_id = 32838;

-- =====================================================================
-- Actividad 2b. Distribución de days_supply (solo prescripciones)
-- Decisión 4: se reporta CRUDA + tabla de banderas; no se limpia aquí.
-- Concepto: percentile_cont(p) WITHIN GROUP (ORDER BY x) es una función de
-- agregado ordenado: ordena los valores y devuelve el percentil p
-- (interpolando si cae entre dos valores).
-- =====================================================================
SELECT
    count(*)                                                     AS recetas,
    count(*) FILTER (WHERE days_supply IS NULL)                  AS nulos,
    min(days_supply)                                             AS minimo,
    percentile_cont(0.25) WITHIN GROUP (ORDER BY days_supply)    AS p25,
    percentile_cont(0.50) WITHIN GROUP (ORDER BY days_supply)    AS mediana,
    percentile_cont(0.75) WITHIN GROUP (ORDER BY days_supply)    AS p75,
    percentile_cont(0.95) WITHIN GROUP (ORDER BY days_supply)    AS p95,
    max(days_supply)                                             AS maximo,
    -- ¿days_supply es un dato propio o se derivó de las fechas?
    count(*) FILTER (WHERE days_supply = drug_exposure_end_date
                                       - drug_exposure_start_date) AS igual_fin_menos_inicio
FROM cdm.drug_exposure
WHERE drug_type_concept_id = 32838;

-- Tabla de banderas: categorías excluyentes que deben sumar 388,700.
-- CASE evalúa en orden y se queda con la PRIMERA condición verdadera.
SELECT bandera, count(*) AS recetas,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM (
    SELECT CASE
             WHEN days_supply IS NULL THEN '0. nulo'
             WHEN days_supply < 0     THEN '1. negativo (imposible)'
             WHEN days_supply = 0     THEN '2. cero (fin = inicio)'
             WHEN days_supply = 371   THEN '4. pila en 371 (posible tope del generador)'
             WHEN days_supply > 365   THEN '5. más de 365 días'
             ELSE                          '3. 1-365 días (plausible)'
           END AS bandera
    FROM cdm.drug_exposure
    WHERE drug_type_concept_id = 32838
) t
GROUP BY bandera
ORDER BY bandera;

-- =====================================================================
-- Actividad 2c. Completitud de fechas y conceptos sin mapear
-- Se calcula con y sin vacunas para ver el efecto de la decisión 2.
-- Concepto: FILTER (WHERE ...) restringe un agregado a ciertas filas sin
-- tener que escribir un CASE dentro del count.
-- avg(condición::int) = proporción de filas donde la condición es verdadera.
-- =====================================================================
SELECT
    CASE WHEN grouping(drug_type_concept_id) = 1
         THEN 'Total (con vacunas)'
         ELSE max(c.concept_name) END                                AS grupo,
    count(*)                                                         AS filas,
    count(*) FILTER (WHERE drug_exposure_end_date IS NULL)           AS sin_fin,
    count(*) FILTER (WHERE drug_exposure_end_date
                         = drug_exposure_start_date)                 AS fin_igual_inicio,
    round(100 * avg((drug_exposure_end_date IS NULL
                  OR drug_exposure_end_date = drug_exposure_start_date)::int), 1)
                                                                     AS pct_sin_fin_o_igual,
    count(*) FILTER (WHERE drug_exposure_end_date
                         < drug_exposure_start_date)                 AS fin_antes_inicio,
    count(*) FILTER (WHERE drug_concept_id = 0)                      AS concepto_cero,
    round(100 * avg((drug_concept_id = 0)::int), 2)                  AS pct_concepto_cero
FROM cdm.drug_exposure de
LEFT JOIN cdm.concept c ON c.concept_id = de.drug_type_concept_id   -- solo para el nombre
-- ROLLUP añade una fila extra con el total de todos los grupos.
GROUP BY ROLLUP (drug_type_concept_id)
ORDER BY grouping(drug_type_concept_id), filas DESC;

-- =====================================================================
-- Actividad 3. Buscar por ingrediente, no por producto (lisinopril)
-- Decisión 5: ingrediente = lisinopril (1308216); se reutiliza en act. 4-5.
-- Concepto: concept_ancestor guarda TODOS los pares ancestro → descendiente
-- a cualquier distancia (incluido el propio concepto, con nivel 0). Con un
-- solo JOIN se obtiene todo lo que "contiene" el ingrediente.
-- El par (ancestor, descendant) es único, así que filtrar por UN ancestro
-- no multiplica filas: cada receta aparece como máximo una vez.
-- =====================================================================
WITH ing AS (SELECT 1308216 AS id)               -- lisinopril
SELECT
    c.concept_name                                          AS ingrediente,
    -- 1) Búsqueda directa: solo recetas cuyo producto ES el ingrediente
    (SELECT count(DISTINCT de.person_id)
       FROM cdm.drug_exposure de
      WHERE de.drug_type_concept_id = 32838
        AND de.drug_concept_id = ing.id)                    AS pacientes_exacto,
    -- 2) Búsqueda jerárquica: el ingrediente y todos sus descendientes
    (SELECT count(DISTINCT de.person_id)
       FROM cdm.drug_exposure de
       JOIN cdm.concept_ancestor ca
         ON ca.descendant_concept_id = de.drug_concept_id
      WHERE de.drug_type_concept_id = 32838
        AND ca.ancestor_concept_id = ing.id)                AS pacientes_con_descendientes
FROM ing
JOIN cdm.concept c ON c.concept_id = ing.id;

-- ¿De dónde sale la diferencia? Productos descendientes presentes en los
-- datos, con su clase y la distancia en la jerarquía.
SELECT p.concept_name        AS producto,
       p.concept_class_id    AS clase,
       ca.min_levels_of_separation AS niveles,
       count(DISTINCT de.person_id) AS pacientes,
       count(*)                     AS recetas
FROM cdm.drug_exposure de
JOIN cdm.concept_ancestor ca ON ca.descendant_concept_id = de.drug_concept_id
JOIN cdm.concept p           ON p.concept_id = de.drug_concept_id
WHERE de.drug_type_concept_id = 32838
  AND ca.ancestor_concept_id = 1308216
GROUP BY p.concept_name, p.concept_class_id, ca.min_levels_of_separation
ORDER BY pacientes DESC;

-- =====================================================================
-- Actividad 4a. Exposiciones de lisinopril listas para construir eras
-- Decisión 6: replicar las reglas OHDSI "non-stockpile" que usó ETL-Synthea
-- (insert_drug_era.sql), para que cualquier diferencia con cdm.drug_era sea
-- de implementación y no de reglas:
--   * fin = end_date; si fuera NULL → inicio + days_supply; si no → inicio + 1
--     (aquí end_date nunca es NULL, así que los 0 días se quedan en 0)
--   * se excluyen days_supply negativos (fin antes que inicio) y concepto 0
-- Se guarda en results (nunca en cdm) para reutilizarla en 4b y en la act. 5.
-- =====================================================================
DROP TABLE IF EXISTS results.lisinopril_exposicion;
CREATE TABLE results.lisinopril_exposicion AS
SELECT
    de.drug_exposure_id,
    de.person_id,
    de.drug_exposure_start_date                          AS inicio,
    COALESCE(de.drug_exposure_end_date,
             de.drug_exposure_start_date + NULLIF(de.days_supply, 0),
             de.drug_exposure_start_date + 1)            AS fin,
    de.days_supply,
    -- Synthea dejó STOP vacío = tratamiento en curso al exportar; el ETL lo
    -- convirtió en fin = inicio. Se marca para la actividad 5 (PDC).
    (de.verbatim_end_date IS NULL)                       AS en_curso
FROM cdm.drug_exposure de
JOIN cdm.concept_ancestor ca
  ON ca.descendant_concept_id = de.drug_concept_id
 AND ca.ancestor_concept_id   = 1308216                  -- lisinopril
WHERE de.drug_type_concept_id = 32838                    -- prescripciones (decisión 2)
  AND de.drug_concept_id <> 0
  AND COALESCE(de.days_supply, 0) >= 0;                  -- fuera los 83 negativos

-- Control: 42,085 recetas − 83 negativas = 42,002 (= drug_exposure_count de
-- cdm.drug_era para lisinopril). Duplicados de drug_exposure_id deben ser 0.
SELECT count(*)                                   AS exposiciones,
       count(*) - count(DISTINCT drug_exposure_id) AS duplicados,
       count(DISTINCT person_id)                  AS pacientes,
       count(*) FILTER (WHERE fin = inicio)       AS cero_dias,
       count(*) FILTER (WHERE en_curso)           AS en_curso,
       count(*) FILTER (WHERE fin < inicio)       AS fin_antes_inicio,
       (SELECT sum(drug_exposure_count) FROM cdm.drug_era
         WHERE drug_concept_id = 1308216)         AS referencia_cdm
FROM results.lisinopril_exposicion;

-- =====================================================================
-- Actividad 4b. Eras de lisinopril con gaps and islands (gap 30 días)
-- Paso 1: para cada exposición, el fin MÁXIMO de las anteriores del paciente
--   (no LAG: una receta larga puede cubrir varias cortas que acaban antes).
-- Paso 2: bandera = 1 si empieza más de 30 días después de ese máximo
--   (o es la primera) → arranca una era nueva.
-- Paso 3: suma acumulada de banderas = número de era (la "isla").
-- Paso 4: agrupar por era. gap_days = días de la era sin cobertura
--   (longitud − días cubiertos, contando una sola vez los solapes).
-- Orden lógico: las ventanas (OVER) se evalúan en el SELECT, por eso cada
-- paso necesita su propia CTE para usar el resultado del anterior.
-- =====================================================================
DROP TABLE IF EXISTS results.lisinopril_era;
CREATE TABLE results.lisinopril_era AS
WITH paso1 AS (
    SELECT person_id, inicio, fin,
           max(fin) OVER (PARTITION BY person_id ORDER BY inicio, fin
                          ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS fin_max_previo
    FROM results.lisinopril_exposicion
), paso2 AS (
    SELECT *,
           CASE WHEN fin_max_previo IS NULL OR inicio > fin_max_previo + 30
                THEN 1 ELSE 0 END                                   AS era_nueva,
           -- días que esta exposición añade y que no cubría ninguna anterior
           greatest(0, fin - greatest(inicio, coalesce(fin_max_previo, inicio))) AS dias_nuevos
    FROM paso1
), paso3 AS (
    SELECT *, sum(era_nueva) OVER (PARTITION BY person_id ORDER BY inicio, fin
                                   ROWS UNBOUNDED PRECEDING)          AS num_era
    FROM paso2
)
SELECT person_id,
       1308216                          AS drug_concept_id,
       min(inicio)                      AS drug_era_start_date,
       max(fin)                         AS drug_era_end_date,
       count(*)                         AS drug_exposure_count,
       (max(fin) - min(inicio)) - sum(dias_nuevos) AS gap_days
FROM paso3
GROUP BY person_id, num_era;

-- Primera comparación con la referencia (cdm.drug_era, mismo ingrediente)
SELECT 'propia' AS fuente, count(*) AS eras, count(DISTINCT person_id) AS pacientes,
       sum(drug_exposure_count) AS exposiciones, sum(gap_days) AS gap_days,
       count(*) FILTER (WHERE gap_days > 0) AS eras_con_hueco
FROM results.lisinopril_era
UNION ALL
SELECT 'cdm.drug_era', count(*), count(DISTINCT person_id),
       sum(drug_exposure_count), sum(gap_days),
       count(*) FILTER (WHERE gap_days > 0)
FROM cdm.drug_era WHERE drug_concept_id = 1308216;

-- =====================================================================
-- Actividad 4c. Comparación era por era con cdm.drug_era
-- Por qué: que los totales coincidan no basta; dos errores pueden
-- compensarse (una era de más en un paciente y una de menos en otro).
-- FULL OUTER JOIN conserva las eras que solo existen en UNA de las dos
-- tablas (con LEFT o INNER JOIN desaparecerían justo las diferencias).
-- Clave del JOIN: (person_id, fecha de inicio). Un paciente no puede tener
-- dos eras del mismo ingrediente que empiecen el mismo día, así que el JOIN
-- es 1 a 1 y no multiplica filas (se verifica abajo).
-- =====================================================================
WITH ref AS (
    SELECT person_id, drug_era_start_date, drug_era_end_date,
           drug_exposure_count, gap_days
    FROM cdm.drug_era
    WHERE drug_concept_id = 1308216
), cmp AS (
    SELECT p.person_id AS pid_propia, r.person_id AS pid_ref,
           p.drug_era_end_date AS fin_propia, r.drug_era_end_date AS fin_ref,
           p.drug_exposure_count AS n_propia, r.drug_exposure_count AS n_ref,
           p.gap_days AS gap_propia, r.gap_days AS gap_ref
    FROM results.lisinopril_era p
    FULL OUTER JOIN ref r
      ON r.person_id = p.person_id
     AND r.drug_era_start_date = p.drug_era_start_date
)
SELECT
    count(*)                                                    AS filas_tras_join,
    count(*) FILTER (WHERE pid_ref IS NULL)                     AS solo_propia,
    count(*) FILTER (WHERE pid_propia IS NULL)                  AS solo_referencia,
    count(*) FILTER (WHERE pid_propia IS NOT NULL AND pid_ref IS NOT NULL
                       AND fin_propia = fin_ref
                       AND n_propia = n_ref
                       AND gap_propia = gap_ref)                AS identicas,
    count(*) FILTER (WHERE pid_propia IS NOT NULL AND pid_ref IS NOT NULL
                       AND fin_propia <> fin_ref)               AS mismo_inicio_otro_fin,
    count(*) FILTER (WHERE pid_propia IS NOT NULL AND pid_ref IS NOT NULL
                       AND (n_propia <> n_ref OR gap_propia <> gap_ref)) AS otro_conteo_o_gap
FROM cmp;
-- Esperado si todo coincide: filas_tras_join = 1,541 = identicas; el resto 0.
-- Si filas_tras_join > 1,541, hay eras que no casan (aparecen en "solo_...").

-- =====================================================================
-- Actividad 5a. Cohorte para el PDC de lisinopril (decisión 7)
-- Índice = primera receta (diseño de usuario nuevo). Se exige que el
-- observation_period que contiene el índice dure 365 días más (índice + 364).
-- Se guarda el fin de observación porque la decisión 7.3 extiende hasta ahí
-- las recetas "en curso".
-- =====================================================================
DROP TABLE IF EXISTS results.lisinopril_pdc_cohorte;
CREATE TABLE results.lisinopril_pdc_cohorte AS
WITH indice AS (
    SELECT person_id, min(inicio) AS fecha_indice
    FROM results.lisinopril_exposicion
    GROUP BY person_id
)
SELECT i.person_id,
       i.fecha_indice,
       i.fecha_indice + 364                  AS fin_ventana,
       op.observation_period_end_date        AS fin_observacion,
       (op.observation_period_end_date >= i.fecha_indice + 364) AS seguimiento_1_anio
FROM indice i
-- El índice cae dentro de un observation_period; cada persona tiene uno solo
-- (5,904 periodos para 5,904 personas), así que el JOIN no multiplica filas.
JOIN cdm.observation_period op
  ON op.person_id = i.person_id
 AND i.fecha_indice BETWEEN op.observation_period_start_date
                        AND op.observation_period_end_date;

-- Control: 1,522 pacientes antes del JOIN y después; cuántos quedan.
SELECT count(*)                                      AS pacientes,
       count(*) - count(DISTINCT person_id)          AS duplicados,
       count(*) FILTER (WHERE seguimiento_1_anio)     AS con_1_anio,
       count(*) FILTER (WHERE NOT seguimiento_1_anio) AS excluidos_seguimiento_corto
FROM results.lisinopril_pdc_cohorte;

-- =====================================================================
-- Actividad 5b. PDC a un año por paciente (principal y sensibilidad)
-- Concepto: generate_series(inicio, fin, '1 day') devuelve una fila por día.
-- Se cruza cada día de la ventana con las recetas que lo cubren; un día
-- cubierto por dos recetas sigue contando UNA vez (bool_or) → sin
-- stockpiling (decisión 7.4) y PDC ≤ 1 por construcción.
-- Cobertura de una receta: días [inicio, fin), es decir fin − inicio días.
--   principal (7.3): receta en curso cubre hasta fin_observacion (inclusive)
--   sensibilidad   : reglas del ETL, receta en curso cubre 0 días
-- =====================================================================
DROP TABLE IF EXISTS results.lisinopril_pdc;
CREATE TABLE results.lisinopril_pdc AS
WITH dias AS (
    SELECT c.person_id, c.fin_observacion, d::date AS dia
    FROM results.lisinopril_pdc_cohorte c
    CROSS JOIN LATERAL generate_series(c.fecha_indice, c.fin_ventana,
                                       interval '1 day') AS d
    WHERE c.seguimiento_1_anio                        -- decisión 7.2
), cobertura AS (
    SELECT d.person_id, d.dia,
           -- LEFT JOIN: los días sin ninguna receta se conservan (x = NULL);
           -- bool_or de NULLs es NULL → coalesce a false (día no cubierto).
           coalesce(bool_or(d.dia >= x.inicio AND d.dia < CASE WHEN x.en_curso
                                 THEN d.fin_observacion + 1 ELSE x.fin END), false) AS cubierto_principal,
           coalesce(bool_or(d.dia >= x.inicio AND d.dia < x.fin), false)            AS cubierto_sensibilidad
    FROM dias d
    LEFT JOIN results.lisinopril_exposicion x
      ON x.person_id = d.person_id
     AND x.inicio <= d.dia                            -- solo recetas ya iniciadas
    GROUP BY d.person_id, d.dia
)
SELECT person_id,
       count(*)                                        AS dias_ventana,
       count(*) FILTER (WHERE cubierto_principal)      AS dias_cubiertos,
       round(avg(cubierto_principal::int), 4)          AS pdc,
       round(avg(cubierto_sensibilidad::int), 4)       AS pdc_sensibilidad
FROM cobertura
GROUP BY person_id;

-- Controles: 1,461 pacientes; todos con 365 días; PDC dentro de [0, 1].
SELECT count(*)                                        AS pacientes,
       count(*) FILTER (WHERE dias_ventana <> 365)     AS ventana_distinta_365,
       count(*) FILTER (WHERE pdc NOT BETWEEN 0 AND 1
                           OR pdc_sensibilidad NOT BETWEEN 0 AND 1) AS fuera_de_rango,
       count(*) FILTER (WHERE pdc < pdc_sensibilidad)  AS principal_menor_que_sens
FROM results.lisinopril_pdc;

-- =====================================================================
-- Actividad 5c. Distribución del PDC, % adherentes y contraste con MPR
-- MPR (medication possession ratio) = suma de days_supply de las recetas
-- que EMPIEZAN en la ventana / 365. Suma recetas, no días: los solapes se
-- cuentan dos veces y una receta larga cuenta entera aunque se salga de la
-- ventana → puede superar 1. El PDC cuenta días distintos → ≤ 1.
-- Para el MPR se usa days_supply tal como lo dejó el ETL (en curso = 0).
-- =====================================================================
WITH mpr AS (
    SELECT c.person_id,
           coalesce(sum(x.days_supply), 0) / 365.0 AS mpr
    FROM results.lisinopril_pdc_cohorte c
    LEFT JOIN results.lisinopril_exposicion x
      ON x.person_id = c.person_id
     AND x.inicio BETWEEN c.fecha_indice AND c.fin_ventana
    WHERE c.seguimiento_1_anio
    GROUP BY c.person_id
), t AS (
    SELECT p.*, m.mpr FROM results.lisinopril_pdc p JOIN mpr m USING (person_id)
)
SELECT medida,
       count(*)                                                       AS pacientes,
       round(avg(v), 3)                                               AS media,
       round(percentile_cont(0.25) WITHIN GROUP (ORDER BY v)::numeric, 3) AS p25,
       round(percentile_cont(0.50) WITHIN GROUP (ORDER BY v)::numeric, 3) AS mediana,
       round(min(v), 3) AS minimo, round(max(v), 3) AS maximo,
       count(*) FILTER (WHERE v = 0)                                  AS igual_0,
       count(*) FILTER (WHERE v > 0 AND v < 0.5)                      AS de_0_a_05,
       count(*) FILTER (WHERE v >= 0.5 AND v < 0.8)                   AS de_05_a_08,
       count(*) FILTER (WHERE v >= 0.8)                               AS mayor_igual_08,
       round(100.0 * avg((v >= 0.8)::int), 1)                         AS pct_adherentes,
       count(*) FILTER (WHERE v > 1)                                  AS mayor_que_1
FROM t
CROSS JOIN LATERAL (VALUES ('1. PDC principal (en curso extendido)', pdc),
                           ('2. PDC sensibilidad (reglas ETL)',      pdc_sensibilidad),
                           ('3. MPR (contraste)',                    mpr)) AS m(medida, v)
GROUP BY medida
ORDER BY medida;

-- =====================================================================
-- Actividad 6a. Top 15 de analitos en measurement
-- Se ordena por número de mediciones y se muestra también pacientes
-- distintos: un analito puede tener muchas mediciones en pocos pacientes
-- (mediciones repetidas) y eso cambia su utilidad para una cohorte.
-- measurement_concept_id es FK a concept (clave primaria) → el JOIN no
-- multiplica filas. Orden lógico: FROM/JOIN → GROUP BY → SELECT → ORDER BY → LIMIT
-- =====================================================================
SELECT m.measurement_concept_id,
       c.concept_name                                   AS analito,
       c.vocabulary_id,
       count(*)                                         AS mediciones,
       count(DISTINCT m.person_id)                      AS pacientes,
       round(count(*)::numeric / count(DISTINCT m.person_id), 1) AS mediciones_por_paciente,
       round(100.0 * avg((m.value_as_number IS NULL)::int), 1)  AS pct_valor_nulo,
       count(DISTINCT m.unit_concept_id)                AS unidades_distintas
FROM cdm.measurement m
JOIN cdm.concept c ON c.concept_id = m.measurement_concept_id
GROUP BY m.measurement_concept_id, c.concept_name, c.vocabulary_id
ORDER BY mediciones DESC
LIMIT 15;

-- =====================================================================
-- Actividad 6b. Distribución de unidades de un analito: globulina (3027970)
-- Elegida porque tiene 2 unidades (g/L y g/dL) y sospechamos un error de
-- etiquetado: la globulina sérica normal es ~2.0-3.5 g/dL = 20-35 g/L.
-- Si los valores «en g/L» caen en 2-3.5, en realidad son g/dL.
-- Se muestra unit_source_value (texto original) junto al concepto mapeado
-- para ver si el error viene del origen o del ETL.
-- LEFT JOIN a concept: una unidad 0 o sin concepto no debe desaparecer.
-- =====================================================================
SELECT m.unit_concept_id,
       coalesce(u.concept_code, '(sin concepto)')   AS unidad,
       m.unit_source_value                          AS unidad_origen,
       count(*)                                     AS mediciones,
       count(DISTINCT m.person_id)                  AS pacientes,
       count(m.value_as_number)                     AS con_valor,
       min(m.value_as_number)                       AS minimo,
       percentile_cont(0.05) WITHIN GROUP (ORDER BY m.value_as_number) AS p05,
       percentile_cont(0.50) WITHIN GROUP (ORDER BY m.value_as_number) AS mediana,
       percentile_cont(0.95) WITHIN GROUP (ORDER BY m.value_as_number) AS p95,
       max(m.value_as_number)                       AS maximo
FROM cdm.measurement m
LEFT JOIN cdm.concept u ON u.concept_id = m.unit_concept_id
WHERE m.measurement_concept_id = 3027970
GROUP BY m.unit_concept_id, u.concept_code, m.unit_source_value
ORDER BY mediciones DESC;

-- =====================================================================
-- Actividad 6c. Valores nulos y operador en measurement
-- (1) % de filas sin value_as_number y, de esas, cuántas traen el valor
--     como texto en value_source_value (resultados cualitativos).
-- (2) operator_concept_id: distinguir NULL de 0. Un 0 significa «sin
--     concepto», no «igual»: si todo es 0 o NULL, NO hay forma de saber
--     desde OMOP si un valor estaba censurado (<, >).
-- (3) Comprobación cruzada: ¿algún texto de origen empieza con < o >?
-- =====================================================================
-- (1) completitud del valor numérico
SELECT count(*)                                                  AS mediciones,
       count(*) FILTER (WHERE value_as_number IS NULL)           AS sin_numero,
       round(100.0 * count(*) FILTER (WHERE value_as_number IS NULL) / count(*), 1) AS pct_sin_numero,
       count(*) FILTER (WHERE value_as_number IS NULL
                          AND nullif(trim(value_source_value), '') IS NOT NULL) AS sin_numero_con_texto,
       count(*) FILTER (WHERE value_as_number IS NULL
                          AND nullif(trim(value_source_value), '') IS NULL)     AS sin_valor_alguno
FROM cdm.measurement;

-- (1b) top 10 analitos sin número: ¿qué tipo de resultado son?
SELECT c.concept_name                         AS analito,
       count(*)                               AS sin_numero,
       count(DISTINCT m.value_source_value)   AS textos_distintos,
       min(m.value_source_value)              AS ejemplo_texto
FROM cdm.measurement m
JOIN cdm.concept c ON c.concept_id = m.measurement_concept_id
WHERE m.value_as_number IS NULL
GROUP BY c.concept_name
ORDER BY sin_numero DESC
LIMIT 10;

-- (2) operador: NULL vs 0 vs concepto real
SELECT CASE WHEN m.operator_concept_id IS NULL THEN '(NULL)'
            WHEN m.operator_concept_id = 0     THEN '0 = sin concepto'
            ELSE o.concept_name END            AS operador,
       count(*)                                AS mediciones,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM cdm.measurement m
LEFT JOIN cdm.concept o ON o.concept_id = m.operator_concept_id
GROUP BY 1
ORDER BY mediciones DESC;

-- (3) signos de censura en el texto de origen
SELECT count(*) AS textos_con_signo
FROM cdm.measurement
WHERE value_source_value ~ '^\s*(<|>|<=|>=)';

-- =====================================================================
-- Actividad 7a. Normalizar la globulina (3027970) a g/L (unidad canónica)
-- Decisión 9: unidad canónica g/L (SI) y unidad REAL decidida por el rango
-- del valor, no por la etiqueta (6b: los valores «en g/L» son g/dL).
--   * valor < 10  → se interpreta como g/dL  → ×10
--   * valor >= 10 → se interpreta como g/L   → ×1
-- Umbral 10: la globulina normal es ~2.2-4.2 g/dL (suma de fracciones
-- alfa-1, alfa-2, beta y gamma; MedlinePlus, Protein electrophoresis -
-- serum) = 22-42 g/L. El corte cae en el hueco entre las dos escalas.
-- Factor: UCUM, prefijo d = 10^-1 (tabla 1) y L = dm3 (tabla 5) →
-- 1 dL = 0.1 L → 1 g/dL = 10 g/L.
-- Se conservan valor y unidad originales, y se anota qué regla se aplicó.
-- Los nulos se mantienen (ninguno aquí, 6b) y no se convierten.
-- =====================================================================
DROP TABLE IF EXISTS results.globulina_normalizada;
CREATE TABLE results.globulina_normalizada AS
SELECT m.measurement_id,
       m.person_id,
       m.measurement_date,
       m.value_as_number                               AS valor_original,
       m.unit_concept_id                               AS unidad_original_concept_id,
       m.unit_source_value                             AS unidad_original_texto,
       CASE WHEN m.value_as_number < 10 THEN 'g/dL' ELSE 'g/L' END AS unidad_inferida,
       CASE WHEN m.value_as_number < 10 THEN m.value_as_number * 10
            ELSE m.value_as_number END                 AS valor_g_l,
       8636                                            AS unidad_canonica_concept_id, -- g/L
       CASE WHEN m.value_as_number IS NULL               THEN 'sin_valor'
            WHEN (m.value_as_number < 10) = (m.unit_concept_id = 8713)
                                                         THEN 'etiqueta_coherente'
            ELSE 'reetiquetada_por_rango' END            AS regla_aplicada
FROM cdm.measurement m
WHERE m.measurement_concept_id = 3027970;

-- Verificación: filas por regla, unidad original e inferida
-- (esperado: 20,428 en total = conteo de 6b; ninguna con valor >= 10)
SELECT regla_aplicada, unidad_original_texto, unidad_inferida,
       count(*)              AS filas,
       min(valor_original)   AS min_orig,  max(valor_original) AS max_orig,
       min(valor_g_l)        AS min_g_l,   max(valor_g_l)      AS max_g_l
FROM results.globulina_normalizada
GROUP BY 1, 2, 3
ORDER BY filas DESC;

-- =====================================================================
-- Actividad 8a. Criterios de plausibilidad (citados) y valores fuera
-- Decisión 10: creatinina, HbA1c y colesterol. Los rangos NO se inventan:
--  * Creatinina 0.1-5 mg/dL y colesterol 50-500 mg/dL: OHDSI Data Quality
--    Dashboard v2.9.1, inst/csv/OMOP_CDMv5.4_Concept_Level.csv. Allí están
--    definidos sobre conceptos SNOMED (37392176; 37393449...); se aplican
--    al LOINC equivalente (mismo analito y unidad).
--  * HbA1c 3.5-20.0 %: rango reportable del método NHANES (Bio-Rad D-100
--    HPLC, manual revisado 2023-12-05, sección 9). Fuera de él el
--    laboratorio informa "< 3.5" / "> 20.0", nunca un número.
-- Se guardan en una tabla para reutilizarlos al marcar filas (8c).
-- LEFT JOIN de criterios a measurement por concepto+unidad: cada fila de
-- measurement casa con un solo criterio → no multiplica filas.
-- =====================================================================
DROP TABLE IF EXISTS results.criterios_plausibilidad;
CREATE TABLE results.criterios_plausibilidad AS
SELECT * FROM (VALUES
  (3051825, 8840, 'Creatinina',  0.1,   5.0, 'OHDSI DQD v2.9.1 (SNOMED 37392176, mg/dL)'),
  (3004410, 8554, 'HbA1c',       3.5,  20.0, 'NHANES GHB Bio-Rad D-100, sec. 9 rango reportable'),
  (3027114, 8840, 'Colesterol', 50.0, 500.0, 'OHDSI DQD v2.9.1 (SNOMED 37393449, mg/dL)')
) AS t(measurement_concept_id, unit_concept_id, analito, bajo, alto, fuente);

-- Conteos: total, nulos, por debajo, dentro, por encima (filas y pacientes)
SELECT k.analito, k.bajo, k.alto,
       count(m.measurement_id)                                   AS mediciones,
       count(*) FILTER (WHERE m.value_as_number IS NULL)         AS nulos,
       count(*) FILTER (WHERE m.value_as_number <  k.bajo)       AS por_debajo,
       count(*) FILTER (WHERE m.value_as_number >  k.alto)       AS por_encima,
       round(100.0 * count(*) FILTER (WHERE m.value_as_number NOT BETWEEN k.bajo AND k.alto)
             / count(m.measurement_id), 1)                       AS pct_fuera,
       count(DISTINCT m.person_id) FILTER (WHERE m.value_as_number NOT BETWEEN k.bajo AND k.alto)
                                                                 AS pacientes_fuera,
       count(*) FILTER (WHERE m.unit_concept_id <> k.unit_concept_id) AS otra_unidad
FROM results.criterios_plausibilidad k
LEFT JOIN cdm.measurement m ON m.measurement_concept_id = k.measurement_concept_id
GROUP BY k.analito, k.bajo, k.alto
ORDER BY k.analito;

-- =====================================================================
-- Actividad 8b. Centinelas y contexto clínico
-- (1) Centinela = valor fuera de rango que se repite EXACTAMENTE mucho más
--     que sus vecinos (p. ej. 9999 o un valor por defecto del sistema).
--     Se compara cada valor con la media de los valores ±0.1 a su lado:
--     una pila aislada (razón >> 1) es sospechosa; una curva suave, no.
-- (2) Creatinina > 5 según contexto renal: diálisis (procedure) o ERC
--     terminal (condition) registrada ANTES o el mismo día de la medición.
--     El contexto posterior no cuenta (no se puede usar el futuro).
-- =====================================================================
-- (1) top 5 de valores fuera de rango por analito, frente a sus vecinos
WITH fuera AS (
  SELECT k.analito, m.value_as_number AS v, count(*) AS n
  FROM results.criterios_plausibilidad k
  JOIN cdm.measurement m ON m.measurement_concept_id = k.measurement_concept_id
  WHERE m.value_as_number NOT BETWEEN k.bajo AND k.alto
  GROUP BY k.analito, m.value_as_number
)
SELECT * FROM (
  SELECT f.analito, f.v AS valor, f.n AS repeticiones,
         coalesce((SELECT round(avg(g.n), 1) FROM fuera g
                   WHERE g.analito = f.analito AND abs(g.v - f.v) BETWEEN 0.05 AND 0.15), 0) AS media_vecinos,
         row_number() OVER (PARTITION BY f.analito ORDER BY f.n DESC) AS rk
  FROM fuera f) t
WHERE rk <= 5
ORDER BY analito, rk;

-- (2) creatinina > 5 mg/dL según contexto renal previo
WITH renal AS (            -- primera fecha de contexto renal por paciente
  SELECT person_id, min(fecha) AS desde FROM (
    SELECT p.person_id, p.procedure_date AS fecha
    FROM cdm.procedure_occurrence p WHERE p.procedure_concept_id IN (4120120, 4146536)
    UNION ALL
    SELECT o.person_id, o.condition_start_date
    FROM cdm.condition_occurrence o JOIN cdm.concept c ON c.concept_id = o.condition_concept_id
    WHERE c.concept_name ILIKE '%end-stage renal%') x
  GROUP BY person_id)      -- 1 fila por paciente → el LEFT JOIN no multiplica
SELECT CASE WHEN m.value_as_number > 30 THEN 'b >30' ELSE 'a 5-30' END AS tramo,
       CASE WHEN r.desde <= m.measurement_date THEN 'contexto renal previo'
            WHEN r.desde IS NOT NULL            THEN 'contexto solo posterior'
            ELSE 'sin contexto renal' END       AS contexto,
       count(*) AS mediciones, count(DISTINCT m.person_id) AS pacientes,
       min(m.value_as_number) AS minimo, max(m.value_as_number) AS maximo
FROM cdm.measurement m
LEFT JOIN renal r ON r.person_id = m.person_id
WHERE m.measurement_concept_id = 3051825 AND m.value_as_number > 5
GROUP BY 1, 2 ORDER BY 1, 2;

-- =====================================================================
-- Actividad 8c. Marcar cada medición (no se borra nada)
-- Decisión 11: marcar en todos los grupos; solo la HbA1c < 3.5 % pasa a
-- NULL en valor_analitico (un laboratorio la informaría como "< 3.5",
-- sin número). valor_original se conserva siempre.
-- Creatinina > 5: se clasifica por contexto renal (8b) con la fecha:
-- previo = extremo real; solo posterior o ninguno = revisar.
-- Granularidad: 1 fila por measurement_id de los 3 analitos.
-- =====================================================================
DROP TABLE IF EXISTS results.measurement_plausibilidad;
CREATE TABLE results.measurement_plausibilidad AS
WITH renal AS (
  SELECT person_id, min(fecha) AS desde FROM (
    SELECT person_id, procedure_date AS fecha FROM cdm.procedure_occurrence
    WHERE procedure_concept_id IN (4120120, 4146536)
    UNION ALL
    SELECT o.person_id, o.condition_start_date FROM cdm.condition_occurrence o
    JOIN cdm.concept c ON c.concept_id = o.condition_concept_id
    WHERE c.concept_name ILIKE '%end-stage renal%') x
  GROUP BY person_id)
SELECT m.measurement_id, m.person_id, m.measurement_date, k.analito,
       m.value_as_number AS valor_original, m.unit_concept_id,
       CASE WHEN m.value_as_number BETWEEN k.bajo AND k.alto THEN 'dentro_rango'
            WHEN k.analito = 'HbA1c'                          THEN 'implausible_metodo'
            WHEN k.analito = 'Creatinina' AND r.desde <= m.measurement_date
                                                              THEN 'extremo_real_contexto_renal'
            WHEN k.analito = 'Creatinina' AND r.desde IS NOT NULL
                                                              THEN 'revisar_contexto_posterior'
            WHEN k.analito = 'Creatinina'                     THEN 'revisar_sin_contexto'
            ELSE 'extremo_cerca_limite' END                   AS clasificacion,
       CASE WHEN k.analito = 'HbA1c' AND m.value_as_number < k.bajo THEN NULL
            ELSE m.value_as_number END                        AS valor_analitico,
       k.fuente                                               AS fuente_rango
FROM results.criterios_plausibilidad k
JOIN cdm.measurement m ON m.measurement_concept_id = k.measurement_concept_id
LEFT JOIN renal r ON r.person_id = m.person_id;   -- renal: 1 fila/paciente

-- Verificación: total esperado 162,409 (34,334 + 69,106 + 58,969, de 8a)
SELECT analito, clasificacion, count(*) AS filas,
       count(DISTINCT person_id) AS pacientes,
       count(valor_analitico)    AS con_valor_analitico,
       min(valor_original) AS minimo, max(valor_original) AS maximo
FROM results.measurement_plausibilidad
GROUP BY ROLLUP (analito, clasificacion)
ORDER BY analito NULLS LAST, filas DESC;

-- =====================================================================
-- Actividad 9a. ¿En qué tabla dejó el ETL cada hecho clínico?
-- Regla del CDM: la tabla la decide el domain_id del concepto estándar.
-- Se busca cada hecho en measurement, observation y person, y se muestra
-- en qué campo quedó el valor (número, concepto o solo texto de origen).
-- count(nullif(x, 0)): cuenta solo conceptos reales (0 = «sin concepto»).
-- =====================================================================
WITH hechos AS (
  SELECT 'measurement' AS tabla, measurement_concept_id AS concept_id, person_id,
         value_as_number, nullif(value_as_concept_id, 0) AS valor_concepto,
         nullif(trim(value_source_value), '') AS valor_texto
  FROM cdm.measurement WHERE measurement_concept_id IN (3025315, 43054909, 3046853, 4013886)
  UNION ALL
  SELECT 'observation', observation_concept_id, person_id,
         value_as_number, nullif(value_as_concept_id, 0),
         coalesce(nullif(trim(value_as_string), ''), nullif(trim(value_source_value), ''))
  FROM cdm.observation WHERE observation_concept_id IN (3025315, 43054909, 3046853, 4013886)
)
SELECT h.tabla, c.concept_name AS hecho, c.domain_id, c.vocabulary_id,
       count(*)                       AS filas,
       count(DISTINCT h.person_id)    AS pacientes,
       count(h.value_as_number)       AS con_numero,
       count(h.valor_concepto)        AS con_concepto,
       count(h.valor_texto)           AS con_texto
FROM hechos h JOIN cdm.concept c ON c.concept_id = h.concept_id
GROUP BY 1, 2, 3, 4
UNION ALL   -- la raza también vive en person (1 fila por persona)
SELECT 'person', 'race_concept_id', 'Race', NULL, count(*), count(DISTINCT person_id),
       NULL, count(nullif(race_concept_id, 0)), count(nullif(trim(race_source_value), ''))
FROM cdm.person
ORDER BY hecho, tabla;

-- =====================================================================
-- Actividad 9b. Raza: ¿coinciden person y observation?
-- Se reduce observation a 1 fila por paciente con su(s) raza(s) declarada(s)
-- (sin «I choose not to answer», que es un NULL con otro nombre) y se
-- compara con person. Las etiquetas de texto difieren entre tablas
-- («Pacific Islander» vs «hawaiian»), así que se traducen con un VALUES.
-- Granularidad tras el CTE obs: 1 fila por paciente → el JOIN no multiplica.
-- =====================================================================
WITH equiv(texto_obs, texto_person) AS (VALUES
  ('White', 'white'), ('Black/African American', 'black'), ('Asian', 'asian'),
  ('Other', 'other'), ('Pacific Islander', 'hawaiian'),
  ('American Indian/Alaskan Native', 'native')),
obs AS (
  SELECT o.person_id,
         count(DISTINCT e.texto_person)                      AS razas_distintas,
         min(e.texto_person)                                 AS raza_obs,
         bool_or(o.value_source_value LIKE 'I choose not%')  AS alguna_vez_no_responde
  FROM cdm.observation o
  LEFT JOIN equiv e ON e.texto_obs = o.value_source_value
  WHERE o.observation_concept_id = 3046853
  GROUP BY o.person_id)
SELECT CASE WHEN o.person_id IS NULL        THEN '1 sin raza en observation'
            WHEN o.razas_distintas = 0      THEN '2 solo «no responde»'
            WHEN o.razas_distintas > 1      THEN '3 más de una raza'
            WHEN o.raza_obs = p.race_source_value THEN '4 coincide'
            ELSE '5 NO coincide' END        AS comparacion,
       count(*) AS pacientes,
       count(*) FILTER (WHERE o.alguna_vez_no_responde) AS con_algun_no_responde,
       count(*) FILTER (WHERE p.race_concept_id = 0)    AS person_sin_mapear
FROM cdm.person p
LEFT JOIN obs o ON o.person_id = p.person_id
GROUP BY 1 ORDER BY 1;

-- ¿Hay conceptos estándar de raza para los textos que person dejó en 0?
SELECT concept_id, concept_name, concept_code
FROM cdm.concept
WHERE domain_id = 'Race' AND standard_concept = 'S'
  AND (concept_name ILIKE '%hawaiian%' OR concept_name ILIKE '%american indian%'
       OR concept_name ILIKE '%more than one%' OR concept_name ILIKE 'other race%')
ORDER BY concept_id;

-- =====================================================================
-- Actividad 10a. Creatinina basal más cercana al inicio de lisinopril
-- Decisión 13: índice = primera receta de lisinopril (results.lisinopril_
-- exposicion, 1,522 pac.); analito = creatinina (valor_analitico de 8c).
--  * Política A (principal): días en [-90, 0]. Después del índice el
--    lisinopril ya puede subir la creatinina → usarla sería fuga.
--  * Política B (contraste): días en [-90, +90], como pide el enunciado.
-- "Más cercano" = menor |días|; empate (−d y +d) gana el anterior (días
-- ASC); mismo día → measurement_id DESC (determinista, no clínico).
-- Patrón de la sesión 11: ROW_NUMBER() por paciente y quedarse con rn = 1.
-- Granularidad final: 1 fila por paciente con índice (LEFT JOIN → NULL si no hay).
-- =====================================================================
DROP TABLE IF EXISTS results.creatinina_basal;
CREATE TABLE results.creatinina_basal AS
WITH indice AS (
  SELECT person_id, min(inicio) AS fecha_indice
  FROM results.lisinopril_exposicion GROUP BY person_id),
candidatos AS (            -- todos los valores en ±90 días (antes de elegir)
  SELECT i.person_id, p.measurement_id, p.valor_analitico, p.clasificacion,
         p.measurement_date - i.fecha_indice AS dias      -- <0 antes, >0 después
  FROM indice i
  JOIN results.measurement_plausibilidad p
    ON p.person_id = i.person_id AND p.analito = 'Creatinina'
   AND p.measurement_date BETWEEN i.fecha_indice - 90 AND i.fecha_indice + 90
  WHERE p.valor_analitico IS NOT NULL),
rank_a AS (
  SELECT *, row_number() OVER (PARTITION BY person_id
              ORDER BY abs(dias), dias, measurement_id DESC) AS rn
  FROM candidatos WHERE dias <= 0),
rank_b AS (
  SELECT *, row_number() OVER (PARTITION BY person_id
              ORDER BY abs(dias), dias, measurement_id DESC) AS rn
  FROM candidatos)
SELECT i.person_id, i.fecha_indice,
       a.valor_analitico AS creat_a, a.dias AS dias_a, a.clasificacion AS clasif_a,
       b.valor_analitico AS creat_b, b.dias AS dias_b, b.clasificacion AS clasif_b
FROM indice i
LEFT JOIN rank_a a ON a.person_id = i.person_id AND a.rn = 1
LEFT JOIN rank_b b ON b.person_id = i.person_id AND b.rn = 1;

-- Verificación: 1 fila por paciente (esperado 1,522 y 0 duplicados)
SELECT count(*) AS filas, count(DISTINCT person_id) AS pacientes,
       count(creat_a) AS con_valor_a, count(*) - count(creat_a) AS sin_valor_a,
       round(100.0 * count(creat_a) / count(*), 1) AS pct_a,
       count(creat_b) AS con_valor_b, round(100.0 * count(creat_b) / count(*), 1) AS pct_b,
       count(*) FILTER (WHERE dias_b > 0)              AS b_usa_posterior,
       count(*) FILTER (WHERE creat_a <> creat_b)      AS a_y_b_distintos,
       count(*) FILTER (WHERE dias_a = 0)              AS a_del_dia_0
FROM results.creatinina_basal;
