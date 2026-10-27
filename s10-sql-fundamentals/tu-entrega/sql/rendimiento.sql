-- Actividad 9: medir el rendimiento.
-- Consulta elegida: 6.15 (urgencias sin diagnóstico), una de las dos más lentas de las 15
-- (~39 ms en la primera corrida; ninguna pasa de 40 ms).
-- Cambio probado: reemplazar NOT EXISTS correlacionado por LEFT JOIN ... WHERE c.encounter IS NULL.
-- Ambas devuelven lo mismo: 5 272 encuentros, 1 873 pacientes.
--
-- Mediciones (DuckDB, 31 corridas por versión, mediana; memoria = pico RSS en proceso nuevo,
-- 1 hilo, 8 corridas idénticas, línea base de 66 MB solo abriendo la base):
--
--                 A: NOT EXISTS      B: LEFT JOIN ... IS NULL
--   Mediana       14.8 ms            6.9 ms
--   Rango         12.0 - 21.2 ms     6.3 - 9.1 ms
--   Pico RSS      92 MB (+26)        85 MB (+19)
--   Join          MARK + Filter      RIGHT_ANTI
--
-- Explicación (del autor):
-- DuckDB transformó la subconsulta correlacionada de A (NOT EXISTS) mediante un operador de
-- join marcador (MARK) seguido de un filtro secuencial sobre la columna booleana generada,
-- mientras que en B (LEFT JOIN ... IS NULL) aplicó directamente un operador nativo
-- RIGHT_ANTI. La variante B fue dos veces más rápida (~6.9 ms vs 14.8 ms) porque el
-- anti-join descarta inmediatamente en la fase de sondeo (probe) las filas con coincidencia,
-- evitando el cómputo y la evaluación posterior del predicado marcador. Respecto a la
-- memoria, la predicción de que B consumiría más resultó falsa: B requirió ~7 MB menos de
-- pico RSS (85 MB vs 92 MB), confirmando empíricamente que materializar el vector marcador
-- en el plan de A introdujo tanto sobrecosto de CPU como una mayor huella de asignación
-- temporal.
--
-- Nota: lo medido es el tiempo y el pico RSS; que la causa sea el vector marcador es una
-- lectura del plan, no se aisló con un experimento. El RSS incluye todo el proceso y la
-- diferencia (7 MB) es pequeña frente a la base de 66 MB.
--
-- Qué NO cambió: ambos planes leen solo las columnas necesarias (id, patient / encounter) y
-- aplican el filtro encounterclass = 'emergency' dentro del escaneo. Reordenar el WHERE o
-- quitar columnas no habría cambiado nada: el motor columnar y el optimizador ya lo hacen.
-- Los operadores marcan 10 ms de resolución en el plan A, por lo que no se puede atribuir el
-- tiempo a un operador concreto; por eso se compara el tiempo total con repeticiones.

-- ===================== A: NOT EXISTS =====================
WITH urgencias_sin_diagnostico AS (
    SELECT
        e.Id AS encounter_id,
        e.patient
    FROM encounters e
    WHERE e.encounterclass = 'emergency'
      AND NOT EXISTS (
          SELECT 1
          FROM conditions c
          WHERE c.encounter = e.Id
      )
)
SELECT
    COUNT(*) AS encuentros_urgencias_sin_diagnostico,
    COUNT(DISTINCT patient) AS pacientes_afectados
FROM urgencias_sin_diagnostico;

-- Plan A (EXPLAIN ANALYZE):
-- ╭─ Summary ───────────╮
-- │ Total Time: 0.0211s │
-- ╰─────────────────────╯
-- ╭─ CTE ──────────────────────────────────╮
-- │ CTE Name: __aggregate_cte_33           │
-- │ Table Index: 33                        │
-- │ Execution Mode: STREAMING_FANOUT       │
-- │ Fanout Mode: DIRECT                    │
-- │ Consumers: 2                           │
-- │ Direct Consumers: 2                    │
-- │ Buffered Consumers: 0                  │
-- │ Chunk Storage: NONE                    │
-- │ Order Mode: UNORDERED                  │
-- │ 0 rows                             0µs │
-- ╰────────────────────┬───────────────────╯
--                      ├────────────────────────────────────────────────────────────────────────╮
-- ╭─ Projection ───────┴───────────────────╮                                      ╭─ Projection ┴────────────╮
-- │ Projections: #0                        │                                      │ Projections: #1, #0      │
-- │ 5,272 rows                         0µs │                                      │ 1 row                0µs │
-- ╰────────────────────┬───────────────────╯                                      ╰─────────────┬────────────╯
-- ╭─ Filter ───────────┴───────────────────╮                                      ╭─ Cross Product ──────────╮
-- │ Expression: NOT SUBQUERY               │                                      │ 1 row                0µs │
-- │ 5,272 rows                         0µs │                                      ╰─────────────┬────────────╯
-- ╰────────────────────┬───────────────────╯                                                    ├─────────────────────────────╮
-- ╭─ Hash Join ────────┴───────────────────╮                                      ╭─ Ungrouped Aggregate ────╮  ╭─ Ungrouped Aggregate ────╮
-- │ Join Type: MARK                        │                                      │ Aggregates: count_star() │  │ Aggregates: count_star() │
-- │ Conditions: id IS NOT DISTINCT FROM id │                                      │ 1 row                0µs │  │ 1 row                0µs │
-- │ 15,958 rows                     10.0ms │                                      ╰─────────────┬────────────╯  ╰─────────────┬────────────╯
-- ╰────────────────────┬───────────────────╯                                      ╭─ Hash Group By ──────────╮  ╭─ CTE Scan ──┴────────────╮
--                      ├───────────────────────────────────────┰┒                 │ Groups: #0               │  │ CTE Index: 33            │
-- ╭─ Table Scan ───────┴───────────────────╮  ╭─ Table Scan ───┚┖──────────────╮  │ 1,873 rows           0µs │  │ CTE Mode: DIRECT         │
-- │ Table: clinica.main.encounters         │  │ Table: clinica.main.conditions │  ╰─────────────┬────────────╯  │ Consumer: 1              │
-- │ Type: Sequential Scan                  │  │ Type: Sequential Scan          │  ╭─ Projection ┴────────────╮  │ 5,272 rows           0µs │
-- │ Projections: id, patient               │  │ Projections: encounter         │  │ Projections: patient     │  ╰──────────────────────────╯
-- │ Filters: encounterclass = 'emergency'  │  │ Filters: encounter = encounter │  │ 5,272 rows           0µs │
-- │ Row Groups Scanned: 4 / 4              │  │ Row Groups Scanned: 2 / 2      │  ╰─────────────┬────────────╯
-- │ 15,958 rows                     10.0ms │  │ 235,504 rows            10.0ms │  ╭─ CTE Scan ──┴────────────╮
-- ╰────────────────────────────────────────╯  ╰────────────────────────────────╯  │ CTE Index: 33            │
--                                                                                 │ CTE Mode: DIRECT         │
--                                                                                 │ Consumer: 0              │
--                                                                                 │ 5,272 rows           0µs │
--                                                                                 ╰──────────────────────────╯

