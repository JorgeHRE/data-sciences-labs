# Actividad 6 — El concept set de HbA1c

Consulta: `actividades.sql`, actividad 6a. Decisión: `DECISIONES.md`, decisión 8.

**Cómo se buscaron los candidatos.** Todos los códigos LOINC cuyo eje Component empieza por «Hemoglobin A1c» (relación `Has component`): 10 códigos, todos estándar. El LOINC Group LG51070-7 (`concept_id` 1621295) solo agrupa 4 de ellos (4548-4, 17856-6, 4549-2, 62388-4), así que partir del grupo habría dejado fuera la HbA1c IFCC.

## Códigos incluidos (8)

Criterio: todo lo que mide la **fracción de HbA1c sobre la hemoglobina total**, sea cual sea el método o la escala.

| LOINC | concept_id | Qué es | Conversión a % (NGSP) | Mediciones | Pacientes |
|---|---|---|---|---|---|
| **4548-4** | 3004410 | HbA1c, cualquier método | — | **58,969** | **2,565** |
| 17856-6 | 3005673 | por HPLC | — | 0 | 0 |
| 4549-2 | 3003309 | por electroforesis | — | 0 | 0 |
| 62388-4 | 40765129 | protocolo JDS/JSCC (Japón) | — | 0 | 0 |
| 17855-8 | 3007263 | calculada | — | 0 | 0 |
| 96595-4 | 36032094 | gota de sangre seca (DBS) | — | 0 | 0 |
| 59261-8 | 40762352 | estandarizada IFCC (mmol/mol) | **0.0915 · x + 2.15** | 0 | 0 |
| 71875-9 | 42869630 | fracción decimal (0.065 = 6.5 %) | **x · 100** | 0 | 0 |

Las variantes por método (HPLC, electroforesis, JDS/JSCC) solo difieren de 4548-4 en el eje Method; 4548-4 tiene Method vacío porque vale para cualquier método. 59261-8 y 71875-9 miden lo mismo en otra escala: entran al concept set, pero hay que convertirlos antes de promediar (actividad 7).

## Códigos excluidos (2)

| LOINC | concept_id | Qué es | Por qué queda fuera |
|---|---|---|---|
| 86910-7 | 36304734 | HbA1c **meta** (*goal*) | Es el objetivo que fija el médico (p. ej. < 7 %), no un resultado de laboratorio; su clase es *Clinical Observation*, no *Lab Test*. Incluirlo metería valores redondos (7.0, 8.0) que no reflejan la glucemia del paciente. |
| 41995-2 | 3034639 | HbA1c en **masa/volumen** (g/dL) | Property *Mass concentration*: son gramos de HbA1c por decilitro, que dependen de la glucemia **y** de la hemoglobina total. Con la misma HbA1c de 6.5 %, un paciente con Hb 15 g/dL tiene 0.98 g/dL y uno anémico con Hb 9 g/dL, 0.59 g/dL. No se puede pasar a % sin la Hb total del mismo tubo: es otra cantidad, no otra unidad. |

Regla usada: si basta un factor o una fórmula, es un problema de unidades y el código entra; si falta un dato del paciente o no es una medición, queda fuera.

## Comparación con usar solo 4548-4

| | Solo 4548-4 | Concept set (8 códigos) |
|---|---|---|
| Códigos | 1 | 8 |
| Mediciones en esta base | 58,969 | 58,969 |
| Pacientes en esta base | 2,565 | 2,565 |

En esta base el resultado es idéntico: Synthea registra toda la HbA1c con 4548-4. Se comprobó además que no hay HbA1c escondida en otro lado: 0 mediciones con `measurement_concept_id = 0` y ningún `measurement_source_value` con otro código de HbA1c.

La diferencia está en la **portabilidad**. Un laboratorio que reporte por HPLC o en IFCC registra sus resultados en otro código; un hospital europeo que use IFCC tendría el 100 % de sus HbA1c en 59261-8, y con «solo 4548-4» su cohorte tendría 0 pacientes. El concept set no se diseña para la base donde se escribe, sino para cualquier base donde se vaya a ejecutar. Es la misma lección que en la actividad 4 con la metformina: la definición cambia mucho aunque en Synthea los pacientes no.
