# Registro de decisiones — Lab 16 (Jerarquías: concept_relationship y concept_ancestor)

Formato: qué se decidió, qué alternativas había y por qué se eligió esta.

## 1. Motor y base de datos
- **Decisión:** trabajar sobre el Postgres del lab 12 (contenedor `lab12-omop-db-1`, esquema `cdm` de solo lectura, vocabulario v5.0 29-AUG-26), con `psql` dentro del contenedor. Los `EXPLAIN ANALYZE` de la actividad 8 son de **PostgreSQL**.
- **Alternativas:** DuckDB con jupysql, como sugiere el enunciado (descartada: habría que copiar `concept_ancestor`, de 12 millones de filas, `concept_relationship` y `relationship`, y volver a validarlas; además, en DuckDB, que guarda por columnas y casi no usa índices, la actividad 8 mostraría menos cambios en el plan).
- **Por qué:** `relationship` ya está cargada (724 tipos), igual que el concept set de T2DM del lab 14 (`results.cs_t2dm`), que se reutiliza en las actividades 5 a 8. Los planes de Postgres nombran cada operación (Seq Scan, Index Scan, Hash Join), y eso es lo que pide comparar la actividad 8.
