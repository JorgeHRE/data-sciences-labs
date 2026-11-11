-- =====================================================================
-- Lab 14 — Construir y defender un concept set (SNOMED CT e ICD-10-CM)
-- Base: Postgres del lab 12 (contenedor lab12-omop-db-1, BD omop_lab12).
-- El esquema cdm es de solo lectura. Lo propio (vista del concept set y
-- tabla de exclusiones) se escribe en el esquema results (actividad 4).
-- Ejecutar completo:
--   docker exec -i lab12-omop-db-1 psql -U <usuario> -d omop_lab12 \
--     -v ON_ERROR_STOP=1 < concept_set.sql
-- Recordatorio del orden lógico de ejecución de un SELECT:
--   FROM → WHERE → GROUP BY → HAVING → SELECT → ORDER BY
-- =====================================================================

-- Paso 0a. Tamaño del vocabulario. Por qué: un vocabulario cargado a
-- medias produce concept sets que parecen correctos y no lo son.
-- Esperado: concept_relationship 14,138,100 · concept_ancestor 12,077,497 ·
-- SNOMED 1,106,309 (356,613 estándar) · ICD10CM 100,273 (0 estándar).
SELECT 'concept_relationship' AS objeto, count(*) AS filas, NULL::bigint AS estandar
FROM cdm.concept_relationship
UNION ALL SELECT 'concept_ancestor', count(*), NULL FROM cdm.concept_ancestor
UNION ALL
SELECT 'concept ' || vocabulary_id, count(*),
       count(*) FILTER (WHERE standard_concept = 'S')
FROM cdm.concept
WHERE vocabulary_id IN ('SNOMED', 'ICD10CM')
GROUP BY vocabulary_id;

-- Paso 0b. ¿concept_ancestor está completo? Por qué: el tamaño no basta.
-- Cada arista directa «Is a» entre dos SNOMED estándar debe tener su
-- pareja ancestro-descendiente en concept_ancestor. Esperado: 587,392
-- aristas y 0 sin pareja. El LEFT JOIN deja a la vista las que faltan
-- (quedarían con NULL); con un JOIN normal desaparecerían sin avisar.
SELECT count(*)                                         AS aristas_is_a,
       count(*) FILTER (WHERE ca.ancestor_concept_id IS NULL) AS sin_pareja
FROM cdm.concept_relationship r
JOIN cdm.concept hijo  ON hijo.concept_id  = r.concept_id_1
                      AND hijo.vocabulary_id  = 'SNOMED' AND hijo.standard_concept  = 'S'
JOIN cdm.concept padre ON padre.concept_id = r.concept_id_2
                      AND padre.vocabulary_id = 'SNOMED' AND padre.standard_concept = 'S'
LEFT JOIN cdm.concept_ancestor ca
       ON ca.ancestor_concept_id   = r.concept_id_2
      AND ca.descendant_concept_id = r.concept_id_1
WHERE r.relationship_id = 'Is a';

-- =====================================================================
-- Actividad 1. Condición elegida: diabetes mellitus tipo 2 (SNOMED 201826).
-- Antes de comprometerse: ¿hay suficientes pacientes (≥ ~50)?
-- Por qué pacientes distintos y no filas: un diabético con 30 visitas
-- genera 30 filas en condition_occurrence, pero es UN paciente.
-- Se cuenta el concepto exacto y con descendientes (concept_ancestor
-- incluye la semilla a distancia 0) para ver ya si la jerarquía añade
-- pacientes. Orden lógico: FROM → WHERE → SELECT.
-- =====================================================================
SELECT 'exacto' AS alcance,
       count(*)                     AS filas,
       count(DISTINCT co.person_id) AS pacientes
FROM cdm.condition_occurrence co
WHERE co.condition_concept_id = 201826
UNION ALL
SELECT 'con descendientes',
       count(*),
       count(DISTINCT co.person_id)
FROM cdm.condition_occurrence co
-- IN (subconsulta) y no JOIN: solo pregunta "¿está en la lista?", así que
-- no puede duplicar filas aunque la lista tuviera repetidos.
WHERE co.condition_concept_id IN (SELECT descendant_concept_id
                                  FROM cdm.concept_ancestor
                                  WHERE ancestor_concept_id = 201826);