-- ===================== B: LEFT JOIN ... IS NULL =====================
WITH urgencias_sin_diagnostico AS (
    SELECT
        e.Id AS encounter_id,
        e.patient
    FROM encounters e
    LEFT JOIN conditions c
      ON c.encounter = e.Id
    WHERE e.encounterclass = 'emergency'
      AND c.encounter IS NULL
)
SELECT
    COUNT(*) AS encuentros_urgencias_sin_diagnostico,
    COUNT(DISTINCT patient) AS pacientes_afectados
FROM urgencias_sin_diagnostico;

-- Plan B (EXPLAIN ANALYZE):
-- ╭─ Summary ───────────╮
-- │ Total Time: 0.0085s │
-- ╰─────────────────────╯
-- ╭─ CTE ────────────────────────────╮
-- │ CTE Name: __aggregate_cte_16     │
-- │ Table Index: 16                  │
-- │ Execution Mode: STREAMING_FANOUT │
-- │ Fanout Mode: DIRECT              │
-- │ Consumers: 2                     │
-- │ Direct Consumers: 2              │
-- │ Buffered Consumers: 0            │
-- │ Chunk Storage: NONE              │
-- │ Order Mode: UNORDERED            │
-- │ 0 rows                       0µs │
-- ╰─────────────────┬────────────────╯
--                   ├────────────────────────────────────────────────────────────────────────────╮
-- ╭─ Hash Join ─────┴────────────────╮                                             ╭─ Projection ┴────────────╮
-- │ Join Type: RIGHT_ANTI            │                                             │ Projections: #1, #0      │
-- │ Conditions: encounter = id       │                                             │ 1 row                0µs │
-- │ 5,272 rows                10.0ms │                                             ╰─────────────┬────────────╯
-- ╰─────────────────┰┰───────────────╯                                             ╭─ Cross Product ──────────╮
--                   ┃┠──────────────────────────────────────╮                      │ 1 row                0µs │
-- ╭─ Table Scan ────┚┖───────────────╮  ╭─ Table Scan ──────┴───────────────────╮  ╰─────────────┬────────────╯
-- │ Table: clinica.main.conditions   │  │ Table: clinica.main.encounters        │                ├─────────────────────────────╮
-- │ Type: Sequential Scan            │  │ Type: Sequential Scan                 │  ╭─ Ungrouped Aggregate ────╮  ╭─ Ungrouped Aggregate ────╮
-- │ Projections: encounter           │  │ Projections: id, patient              │  │ Aggregates: count_star() │  │ Aggregates: count_star() │
-- │ Row Groups Scanned: 2 / 2        │  │ Filters: encounterclass = 'emergency' │  │ 1 row                0µs │  │ 1 row                0µs │
-- │ 235,504 rows                 0µs │  │ Row Groups Scanned: 4 / 4             │  ╰─────────────┬────────────╯  ╰─────────────┬────────────╯
-- ╰──────────────────────────────────╯  │ 15,958 rows                       0µs │  ╭─ Hash Group By ──────────╮  ╭─ CTE Scan ──┴────────────╮
--                                       ╰───────────────────────────────────────╯  │ Groups: #0               │  │ CTE Index: 16            │
--                                                                                  │ 1,873 rows           0µs │  │ CTE Mode: DIRECT         │
--                                                                                  ╰─────────────┬────────────╯  │ Consumer: 1              │
--                                                                                  ╭─ Projection ┴────────────╮  │ 5,272 rows           0µs │
--                                                                                  │ Projections: patient     │  ╰──────────────────────────╯
--                                                                                  │ 5,272 rows           0µs │
--                                                                                  ╰─────────────┬────────────╯
--                                                                                  ╭─ CTE Scan ──┴────────────╮
--                                                                                  │ CTE Index: 16            │
--                                                                                  │ CTE Mode: DIRECT         │
--                                                                                  │ Consumer: 0              │
--                                                                                  │ 5,272 rows           0µs │
--                                                                                  ╰──────────────────────────╯
