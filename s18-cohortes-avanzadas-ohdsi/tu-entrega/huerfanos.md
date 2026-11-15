# Conceptos huérfanos: cifras

Generado por `tabla_huerfanos.py` (no editar a mano).

## Búsqueda por texto en CONCEPT

| concept set | nivel | coinciden con registros | están en el set | huérfanos |
|---|---|---:|---:|---:|
| amlodipino | estricto | 6 | 6 | 0 |
| demencia | estricto | 2 | 2 | 0 |
| demencia | ampliado | 2 | 2 | 0 |
| hipertensión | estricto | 1 | 1 | 0 |
| hipertensión | ampliado | 6 | 2 | 4 |
| lisinopril | estricto | 9 | 9 | 0 |

## Huérfanos encontrados (nivel ampliado de hipertensión)

| concept_id | concepto | personas |
|---:|---|---:|
| 45769905 | Microalbuminuria due to type 2 diabetes mellitus | 792 |
| 45757499 | Proteinuria due to type 2 diabetes mellitus | 613 |
| 137613 | Eclampsia in pregnancy | 120 |
| 4065875 | Blood pressure within reference range | 3 |

**Sin mapear y códigos fuente:** condiciones sin mapear 0, recetas sin mapear 0, valores fuente de condición fuera del set 0, valores fuente de receta fuera del set 0.

## Presión arterial elevada sin diagnóstico de hipertensión

En toda la base, 2,078 personas tienen presión elevada (sistólica ≥ 140 o diastólica ≥ 90) en ≥ 2 fechas: 1,163 con diagnóstico de hipertensión y **915 sin él**.

En la cohorte 1701, de las 22 personas que fallan **solo** el criterio de hipertensión:

| umbral (sistólica/diastólica) | con ≥ 1 fecha elevada | con ≥ 2 fechas | con ≥ 3 fechas |
|---|---:|---:|---:|
| 130/80 | 8 | 7 | 7 |
| 140/90 | 4 | 3 | 2 |
| 160/100 | 1 | 0 | 0 |

## Pre-eclampsia dentro del criterio de hipertensión

En la base: 85 personas con el código, 2,207 con algún código del set y **62** que cumplirían el criterio solo por él.

| cohorte | primeras recetas | cumplen hipertensión | solo por pre-eclampsia | …con índice desde 2017 | …en la cohorte final |
|---|---:|---:|---:|---:|---:|
| 1701 | 1,522 | 1,447 | 0 | 0 | 0 |
| 1702 | 1,104 | 1,102 | 0 | 0 | 0 |

**Eclampsia (137613, fuera del set):** de quienes fallan solo el criterio de hipertensión, 0 tienen ese código hasta el índice.


## Otros inhibidores de la ECA en la base

| ingrediente | personas con receta |
|---|---:|
| lisinopril | 1,522 |
| ramipril | 14 |
| enalapril | 13 |
| benazepril | 9 |
| quinapril | 2 |