-- =====================================================================
-- Actividad 2a. Las banderas de la semilla 201826.
-- Por qué: el concepto tiene que ser estándar ('S'), de dominio Condition
-- (si no, sus pacientes no están en condition_occurrence) y vigente
-- (invalid_reason NULL y valid_end_date en el futuro, típico 2099-12-31).
-- =====================================================================
SELECT concept_id, concept_name, domain_id, vocabulary_id, concept_class_id,
       standard_concept, invalid_reason, concept_code,
       valid_start_date, valid_end_date
FROM cdm.concept
WHERE concept_id = 201826;

-- Actividad 2b. Un nivel arriba y un nivel abajo.
-- min_levels_of_separation = 1 → padre o hijo directo. En SNOMED un
-- concepto puede tener VARIOS padres: más de una fila no es un error.
-- Esperado: 1 padre (201820 Diabetes mellitus) y 12 hijos directos.
SELECT 'padre' AS sentido, c.concept_id, c.concept_name
FROM cdm.concept_ancestor a
JOIN cdm.concept c ON c.concept_id = a.ancestor_concept_id
WHERE a.descendant_concept_id = 201826 AND a.min_levels_of_separation = 1
UNION ALL
SELECT 'hijo', c.concept_id, c.concept_name
FROM cdm.concept_ancestor a
JOIN cdm.concept c ON c.concept_id = a.descendant_concept_id
WHERE a.ancestor_concept_id = 201826 AND a.min_levels_of_separation = 1
ORDER BY sentido DESC, concept_name;

-- Actividad 2c. Número total de descendientes (cualquier distancia).
-- Se excluye la propia semilla, que es su ancestro a distancia 0.
-- Esperado: 14 (12 hijos + 2 nietos).
SELECT count(*) AS descendientes
FROM cdm.concept_ancestor
WHERE ancestor_concept_id = 201826
  AND descendant_concept_id <> 201826;

-- =====================================================================
-- Actividad 3a. Traducir 16 códigos ICD-10-CM a conceptos estándar.
-- Fuente: clasificación ICD-10-CM FY2027 (CDC/CMS), la versión cargada.
-- 11 códigos E11 (uno por tipo de complicación) + 5 de borde.
-- Los cuatro filtros:
--   1. dirección: 'Maps to', con el ICD en concept_id_1 (fuente → estándar)
--   2. destino estándar: e.standard_concept = 'S'
--   3. destino vigente:  e.invalid_reason IS NULL
--   4. relación vigente: r.invalid_reason IS NULL
-- El código FUENTE no se filtra por vigencia a propósito: E11.640 está
-- retirado, pero puede aparecer en historias antiguas y debe verse.
-- LEFT JOIN (r JOIN e): el paréntesis une primero relación y destino, y
-- solo después se cuelga del código. Así una relación cuyo destino no
-- pasa los filtros se descarta entera y el código queda con NULL ("no
-- mapea"), en vez de aparecer como fila con destino vacío.
-- Orden lógico: FROM/JOIN → SELECT → ORDER BY.
-- =====================================================================
WITH codigos (codigo_icd10) AS (
    VALUES ('E11.9'), ('E11.65'), ('E11.21'), ('E11.22'), ('E11.319'),
           ('E11.42'), ('E11.51'), ('E11.621'), ('E11.649'), ('E11.8'),
           ('E11.A'),
           ('E11.640'), ('O24.111'), ('E13.9'), ('R73.03'), ('Z79.84')
)
SELECT k.codigo_icd10,
       f.concept_id   AS concept_id_origen,
       f.invalid_reason AS origen_retirado,
       e.concept_id   AS concept_id_estandar,
       e.concept_name AS nombre_estandar,
       e.domain_id    AS dominio_estandar
FROM codigos k
JOIN cdm.concept f
  ON f.concept_code = k.codigo_icd10 AND f.vocabulary_id = 'ICD10CM'
LEFT JOIN (cdm.concept_relationship r
           JOIN cdm.concept e
             ON e.concept_id = r.concept_id_2
            AND e.standard_concept = 'S'           -- filtro 2
            AND e.invalid_reason IS NULL)          -- filtro 3
  ON r.concept_id_1 = f.concept_id
 AND r.relationship_id = 'Maps to'                 -- filtro 1
 AND r.invalid_reason IS NULL                      -- filtro 4
ORDER BY k.codigo_icd10, e.concept_id;

-- =====================================================================
-- Actividad 3b. ¿Cuántos códigos mapean a 0, 1 o más de 1 estándar?
-- Mismos cuatro filtros que en 3a. Dos niveles de agregación:
--   1) por código: n_estandar = cuántos destinos tiene cada uno
--   2) por grupo:  cuántos códigos hay con 0, 1 o >1 destinos
-- count(e.concept_id) y no count(*): count(*) contaría 1 también para
-- el código sin mapeo (su fila existe, con NULL); count(columna) ignora
-- los NULL y da 0, que es lo correcto.
-- Grupos: la lista de 16 de la actividad 3a, y la categoría E11 completa.
-- Orden lógico: FROM/JOIN → GROUP BY (por código) → SELECT → GROUP BY
-- (por grupo) → SELECT → ORDER BY.
-- =====================================================================
WITH por_codigo AS (
    SELECT f.concept_code,
           f.concept_code IN ('E11.9', 'E11.65', 'E11.21', 'E11.22', 'E11.319',
                              'E11.42', 'E11.51', 'E11.621', 'E11.649', 'E11.8',
                              'E11.A', 'E11.640', 'O24.111', 'E13.9', 'R73.03',
                              'Z79.84')       AS en_lista_16,
           count(e.concept_id)                AS n_estandar
    FROM cdm.concept f
    LEFT JOIN (cdm.concept_relationship r
               JOIN cdm.concept e
                 ON e.concept_id = r.concept_id_2
                AND e.standard_concept = 'S' AND e.invalid_reason IS NULL)
      ON r.concept_id_1 = f.concept_id
     AND r.relationship_id = 'Maps to' AND r.invalid_reason IS NULL
    WHERE f.vocabulary_id = 'ICD10CM'
      AND (f.concept_code LIKE 'E11%' OR f.concept_code IN ('O24.111', 'E13.9', 'R73.03', 'Z79.84'))
    GROUP BY f.concept_code
)
SELECT grupo,
       count(*)                                AS codigos,
       count(*) FILTER (WHERE n_estandar = 0)  AS sin_mapeo,
       count(*) FILTER (WHERE n_estandar = 1)  AS mapeo_1_a_1,
       count(*) FILTER (WHERE n_estandar > 1)  AS mapeo_1_a_n,
       sum(n_estandar)                         AS filas_tras_join
