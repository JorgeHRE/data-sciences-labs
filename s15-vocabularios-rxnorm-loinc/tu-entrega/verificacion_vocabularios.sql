-- =====================================================================
-- Lab 15 — Paso 0. Verificación de vocabularios antes de empezar
-- Base: Postgres del lab 12 (contenedor lab12-omop-db-1, BD omop_lab12).
-- Solo lectura sobre el esquema cdm.
-- Ejecutar completo:
--   docker exec -i lab12-omop-db-1 psql -U <usuario> -d omop_lab12 \
--     -v ON_ERROR_STOP=1 < verificacion_vocabularios.sql
-- =====================================================================

-- Paso 0a. ¿Están los vocabularios que pide el lab, y en qué versión?
-- Por qué: el enunciado avisa que descubrir en la actividad 4 que falta
-- uno es perder media hora. El LEFT JOIN desde la lista de nombres hace
-- que un vocabulario ausente salga con 0 filas en vez de desaparecer.
-- Esperado: RxNorm 316,330 · ATC 7,327 (0 'S', son clasificación 'C') ·
-- LOINC 287,814 · UCUM 1,130 · CVX con filas · RxNorm Extension 0.
SELECT v.vocabulary_id,
       count(c.concept_id)                                   AS conceptos,
       count(c.concept_id) FILTER (WHERE c.standard_concept = 'S') AS estandar,
       count(c.concept_id) FILTER (WHERE c.standard_concept = 'C') AS clasificacion,
       max(voc.vocabulary_version)                           AS version
FROM (VALUES ('RxNorm'), ('RxNorm Extension'), ('ATC'), ('LOINC'), ('UCUM'), ('CVX'))
     AS v(vocabulary_id)
LEFT JOIN cdm.concept    c   ON c.vocabulary_id   = v.vocabulary_id
LEFT JOIN cdm.vocabulary voc ON voc.vocabulary_id = v.vocabulary_id
GROUP BY v.vocabulary_id
ORDER BY v.vocabulary_id;

-- Paso 0b. ¿Necesitamos RxNorm Extension para NUESTROS datos?
-- Por qué: falta en la base, pero solo importa si algún drug_concept_id
-- de drug_exposure pertenece a él. Agrupamos los conceptos de los datos
-- por vocabulario. El LEFT JOIN deja a la vista los drug_concept_id que
-- no existan en concept (saldrían con vocabulario NULL).
-- Esperado: RxNorm 346 conceptos, CVX 19 (vacunas), 0 RxNorm Extension
-- y ninguna fila NULL. Total de filas: 467,590.
SELECT c.vocabulary_id,
       count(DISTINCT de.drug_concept_id) AS conceptos,
       count(*)                           AS filas
FROM cdm.drug_exposure de
LEFT JOIN cdm.concept c ON c.concept_id = de.drug_concept_id
GROUP BY c.vocabulary_id
ORDER BY filas DESC;

-- Paso 0c. ¿concept_ancestor está completo para los fármacos?
-- Por qué: la actividad 2 sube de producto a ingrediente y la 4 baja de
-- ingrediente a productos, ambas por concept_ancestor. Si a un producto
-- le faltara su fila producto → ingrediente, desaparecería de cualquier
-- concept set sin avisar. Es el equivalente al 0b del lab 14.
-- NOT EXISTS: para cada producto, pregunta «¿existe al menos un ancestro
-- de clase Ingredient?». Devuelve verdadero/falso, no filas, así que no
-- multiplica nada aunque un producto combinado tenga 2 ingredientes.
-- Se excluye la clase Ingredient: cada ingrediente es su propio ancestro
-- (nivel 0) y siempre pasaría el control (Trampa 1 de la actividad 2).
-- en_datos: cuántos de esos productos aparecen en drug_exposure. Los
-- drug_concept_id distintos se calculan UNA vez (CTE en_datos) y se pegan
-- con LEFT JOIN. Una primera versión usaba EXISTS contra drug_exposure
-- por cada producto y no terminó en 2 min: drug_exposure no tiene índice
-- en drug_concept_id, así que eran 143,444 recorridos de 467,590 filas.
-- El DISTINCT garantiza 1 fila por producto: el LEFT JOIN no multiplica.
-- Esperado: 10 clases, 0 sin ingrediente en todas; en_datos suma 344.
-- No 346 (0b): los otros 2 drug_concept_id de los datos ya son de clase
-- Ingredient (84 filas) y este control los excluye a propósito.
WITH productos AS (
    SELECT c.concept_id, c.concept_class_id
    FROM cdm.concept c
    WHERE c.vocabulary_id = 'RxNorm'
      AND c.standard_concept = 'S'
      AND c.concept_class_id <> 'Ingredient'
),
en_datos AS (
    SELECT DISTINCT drug_concept_id FROM cdm.drug_exposure
)
SELECT p.concept_class_id,
       count(*) AS productos,
       count(*) FILTER (WHERE NOT EXISTS (
           SELECT 1
           FROM cdm.concept_ancestor a
           JOIN cdm.concept i ON i.concept_id = a.ancestor_concept_id
           WHERE a.descendant_concept_id = p.concept_id
             AND i.vocabulary_id = 'RxNorm'
             AND i.concept_class_id = 'Ingredient'))  AS sin_ingrediente,
       count(d.drug_concept_id)                       AS en_datos
FROM productos p
LEFT JOIN en_datos d ON d.drug_concept_id = p.concept_id
GROUP BY p.concept_class_id
ORDER BY productos DESC;
