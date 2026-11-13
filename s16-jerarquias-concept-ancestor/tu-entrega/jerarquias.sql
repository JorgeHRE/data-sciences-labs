-- =====================================================================
-- Lab 16 — Jerarquías en acción: concept_relationship y concept_ancestor
-- Base: Postgres del lab 12 (lab12-omop-db-1), esquema cdm de solo lectura.
-- Vocabulario: v5.0 29-AUG-26 (SNOMED, RxNorm, ATC, LOINC de ATHENA).
-- Motor de los EXPLAIN ANALYZE (actividad 8): PostgreSQL.
-- Cada consulta va precedida de qué responde y qué se encontró.
-- Orden lógico de un SELECT: FROM → WHERE → GROUP BY → HAVING → SELECT → ORDER BY
-- =====================================================================

-- Control 0. ¿Están las cuatro tablas que pide el lab, y con qué índices?
-- Por qué: si concept_ancestor o relationship estuvieran vacías, las
-- actividades 2 y 3 «funcionarían» con 0 filas sin dar error. Los índices
-- se anotan ahora porque la actividad 8 compara planes y hay que saber
-- de qué índices se partía antes de crear ninguno.
-- Se usa count(*) real (no la estimación de pg_class) porque hay que
-- comparar contra cifras exactas; tarda ~1 s por los 12 M de concept_ancestor.
-- Resultado (2026-11-13), 4 filas, ~1.5 s:
--   concept               2,028,013 · concept_relationship  14,138,100
--   concept_ancestor     12,077,497 · relationship                  724
SELECT 'concept' AS tabla, count(*) AS filas FROM cdm.concept
UNION ALL SELECT 'concept_relationship', count(*) FROM cdm.concept_relationship
UNION ALL SELECT 'concept_ancestor', count(*) FROM cdm.concept_ancestor
UNION ALL SELECT 'relationship', count(*) FROM cdm.relationship;

-- Control 0b. Índices de las tablas que usará el lab.
-- Resultado: 7 filas. concept_ancestor indexada por ancestro y por
-- descendiente; concept_relationship por concept_id_2, relationship_id y
-- su PK (concept_id_1, concept_id_2, relationship_id), que empieza por
-- concept_id_1 y por eso también sirve para subir con 'Is a' (actividad 1);
-- condition_occurrence SOLO su PK: no hay índice en condition_concept_id.
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'cdm'
  AND tablename IN ('concept_ancestor', 'concept_relationship',
                    'relationship', 'condition_occurrence')
ORDER BY tablename, indexname;

-- =====================================================================
-- Actividad 1. Subir con 'Is a' desde T2DM (201826) hasta la raíz.
-- =====================================================================
-- Actividad 1a. Cada paso de la subida, con su nivel.
-- Cómo funciona un WITH RECURSIVE: la parte de arriba del UNION ALL (ancla)
-- se ejecuta una vez y produce el nivel 0; la parte de abajo se repite
-- usando SOLO las filas nuevas de la vuelta anterior, hasta que una vuelta
-- no produce filas. Por eso cada vuelta sube exactamente un nivel.
-- Las tres trampas del enunciado:
--   1) relationship_id = 'Is a': solo hacia arriba ('Subsumes' es la misma
--      arista al revés; sin el filtro se sube y se baja sin fin).
--   2) nivel < 20: freno de seguridad aunque haya ruta.
--   3) invalid_reason IS NULL: no recorrer aristas retiradas.
-- ruta (ARRAY): lista ordenada de los concept_id recorridos; con || se le
-- añade el nuevo, y NOT (id = ANY(ruta)) impide visitar dos veces el mismo
-- concepto en un camino (protección contra ciclos; decisión 3).
-- Resultado (2026-11-13): 20 filas, niveles 0 a 7, 11 conceptos distintos.
--   Hay repetidos a propósito (UNION ALL): Disease sale 3 veces (niveles 4
--   y 5), Clinical finding 4 (5 y 6), SNOMED CT Concept 4 (6 y 7): una
--   fila por camino. 3 conceptos sin standard_concept (NULL = no estándar,
--   de clasificación): Disorder by body site, Finding by site, SNOMED CT
--   Concept → pista para la actividad 2.
WITH RECURSIVE sube AS (
    -- Ancla: el concepto de partida (nivel 0).
    SELECT c.concept_id, 0 AS nivel, ARRAY[c.concept_id] AS ruta
    FROM cdm.concept c
    WHERE c.concept_id = 201826
    UNION ALL
    -- Paso recursivo: los padres directos de las filas de la vuelta anterior.
    SELECT cr.concept_id_2, s.nivel + 1, s.ruta || cr.concept_id_2
    FROM sube s
    JOIN cdm.concept_relationship cr
      ON cr.concept_id_1 = s.concept_id      -- hijo → padre
     AND cr.relationship_id = 'Is a'          -- trampa 1
     AND cr.invalid_reason IS NULL            -- trampa 3
    WHERE s.nivel < 20                        -- trampa 2
      AND NOT (cr.concept_id_2 = ANY(s.ruta)) -- sin ciclos
)
SELECT s.nivel, s.concept_id, c.concept_name, c.standard_concept
FROM sube s
JOIN cdm.concept c USING (concept_id)         -- 1 fila por concept_id: no duplica
ORDER BY s.nivel, s.concept_id;

