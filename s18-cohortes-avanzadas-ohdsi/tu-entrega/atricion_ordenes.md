# La tabla de atrición en dos órdenes

Generada por `tabla_orden.py` (no editar a mano). Orden A = el del lab 17 (`orden_lab17.sql`); orden B = intercambia «≥ 2 visitas» y «sin otro fármaco» (`orden_b.sql`).

## Lisinopril (1701)

| paso | orden A: criterio | N | pérdida | orden B: criterio | N | pérdida |
|---:|---|---:|---:|---|---:|---:|
| 0 | primera receta (toda la historia) | 1,522 | — | primera receta (toda la historia) | 1,522 | — |
| 1 | índice desde 2017-01-01 | 346 | −1,176 | índice desde 2017-01-01 | 346 | −1,176 |
| 2 | + 365 d de observación previa | 346 | −0 | + 365 d de observación previa | 346 | −0 |
| 3 | + lavado de 365 d | 346 | −0 | + lavado de 365 d | 346 | −0 |
| 4 | + edad ≥ 18 | 346 | −0 | + edad ≥ 18 | 346 | −0 |
| 5 | + hipertensión (−∞, 0] | 320 | −26 | + hipertensión (−∞, 0] | 320 | −26 |
| 6 | **+ ≥ 2 visitas en [−365, −1]** | 173 | **−147** | **− otro fármaco previo** | 257 | **−63** |
| 7 | − demencia previa | 172 | −1 | − demencia previa | 255 | −2 |
| 8 | **− otro fármaco previo** | 122 | **−50** | **+ ≥ 2 visitas en [−365, −1]** | 122 | **−133** |
| 9 | − combinación en el índice | 122 | −0 | − combinación en el índice | 122 | −0 |

**Pérdida de cada criterio según el orden (Lisinopril (1701))**

| criterio | falla solo (de las 1,522) | pérdida en orden A | pérdida en orden B | costo marginal |
|---|---:|---:|---:|---:|
| índice desde 2017-01-01 | 1,176 | 1,176 | 1,176 | +120 |
| 365 d de observación previa | 0 | 0 | 0 | +0 |
| lavado de 365 d | 0 | 0 | 0 | +0 |
| edad ≥ 18 | 0 | 0 | 0 | +0 |
| hipertensión (−∞, 0] | 75 | 26 | 26 | +22 |
| ≥ 2 visitas en [−365, −1] | 1,035 | 147 | 133 | +133 |
| demencia previa | 18 | 1 | 2 | +1 |
| otro fármaco previo | 576 | 50 | 63 | +49 |
| combinación en el índice | 14 | 0 | 0 | +0 |
| **N final** | | **122** | **122** | |

*Costo marginal = personas que se sumarían a la cohorte final si ese criterio (y solo ese) se quitara de la definición (N sin el criterio − N final). No depende del orden (`consulta_marginal.sql`).*

## Amlodipino (1702)

| paso | orden A: criterio | N | pérdida | orden B: criterio | N | pérdida |
|---:|---|---:|---:|---|---:|---:|
| 0 | primera receta (toda la historia) | 1,104 | — | primera receta (toda la historia) | 1,104 | — |
| 1 | índice desde 2017-01-01 | 238 | −866 | índice desde 2017-01-01 | 238 | −866 |
| 2 | + 365 d de observación previa | 238 | −0 | + 365 d de observación previa | 238 | −0 |
| 3 | + lavado de 365 d | 238 | −0 | + lavado de 365 d | 238 | −0 |
| 4 | + edad ≥ 18 | 238 | −0 | + edad ≥ 18 | 238 | −0 |
| 5 | + hipertensión (−∞, 0] | 237 | −1 | + hipertensión (−∞, 0] | 237 | −1 |
| 6 | **+ ≥ 2 visitas en [−365, −1]** | 165 | **−72** | **− otro fármaco previo** | 135 | **−102** |
| 7 | − demencia previa | 164 | −1 | − demencia previa | 135 | −0 |
| 8 | **− otro fármaco previo** | 81 | **−83** | **+ ≥ 2 visitas en [−365, −1]** | 81 | **−54** |
| 9 | − combinación en el índice | 81 | −0 | − combinación en el índice | 81 | −0 |

**Pérdida de cada criterio según el orden (Amlodipino (1702))**

| criterio | falla solo (de las 1,104) | pérdida en orden A | pérdida en orden B | costo marginal |
|---|---:|---:|---:|---:|
| índice desde 2017-01-01 | 866 | 866 | 866 | +50 |
| 365 d de observación previa | 0 | 0 | 0 | +0 |
| lavado de 365 d | 0 | 0 | 0 | +0 |
| edad ≥ 18 | 0 | 0 | 0 | +0 |
| hipertensión (−∞, 0] | 2 | 1 | 1 | +0 |
| ≥ 2 visitas en [−365, −1] | 763 | 72 | 54 | +54 |
| demencia previa | 13 | 1 | 0 | +0 |
| otro fármaco previo | 628 | 83 | 102 | +82 |
| combinación en el índice | 3 | 0 | 0 | +0 |
| **N final** | | **81** | **81** | |

*Costo marginal = personas que se sumarían a la cohorte final si ese criterio (y solo ese) se quitara de la definición (N sin el criterio − N final). No depende del orden (`consulta_marginal.sql`).*

## Lo que no es reordenar: el índice

Filtrar por fecha **antes** de tomar la primera receta cambia cuál es el índice. Personas con alguna receta desde 2017-01-01: **1,233** (1701) y **934** (1702), contra 346 y 238 con el índice de toda la historia (`contraejemplo_indice.sql`).
