# Registro de decisiones — Lab 13 (Drug Exposure, Measurement y tablas derivadas)

Formato: qué se decidió, qué alternativas había y por qué se eligió esta.

## 1. Motor y base de datos
- **Decisión:** trabajar sobre el Postgres del lab 12 (`lab12-omop`, puerto 5433, BD `omop_lab12`), leyendo de `cdm` y escribiendo las tablas propias en un esquema nuevo `results`. No se re-corre el ETL.
- **Alternativas:** exportar el CDM a DuckDB (descartada: duplica ~4 M de mediciones y 12 M de `concept_ancestor`, y obliga a re-verificar la copia) o volver a correr ETL-Synthea (descartada: tarda y no aporta nada nuevo).
- **Por qué:** es la misma base ya validada en el lab 12 (conteos verificados en el paso 0) y separar `results` de `cdm` es la convención OHDSI: el CDM queda intacto y lo derivado se puede borrar y regenerar.