-- Actividad 1b. Los caminos completos hasta la raíz y la profundidad.
-- Misma recursión que 1a (se repite para que cada consulta corra sola).
-- Un camino termina donde el concepto ya no tiene padre 'Is a' vigente
-- (NOT EXISTS): esa fila es la raíz y su ruta es el camino entero.
-- Para pasar la ruta (ARRAY de ids) a texto: unnest la abre en filas,
-- WITH ORDINALITY numera la posición (pos) para conservar el orden, y
-- string_agg(... ORDER BY pos) la vuelve a juntar con nombres.
-- min/max OVER (): funciones de ventana sobre todo el resultado; se
-- calculan DESPUÉS del GROUP BY, por eso ven los 4 caminos ya formados.
-- Resultado (2026-11-13): 4 caminos, todos terminan en SNOMED CT Concept
-- (4008453). Profundidad mínima 6 (vía Disorder of endocrine system ›
-- Disorder of body system › Disease) y máxima 7 (los otros 3).
-- Comprobación contra 1a: las 20 filas de 1a son los tramos distintos de
-- estos 4 caminos; por nivel 0..7 hay 1+1+2+2+3+4+4+3 = 20.
WITH RECURSIVE sube AS (
    SELECT c.concept_id, 0 AS nivel, ARRAY[c.concept_id] AS ruta
    FROM cdm.concept c
    WHERE c.concept_id = 201826
    UNION ALL
    SELECT cr.concept_id_2, s.nivel + 1, s.ruta || cr.concept_id_2
    FROM sube s
    JOIN cdm.concept_relationship cr
      ON cr.concept_id_1 = s.concept_id
     AND cr.relationship_id = 'Is a'
     AND cr.invalid_reason IS NULL
    WHERE s.nivel < 20
      AND NOT (cr.concept_id_2 = ANY(s.ruta))
),
caminos AS (                                  -- 1 fila por camino completo
    SELECT s.nivel AS profundidad, s.ruta
    FROM sube s
    WHERE NOT EXISTS (                        -- sin padre = raíz
        SELECT 1 FROM cdm.concept_relationship cr
        WHERE cr.concept_id_1 = s.concept_id
          AND cr.relationship_id = 'Is a'
          AND cr.invalid_reason IS NULL)
)
SELECT k.profundidad,
       min(k.profundidad) OVER () AS prof_min,
       max(k.profundidad) OVER () AS prof_max,
       string_agg(c.concept_name, ' › ' ORDER BY r.pos) AS camino
FROM caminos k
CROSS JOIN LATERAL unnest(k.ruta) WITH ORDINALITY AS r(concept_id, pos)
JOIN cdm.concept c ON c.concept_id = r.concept_id   -- 1:1 por PK
GROUP BY k.profundidad, k.ruta
ORDER BY k.profundidad, camino;
