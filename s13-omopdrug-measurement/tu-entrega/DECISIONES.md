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

## 3. Cómo pasar de producto a ingrediente (actividad 2)
- **Decisión:** subir de producto a ingrediente con `concept_ancestor` (ancestro de clase *Ingredient*, estándar) y contar `count(DISTINCT person_id)`.
- **Alternativa:** `drug_strength` (descartada: cubre 335 de los 346 productos recetados; su ventaja, la dosis por ingrediente, no se usa aquí).
- **Por qué:** cubre el 100 % y es la misma vía de `drug_era` y de las actividades 3-4. Los 55 productos multi-ingrediente convierten 388,700 recetas en 448,889 pares receta-ingrediente: es correcto para contar pacientes por ingrediente, pero nunca se deben sumar recetas después de ese JOIN.

## 4. Cómo presentar `days_supply` (actividad 2)
- **Decisión:** distribución cruda + tabla de banderas excluyentes (negativos, ceros, pila en 371, >365); no se limpia en la actividad 2.
- **Alternativas:** mostrarla ya limpia (descartada: esconde los problemas en el paso de diagnóstico) o imputar ceros y negativos (descartada: inventa datos sobre una columna que ni siquiera es original, pues es fin − inicio en el 100 % de las filas).
- **Por qué:** primero se diagnostica y después se limpia, en la actividad donde cada regla cambia un resultado medible (eras y PDC, actividades 4-5).

## 5. Ingrediente de estudio (actividades 3-5)
- **Decisión:** lisinopril (`1308216`): 1,522 pacientes, 27.7 recetas por paciente, 9 productos en los datos (6 dosis de comprimido simple y 3 combinaciones con hidroclorotiazida que suman 15 pacientes).
- **Alternativas:** amlodipino (descartado: el 99.7 % de sus recetas es un solo producto, la jerarquía casi no se ve), hidroclorotiazida (descartada: muchas combinaciones que en la act. 4 generan solapes entre productos) y acetaminofén (descartado: uso agudo a demanda, el PDC no tiene sentido clínico).
- **Por qué:** es frecuente, crónico y tiene una jerarquía variada sin exceso de combinaciones; sirve igual para la búsqueda por ingrediente, las eras y el PDC, y `cdm.drug_era` trae su referencia (1,541 eras).

## 6. Reglas para construir `drug_era` a mano (actividad 4)
- **Decisión:** replicar las reglas OHDSI «non-stockpile» que usó ETL-Synthea (`insert_drug_era.sql`): fin = `end_date` (inicio + `days_supply` o inicio + 1 solo si fuera NULL), excluir `days_supply` negativos y concepto 0, fusionar solapes sin desplazarlos, ventana de persistencia de 30 días. Las exposiciones preparadas quedan en `results.lisinopril_exposicion`.
- **Alternativas:** reglas «clínicas» propias (0 días → 1 día, invertir negativos, desplazar solapes) o ambas como análisis de sensibilidad (descartadas: con reglas distintas no se puede saber si una diferencia con `cdm.drug_era` viene de la regla o de un error; y el impacto sería mínimo: 548 solapes y 6 huecos cortos en 42,085 recetas).
- **Por qué:** la actividad es validar contra la tabla derivada, y eso solo tiene sentido con las mismas reglas. El caso de los tratamientos en curso (STOP vacío en Synthea → fin = inicio por el ETL; 1,585 recetas de lisinopril, marcadas en `en_curso`) se decide en la actividad 5, donde sí cambia el resultado.

## 7. Diseño del PDC (actividad 5)
- **Decisión:** (1) índice = primera receta de lisinopril y ventana de 365 días [índice, índice + 364] (diseño de usuario nuevo); (2) se excluyen los pacientes con menos de 365 días de `observation_period` tras el índice; (3) las recetas «en curso» (`verbatim_end_date IS NULL`) se extienden hasta el fin de su `observation_period` como resultado principal, y se reporta como sensibilidad el PDC con las reglas del ETL (0 días); (4) no se desplazan los solapes (cada día cubierto cuenta una vez).
- **Alternativas:** año calendario fijo (descartada: mezcla usuarios nuevos y prevalentes); denominador acortado al seguimiento disponible (descartada: PDC sobre 30 días no es comparable con uno sobre 365); dejar las recetas en curso en 0 días (queda como sensibilidad: produce 65 pacientes con PDC = 0 que siguen en tratamiento) o excluirlos (descartada: sesga la cohorte); *stockpiling* (descartada: incoherente con las eras OHDSI y sin efecto medible aquí).
- **Por qué:** es el diseño estándar en farmacoepidemiología, el denominador es igual para todos y el supuesto sobre los tratamientos en curso respeta el dato de origen (Synthea los marca activos). El contraste principal/sensibilidad muestra cuánto puede mover un supuesto del ETL una métrica clínica.

## 8. Analito para la distribución de unidades (actividad 6)
- **Decisión:** globulina (3027970): 20,412 filas en g/L y 16 en g/dL. También será el analito que se normalice en la actividad 7.
- **Alternativas:** temperatura (Cel 6,346 / [degF] 3; descartada: conversión de manual que solo afecta a 3 filas); troponina (pg/mL 3,078 / ng/L 219; descartada: unidades equivalentes 1:1, conversión trivial); GFR (unit 0 en 59,485 filas con texto «mL/min/{1.73_m2}» frente a mL/min 26,125; descartada: es un problema de mapeo, no de conversión).
- **Por qué:** es la única opción con un problema de calidad real. Los valores «en g/L» (2.0-3.5) son g/dL mal etiquetados en origen (Synthea), y una conversión que se fíe de la etiqueta empeoraría los datos. Obliga a decidir la unidad por el rango del valor y a documentar la regla.
