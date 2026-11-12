# Actividad 5 — Leer tres códigos LOINC

Consultas: `actividades.sql`, actividades 5a (ejes), 5a-verificación, 5b (System en `measurement`) y 5c (paneles). En OMOP cada eje LOINC es un concepto aparte, unido al código por una relación «Has …» en `concept_relationship` (`Has component`, `Has property`, `Has time aspect`, `Has system`, `Has scale type`, `Has method`).

## Los seis ejes

| LOINC | Component | Property | Time | System | Scale | Method |
|---|---|---|---|---|---|---|
| **4548-4** | Hemoglobin A1c/Hemoglobin.total | Mass fraction | Point in time (spot) | **Blood** | Qn | (sin método) |
| **2160-0** | Creatinine | Mass Concentration | Point in time (spot) | **Serum or Plasma** | Qn | (sin método) |
| **2345-7** | Glucose | Mass Concentration | Point in time (spot) | **Serum or Plasma** | Qn | (sin método) |

Verificación: sin pivotar salen 15 filas, 5 ejes distintos por código, así que ningún eje está duplicado. El eje Method está vacío en los tres, pero no por un fallo de carga: la relación `Has method` existe en la base (143,014 filas). LOINC deja Method vacío cuando el código vale para cualquier método.

## Qué mide cada uno

**4548-4.** Mide qué **fracción de la hemoglobina total está glucosilada como HbA1c** (propiedad *Mass fraction*, se reporta en %), en **sangre total**, en una sola muestra puntual, como valor cuantitativo y **sin importar el método**. Por eso agrupa HPLC, inmunoensayo, etc.; el mismo análisis por HPLC tiene su propio código (17856-6).

**2160-0.** Mide la **concentración en masa de creatinina** (mg/dL) en **suero o plasma**, en una muestra puntual, como valor cuantitativo y sin método especificado. Si el resultado viene en µmol/L, en rigor corresponde a otro código (14682-9, *Moles/volume*), y si la muestra fue sangre total, a 38483-4.

**2345-7.** Mide la **concentración en masa de glucosa** (mg/dL) en **suero o plasma**, en una muestra puntual, como valor cuantitativo y sin método especificado. **No dice si el paciente estaba en ayunas**: LOINC describe qué se midió, no en qué condiciones estaba el paciente. El mismo analito en sangre total (2339-0) da valores ~11 % más bajos y en esta base convive con este el mismo día.

Los códigos hermanos citados (17856-6, 14682-9, 14749-6) existen en el vocabulario y tienen 0 mediciones en la base.

## Hallazgo: la base mezcla sangre total y suero/plasma

Para glucosa y creatinina hay dos códigos en uso que solo difieren en el eje System (consulta 5b):

| LOINC | System | Analito | Mediciones | Pacientes |
|---|---|---|---|---|
| 2339-0 | Blood | Glucosa | 69,106 | 2,748 |
| 2345-7 | Serum or Plasma | Glucosa | 49,484 | 1,395 |
| 38483-4 | Blood | Creatinina | 69,106 | 2,748 |
| 2160-0 | Serum or Plasma | Creatinina | 49,484 | 1,395 |

Sangre total es el 58 % de las mediciones. Quien arme «glucosa» solo con el código de libro (2345-7) pierde 69,106 mediciones y a la mitad de los pacientes.

**Vienen en paneles** (consulta 5c, agrupando por persona y fecha). En todos los persona-días, glucosa y creatinina del mismo System aparecen el mismo número de veces: Synthea genera paneles completos, uno en sangre y otro en suero/plasma. Los conteos idénticos por pares son una huella de datos sintéticos.

| Patrón del día | Persona-días |
|---|---|
| Solo panel en sangre | 44,078 |
| Solo panel en suero/plasma | 23,904 |
| **Ambos paneles el mismo día** | **24,827** |

En 24,827 persona-días el paciente tiene, el mismo día, una glucosa «en sangre» y otra «en suero». Si se juntan ambos códigos y se promedia por paciente, esos días cuentan doble; en datos reales los dos valores además diferirían. Hay también 933 persona-días con 2 o 3 paneles del mismo tipo (mediciones repetidas). Comprobación: la suma de mediciones en 5c es 237,180 = 2 × (69,106 + 49,484).

No es un error del análisis: es una propiedad de la base que cualquier concept set de glucosa o creatinina tiene que decidir explícitamente (incluir ambos System o no, y cómo deduplicar por día).
