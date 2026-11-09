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

- **Sin `Maps to` en la descarga.** Los 27 códigos de `conditions` y los 3 de `devices` existen en `concept`, no son estándar y no tienen `Maps to` ni `Concept replaced by`. Incluyen sobredosis de drogas (907 filas), dependencia de drogas (323), concusión (314) y metástasis (43). *Actualizado en la act. 9 (sección 8):* 5 son códigos SNOMED retirados y 2 de ellos tienen un equivalente estándar vía `Concept poss_eq to` (1,230 filas recuperables).
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
- **ATHENA** (actividad 9, sección 8): confirmado que los códigos de sobredosis están retirados también en el vocabulario oficial; que `D####` sean CDT sigue sin confirmar (ATHENA no los devuelve).
- **Clasificación por mapa.** Para decidir el destino de cada código se usó `source_to_standard_vocab_map`. En `immunizations` el mapa por sí solo no predecía la pérdida, que se detectó al cuadrar contra el CDM. La cuadratura contra el CDM es la medición de referencia.

## 5. Actividad 6: descripción de la población

Consultas en `consultas_omop.sql`, partes 6.1 a 6.4. Decisiones 23 y 24.

### Personas, sexo y nacimiento

- **5,904 personas** (5,000 vivas + 904 fallecidas en Synthea). El JOIN a `concept` no multiplica filas.
- **Sexo:** 2,967 hombres (50.3 %) y 2,937 mujeres (49.7 %). Sin `gender_concept_id = 0`.
- **Año de nacimiento:** de 1916 a 2026, sin NULLs. Por década: 1910s 81, 1920s 186, 1930s 122, 1940s 390, 1950s 543, 1960s 781, 1970s 774, 1980s 667, 1990s 630, 2000s 754, 2010s 610, 2020s 366. Las décadas anteriores a 1940 son pequeñas; la hipótesis es que se debe a la mortalidad que simula Synthea (los nacidos entonces sobreviven poco hasta la fecha de simulación), **sin verificar**.

### Tiempo de observación

`observation_period` tiene una fila por persona, del primer al último encuentro (`insert_observation_period.sql`): es el lapso con atención registrada, no la edad ni un periodo de afiliación.

| Mediana | p25 | p75 | Media | Con 0 días |
|---|---|---|---|---|
| 11,544.5 días (31.6 años) | 4,695 | 17,790.5 | 11,999 | 8 |

Los 8 periodos de 0 días son recién nacidos de 2026 con un solo encuentro.

### Top 20 de diagnósticos (personas distintas)

| # | Diagnóstico | Personas | % población | Registros |
|---|---|---|---|---|
| 1 | Gingivitis | 4,891 | 82.8 | 12,221 |
| 2 | Viral sinusitis | 3,744 | 63.4 | 5,993 |
| 3 | Dental caries | 3,297 | 55.8 | 4,721 |
| 4 | Limited social contact | 3,275 | 55.5 | 7,078 |
| 5 | Social isolation | 3,238 | 54.8 | 7,004 |
| 6 | Body mass index 30+ - obesity | 2,819 | 47.7 | 2,819 |
| 7 | Acute viral pharyngitis | 2,550 | 43.2 | 3,400 |
| 8 | Acute bronchitis | 2,251 | 38.1 | 2,798 |
| 9 | Prediabetes | 2,239 | 37.9 | 2,239 |
| 10 | Anemia | 2,156 | 36.5 | 2,156 |
| 11 | Essential hypertension | 2,145 | 36.3 | 2,145 |
| 12 | Tooth eruption disorder | 1,450 | 24.6 | 1,625 |
| 13 | Chronic pain | 1,446 | 24.5 | 1,446 |
| 14 | Risk activity involvement | 1,427 | 24.2 | 1,522 |
| 15 | Chronic sinusitis | 1,225 | 20.7 | 1,227 |
| 16 | Metabolic syndrome X | 1,121 | 19.0 | 1,121 |
| 17 | Abnormal findings diagnostic imaging heart+coronary circulat | 1,051 | 17.8 | 1,051 |
| 17 | Ischemic heart disease | 1,051 | 17.8 | 1,051 |
| 19 | Chronic low back pain | 1,024 | 17.3 | 1,024 |
| 20 | Normal pregnancy | 1,023 | 17.3 | 2,384 |

- **No todo es enfermedad.** 12 de los 20 son de clase `Disorder`; los otros 8 son `Clinical Finding`, entre ellos situaciones sociales (*Limited social contact*, *Social isolation*, *Risk activity involvement*) que el vocabulario asigna al dominio Condition, así que el ETL acierta al ponerlas aquí. Filtrar por `Disorder` no es una limpieza neutra: también quitaría *Chronic pain*, *obesity* y *Normal pregnancy*. Una cohorte debe definirse por conceptos (y sus descendientes), no por clase.
- **Empate en el puesto 17, no es multi-mapeo.** Los dos conceptos cardíacos vienen de códigos SNOMED de origen distintos (274531002 y 414545008); 1,042 personas tienen ambos, siempre en fechas diferentes, y 9 de cada lado tienen solo uno. Probablemente el módulo cardíaco de Synthea registra el hallazgo de imagen y luego el diagnóstico (**sin verificar**).
- **Sesgo hacia lo dental y lo respiratorio agudo:** refleja los módulos de Synthea, no una población real.

