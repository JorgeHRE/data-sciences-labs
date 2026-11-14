# Tiempos — Lab 16, actividad 8

Pregunta: ¿cuántos pacientes tienen insuficiencia cardiaca? (concept set de la actividad 5, 194 pacientes). Consultas en `jerarquias.sql`, bloques 8a-8c (decisión 9).

**Entorno:** PostgreSQL del lab 12 (contenedor Docker `lab12-omop-db-1`), vocabulario v5.0 29-AUG-26. `condition_occurrence` 101,699 filas, **sin índice en `condition_concept_id`**. Medición 2026-11-14 con `EXPLAIN (ANALYZE, BUFFERS)`, una sola sesión de psql, versiones intercaladas (1, 2, 1, 2, 1, 2).

## Versiones
1. `WHERE condition_concept_id IN (subconsulta sobre concept_ancestor)`: el concept set se recalcula en cada ejecución.
2. Concept set materializado en una tabla temporal `cs_ic` (124 conceptos, `PRIMARY KEY` = índice, `ANALYZE`) y `JOIN`.

## Tiempos (Execution Time, ms)
| Versión | Corrida 1 | Corrida 2 | Corrida 3 | **Mediana** |
|---|---|---|---|---|
| 1. `IN` + subconsulta | 8.53 | 8.08 | 7.84 | **8.08** |
| 2. Tabla materializada + `JOIN` | 8.15 | 7.81 | 7.88 | **7.88** |

Diferencia de medianas: 0.2 ms (≈2.5 %), menor que la variación entre corridas de una misma versión (≈0.7 ms). **No medí diferencia a esta escala.**

Nota: una medición exploratoria previa, con la caché todavía fría, dio 12.3 vs 8.5 ms y exageraba la diferencia. En las 6 corridas reportadas `BUFFERS` muestra solo `hit` (0 `read`): todo estaba en memoria.

## Qué cambió en el plan
| | Versión 1 | Versión 2 |
|---|---|---|
| Tipo de unión | Hash Semi Join | Hash Join |
| Origen de la tabla hash | Bitmap Index Scan (`idx_ca_ancestor`) + Bitmap Heap Scan en `concept_ancestor`: 176 pares, 180 bloques | Seq Scan de `cs_ic`: 124 conceptos, 1 bloque (el índice de la PK no se usa) |
| Tabla grande | Seq Scan de `condition_occurrence`, 1,375 bloques | igual |
| Filas estimadas / reales tras la unión | 335 / 194 | 30,097 / 194 |

Lo que cambió fue el tipo de unión: en el segundo plan se usa un Hash Join normal (la PK garantiza que no hay repetidos), construido con un Seq Scan de `cs_ic` (124 conceptos, 1 bloque) en lugar de los 176 pares y 180 bloques que la versión 1 lee de `concept_ancestor` en cada ejecución. En cuanto a las estimaciones, la versión 1 estimó 335 filas cuando en realidad fueron 194, y la versión 2 estimó peor: 30,097 para las mismas 194 reales.

**Por qué casi no movió el tiempo:** las dos versiones gastan casi todo en el mismo paso, el Seq Scan completo de `condition_occurrence` (1,375 de ~1,555 bloques, ~3.3 ms), que no cambió. Materializar solo ahorra preparar el concept set (~0.1 ms). Lo que sí cambiaría el plan es un índice en `condition_occurrence(condition_concept_id)` (Index Scan en lugar de Seq Scan); no se creó porque `cdm` es de solo lectura (decisión 1). En una base real, con cientos de millones de filas y concept sets de miles de conceptos reutilizados en muchas consultas, la materialización con índice sí pesa más.

## Plan de ejecución, versión 1 (corrida mediana: 2)
```
 Aggregate  (cost=8145.48..8145.49 rows=1 width=8) (actual time=8.065..8.066 rows=1 loops=1)
   Buffers: shared hit=1555
   ->  Sort  (cost=8143.80..8144.64 rows=335 width=4) (actual time=8.051..8.057 rows=194 loops=1)
         Sort Key: co.person_id
         Sort Method: quicksort  Memory: 25kB
         Buffers: shared hit=1555
         ->  Hash Semi Join  (cost=5456.61..8129.75 rows=335 width=4) (actual time=0.221..8.044 rows=194 loops=1)
               Hash Cond: (co.condition_concept_id = ca.descendant_concept_id)
               Buffers: shared hit=1555
               ->  Seq Scan on condition_occurrence co  (cost=0.00..2391.99 rows=101699 width=8) (actual time=0.001..3.348 rows=101699 loops=1)
                     Buffers: shared hit=1375
               ->  Hash  (cost=5437.37..5437.37 rows=1539 width=4) (actual time=0.118..0.118 rows=176 loops=1)
                     Buckets: 2048  Batches: 1  Memory Usage: 23kB
                     Buffers: shared hit=180
                     ->  Bitmap Heap Scan on concept_ancestor ca  (cost=25.23..5437.37 rows=1539 width=4) (actual time=0.029..0.107 rows=176 loops=1)
                           Recheck Cond: (ancestor_concept_id = ANY ('{316139,319835,444031}'::integer[]))
                           Heap Blocks: exact=171
                           Buffers: shared hit=180
                           ->  Bitmap Index Scan on idx_ca_ancestor  (cost=0.00..24.85 rows=1539 width=0) (actual time=0.015..0.015 rows=176 loops=1)
                                 Index Cond: (ancestor_concept_id = ANY ('{316139,319835,444031}'::integer[]))
                                 Buffers: shared hit=9
 Planning:
   Buffers: shared hit=8
 Planning Time: 0.093 ms
 Execution Time: 8.081 ms
```

## Plan de ejecución, versión 2 (corrida mediana: 3)
```
 Aggregate  (cost=5054.74..5054.75 rows=1 width=8) (actual time=7.869..7.870 rows=1 loops=1)
   Buffers: shared hit=1375, local hit=1
   ->  Sort  (cost=4904.26..4979.50 rows=30097 width=4) (actual time=7.855..7.861 rows=194 loops=1)
         Sort Key: co.person_id
         Sort Method: quicksort  Memory: 25kB
         Buffers: shared hit=1375, local hit=1
         ->  Hash Join  (cost=3.79..2665.44 rows=30097 width=4) (actual time=0.120..7.849 rows=194 loops=1)
               Hash Cond: (co.condition_concept_id = cs.concept_id)
               Buffers: shared hit=1375, local hit=1
               ->  Seq Scan on condition_occurrence co  (cost=0.00..2391.99 rows=101699 width=8) (actual time=0.001..3.282 rows=101699 loops=1)
                     Buffers: shared hit=1375
               ->  Hash  (cost=2.24..2.24 rows=124 width=4) (actual time=0.012..0.012 rows=124 loops=1)
                     Buckets: 1024  Batches: 1  Memory Usage: 13kB
                     Buffers: local hit=1
                     ->  Seq Scan on cs_ic cs  (cost=0.00..2.24 rows=124 width=4) (actual time=0.002..0.005 rows=124 loops=1)
                           Buffers: local hit=1
 Planning:
   Buffers: local hit=4
 Planning Time: 0.054 ms
 Execution Time: 7.879 ms
```
