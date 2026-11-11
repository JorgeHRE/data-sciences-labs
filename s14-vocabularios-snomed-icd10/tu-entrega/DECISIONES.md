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

## 5. Traducción de ICD-10-CM (actividad 3)
- **Decisión (códigos):** una lista razonada de 16 códigos de ICD-10-CM FY2027: 11 de la categoría E11, uno por tipo de complicación, y 5 de borde (E11.640 retirado, O24.111 embarazo, E13.9 otra diabetes, R73.03 prediabetes, Z79.84 uso crónico de hipoglucemiantes). Se acompaña de un resumen de toda la categoría E11 (118 códigos).
- **Decisión (1:N):** la traducción **audita** el concept set, no lo construye. Cada destino estándar se clasifica según dónde cae: bajo la semilla 201826, en la rama 443732 o fuera de ambas.
- **Alternativas:** todos los E11 por patrón (descartada como tabla: 233 filas ilegibles; se queda como resumen) o 10 códigos típicos (descartada: todos se comportan igual); para el 1:N, solo informar (descartada: no aprovecha nada) o construir el concept set con la unión de los destinos (descartada: mete «First trimester pregnancy», «Diabetes mellitus» y «Complication due to diabetes mellitus», lo que baja el VPP).
- **Por qué:** los códigos de borde ponen a prueba los cuatro filtros y el LEFT JOIN. El contraste confirma la decisión 4 con datos: los 8 destinos de complicación caen en la rama 443732 y ninguno bajo la semilla.

## 6. Cómo guardar las tres versiones (actividad 4)
- **Decisión:** una vista `results.cs_t2dm` en formato largo (`version`, `concept_id`), calculada desde `concept_ancestor`, y una tabla `results.cs_t2dm_exclusiones` (`concept_id` clave primaria, `motivo` obligatorio) que se llena en la actividad 6. Cada exclusión arrastra a sus descendientes.
- **Alternativas:** solo consultas SELECT sin guardar nada (descartada: las actividades 5-6 y la sesión 17 tendrían que copiar la lógica) o una tabla con el resultado (descartada: queda desfasada sin avisar si cambian las exclusiones o el vocabulario; sirve cuando se congela un protocolo).
- **Por qué:** la lógica se escribe una sola vez y siempre está al día. Las exclusiones quedan como datos con su motivo, igual que en ATLAS («incluir descendientes» / «excluir»). El formato largo permite contar las tres versiones con un solo `GROUP BY`. Resultado sin exclusiones: A 1, B 15, C 134. Prueba con ROLLBACK: excluir 443732 deja C en 15.
