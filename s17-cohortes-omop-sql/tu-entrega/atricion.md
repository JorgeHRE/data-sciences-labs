# Tabla de atrición — Lab 17

Generada por SQL: es el `SELECT` final de `cohorte_definicion.sql` (una fila por paso y cohorte). Las cifras de este archivo se copiaron de esa salida por script, no a mano. «% que queda» se mide contra el evento inicial; «% perdido en el paso», contra el paso anterior. Todos los pasos cuentan personas, salvo el 0 (recetas).

Cohortes: **1701 lisinopril** y **1702 amlodipino** (definición principal, índice desde 2017-01-01); **1711 / 1712** son las mismas sin inicio de estudio (sensibilidad, para ver cuánto pesa esa decisión).

## La tabla del enunciado (definición principal)

| paso | lisinopril N | % que queda | amlodipino N | % que queda |
|---|---:|---:|---:|---:|
| con el evento inicial | 1,522 | 100.0 % | 1,104 | 100.0 % |
| + índice desde 2017-01-01 (periodo de estudio, no está en el enunciado) | 346 | 22.7 % | 238 | 21.6 % |
| + 365 días de observación | 346 | 22.7 % | 238 | 21.6 % |
| + lavado sin exposición | 346 | 22.7 % | 238 | 21.6 % |
| + criterios de inclusión (edad, hipertensión, ≥ 2 visitas) | 173 | 11.4 % | 165 | 14.9 % |
| + criterios de exclusión (demencia, otro fármaco, combinación) | 122 | 8.0 % | 81 | 7.3 % |
| cohorte final (con fecha de salida) | 122 | 8.0 % | 81 | 7.3 % |

## Qué criterio costó más, y si vale la pena

**El que más costó no es clínico: es el inicio del estudio en 2017.** Quita 1,176 de 1,522 (77.3 %) en lisinopril y 866 de 1,104 (78.4 %) en amlodipino, más de cinco veces lo que quitan todos los criterios clínicos juntos (224 y 157 personas). Sí vale la pena: sin él, los 665 y 545 «nuevos usuarios» de 2016 son, muy probablemente, usuarios previos que aparecen como nuevos cuando la base empieza a registrar con detalle (figura de la actividad 3; es una inferencia por el pico y la cobertura de visitas, no se puede comprobar con esta base), y esa cohorte sería de calidad dudosa aunque fuera grande (decisión 9). La atrición es la medida honesta de ese costo, no un defecto.

**Entre los criterios clínicos,** en lisinopril costó más el de ≥ 2 visitas (147 de 320, 45.9 % de quienes llegaban a él); en amlodipino, el del otro fármaco (83 de 164, 50.6 %). El del otro fármaco no se negocia: sin él, las dos cohortes se mezclan y no habría comparación. El de visitas es el más discutible, porque N = 2 es una elección y no una necesidad (decisión 11); se mantuvo porque aflojarlo para tener más personas es justo el sesgo que esta tabla existe para evitar. El reparto depende del orden: el otro fármaco, solo, quita 63 / 102; en secuencia, 50 / 83.

**Resultado y lo que no se puede decir.** La cohorte no quedó vacía: 122 y 81 personas (8.0 % y 7.3 % de las iniciales). Pero en esos 122 y 81 hay **0 demencias incidentes** en el seguimiento (373 y 216 años-persona); en la sensibilidad sin inicio de estudio hay 3 y 2 (1,421 y 644 años-persona). Es decir, la definición es válida y las cohortes se pueden describir (actividad 9), pero esta base no puede responder la pregunta sobre demencia. Se reporta así, sin aflojar ningún criterio para conseguir casos.

## Detalle, una fila por paso — 1701 · lisinopril (principal)

| paso | N | perdidos | % perdido en el paso | % que queda |
|---|---:|---:|---:|---:|
| 0 recetas del fármaco | 42,085 | — | — | — |
| 1 evento inicial | 1,522 | — | — | 100.0 % |
| 2 índice en el periodo de estudio | 346 | 1,176 | 77.3 % | 22.7 % |
| 3 + 365 días de observación | 346 | 0 | 0.0 % | 22.7 % |
| 4 + lavado 365 días | 346 | 0 | 0.0 % | 22.7 % |
| 5a + edad ≥ 18 | 346 | 0 | 0.0 % | 22.7 % |
| 5b + hipertensión (−∞, 0] | 320 | 26 | 7.5 % | 21.0 % |
| 5c + ≥ 2 visitas en [−365, −1] | 173 | 147 | 45.9 % | 11.4 % |
| 5d − demencia previa | 172 | 1 | 0.6 % | 11.3 % |
| 5e − otro fármaco previo | 122 | 50 | 29.1 % | 8.0 % |
| 5f − combinación en el índice | 122 | 0 | 0.0 % | 8.0 % |
| 6 con fecha de salida | 122 | 0 | 0.0 % | 8.0 % |

