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
