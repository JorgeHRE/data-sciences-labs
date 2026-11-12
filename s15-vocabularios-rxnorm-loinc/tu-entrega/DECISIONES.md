# Registro de decisiones — Lab 15 (Concept sets de fármacos y laboratorios: RxNorm y LOINC)

Formato: qué se decidió, qué alternativas había y por qué se eligió esta.

## 1. Motor, base de datos y vocabularios
- **Decisión:** trabajar sobre el Postgres del lab 12 (`lab12-omop`, BD `omop_lab12`, esquema `cdm` de solo lectura), con el vocabulario de ATHENA ya cargado (v5.0 29-AUG-26: RxNorm 20260601, ATC 2026-02-01, LOINC 2.82, UCUM 1.8.2, CVX 20260409). No se descarga RxNorm Extension.
- **Alternativas:** DuckDB, como sugiere el enunciado (descartada: habría que copiar `concept_ancestor` y `concept_relationship` y volver a validarlas), o descargar RxNorm Extension de ATHENA (descartada: el control 0b muestra que ningún `drug_concept_id` de los datos pertenece a él; los 365 son RxNorm, 346, o vacunas CVX, 19).
- **Por qué:** es la misma base de los labs 12-14; los concept sets de aquí se cruzarán con el de T2DM del lab 14 en la sesión 17. RxNorm Extension cubre fármacos fuera de EE. UU.; haría falta con datos europeos o con el catálogo local de la actividad 8 si algún producto mexicano no existe en RxNorm (se revisará entonces).

## 2. Tres fármacos de referencia (actividad 1)
- **Decisión:** metformina (fármaco principal, 231 pacientes en la base), lisinopril (IECA, 1,522 pacientes) y empagliflozina (iSGLT2, 0 pacientes en la base).
- **Alternativas:** metformina + lisinopril + liraglutida, los tres presentes en la base (descartada: la liraglutida casi no tiene combinaciones y solo aporta 2 pacientes); sitagliptina o glipizida como comparador A10B (descartadas: tampoco están en la base y no tienen relación directa con la función renal).
- **Por qué:** los tres tocan la pregunta de la actividad 4 (metformina y función renal) desde ángulos distintos: la metformina depende del riñón para eliminarse, y el lisinopril y la empagliflozina lo protegen; además, la empagliflozina tiene combinaciones con metformina, que es justo el problema de la versión B. Que la empagliflozina no esté en la base se reporta como hallazgo de cobertura de Synthea.