## Detalle, una fila por paso — 1702 · amlodipino (principal)

| paso | N | perdidos | % perdido en el paso | % que queda |
|---|---:|---:|---:|---:|
| 0 recetas del fármaco | 34,475 | — | — | — |
| 1 evento inicial | 1,104 | — | — | 100.0 % |
| 2 índice en el periodo de estudio | 238 | 866 | 78.4 % | 21.6 % |
| 3 + 365 días de observación | 238 | 0 | 0.0 % | 21.6 % |
| 4 + lavado 365 días | 238 | 0 | 0.0 % | 21.6 % |
| 5a + edad ≥ 18 | 238 | 0 | 0.0 % | 21.6 % |
| 5b + hipertensión (−∞, 0] | 237 | 1 | 0.4 % | 21.5 % |
| 5c + ≥ 2 visitas en [−365, −1] | 165 | 72 | 30.4 % | 14.9 % |
| 5d − demencia previa | 164 | 1 | 0.6 % | 14.9 % |
| 5e − otro fármaco previo | 81 | 83 | 50.6 % | 7.3 % |
| 5f − combinación en el índice | 81 | 0 | 0.0 % | 7.3 % |
| 6 con fecha de salida | 81 | 0 | 0.0 % | 7.3 % |

## Detalle, una fila por paso — 1711 · lisinopril, sensibilidad sin inicio de estudio

| paso | N | perdidos | % perdido en el paso | % que queda |
|---|---:|---:|---:|---:|
| 0 recetas del fármaco | 42,085 | — | — | — |
| 1 evento inicial | 1,522 | — | — | 100.0 % |
| 2 índice en el periodo de estudio | 1,522 | 0 | 0.0 % | 100.0 % |
| 3 + 365 días de observación | 1,522 | 0 | 0.0 % | 100.0 % |
| 4 + lavado 365 días | 1,522 | 0 | 0.0 % | 100.0 % |
| 5a + edad ≥ 18 | 1,522 | 0 | 0.0 % | 100.0 % |
| 5b + hipertensión (−∞, 0] | 1,447 | 75 | 4.9 % | 95.1 % |
| 5c + ≥ 2 visitas en [−365, −1] | 421 | 1,026 | 70.9 % | 27.7 % |
| 5d − demencia previa | 409 | 12 | 2.9 % | 26.9 % |
| 5e − otro fármaco previo | 246 | 163 | 39.9 % | 16.2 % |
| 5f − combinación en el índice | 242 | 4 | 1.6 % | 15.9 % |
| 6 con fecha de salida | 242 | 0 | 0.0 % | 15.9 % |

## Detalle, una fila por paso — 1712 · amlodipino, sensibilidad sin inicio de estudio

| paso | N | perdidos | % perdido en el paso | % que queda |
|---|---:|---:|---:|---:|
| 0 recetas del fármaco | 34,475 | — | — | — |
| 1 evento inicial | 1,104 | — | — | 100.0 % |
| 2 índice en el periodo de estudio | 1,104 | 0 | 0.0 % | 100.0 % |
| 3 + 365 días de observación | 1,104 | 0 | 0.0 % | 100.0 % |
| 4 + lavado 365 días | 1,104 | 0 | 0.0 % | 100.0 % |
| 5a + edad ≥ 18 | 1,104 | 0 | 0.0 % | 100.0 % |
| 5b + hipertensión (−∞, 0] | 1,102 | 2 | 0.2 % | 99.8 % |
| 5c + ≥ 2 visitas en [−365, −1] | 340 | 762 | 69.1 % | 30.8 % |
| 5d − demencia previa | 329 | 11 | 3.2 % | 29.8 % |
| 5e − otro fármaco previo | 131 | 198 | 60.2 % | 11.9 % |
| 5f − combinación en el índice | 131 | 0 | 0.0 % | 11.9 % |
| 6 con fecha de salida | 131 | 0 | 0.0 % | 11.9 % |