### Visitas por persona (denominador: las 5,904 personas)

| Tipo de visita | Visitas | Media | Mediana | Personas con 0 |
|---|---|---|---|---|
| Total | 385,971 | 65.4 | 37 | 0 |
| Outpatient Visit | 362,386 | 61.4 | 35 | 0 |
| Emergency Room Visit | 15,954 | 2.7 | 1 | 1,619 |
| Inpatient Visit | 7,631 | 1.3 | 1 | 2,904 |

- Sin visitas huérfanas ni personas sin visita. La suma por tipo cuadra con `visit_occurrence` (385,971).
- **Distribución sesgada a la derecha:** media 65.4 frente a mediana 37; pocas personas con muchísimas visitas suben la media. Para describir a la persona típica, la mediana.
- El 94 % de las visitas son ambulatorias; la mitad de la población (2,904) nunca fue hospitalizada.

## 6. Actividad 7: estándar contra origen

Consultas en `consultas_omop.sql`, partes 7a-7d. Decisión 25.

| Forma de contar *Dental caries* | Filas | Personas |
|---|---|---|
| Por concepto estándar `133228` | **4,721** | **3,297** |
| Por origen `80967001` (SNOMED) | 3,498 | 2,581 |
| Por origen `K02.9` (ICD-10-CM) | 1,223 | 799 |
| Estándar + descendientes (`concept_ancestor`) | 5,482 | 3,636 |

**No dan el mismo número.** Synthea registra la caries a veces en SNOMED y a veces en ICD-10; ambos códigos tienen `Maps to` hacia el mismo concepto estándar, que los reúne. Contar por un solo código de origen pierde el 26 % (solo SNOMED) o el 74 % (solo ICD-10) de los registros. La fuente cuadra fila a fila con el CDM para ambos códigos: no hay pérdida, solo agrupación.

- **Las filas se suman, las personas no:** 2,581 + 799 = 3,380 > 3,297, porque 83 personas tienen la caries registrada con ambos códigos.
- **El concepto estándar no incluye a sus hijos.** Los subtipos (por superficie y profundidad, *Arrested dental caries*…) se guardan con su propio ID. Para contar toda la caries hay que expandir con `concept_ancestor`: +761 registros y +339 personas (9 conceptos). Es el "include descendants" de un *concept set* de ATLAS.
- **Los otros dos mecanismos del enunciado, en este CDM:**
  - *Un origen → varios estándar:* 7 códigos ICD-10 con multi-mapeo (p. ej. `S02.5XXA`, 98 filas a 2 conceptos); la misma fila de origen cuenta en ambos.
  - *Códigos sin mapear al 0:* no ocurre. ETL-Synthea **descarta** esas filas en lugar de escribirlas con concepto 0 (sección 2): una condición sin mapeo, como la sobredosis de drogas (907 filas en origen), no aparece en `condition_occurrence` por ninguna de las dos vías.

## 7. Actividad 8: eventos dentro de `observation_period`

Consultas en `consultas_omop.sql`, partes 8a-8b. Decisión 26.

| Eventos de `condition_occurrence` | Filas |
|---|---|
| Sin filtrar | **101,699** |
| Dentro de la ventana de observación | **101,085** |
| Fuera (todos antes del inicio; 0 después del fin, 0 sin periodo) | 614 |
| **Diferencia** | **0.60 %** |

### Por qué quedan 614 fuera: zona horaria de Synthea

- **Patrón:** las 614 filas (522 personas) empiezan exactamente **1 día** antes del inicio del periodo, y todas pertenecen a la **primera visita** de la persona. Con 1 día de tolerancia entran las 101,699.
- **Causa, verificada en los CSV originales:** `encounters.csv` guarda fecha y hora en UTC (`2025-05-02T05:37:07Z`) y `conditions.csv` solo una fecha (`2025-05-01`). En la fuente hay 48,798 condiciones fechadas un día antes que su propio encuentro, y **todos** esos encuentros ocurren entre las 00 y las 05 h UTC; las que coinciden en fecha tienen horas de 0 a 23. La fecha de la condición está, por tanto, en hora local, aparentemente de EE. UU. (inferido por el rango horario, **sin confirmar** en la documentación de Synthea).
- **Por qué cruzan el inicio:** el ETL construye `observation_period` con `min(encounters.start)` (fecha UTC). Si la condición es de la primera visita y esa visita fue de madrugada en UTC, queda un día antes del periodo.
- **Alcance:** el desfase afecta a las 48,798 condiciones de la fuente (también desplaza su fecha frente a la visita), pero solo cruza la ventana en las 614 de la primera visita. Otras tablas que ETL-Synthea fecha desde columnas de solo fecha podrían tener el mismo efecto; **no se midió**.

