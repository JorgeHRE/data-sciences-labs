# Registro de decisiones — Lab 14 (Vocabularios estándar: construir y defender un concept set)

Formato: qué se decidió, qué alternativas había y por qué se eligió esta.

## 1. Motor y base de datos
- **Decisión:** trabajar sobre el Postgres del lab 12 (`lab12-omop`, puerto 5433, BD `omop_lab12`, esquema `cdm`), con el vocabulario de ATHENA ya cargado. El esquema `cdm` se usa solo para leer.
- **Alternativas:** DuckDB, como sugiere el enunciado (descartada: habría que copiar `concept_relationship`, con 14 M de filas, y `concept_ancestor`, con 12 M, y volver a comprobar la copia) o descargar otro vocabulario de ATHENA (descartada: el cargado está completo, ver el control del paso 0).
- **Por qué:** es la misma base validada en los labs 12 y 13; los concept sets que salgan de aquí se reutilizan en la sesión 17 sobre esa misma base.

## 2. Condición del concept set (actividad 1)
- **Decisión:** diabetes mellitus tipo 2 (SNOMED `201826`): 444 pacientes distintos (444 filas), muy por encima del mínimo de ~50.
- **Alternativas:** hipertensión (descartada: con la semilla esencial A y B salen iguales, solo hay 13 descendientes y 1 concepto en los datos) y cardiopatía isquémica (descartada: mezcla cuadros agudos y crónicos, lo que obliga a otra pregunta).
- **Por qué:** es la candidata que más pone a prueba el método: 117 códigos ICD-10-CM `E11.x`, casi todos con mapeo 1:N; descendientes discutibles (gestacional, en remisión); y las complicaciones «due to type 2 diabetes» en una rama hermana del concepto, con 641 pacientes que no tienen el código `201826`.

## 3. Pregunta de investigación (actividad 1)
- **Decisión:** estudiar la utilización de la metformina en pacientes con T2DM (inicio y persistencia). Esa cohorte se construye en la sesión 17.
- **Alternativas:** estimar la prevalencia de T2DM (descartada: obliga a maximizar a la vez la sensibilidad y el VPP, y no lleva a ninguna cohorte de tratamiento) o tomar las complicaciones como desenlace (descartada aquí: sacaría las complicaciones de la definición; queda como posible análisis aparte).
- **Por qué:** es la pregunta típica de un estudio de utilización de fármacos con datos reales en la industria y enlaza con las eras y el PDC del lab 13. Define qué error pesa más: los falsos positivos (VPP), porque pacientes sin T2DM diluyen cualquier medida de tratamiento. Limitación: solo 231 pacientes con metformina en la base.

## 4. Semilla y rama de complicaciones (actividad 2)
- **Decisión:** la semilla es `201826` Type 2 diabetes mellitus. Las versiones A y B se construyen solo desde ella. La rama hermana `443732` «Disorder due to type 2 diabetes mellitus», con sus 118 descendientes, entra en la versión C como inclusión razonada.
- **Alternativas:** solo `201826` en todas las versiones (descartada: pierde 641 pacientes que solo tienen una complicación codificada, el 59 % de los 1,085 posibles) o una doble semilla desde la versión A (descartada: A deja de ser un solo concepto y la comparación A/B ya no mide solo el efecto de la jerarquía).
- **Por qué:** una complicación «due to type 2 diabetes» implica que el paciente tiene T2DM. Incluirla sube la sensibilidad casi sin coste en VPP, que es el error prioritario para la pregunta de la metformina. Los 119 conceptos de la rama mencionan «type 2» en el nombre. Mantener A y B limpias permite mostrar que la jerarquía de SNOMED no coincide siempre con la definición clínica.
