# Registro de decisiones — Lab 13 (Drug Exposure, Measurement y tablas derivadas)

Formato: qué se decidió, qué alternativas había y por qué se eligió esta.

## 1. Motor y base de datos
- **Decisión:** trabajar sobre el Postgres del lab 12 (`lab12-omop`, puerto 5433, BD `omop_lab12`), leyendo de `cdm` y escribiendo las tablas propias en un esquema nuevo `results`. No se re-corre el ETL.
- **Alternativas:** exportar el CDM a DuckDB (descartada: duplica ~4 M de mediciones y 12 M de `concept_ancestor`, y obliga a re-verificar la copia) o volver a correr ETL-Synthea (descartada: tarda y no aporta nada nuevo).
- **Por qué:** es la misma base ya validada en el lab 12 (conteos verificados en el paso 0) y separar `results` de `cdm` es la convención OHDSI: el CDM queda intacto y lo derivado se puede borrar y regenerar.

## 2. Qué tipos de exposición entran en las métricas de fármacos (actividad 1)
- **Decisión:** las actividades 2-5 usan solo prescripciones (`drug_type_concept_id = 32838`, «EHR prescription», 388,700 filas, todo RxNorm). Las vacunas (`32827`, «EHR encounter record», 78,890 filas, todo CVX) se describen en la actividad 1 y quedan excluidas de forma explícita con un `WHERE`, sin borrarlas de `cdm`.
- **Alternativas:** mezclar ambos tipos (descartada: las vacunas tienen fin = inicio y meten 78,890 ceros en `days_supply`, además de mezclar dos niveles de evidencia) o estratificar cada tabla por tipo (descartada: duplica resultados y las vacunas no aportan nada a eras ni a PDC).
- **Por qué:** un estudio define una sola fuente de exposición. Además, ninguno de los 19 conceptos CVX tiene un ancestro *Ingredient*, así que no pueden aparecer en búsquedas por ingrediente ni en `drug_era`. En la actividad 2 se muestra el efecto de la exclusión (porcentaje de fin = inicio con y sin vacunas).