### Qué significaría ignorar la ventana en un estudio real

Ignorarla cuenta eventos ocurridos cuando el paciente no estaba siendo observado: mezcla casos previos con incidentes y, en el denominador, suma tiempo en que nada podía registrarse; las tasas salen sesgadas (en este CDM, contar desde el nacimiento en vez de desde el periodo añade un 22 % de personas-año no observadas). Aquí la diferencia es solo del 0.60 % y es un artefacto, porque el periodo se construye con los mismos encuentros que generan los eventos; en datos de aseguradoras, donde la ventana es la afiliación, la brecha suele ser mucho mayor.

## 8. Actividad 9: los tres conceptos más usados, en ATHENA

Consulta local en `consultas_omop.sql`, parte 9; búsqueda en la web de ATHENA (athena.ohdsi.org). Decisiones 27-29.

| | Dental caries | Essential hypertension | Gingivitis |
|---|---|---|---|
| **`concept_id`** | 133228 | 320128 | 4281516 |
| **Vocabulario / dominio / estándar** | SNOMED / Condition / S | SNOMED / Condition / S | SNOMED / Condition / S |
| **Hijos en ATHENA** | 28 (27 SNOMED + 1 OMOP Extension) | 8 (SNOMED) | 37 (35 SNOMED + 1 OMOP Extension + 1 SNOMED Veterinary) |
| **Hijos en la base** | 27 | 8 | 35 |
| **Descendientes en la base** | 101 | 13 | 76 |
| **Código de origen que mapea a él** | ICD10CM `K02.9` (`35208124`) | ICD10CM `I10` (`35207668`) | SNOMED `196355002` (`40397494`), inactivo |
| **Vocabularios con `Mapped from` en ATHENA** | ICD10CM, SNOMED y otros | ICD10CM, ICD10, ICD9CM, Read, Nebraska Lexicon, KCD7, CIEL… | SNOMED, Read, Nebraska Lexicon, CIEL, MeSH, OXMIS, HPO; **ningún ICD-10** |

### Lo que muestra la comparación

- **Todo lo que hay en la base coincide con ATHENA:** atributos, hijos SNOMED y los tres mapeos ICD10CM de control. La base es completa **dentro de los vocabularios descargados**.
- **Las diferencias son vocabularios no descargados:** hijos de OMOP Extension y SNOMED Veterinary (0 conceptos en la base) y la mayoría de los códigos de origen (Read, ICD9CM, CIEL…). No afecta a los conteos de este lab, porque Synthea solo usa SNOMED e ICD-10, pero datos codificados en ICD9CM se descartarían enteros.
- **La gingivitis genérica no tiene traducción ICD-10**, ni aquí ni en ATHENA: los códigos ICD-10 de gingivitis (`K05.00`, `K05.01`) van al hijo *Acute gingivitis*.
- **Nomenclatura:** la web muestra el nombre de la relación, no su id: `Mapped from` = "Standard to Non-standard map (OMOP)" y `Maps to` = "Non-standard to Standard map (OMOP)". *Hierarchy* muestra solo hijos estándar; `Subsumes` incluye los no estándar (44 frente a 37 en gingivitis).

### Pendientes de la act. 5 resueltos

Los 27 códigos de `conditions` sin destino (4,465 filas) no son un caso único:

| Tipo | Códigos | Filas | Ejemplos |
|---|---|---|---|
| SNOMED **retirado** | 4 | 1,771 | Drug overdose (retirado 2021), Dependent drug abuse (2024), Concussion (2026) |
| SNOMED actualizado | 1 | 271 | Served in armed forces |
| SNOMED válido, no estándar, sin `Maps to` | 15 | 2,393 | *History of…* (antecedentes), Refugee, Smokes tobacco daily |
| ICD10CM válido sin `Maps to` | 7 | 30 | Metástasis |

- **Synthea v3.3.0 genera códigos que SNOMED ya retiró.** En ATHENA, *Drug overdose* figura como **Deprecated** (verificado por URL directa; los conceptos retirados no salen en la búsqueda).
- **1,230 filas serían recuperables:** sobredosis y dependencia tienen un equivalente estándar vía `Concept poss_eq to` (*Overdose* `607147`, *Substance dependence* `37165431`), pero ETL-Synthea solo sigue `Maps to`. Un ETL de producción lo resolvería con `source_to_concept_map`. Solo se documenta (decisión 18).
- **`D7140`, `D0120`:** ATHENA no los devuelve y la base no tiene vocabulario CDT: consistente con códigos dentales CDT de licencia restringida, **no confirmado**.
