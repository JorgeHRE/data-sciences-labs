# Reporte de calidad — Lab 13 (Drug Exposure y Measurement)

Base: OMOP CDM del lab 12 (Synthea, 5,000 pacientes, ETL-Synthea), Postgres `omop_lab12`, esquema `cdm`. Consultas en `farmacoepi.sql`.

## 1. Tipo de exposición

| `drug_type_concept_id` | Tipo | Vocabulario del fármaco | Filas | Personas | % filas |
|---|---|---|---|---|---|
| 32838 | EHR prescription | RxNorm | 388,700 | 5,638 | 83.1 |
| 32827 | EHR encounter record | CVX (vacunas) | 78,890 | 5,896 | 16.9 |

Controles: 467,590 filas antes y después de los JOIN con `concept`; 0 filas con tipo NULL o 0.

**Diagnóstico:** los datos de medicamentos son **prescripciones** (la orden en la historia clínica). No hay dispensaciones ni administraciones de medicamentos; las vacunas registradas en la visita son lo más parecido a una administración. Por eso, «paciente expuesto» significa aquí «paciente al que se le recetó»: no sabemos si surtió la receta ni si tomó el fármaco, lo que **sobreestima la exposición real**, y cualquier adherencia (PDC, actividad 5) mide cobertura de recetas, no toma efectiva.

**Decisión derivada:** las métricas de fármacos (actividades 2-5) usan solo prescripciones; las vacunas se excluyen explícitamente (ver `DECISIONES.md`, decisión 2).

## 2. Caracterización de `drug_exposure` (solo prescripciones)

### 2a. Top 20 de ingredientes por pacientes distintos

Producto → ingrediente con `concept_ancestor` (decisión 3). Control del JOIN: 388,700 recetas → 448,889 pares receta-ingrediente (55 productos multi-ingrediente) → 388,700 recetas con ingrediente (ninguna se pierde).

| # | Ingrediente (concept_id) | Pacientes | Recetas |
|---|---|---|---|
| 1 | acetaminophen (1125315) | 3,675 | 21,958 |
| 2 | amoxicillin (1713332) | 1,659 | 1,992 |
| 3 | lisinopril (1308216) | 1,522 | 42,085 |
| 4 | ibuprofen (1177480) | 1,517 | 6,537 |
| 5 | naproxen (1115008) | 1,282 | 1,391 |
| 6 | simvastatin (1539403) | 1,270 | 6,772 |
| 7 | hydrochlorothiazide (974166) | 1,234 | 36,046 |
| 8 | clavulanate (1759842) | 1,231 | 1,378 |
| 9 | amlodipine (1332418) | 1,104 | 34,475 |
| 10 | nitroglycerin (1361711) | 1,077 | 1,135 |
| 11 | metoprolol (1307046) | 1,044 | 1,128 |
| 12 | ethinyl estradiol (1549786) | 1,026 | 2,207 |
| 13 | inert ingredients (19127890) | 906 | 1,787 |
| 14 | levonorgestrel (1589505) | 889 | 1,471 |
| 15 | clopidogrel (1322184) | 854 | 870 |
| 16 | penicillin V (1729720) | 755 | 822 |
| 17 | hydrocodone (1174888) | 710 | 7,283 |
| 18 | norethindrone (1521369) | 697 | 1,473 |
| 19 | dextromethorphan (1119510) | 680 | 723 |
| 20 | doxylamine (738818) | 680 | 723 |

Notas: «inert ingredients» no es un fármaco (son los placebos de los paquetes de anticonceptivos; artefacto de la jerarquía). Clavulanato, y dextrometorfano/doxilamina, aparecen por productos combinados: un producto suma un paciente a cada ingrediente. Las recetas por paciente separan crónicos (lisinopril 27.7) de agudos (amoxicilina 1.2).

### 2b. Distribución de `days_supply`

Sin NULL. Mínimo −6, p25 0, mediana 7, p75 56, p95 371, máximo 22,576 días. `days_supply` = fin − inicio en el 100 % de las filas: **lo derivó el ETL de las fechas**, no es un dato de farmacia independiente.