FROM (SELECT 'lista de 16' AS grupo, n_estandar FROM por_codigo WHERE en_lista_16
      UNION ALL
      SELECT 'categoría E11 completa', n_estandar FROM por_codigo
      WHERE concept_code LIKE 'E11%') g
GROUP BY grupo
ORDER BY grupo DESC;

-- =====================================================================
-- Actividad 3c. Contraste: ¿dónde caen los destinos estándar de los 16
-- códigos respecto al concept set? (decisión 5: la traducción ICD audita
-- el concept set, no lo construye)
--   'semilla'  → 201826 o descendiente (entra en las versiones A/B)
--   'rama'     → 443732 o descendiente (entra en C, decisión 4)
--   'fuera'    → ninguno de los dos: habría que justificar por qué no entra
-- EXISTS solo pregunta "¿hay al menos una fila?" y no multiplica filas,
-- a diferencia de un JOIN a concept_ancestor.
-- Granularidad: una fila por destino estándar distinto (el JOIN 1:N ya
-- no infla nada: se agrupa por destino y los códigos se listan juntos).
-- Orden lógico: FROM/JOIN → GROUP BY → SELECT → ORDER BY.
-- =====================================================================
WITH codigos (codigo_icd10) AS (
    VALUES ('E11.9'), ('E11.65'), ('E11.21'), ('E11.22'), ('E11.319'),
           ('E11.42'), ('E11.51'), ('E11.621'), ('E11.649'), ('E11.8'),
           ('E11.A'),
           ('E11.640'), ('O24.111'), ('E13.9'), ('R73.03'), ('Z79.84')
),
destinos AS (
    SELECT k.codigo_icd10, e.concept_id, e.concept_name
    FROM codigos k
    JOIN cdm.concept f
      ON f.concept_code = k.codigo_icd10 AND f.vocabulary_id = 'ICD10CM'
    -- JOIN normal (no LEFT): aquí solo interesan los códigos que SÍ mapean;
    -- el que no mapea (E11.640) ya quedó documentado en 3a y 3b.
    JOIN cdm.concept_relationship r
      ON r.concept_id_1 = f.concept_id
     AND r.relationship_id = 'Maps to' AND r.invalid_reason IS NULL
    JOIN cdm.concept e
      ON e.concept_id = r.concept_id_2
     AND e.standard_concept = 'S' AND e.invalid_reason IS NULL
)
SELECT CASE
         WHEN EXISTS (SELECT 1 FROM cdm.concept_ancestor a
                      WHERE a.ancestor_concept_id = 201826
                        AND a.descendant_concept_id = d.concept_id) THEN 'semilla'
         WHEN EXISTS (SELECT 1 FROM cdm.concept_ancestor a
                      WHERE a.ancestor_concept_id = 443732
                        AND a.descendant_concept_id = d.concept_id) THEN 'rama'
         ELSE 'fuera'
       END                                             AS donde_cae,
       d.concept_id, d.concept_name,
       string_agg(d.codigo_icd10, ', ' ORDER BY d.codigo_icd10) AS codigos_icd10
