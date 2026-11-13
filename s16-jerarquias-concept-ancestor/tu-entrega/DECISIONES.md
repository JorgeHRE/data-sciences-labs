# Registro de decisiones — Lab 16 (Jerarquías: concept_relationship y concept_ancestor)

Formato: qué se decidió, qué alternativas había y por qué se eligió esta.

## 1. Motor y base de datos
- **Decisión:** trabajar sobre el Postgres del lab 12 (contenedor `lab12-omop-db-1`, esquema `cdm` de solo lectura, vocabulario v5.0 29-AUG-26), con `psql` dentro del contenedor. Los `EXPLAIN ANALYZE` de la actividad 8 son de **PostgreSQL**.
- **Alternativas:** DuckDB con jupysql, como sugiere el enunciado (descartada: habría que copiar `concept_ancestor`, de 12 millones de filas, `concept_relationship` y `relationship`, y volver a validarlas; además, en DuckDB, que guarda por columnas y casi no usa índices, la actividad 8 mostraría menos cambios en el plan).
- **Por qué:** `relationship` ya está cargada (724 tipos), igual que el concept set de T2DM del lab 14 (`results.cs_t2dm`), que se reutiliza en las actividades 5 a 8. Los planes de Postgres nombran cada operación (Seq Scan, Index Scan, Hash Join), y eso es lo que pide comparar la actividad 8.

## 2. Concepto de partida para las actividades 1, 2 y 4
- **Decisión:** diabetes mellitus tipo 2, SNOMED **201826** (estándar, dominio Condition).
- **Alternativas:** trastorno de conducción cardiaca 4229440 (el punto donde se traslapan las ramas de insuficiencia cardiaca de la actividad 5).
- **Por qué:** es el concepto del lab 14 (`results.cs_t2dm`), así que hay continuidad, y ya tiene poli-jerarquía (llega a *Disease* y a *Clinical finding* por varios caminos). Con un solo concepto se resuelven las actividades 1, 2 y 4.

## 3. Cómo tratar los caminos múltiples en la consulta recursiva
- **Decisión:** `UNION ALL` + la ruta recorrida en un `ARRAY` + `NOT (id = ANY(ruta))`, además del freno `nivel < 20`. Se reporta la profundidad **mínima (6) y máxima (7)**, igual que `min_levels_of_separation` y `max_levels_of_separation` de `concept_ancestor`.
- **Alternativas:** `UNION ALL` simple (20 filas con repetidos y sin saber por qué camino llegó cada una) o `UNION` (parece limpio, pero solo quita filas idénticas: *Disease* sigue saliendo en los niveles 4 y 5).
- **Por qué:** cada fila lleva su camino completo, así que se ven los 4 caminos a la raíz. La condición sobre la ruta impide volver a un concepto ya visitado (protege contra ciclos), y la misma consulta sirve después para las actividades 4 y 6.

## 4. Cómo comparar los ancestros de la recursiva con los de `concept_ancestor`
- **Decisión:** `FULL OUTER JOIN` de los dos conjuntos con una columna de origen («ambos», «solo recursiva», «solo concept_ancestor»), una fila por concepto.
- **Alternativas:** dos `EXCEPT` (recursiva − CA y CA − recursiva), que es la comparación de conjuntos literal, pero da dos resultados y no muestra lo que coincide.
- **Por qué:** en una sola tabla se ve lo común y lo distinto, que es la forma habitual de conciliar dos fuentes en la industria. Condición: dejar antes la recursiva en un concepto por fila (`DISTINCT`), porque sus 20 filas con repetidos multiplicarían el JOIN.

## 5. Fármaco para listar las relaciones salientes (actividad 3)
- **Decisión:** metformina como ingrediente, RxNorm **1503297** (clase Ingredient, estándar).
- **Alternativas:** el producto que toman los pacientes de la base, 40163924 (24 HR metformin hydrochloride 500 MG ER Oral Tablet, 8 tipos de relación, con más estructura interna de RxNorm: forma farmacéutica, versión cuantificada).
- **Por qué:** tiene 9 tipos de relación y más variados (ATC, marcas, mapeos, productos que la contienen), es el ingrediente de los concept sets de la sesión 15 y reúne los dos casos que contrastan: `RxNorm ing of` (jerárquica y define ascendencia) y `Has brand name` (jerárquica sin definir ascendencia).

## 6. Par con poli-jerarquía y cómo reconstruir sus caminos (actividad 4)
- **Decisión:** el par T2DM 201826 → *Disease* 4274025 (min 4 / max 5), reconstruido con `concept_relationship` excluyendo los conceptos retirados (`concept.invalid_reason IS NULL` en el destino de cada paso, además de la arista vigente).
- **Alternativas:** el par T2DM → *Clinical finding* 441840 (5/6; la misma idea con un nivel más, casi en la raíz); o reconstruir sin excluir conceptos retirados, que añade un tercer camino de 5 pasos por *Disorder by body site* (retirado en 2021).
- **Por qué:** los dos caminos tienen lectura clínica directa (la diabetes como enfermedad endocrina y como enfermedad metabólica), y sin conceptos retirados salen exactamente los 2 caminos que describe `concept_ancestor` (4 y 5). La trampa 3 de la actividad 1 solo filtraba aristas retiradas, no conceptos retirados.
