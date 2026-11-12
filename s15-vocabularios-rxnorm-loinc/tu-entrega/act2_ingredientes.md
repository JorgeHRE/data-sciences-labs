# Actividad 2 — Del producto al ingrediente

Consulta: `actividades.sql`, actividad 2. Criterio de orden: filas de `drug_exposure` (decisión 3). Ingredientes: ancestros de clase `Ingredient` en `concept_ancestor`, **incluido el nivel 0**, con `LEFT JOIN` (decisión 4).

| drug_concept_id | Nombre | concept_class_id | Filas | Pacientes | Ingrediente(s) |
|---|---|---|---|---|---|
| 19030765 | 1 ML epoetin alfa 4000 UNT/ML Injection [Epogen] | Quant Branded Drug | 81,102 | 272 | epoetin alfa |
| 40213154 | Influenza, split virus, trivalent, injectable, preservative free | CVX | 48,829 | 5,859 | — (vacuna) |
| 19080128 | lisinopril 10 MG Oral Tablet | Clinical Drug | 41,278 | 1,432 | lisinopril |
| 19009384 | insulin isophane, human 70 UNT/ML / insulin, regular, human 30 UNT/ML … | Branded Drug | 37,034 | 620 | insulin isophane + insulin, regular, human |
| 19078106 | hydrochlorothiazide 25 MG Oral Tablet | Clinical Drug | 36,002 | 1,207 | hydrochlorothiazide |
| 19073094 | amlodipine 2.5 MG Oral Tablet | Clinical Drug | 34,464 | 1,101 | amlodipine |
| 35604087 | cisplatin 50 MG Injection | Clinical Drug | 11,995 | 64 | cisplatin |
| 40163924 | 24 HR metformin hydrochloride 500 MG Extended Release Oral Tablet | Quant Clinical Drug | 11,495 | 231 | metformin |
| 1378388 | paclitaxel 100 MG Injection | Clinical Drug | 9,772 | 70 | paclitaxel |
| 46287738 | 24 HR tacrolimus 1 MG Extended Release Oral Tablet [Envarsus] | Quant Branded Drug | 8,556 | 327 | tacrolimus |
| 40173590 | alendronic acid 10 MG Oral Tablet | Clinical Drug | 7,279 | 242 | alendronate |
| 1539463 | simvastatin 10 MG Oral Tablet | Clinical Drug | 5,847 | 633 | simvastatin |
| 19033893 | ibuprofen 400 MG Oral Tablet [Ibu] | Branded Drug | 5,035 | 278 | ibuprofen |
| 19041324 | acetaminophen 325 MG Oral Tablet [Tylenol] | Branded Drug | 4,973 | 282 | acetaminophen |
| 40162606 | acetaminophen 300 MG / hydrocodone bitartrate 5 MG Oral Tablet | Clinical Drug | 4,591 | 494 | acetaminophen + hydrocodone |
| 40231918 | acetaminophen 325 MG / oxycodone hydrochloride 10 MG Oral Tablet [Percocet] | Branded Drug | 4,381 | 225 | acetaminophen + oxycodone |
| 40213227 | tetanus and diphtheria toxoids, adsorbed, preservative free, for adult use | CVX | 4,347 | 4,239 | — (vacuna) |
| 19123989 | albuterol 0.83 MG/ML Inhalation Solution | Clinical Drug | 3,393 | 135 | albuterol |
| 35603224 | 10 ML furosemide 10 MG/ML Injection | Quant Clinical Drug | 3,362 | 179 | furosemide |
| 1127433 | acetaminophen 325 MG Oral Tablet | Clinical Drug | 3,072 | 2,388 | acetaminophen |

## Conteo

**3 de los 20 productos tienen más de un ingrediente** (insulina isófana + regular, paracetamol + hidrocodona, paracetamol + oxicodona). 15 tienen uno y 2 (vacunas CVX) ninguno.

## Trampas y controles

- **Nivel 0 (Trampa 1):** se incluyó `min_levels_of_separation = 0`, de modo que un concepto que ya es un ingrediente se encuentra a sí mismo. En este top-20 ninguno lo es, así que no cambia el resultado; en la base hay 2 conceptos así (84 filas) que con `>= 1` se habrían quedado sin ingrediente.
- **El JOIN multiplica (Trampa 2):** top-20 = 20 filas → 23 tras unir los ingredientes (+3, el segundo ingrediente de cada combinación) → 20 tras el `GROUP BY`.
- **Productos sin ingrediente:** las 2 vacunas siguen en la tabla gracias al `LEFT JOIN`; con un `JOIN` la tabla habría quedado en 18 filas sin avisar.

## Por qué se analiza por ingrediente

El paracetamol aparece en 4 de los 20 productos. Sumar sus pacientes da 3,389, pero hay **2,818 pacientes distintos** (la suma infla un 20 %, porque un paciente recibe varios productos). Y esos 4 son solo parte de los **12 productos con paracetamol** de la base, que suman **3,675 pacientes distintos**. Para medir la exposición a un ingrediente hay que bajar desde el ingrediente a todos sus productos y contar `DISTINCT person_id`.
