# Registro de decisiones — Lab 14 (Vocabularios estándar: construir y defender un concept set)

Formato: qué se decidió, qué alternativas había y por qué se eligió esta.

## 1. Motor y base de datos
- **Decisión:** trabajar sobre el Postgres del lab 12 (`lab12-omop`, puerto 5433, BD `omop_lab12`, esquema `cdm`), con el vocabulario de ATHENA ya cargado. El esquema `cdm` se usa solo para leer.
- **Alternativas:** DuckDB, como sugiere el enunciado (descartada: habría que copiar `concept_relationship`, con 14 M de filas, y `concept_ancestor`, con 12 M, y volver a comprobar la copia) o descargar otro vocabulario de ATHENA (descartada: el cargado está completo, ver el control del paso 0).
- **Por qué:** es la misma base validada en los labs 12 y 13; los concept sets que salgan de aquí se reutilizan en la sesión 17 sobre esa misma base.
