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
