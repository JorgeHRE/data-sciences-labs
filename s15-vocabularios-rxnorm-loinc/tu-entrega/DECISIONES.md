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

## 8. Qué entra en el concept set de HbA1c (actividad 6)
- **Decisión:** 8 códigos LOINC, todo lo que mide la fracción de HbA1c sobre la hemoglobina total: 4548-4, 17856-6 (HPLC), 4549-2 (electroforesis), 62388-4 (JDS/JSCC), 17855-8 (calculada), 96595-4 (gota de sangre seca), 59261-8 (IFCC, mmol/mol) y 71875-9 (fracción decimal). Los dos últimos se marcan «requiere conversión» (NGSP % = 0.0915 × IFCC + 2.15; decimal × 100). Fuera: 86910-7 (meta o *goal*: el objetivo que fija el médico, clase Clinical Observation) y 41995-2 (masa/volumen: depende también de la Hb total, no se puede convertir a %).
- **Alternativas:** solo el LOINC Group LG51070-7 (4 códigos, todos en %) o el grupo más todo lo que esté en % (6). Descartadas porque pierden la HbA1c IFCC, estándar en Europa y en muchos laboratorios, y el concept set dejaría de ser portable a otras bases.
- **Por qué:** el concept set responde «¿esto es una HbA1c?»; armonizar unidades es un paso posterior del análisis (actividad 7). Es la separación que usa OHDSI. La regla para excluir: si basta un factor o una fórmula, es un problema de unidades y el código entra; si falta un dato del paciente o no es una medición, es otra cantidad y queda fuera.

## 9. Qué abarca la auditoría de unidades (actividad 7)
- **Decisión:** auditar los tres analitos con todos sus códigos en uso: glucosa = 2345-7 + 2339-0, creatinina = 2160-0 + 38483-4, HbA1c = concept set de la actividad 6 (en la base, solo 4548-4). Tabla por analito; histogramas separados por código y unidad.
- **Alternativas:** solo los 3 códigos literales de la actividad 5 (descartada: la anomalía de creatinina, con valores hasta 130.6 mg/dL, está en 38483-4 y se perdería) o añadir los códigos en otras unidades, como 14682-9 en µmol/L (descartada: tienen 0 mediciones en la base).
- **Por qué:** la pregunta es si se puede promediar «tal cual», y un analista que promedia «creatinina» junta los dos códigos (actividad 5). Mantiene la consistencia con las actividades 5 y 6: se audita el analito, no un código suelto. Se declara que va más allá de la letra del enunciado.

## 10. Cómo asignar el estadio de ERC a cada creatinina (actividad 7)
- **Decisión:** cada medición de creatinina en sangre (38483-4) toma el estadio de ERC más alto diagnosticado **hasta la fecha de esa medición** (estadios 1-4 y ERC terminal, descendientes de SNOMED 46271022 en `condition_occurrence`; fecha = primer diagnóstico de cada estadio).
- **Alternativas:** el estadio máximo que el paciente tuvo «alguna vez» (descartada: una creatinina de años antes del diagnóstico cuenta como ERC avanzada y difumina la señal; en estadio 3 sube de 0.6 % a 10.8 % la fracción en la moda baja).
- **Por qué:** lo que explica el valor es el estado del riñón cuando se tomó la muestra; es la misma alineación temporal que se usa con la exposición a fármacos. Limitación: si un diagnóstico se registró tarde, el estadio a la fecha queda subestimado.

## 11. Con qué herramienta se mapea el catálogo local (actividad 8)
- **Decisión:** búsqueda por SQL sobre el vocabulario cargado en Postgres (RxNorm 20260601), guardada en `actividades.sql`.
- **Alternativas:** Usagi (descartada para 15 términos: requiere Java e indexar el vocabulario, y sus sugerencias en español son pobres; es la opción para un catálogo real de miles de claves) o ATHENA web a mano (descartada: puede ser otra versión de vocabulario y no deja rastro reproducible).
- **Por qué:** misma versión de vocabulario que los datos, reproducible y auditable; ATHENA consulta por dentro las mismas tablas.

## 12. Reglas de confianza y nivel de destino del mapeo (actividad 8)
- **Decisión:** **alta** = existe un Clinical Drug estándar con mismo ingrediente, dosis y forma (tras convertir unidades). **dudosa** = se mapea a algo menos específico (Clinical Drug Form o Ingredient) o el candidato exige un supuesto no verificable (ingrediente con otro nombre, composición inferida). **no mapeable** = ningún concepto estándar del dominio Drug lo representa; `concept_id = 0`. La gasa va como no mapeable (i), anotando que en OMOP iría a `device_exposure` con SNOMED.
- **Alternativas:** mapear la gasa al Device de SNOMED con confianza alta (ii; descartada: el catálogo es de farmacia y su destino es `drug_exposure`, un Device ahí es un error de dominio); aceptar como «alta» cualquier candidato del ingrediente correcto (descartada: esconde pérdidas de especificidad).
- **Por qué:** un mapeo falsamente confiado contamina todo lo posterior; uno marcado como dudoso se puede usar con cuidado. Las reglas hacen que la confianza sea comprobable y no una impresión.
- **Caso FH-0113 (diclofenaco + complejo B):** no existe en RxNorm (no es por ser combinación: hay 19 formas con diclofenaco; falta esta, típica de México y Europa, cuyo lugar sería RxNorm Extension, no cargada). Se mapea como **dudosa** al Ingredient diclofenac (1124300), perdiendo B1/B6/B12, en vez de no mapeable: así el paciente no desaparece de un estudio de seguridad de AINE. Se descarta *betamethasone / diclofenac / vitamin B12* (añade un corticoide y le faltan B1 y B6). La solución completa en un ETL sería mapear a varios ingredientes, una fila por ingrediente.
