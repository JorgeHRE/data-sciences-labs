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
