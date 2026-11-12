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

## 3. Qué significa «los 20 más frecuentes» (actividad 2)
- **Decisión:** ordenar los `drug_concept_id` por número de filas en `drug_exposure` (registros), con una columna adicional de pacientes distintos.
- **Alternativas:** ordenar por pacientes distintos (descartada aquí: 9 de esos 20 son vacunas CVX sin ingrediente RxNorm, y solo 6 productos coinciden con el top-20 por filas).
- **Por qué:** es la lectura literal del enunciado y deja 18 productos con ingrediente para practicar el paso de producto a ingrediente. Las filas miden volumen de dispensaciones y se inflan con los tratamientos repetidos (epoetina: 81,102 filas y 272 pacientes, unas 298 por paciente); para una pregunta de prevalencia de uso el criterio correcto serían los pacientes.

## 4. Nivel 0 de concept_ancestor y productos sin ingrediente (actividad 2)
- **Decisión:** buscar los ancestros de clase `Ingredient` en `concept_ancestor` **incluido** el nivel 0 (`min_levels_of_separation = 0`), con `LEFT JOIN`.
- **Alternativas:** exigir `min_levels_of_separation >= 1` (descartada: pierde los registros cuyo concepto ya es un ingrediente; 84 filas en la base) o usar la relación directa «RxNorm has ing» (descartada: depende de la clase del producto).
- **Por qué:** si el concepto ya es un ingrediente, se encuentra a sí mismo y no se pierde. El `LEFT JOIN` deja visibles los productos sin ingrediente (las vacunas CVX) con el ingrediente vacío; un `JOIN` los borraría y el top-20 quedaría en 18 sin avisar.
