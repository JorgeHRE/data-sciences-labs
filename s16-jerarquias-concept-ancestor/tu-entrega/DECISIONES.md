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
