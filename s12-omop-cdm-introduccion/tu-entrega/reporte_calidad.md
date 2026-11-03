# Reporte de calidad — OMOP CDM v5.4 sobre Synthea (lab 12)

Base: `omop_lab12`, esquema `cdm` (Postgres 16, ETL-Synthea v2.1.1, Synthea v3.3.0, 5,904 personas).
Consultas: `consultas_omop.sql` (partes 1-10). Decisiones y su porqué: `DECISIONES.md` (15-22).

> Este archivo se amplía en las actividades siguientes. Hoy contiene la **actividad 5**.

## 1. Actividad 5: porcentaje de `concept_id = 0` por dominio

Denominador: todas las filas de la tabla. «Estándar» es el concepto principal del dominio; «origen» es su `*_source_concept_id`. No hay NULLs en ninguna de estas columnas (verificado), así que los ceros contados son todos los que hay.

| Dominio (tabla) | Filas | % cero, estándar | % cero, origen |
|---|---:|---:|---:|
| `person` (género / etnia) | 5,904 | 0 % / 0 % | — |
| `person` (raza) | 5,904 | **2.79 %** (165) | — |
| `visit_occurrence` | 385,971 | 0 % | 100 % (esperado) |
| `condition_occurrence` | 101,699 | 0 % | 0 % |
| `drug_exposure` | 467,590 | 0 % | 0 % |
| `procedure_occurrence` | 454,821 | 0 % | 0 % |
| `measurement` | 4,008,280 | 0 % | 0 % |
| `observation` | 1,929,625 | 0 % | 0 % |
| `device_exposure` | 9,255 | 0 % | 0 % |

Lectura de los dos únicos valores distintos de cero:

- **Raza, 165 personas.** El ETL tiene la raza escrita a mano en `insert_person.sql`: solo `white`, `black` y `asian` tienen concepto. `other` (69), `hawaiian` (58) y `native` (38) van a 0. Para `hawaiian` y `native` existían los conceptos estándar 8557 y 8657, presentes en la descarga de ATHENA; para `other` no hay categoría estándar equivalente.
- **`visit_source_concept_id`, 100 %.** ETL-Synthea no llena esta columna opcional. No es un fallo de mapeo.

## 2. Diagnóstico: ¿está completo el ETL?

**No, aunque la tabla de ceros diga 0 %.** ETL-Synthea **descarta** las filas que no puede mapear en lugar de escribirlas con `concept_id = 0`. Un 0 % de ceros solo describe lo que se escribió. La completitud se midió cuadrando cada tabla de origen (`native.*`) contra el CDM.

| Origen | Filas | Perdidas | % perdido |
|---|---:|---:|---:|
| `procedures` | 869,518 | 168,099 | **19.3 %** |
| `allergies` | 5,262 | 658 | 12.5 % |
| `immunizations` | 86,068 | 7,178 | 8.3 % |
| `devices` | 9,973 | 718 | 7.2 % |
| `observations` | 5,719,327 | 161,825 | 2.8 % |
| `conditions` | 235,504 | 4,712 | 2.0 % |
| `medications` | 388,658 | 0 | 0 % |
| **Total medido** | **7,314,310** | **343,190** | **4.7 %** |

Cada cifra cuadra con el CDM: filas escritas (más las duplicadas por multi-mapeo) = filas de origen − perdidas. Control de ejemplo: `conditions` 101,591 + 108 (multi-mapeo) = 101,699 en `condition_occurrence`, y 129,201 en `observation`.

**Dominio peor mapeado: `procedures`** (19.3 % y el 49 % de todas las filas perdidas). Le sigue `allergies` en porcentaje, pero con solo 658 filas.

### Causas

| Causa | Dónde | Filas | Verificada en |
|---|---|---:|---|
| **A. El ETL no tiene INSERT para ese destino** | `procedures` → Observation (100,892), Drug (1,507), Device (497), Condition (118); `allergies` → Drug (174); `observations` → Note (194), Procedure (104); `conditions` ICD10/SNOMED → Observation, Procedure, Measurement (247) | 103,733 | código del ETL |
| **B. El vocabulario no ofrece destino estándar** | `conditions` (4,465), `procedures` (65,085), `observations` (161,527), `devices` (718), `allergies` (484) | 232,279 | tabla `concept` y `concept_relationship` |
| **C. El JOIN del ETL exige un vocabulario concreto** | `immunizations`: vacunas COVID-19 (CVX 207, 208, 212) | 7,178 | código del ETL (`insert_drug_exposure.sql`, línea 127) |
| **D. Dato codificado a mano** | `person.race_concept_id` | 165 personas | código del ETL (`insert_person.sql`) |

Dentro de B hay dos subcausas:

- **Sin `Maps to` en la descarga.** Los 27 códigos de `conditions` y los 3 de `devices` existen en `concept`, no son estándar y no tienen `Maps to`, `Concept replaced by` ni reemplazo equivalente. Incluyen sobredosis de drogas (907 filas), dependencia de drogas (323), concusión (314) y metástasis (43).
- **Vocabulario ausente.** 442 códigos de `procedures` con forma `D0120`, `D7140`… (63,383 filas) no existen en `concept`, y la base no tiene ningún vocabulario CDT. Por su descripción parecen códigos dentales CDT; **esto es inferido, no confirmado**.

### Ruido frente a pérdida clínica

159,864 de las 161,825 filas perdidas en `observations` son QOLS, QALY y DALY (53,288 de cada una): métricas de calidad de vida que genera Synthea y que no son códigos LOINC. Descontadas del numerador y del denominador, la pérdida clínica medida baja a 183,326 filas de 7,154,446 (**2.6 %**). Es un cálculo derivado de las cifras de arriba.

### Consecuencias para cohortes

- Una cohorte de **vacunación COVID-19** saldría vacía (7,178 dosis ausentes).
- **Sobredosis, abuso de sustancias, concusión y metástasis** no son recuperables desde `condition_occurrence`.
- La **atención dental** casi no existe en el CDM: 40,870 derivaciones van al dominio Observation, que el ETL no escribe para procedimientos, y 63,383 filas son códigos CDT.
- Un análisis **estratificado por raza** no vería a los pacientes nativo-hawaianos ni indígenas americanos (96 personas con concepto disponible).

Ninguno de estos huecos aparece en la tabla de ceros.

## 3. Decisión sobre qué hacer con los hallazgos

Solo se documentan; **no se corrige el ETL ni se vuelve a correr** (~43 min, y ETL-Synthea no es determinista). Ver `DECISIONES.md` 18.

## 4. Límites de este reporte

- **Cuadratura aritmética, no fila a fila.** Los conteos coinciden; no se comparó la identidad de cada fila. Donde fue posible, se usó un control que podía fallar (códigos sin solapes entre fuentes, `*_source_value` contra los códigos de origen).
- **Cobertura.** `careplans` (20,770), `imaging_studies` (658,769) y `supplies` (58,104) no se miden: ningún INSERT del ETL las lee, y `claims` solo alimenta `cost`, que está vacía (decisión 9).
- **Sin confirmar en ATHENA** (actividad 9): si los `Maps to` ausentes faltan solo en esta descarga o también en el vocabulario oficial, y si los códigos `D####` son CDT.
- **Clasificación por mapa.** Para decidir el destino de cada código se usó `source_to_standard_vocab_map`. En `immunizations` el mapa por sí solo no predecía la pérdida, que se detectó al cuadrar contra el CDM. La cuadratura contra el CDM es la medición de referencia.
