# Actividad 3 — De la clase ATC A10B a los ingredientes

Consultas: `actividades.sql`, actividades 3a y 3b. Alcance de A10B: la clase tal como la define ATC, incluidos los inyectables no insulínicos (decisión 5).

## Resultado

| Ingredientes bajo A10B | Productos de la base | Pacientes distintos |
|---|---|---|
| **42** | **2** | **231** |

- Productos de la base: `24 HR metformin hydrochloride 500 MG Extended Release Oral Tablet` (231 pacientes) y `3 ML liraglutide 6 MG/ML Pen Injector` (2 pacientes, que también toman metformina).
- De los 42 ingredientes de la clase, la base usa 2: es un hallazgo de cobertura de Synthea.

### Ingredientes por subclase (4.º nivel ATC)

| Subclase | Ingredientes |
|---|---|
| A10BA Biguanides | 2 |
| A10BB Sulfonylureas | 11 |
| A10BC Sulfonamides (heterocyclic) | 1 |
| A10BD Combinations of oral blood glucose lowering drugs | 25 |
| A10BF Alpha glucosidase inhibitors | 2 |
| A10BG Thiazolidinediones | 3 |
| A10BH DPP-4 inhibitors | 5 |
| A10BJ GLP-1 analogues (inyectables, salvo la semaglutida oral) | 6 |
| A10BK SGLT2 inhibitors | 6 |
| A10BX Other blood glucose lowering drugs | 6 |

La suma por subclase da 67, no 42: los 25 ingredientes de la subclase de combinaciones (A10BD) están todos también en sus subclases propias (67 − 25 = 42) (la metformina está en A10BA y en A10BD). Por eso la consulta usa `DISTINCT`.

**Sobre «hipoglucemiantes orales».** El enunciado llama así a A10B, pero la clase es «Blood glucose lowering drugs, excl. insulins» e incluye inyectables (A10BJ, y pramlintida y tirzepatida en A10BX). La vía es una propiedad del producto, no de la clase: quitar A10BJ quitaría también la semaglutida oral.

## Productos de la base que quedan fuera de ATC

**22 de 365 productos no tienen ningún ancestro ATC**: 79,158 de 467,590 filas de `drug_exposure` (**16.9 %**) y 5,896 pacientes distintos.

| Vocabulario | Productos | Filas | Cuáles |
|---|---|---|---|
| CVX | 19 | 78,890 | Vacunas: gripe (48,829 filas, 5,859 pacientes), tétanos-difteria (4,347), DTaP, neumococo, polio, meningococo, VPH, zóster, hepatitis A y B, Hib, triple viral, varicela, rotavirus |
| RxNorm | 3 | 268 | Parche de etinilestradiol/norelgestromina (157), pancreatina 600 mg (100), levalbuterol inhalador (11) |

- **Para A10B no se pierde nada:** ninguno de los 22 es antidiabético.
- **Pero el hueco es grande y está concentrado en las vacunas.** La clase ATC J07 «Vaccines» existe en el vocabulario y tiene 2,083 descendientes RxNorm, pero **0 de CVX**: una selección de vacunados por J07 daría 0 pacientes en esta base, sin ningún error. Synthea codifica las vacunas en CVX, y en OMOP CVX no cuelga de la jerarquía ATC.
- **Cómo se contó:** partiendo de los productos de la base y preguntando con `NOT EXISTS` si tienen un ancestro ATC. Partiendo de ATC no se podrían encontrar, porque no hay ninguna relación que lleve de ATC a ellos.