FROM destinos d
GROUP BY d.concept_id, d.concept_name
ORDER BY donde_cae DESC, d.concept_name;

-- =====================================================================
-- Actividad 4a. Las tres versiones del concept set (decisión 6).
-- Tabla de exclusiones: las rellena la actividad 6, una fila por concepto
-- excluido y SIEMPRE con su motivo clínico (NOT NULL). IF NOT EXISTS: si
-- el archivo se vuelve a ejecutar, no borra exclusiones ya decididas.
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS results;

CREATE TABLE IF NOT EXISTS results.cs_t2dm_exclusiones (
    concept_id integer PRIMARY KEY,   -- PK: un concepto no se excluye dos veces
    motivo     text    NOT NULL
);

-- Vista en formato largo: una fila por (versión, concepto). No guarda
-- datos: se recalcula desde concept_ancestor cada vez que se consulta.
--   A: solo la semilla.
--   B: semilla + descendientes (concept_ancestor incluye la semilla a
--      distancia 0, por eso no hace falta añadirla aparte).
--   C: semilla y rama 443732 (decisión 4), cada una con descendientes,
--      MENOS cada exclusión y sus propios descendientes.
-- DISTINCT en C: las dos ramas hoy no comparten conceptos, pero si un
-- vocabulario futuro los compartiera, el concepto no saldría dos veces.
-- NOT EXISTS y no NOT IN: si hubiera un NULL en la subconsulta, NOT IN
-- devolvería cero filas sin avisar.
CREATE OR REPLACE VIEW results.cs_t2dm AS
SELECT 'A' AS version, 201826 AS concept_id
UNION ALL
SELECT 'B', ca.descendant_concept_id
FROM cdm.concept_ancestor ca
WHERE ca.ancestor_concept_id = 201826
UNION ALL
SELECT DISTINCT 'C', ca.descendant_concept_id
FROM cdm.concept_ancestor ca
WHERE ca.ancestor_concept_id IN (201826, 443732)
  AND NOT EXISTS (SELECT 1
                  FROM results.cs_t2dm_exclusiones x
                  JOIN cdm.concept_ancestor xa
                    ON xa.ancestor_concept_id = x.concept_id
                  WHERE xa.descendant_concept_id = ca.descendant_concept_id);

-- Actividad 4b. Conceptos por versión. Esperado (sin exclusiones aún):
-- A 1 · B 15 · C 134. count(DISTINCT) = count(*) confirma 0 duplicados.
SELECT version, count(*) AS filas, count(DISTINCT concept_id) AS conceptos
FROM results.cs_t2dm
GROUP BY version
ORDER BY version;

-- Actividad 4c. Prueba de que la exclusión funciona (control que puede
-- fallar). Dentro de una transacción que se deshace con ROLLBACK: no deja
-- nada en la tabla. Si excluimos la rama 443732 entera, C debe caer de
-- 134 a 15 (= B): se quitan 443732 Y sus 118 descendientes.
BEGIN;
INSERT INTO results.cs_t2dm_exclusiones VALUES (443732, 'prueba: se deshace');
SELECT version, count(*) AS conceptos_con_prueba
FROM results.cs_t2dm WHERE version = 'C' GROUP BY version;
ROLLBACK;
