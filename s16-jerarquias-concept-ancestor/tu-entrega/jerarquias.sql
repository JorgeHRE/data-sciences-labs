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
-- Resultado (2026-11-13): 20 filas, niveles 0 a 7, 12 conceptos distintos
--   (T2DM + 11 ancestros).
--   Hay repetidos a propósito (UNION ALL): Disease sale 3 veces (niveles 4
--   y 5), Clinical finding 4 (5 y 6), SNOMED CT Concept 4 (6 y 7): una
--   fila por camino. 3 conceptos sin standard_concept (NULL = no estándar):
--   Disorder by body site y Finding by site, RETIRADOS en 2021 (invalid_reason
--   'U') pero con aristas 'Is a' aún vigentes, y SNOMED CT Concept, la raíz
--   de metadatos (dominio Metadata). Pista para la actividad 2. Ojo: la
--   trampa 3 filtra relaciones retiradas, no conceptos retirados.
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

-- =====================================================================
-- Actividad 2. Los mismos ancestros de T2DM (201826) con concept_ancestor.
-- =====================================================================
-- Actividad 2a. Una sola consulta, sin recursión.
-- concept_ancestor ya tiene precalculado el cierre de la jerarquía: una
-- fila por cada par (ancestro, descendiente), a cualquier distancia, con
-- la distancia mínima y máxima entre ellos (min/max_levels_of_separation).
-- Se busca por descendant_concept_id = 201826 porque queremos sus ancestros.
-- Ojo: incluye una fila del propio concepto consigo mismo (nivel 0/0);
-- la recursiva también lo trae en su nivel 0, así que se comparan igual.
-- Resultado (2026-11-13): 9 filas = T2DM + 8 ancestros (la recursiva da
--   T2DM + 11). Todos con standard_concept = 'S'; no aparecen SNOMED CT
--   Concept, Disorder by body site ni Finding by site. Hay poli-jerarquía
--   en min ≠ max: Disease 4/5 y Clinical finding 5/6, los mismos niveles
--   que dieron los caminos de la actividad 1b.
SELECT ca.ancestor_concept_id,
       c.concept_name,
       c.standard_concept,
       ca.min_levels_of_separation AS min_niv,
       ca.max_levels_of_separation AS max_niv
FROM cdm.concept_ancestor ca
JOIN cdm.concept c ON c.concept_id = ca.ancestor_concept_id   -- 1:1 por PK
WHERE ca.descendant_concept_id = 201826
ORDER BY min_niv, max_niv, ca.ancestor_concept_id;

-- Actividad 2b. ¿Son idénticos los dos conjuntos? Conciliación en una tabla.
-- Por qué GROUP BY en la recursiva: deja UN concepto por fila (hace de
-- DISTINCT) y a la vez calcula su nivel mínimo y máximo entre caminos.
-- Sin él, las 20 filas de 1a multiplicarían el JOIN (Disease 3 veces...).
-- FULL OUTER JOIN: conserva las filas de ambos lados aunque no tengan
-- pareja; donde un lado falta, sus columnas salen NULL. Ese NULL es la
-- señal de «no está en esa fuente», no un dato perdido.
-- COALESCE toma el primer valor no NULL para tener un id en todas las filas.
-- Conteos: rec 12 filas, ca 9 filas, JOIN 12 (9 parejas + 3 sin pareja):
--   no hay multiplicación porque ambos lados tienen 1 fila por concepto.
-- Resultado (2026-11-13): 12 filas. NO son idénticos: 9 «ambos» y 3 «solo
--   recursiva» (Disorder by body site, Finding by site, SNOMED CT Concept,
--   los 3 con standard_concept NULL); 0 «solo concept_ancestor». En los 9
--   comunes los niveles coinciden (niveles_iguales = true en las 9).
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
rec AS (                                      -- 1 fila por concepto
    SELECT concept_id, min(nivel) AS rec_min, max(nivel) AS rec_max
    FROM sube
    GROUP BY concept_id
),
ca AS (                                       -- ya es 1 fila por ancestro
    SELECT ancestor_concept_id AS concept_id,
           min_levels_of_separation AS ca_min,
           max_levels_of_separation AS ca_max
    FROM cdm.concept_ancestor
    WHERE descendant_concept_id = 201826
)
SELECT COALESCE(rec.concept_id, ca.concept_id) AS concept_id,
       c.concept_name,
       c.standard_concept,
       CASE WHEN ca.concept_id IS NULL THEN 'solo recursiva'
            WHEN rec.concept_id IS NULL THEN 'solo concept_ancestor'
            ELSE 'ambos' END AS origen,
       rec.rec_min, rec.rec_max, ca.ca_min, ca.ca_max,
       (rec.rec_min = ca.ca_min AND rec.rec_max = ca.ca_max) AS niveles_iguales
FROM rec
FULL OUTER JOIN ca ON ca.concept_id = rec.concept_id
JOIN cdm.concept c ON c.concept_id = COALESCE(rec.concept_id, ca.concept_id)
ORDER BY origen, rec.rec_min, concept_id;