| Bandera | Recetas | % |
|---|---|---|
| Negativo (fin antes que inicio; imposible) | 479 | 0.1 |
| Cero (fin = inicio) | 137,360 | 35.3 |
| 1-365 días (plausible) | 205,860 | 53.0 |
| Exactamente 371 días | 41,980 | 10.8 |
| Más de 365 días (sin contar 371) | 3,021 | 0.8 |

La pila en 371 no parece un centinela: 68 productos, unas 3,900 recetas por año, encabezada por crónicos (lisinopril, hidroclorotiazida, amlodipino). Hipótesis: Synthea renueva la receta crónica en la visita anual y el ETL toma la siguiente visita como fecha de fin. Se pondrá a prueba en la actividad 4.

### 2c. Completitud de fechas y conceptos sin mapear

| Grupo | Filas | Sin fecha de fin | Fin = inicio | % sin fin o fin = inicio | Fin < inicio | `drug_concept_id = 0` |
|---|---|---|---|---|---|---|
| EHR prescription | 388,700 | 0 | 137,360 | 35.3 | 479 | 0 |
| EHR encounter record (vacunas) | 78,890 | 0 | 78,890 | 100.0 | 0 | 0 |
| Total | 467,590 | 0 | 216,250 | 46.2 | 479 | 0 |

Excluir las vacunas (decisión 2) baja el porcentaje de fin = inicio de 46.2 % a 35.3 %.

### Diagnóstico: ¿sirve esta base para estudiar exposición?

**Sirve para saber quién recibió una receta de qué ingrediente y cuándo empezó:** 0 % de conceptos sin mapear, 0 fechas nulas y una jerarquía completa. **Es débil para medir duración:** la duración no es un dato propio (es fin − inicio), un tercio de las recetas dura cero días, hay 479 duraciones imposibles y el 10.8 % comparte el mismo valor (371). Por eso, todo resultado que dependa de duración (eras, PDC) depende de las reglas de limpieza que se fijen en las actividades 4-5, y se reportará junto con ellas.

## 3. Búsqueda por ingrediente: lisinopril (1308216)

| Búsqueda | Pacientes |
|---|---|
| Directa (`drug_concept_id = 1308216`) | **0** |
| Con descendientes (`concept_ancestor`) | **1,522** |

**Por qué la diferencia es total:** las recetas nunca apuntan al ingrediente, sino a un producto concreto (*Clinical Drug*, 2 niveles por debajo: ingrediente → forma clínica → producto con dosis). La búsqueda directa no encuentra nada; sin `concept_ancestor` el lisinopril «no existiría» en esta base. Lo mismo ocurre con los otros seis candidatos medidos (acetaminofén, amoxicilina, simvastatina, hidroclorotiazida, amlodipino, metoprolol): búsqueda directa = 0 en todos.

| Producto en los datos | Pacientes | Recetas |
|---|---|---|
| lisinopril 10 MG Oral Tablet | 1,432 | 41,278 |
| lisinopril 20 MG Oral Tablet | 97 | 751 |
| lisinopril 5 MG Oral Tablet | 21 | 21 |
| lisinopril 40 MG Oral Tablet | 13 | 13 |
| hydrochlorothiazide 12.5 MG / lisinopril 20 MG Oral Tablet | 11 | 11 |
| lisinopril 2.5 MG Oral Tablet | 5 | 5 |
| hydrochlorothiazide 25 MG / lisinopril 20 MG Oral Tablet | 2 | 2 |
| lisinopril 30 MG Oral Tablet | 2 | 2 |
| hydrochlorothiazide 12.5 MG / lisinopril 10 MG Oral Tablet | 2 | 2 |

Los pacientes por producto suman 1,585, más que los 1,522 distintos: 63 pacientes aparecen con más de un producto (cambios de dosis o paso a combinación). Por eso el total se cuenta con `DISTINCT` sobre toda la jerarquía y no sumando productos. En el vocabulario, lisinopril tiene 98 descendientes (77 estándar; marcas, formas, grupos de dosis, combinaciones); en los datos solo aparecen 9.
