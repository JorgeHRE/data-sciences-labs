# Justificación del concept set — Diabetes mellitus tipo 2

## 1. Condición y pregunta de investigación

**Condición:** diabetes mellitus tipo 2 (T2DM) en adultos: hiperglucemia crónica por resistencia a la insulina con déficit relativo de su secreción. No incluye la diabetes tipo 1, la gestacional ni la secundaria a otras enfermedades.

**Por qué importa y qué pregunta responde:** la T2DM es una de las enfermedades crónicas con más tratamientos farmacológicos y más estudios con datos de vida real en la industria farmacéutica. Usaría la cohorte para describir **cómo se usa la metformina** (primera línea de tratamiento) en pacientes con T2DM: cuántos la inician, cuándo y cuánto tiempo la mantienen. Para esta pregunta importa sobre todo que los pacientes de la cohorte tengan T2DM de verdad (valor predictivo positivo).

**Pacientes en la base:** 444 pacientes distintos con el concepto `201826` (444 filas: Synthea registra la condición crónica una sola vez), muy por encima del mínimo de ~50. No hizo falta cambiar de condición.

## 2. Concepto semilla

Transcripción de la tabla `concept` (vocabulario OHDSI v5.0 29-AUG-26, el mismo que publica ATHENA):

| concept_id | concept_name | domain_id | vocabulary_id | concept_class_id | standard_concept | invalid_reason | vigencia |
|---|---|---|---|---|---|---|---|
| 201826 | Type 2 diabetes mellitus | Condition | SNOMED | Disorder | S | (vacío) | 2002-01-31 a 2099-12-31 |

Es estándar, su dominio es Condition (sus pacientes están en `condition_occurrence`) y está vigente. Código SNOMED CT: 44054006.

- **Padre inmediato:** `201820` Diabetes mellitus (un solo padre).
- **Descendientes:** 14 (12 hijos directos y 2 nietos). Ninguno aparece en los datos de la base.

**Conceptos descartados en la búsqueda:** `1567956` (ICD10CM E11) y `35206882` (ICD10CM E11.9) no son estándar; `506756` Maternal history of T2DM es de dominio Observation y está reemplazado (`U`).

**Rama hermana de complicaciones:** las complicaciones («Microalbuminuria due to type 2 diabetes mellitus», retinopatía, neuropatía…) no son descendientes de `201826`, sino de su hermano `443732` «Disorder due to type 2 diabetes mellitus» (estándar, Condition, vigente, 118 descendientes). Hay 641 pacientes con alguna complicación y sin el código `201826`. La semilla sigue siendo `201826`; la rama `443732` entra en la versión C como inclusión razonada (ver sección de decisiones).

## 3. Traducción de ICD-10-CM a conceptos estándar

16 códigos de ICD-10-CM FY2027 (CDC/CMS), traducidos con `'Maps to'` y los cuatro filtros: dirección fuente → estándar, destino estándar, destino vigente y relación vigente. En esta base las 1,254,595 relaciones `'Maps to'` están vigentes, así que el cuarto filtro no quita ninguna; se aplica igual para que la consulta sirva con cualquier vocabulario.

| codigo_icd10 | concept_id_origen | concept_id_estandar | nombre_estandar | dónde cae |
|---|---|---|---|---|
| E11.9 | 35206882 | 201826 | Type 2 diabetes mellitus | semilla |
| E11.65 | 45605405 | 201826 · 37016349 | T2DM · Hyperglycemia due to T2DM | semilla · rama |
| E11.21 | 45591027 | 201826 · 443731 | T2DM · Renal disorder due to T2DM | semilla · rama |
| E11.22 | 45595797 | 201826 · 43531578 | T2DM · Chronic kidney disease due to T2DM | semilla · rama |
| E11.319 | 45581353 | 201826 · 443733 | T2DM · Disorder of eye due to T2DM | semilla · rama |
| E11.42 | 45557113 | 201826 · 37017432 | T2DM · Polyneuropathy due to T2DM | semilla · rama |
| E11.51 | 45533021 | 201826 · 443729 | T2DM · Peripheral circulatory disorder due to T2DM | semilla · rama |
| E11.621 | 45581355 | 201826 · 43530690 | T2DM · Foot ulcer due to T2DM | semilla · rama |
| E11.649 | 45591031 | 201826 · 45757363 | T2DM · Hypoglycemia due to T2DM | semilla · rama |
| E11.8 | 35206881 | 201826 · 442793 | T2DM · Complication due to diabetes mellitus | semilla · fuera |
| E11.A | 1348414 | 45766052 | Type 2 diabetes mellitus in remission | semilla |
| E11.640 | 35206880 | — | (código retirado, sin mapeo) | — |
| O24.111 | 45587292 | 43531010 · 4239938 | Pre-existing T2DM in pregnancy · First trimester pregnancy | semilla · fuera |
| E13.9 | 35206885 | 201820 | Diabetes mellitus | fuera |
| R73.03 | 37201113 | 37018196 | Prediabetes | fuera |
| Z79.84 | 37202300 | 46272450 | Long-term current use of drug therapy (Observation) | fuera |

**Conteo:** de los 16 códigos, **10 mapean a más de un concepto estándar** y **1 no mapea a ninguno** (E11.640, retirado; su sustituto es E11.649). Los 16 códigos dan 25 destinos, que son 16 conceptos estándar distintos: 3 bajo la semilla, 8 en la rama de complicaciones y 5 fuera. En la categoría E11 completa, 113 de 118 códigos son 1:N y generan 233 filas: un JOIN que asumiera 1:1 casi duplicaría cualquier conteo por filas.

**Qué dice el contraste:**
- Todas las complicaciones caen en la rama `443732`, ninguna bajo la semilla: la decisión de incluir esa rama en la versión C tiene respaldo en cómo se codifica en la práctica.
- Dos destinos «bajo la semilla» son candidatos a exclusión en la actividad 6: `43531010` (embarazo) y `45766052` (en remisión). Ojo: E11.A mapea solo a «in remission», no a T2DM.
- Los 5 destinos «fuera» no son T2DM y no deben entrar: «Diabetes mellitus» y «Complication due to diabetes mellitus» son más generales (incluyen la tipo 1), «First trimester pregnancy» describe el embarazo, «Prediabetes» es otra entidad y «Long-term current use of drug therapy» es una observación sobre el tratamiento.