-- =====================================================================
-- Actividad 3. La tabla RELATIONSHIP: qué relaciones cuentan como jerarquía.
-- =====================================================================
-- Actividad 3a. ¿Cuántos tipos de relación hay y cuántos son jerárquicos o
-- definen ascendencia? ¿Coinciden los dos conjuntos?
-- is_hierarchical: la relación es de tipo «más general / más específico».
-- defines_ancestry: la relación se usa para construir concept_ancestor.
-- Centinela: las dos columnas son varchar(1) con '0'/'1', no números; por
-- eso se compara con '1' (texto).
-- count(*) FILTER (WHERE ...): cuenta solo las filas que cumplen la
-- condición; permite varios conteos distintos en una sola pasada.
-- Resultado (2026-11-13): 724 tipos; 124 jerárquicos; 63 definen
--   ascendencia; 55 ambos → NO coinciden: 69 jerárquicos que no definen
--   ascendencia y 8 que la definen sin ser jerárquicos.
SELECT count(*)                                        AS tipos,
       count(*) FILTER (WHERE is_hierarchical  = '1')  AS jerarquicos,
       count(*) FILTER (WHERE defines_ancestry = '1')  AS definen_ascendencia,
       count(*) FILTER (WHERE is_hierarchical  = '1'
                          AND defines_ancestry = '1')  AS ambos,
       count(*) FILTER (WHERE is_hierarchical  = '1'
                          AND defines_ancestry = '0')  AS solo_jerarquicos,
       count(*) FILTER (WHERE is_hierarchical  = '0'
                          AND defines_ancestry = '1')  AS solo_ascendencia
FROM cdm.relationship;

-- Actividad 3b. Todas las relaciones distintas que SALEN de metformina
-- (RxNorm 1503297, ingrediente; decisión 5).
-- «Salen» = metformina es concept_id_1; concept_id_2 es el destino.
-- Una fila por tipo de relación (GROUP BY), con sus banderas de
-- RELATIONSHIP, cuántos destinos tiene y de qué vocabulario/clase son.
-- ejemplo: el primer destino en orden alfabético (array_agg ordenado y
-- [1]); sirve para ilustrar, no es el destino «principal».
-- Conteos: 247 filas de concept_relationship salen de 1503297, todas
--   vigentes (invalid_reason NULL); los dos JOIN las mantienen en 247
--   (relationship y concept son 1 fila por id) y el GROUP BY da 9.
-- Resultado (2026-11-13): 9 tipos. Solo 2 jerárquicos: RxNorm ing of
--   (1/1, 75 productos que la contienen) y Has brand name (1/0, 23
--   marcas). Los otros 7 son 0/0: mapeos (Maps to apunta a sí misma,
--   Mapped from 120 códigos de otros vocabularios), enlaces a ATC (pr lat
--   23; sec up 1, raro: A12AA20 calcio), equivalencias SNOMED (2), su sal
--   (Has form → metformin hydrochloride) y Value mapped from (alergia).
SELECT cr.relationship_id,
       r.relationship_name,
       r.is_hierarchical  AS jer,
       r.defines_ancestry AS asc_,
       count(*)           AS destinos,
       string_agg(DISTINCT c2.vocabulary_id || '/' || c2.concept_class_id, ', ')
                          AS tipo_destino,
       (array_agg(c2.concept_name ORDER BY c2.concept_name))[1] AS ejemplo
FROM cdm.concept_relationship cr
JOIN cdm.relationship r ON r.relationship_id = cr.relationship_id  -- 1:1
JOIN cdm.concept c2     ON c2.concept_id     = cr.concept_id_2     -- 1:1
WHERE cr.concept_id_1 = 1503297
  AND cr.invalid_reason IS NULL
GROUP BY cr.relationship_id, r.relationship_name,
         r.is_hierarchical, r.defines_ancestry
ORDER BY destinos DESC, cr.relationship_id;

-- Actividad 3c. Comprobación: ¿qué ancestros tiene metformina en
-- concept_ancestor fuera de RxNorm?
-- Por qué: 'RxNorm - ATC pr lat' y su inversa tienen banderas 0/0, así que
-- por la regla general NO deberían crear ascendencia. Si aparecen códigos
-- ATC como ancestros, las banderas no bastan para predecir concept_ancestor.
-- Sin JOIN que multiplique: concept es 1 fila por id.
-- Resultado (2026-11-13): 29 ancestros ATC (la fila de metformina
--   consigo misma no sale: es RxNorm). 23 códigos de 5.º nivel a nivel 0
--   (los mismos 23 de 'RxNorm - ATC pr lat': A10BA02 «metformin; oral» y
--   combinaciones A10BD..), y por encima la jerarquía ATC: A10BA
--   Biguanides y A10BD (1), A10B (2), A10 (3), A (4). También A12AA20
--   (calcio, 5.º nivel pero a nivel 1; «sec up» = secundario hacia
--   arriba), el enlace raro de 'RxNorm - ATC sec up'.
SELECT c.concept_code,
       c.concept_name,
       c.concept_class_id,
       ca.min_levels_of_separation AS min_niv,
       ca.max_levels_of_separation AS max_niv
FROM cdm.concept_ancestor ca
JOIN cdm.concept c ON c.concept_id = ca.ancestor_concept_id   -- 1:1 por PK
WHERE ca.descendant_concept_id = 1503297
  AND c.vocabulary_id = 'ATC'
ORDER BY min_niv, c.concept_code;
