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

## 5. Alcance de la clase ATC A10B (actividad 3)
- **Decisión:** usar A10B tal como la define ATC («Blood glucose lowering drugs, excl. insulins»), con todo lo que cuelga de ella, incluidos los inyectables no insulínicos (análogos de GLP-1, pramlintida, tirzepatida).
- **Alternativas:** quitar las subclases inyectables, como A10BJ (descartada: la vía es una propiedad del producto, no de la clase; quitar A10BJ elimina también la semaglutida oral) o filtrar los productos por forma farmacéutica oral (descartada por ahora: añade un filtro fuera de la jerarquía; se aplicaría en la sesión 17 si la pregunta fuera solo sobre orales).
- **Por qué:** es la definición estándar y reproducible: otro equipo que diga «A10B» obtiene lo mismo. El enunciado la llama «hipoglucemiantes orales», lo cual es inexacto, y se declara en el informe. En la base no cambia nada: los 2 pacientes con liraglutida también toman metformina (231 pacientes con cualquiera de las tres opciones).

## 6. Qué excluye la versión C de metformina (actividad 4)
- **Decisión:** C = B menos los productos que además contienen un inhibidor de SGLT2. La exclusión se define por jerarquía: productos que descienden de cualquier ingrediente de la clase ATC A10BK (hoy 6 ingredientes; 151 conceptos excluidos). C queda con 249 conceptos estándar.
- **Alternativas:** excluir también la combinación con ropinirol (descartada: no tiene relación con la función renal; queda documentada como combinación obsoleta de 2005-2008) o excluir todas las combinaciones (descartada: C quedaría igual que A).
- **Por qué:** la pregunta guía es el efecto de la metformina sobre la función renal. Los iSGLT2 tienen un efecto protector renal propio, así que un paciente con metformina + empagliflozina mezcla dos exposiciones sobre el mismo desenlace. Las combinaciones con iDPP-4 o sulfonilureas se mantienen porque no tienen un efecto renal propio comparable. Definirla por la clase ATC, y no con una lista de nombres, recoge sola los iSGLT2 nuevos (sotagliflozina, bexagliflozina).
- **Nota sobre «monoterapia» en A:** se refiere al **producto** (una pastilla con un solo ingrediente), no al paciente. Quien toma metformina y empagliflozina en dos pastillas separadas está en A; solo sale de A si la metformina le llega dentro de una pastilla combinada. Saber si un paciente está en monoterapia exige comparar fechas de exposición (sesión 17). En la base los 231 pacientes con metformina toman además otro fármaco (102 lisinopril, 2 liraglutida).

## 7. Cómo presentar A/B/C en la gráfica (actividad 4)
- **Decisión:** figura de dos paneles: conceptos por versión y pacientes por versión.
- **Alternativas:** solo pacientes, como pide el enunciado al pie de la letra (descartada: daría tres barras iguales, porque en la base el único producto con metformina es monoterapia).
- **Por qué:** muestra a la vez que la definición cambia mucho (83 / 400 / 249 conceptos) y que en esta base no se nota en los pacientes. Las dos cosas son el resultado; la igualdad de pacientes se declara como limitación de Synthea.
