# Diagnóstico de la cohorte del lab 17

Auditoría de la cohorte de **nuevos usuarios de lisinopril con hipertensión** (`cohort_definition_id` 1701, índice desde 2017-01-01, N = 122) construida en el lab 17 sobre la base OMOP sintética del lab 12 (PostgreSQL, vocabulario v5.0 29-AUG-26). La cohorte 1702 (amlodipino, N = 81) se mide en paralelo cuando no cuesta nada. Todo el SQL es de solo lectura sobre `results.cohort` y `cdm`; las decisiones están en `DECISIONES.md`.

Contenido de este documento (se completa actividad por actividad):

1. [Factibilidad a posteriori](#1-factibilidad-a-posteriori)
2. [Tabla de atrición](#2-tabla-de-atrición)
3. [El orden importa](#3-el-orden-importa)

---

## 1. Factibilidad a posteriori

Código: [`factibilidad.sql`](factibilidad.sql). Desenlace: primer diagnóstico de **demencia** (4182210 y descendientes) después del índice, el de la pregunta del lab 17.

### Los tres conteos

| | 1701 lisinopril | 1702 amlodipino |
|---|---|---|
| **1. Pacientes que entraron** | 122 | 81 |
| **2. Seguimiento tras el índice**, días: mediana [Q1–Q3] | 927.5 [30–1,869] | 401 [30–1,514] |
| Años-persona | 373.3 | 216.3 |
| **3. Eventos de demencia en ese seguimiento** | **0** | **0** |

El seguimiento es el tiempo entre el índice y la salida de la cohorte (incluye 30 días de persistencia y el corte al empezar el otro fármaco, decisiones 13 y 14 del lab 17). Filas = personas distintas en las dos cohortes: nadie está duplicado. Ninguna persona tiene demencia previa (0 y 0), como exige el criterio de exclusión del lab 17.

### Veredicto

**No, este estudio no es factible con estos datos.** Con 0 eventos no hay ni una variable que modelar: la regla de ~10 eventos por variable (Peduzzi et al., 1996) pide al menos 10 eventos para una sola variable, y la pregunta que decide es la 3, no la 1. Tener 122 pacientes es irrelevante si el desenlace no ocurre.

### Qué cambiaría: ¿la pregunta, el desenlace o la fuente?

Se probaron dos cosas para saber si el cero es un problema del diseño o de los datos:

1. **¿El cero lo causa el corte del seguimiento?** En parte. En 1701 hay **2 personas con demencia después de la salida** (a los 9 y 3 años; 61 y 74 años al índice). Las dos salieron de la cohorte por empezar amlodipino a los 30 y 91 días (censura por el otro fármaco, decisión 14 del lab 17). Si se las siguiera hasta el fin de su periodo de observación, sin cortar por el otro fármaco (solo como contraste, no es la definición del lab 17), 1701 tendría **2 eventos en 559 años-persona** (0.36 por 100 años-persona; IC 95 % exacto de Poisson 0.04–1.3) y 1702 tendría 0 en 329. El veredicto no cambia: 2 eventos siguen siendo una quinta parte de lo que pide una sola variable. Con esa tasa (muy imprecisa, son 2 casos) harían falta del orden de 2,800 años-persona para llegar a 10 eventos, unas 5 veces los que hay.
2. **¿Hay otro desenlace con eventos?** Tabla **exploratoria** (no sustituye al desenlace principal, decisión 4 de `DECISIONES.md`; los otros desenlaces se miraron después de ver que la demencia tenía 0):

   | Desenlace (incidente en 1701) | Eventos | Variables que soportaría |
   |---|---|---|
   | Enfermedad renal crónica | 13 | 1 |
   | Diabetes tipo 2 | 2 | 0 |
   | Infarto de miocardio | 1 | 0 |
   | Accidente cerebrovascular | 0 | 0 |
   | Demencia (principal) | 0 | 0 |

   «Incidente» = evento en el seguimiento en personas sin ese mismo diagnóstico antes del índice (sin esa exclusión, cada visita repetiría el código de una ERC que ya existía). Ni siquiera la ERC llega a un modelo con más de una variable.

**Qué cambiaría, en orden de importancia:**

- **La fuente (o la población), antes que el desenlace.** La base **sí tiene demencia** (170 de las 5,904 personas, el 2.9 %, tienen algún diagnóstico de demencia), pero la cohorte es joven: mediana de 40 años y solo el 11 % tiene 65 años o más (caracterización del lab 17). Un desenlace de aparición lenta y tardía necesita una población mayor y un seguimiento de muchos años. Una fuente con más pacientes mayores tendría más oportunidades de verlo.
- **El desenlace**, solo si la pregunta puede cambiar: para un estudio descriptivo con esta base, la enfermedad renal crónica tiene eventos, pero no los suficientes para estimar un efecto.
- **La pregunta (la comparación lisinopril contra amlodipino)** no es el problema: la definición es razonable. El problema es que no ocurre el desenlace.

**No se aflojó ningún criterio ni se rehízo la cohorte para conseguir eventos.** El enunciado pide trabajar con la cohorte que hay y documentar la limitación; esta es la limitación.

---

## 2. Tabla de atrición

Código: [`atricion.sql`](atricion.sql) (banderas), [`orden_lab17.sql`](orden_lab17.sql) (orden de los pasos), [`consulta_atricion.sql`](consulta_atricion.sql) y [`tabla_atricion.py`](tabla_atricion.py), que genera [`atricion_lab17.md`](atricion_lab17.md) con las comprobaciones.

### Cómo se construyó

En lugar de filtrar paso a paso, se calcula **una bandera (verdadero/falso) por criterio** para las personas con primera receta (1,522 en 1701), con el índice ya fijado. La atrición en un orden dado es un `AND` acumulado de esas banderas. Así reordenar los criterios (actividad 3) es cambiar el orden de una lista, sin reescribir el SQL (decisión 6). La primera receta de toda la historia **no** es una bandera: define cuál es el índice (decisión 6).

Las banderas se validaron contra `results.cohort` del lab 17 comparando **personas**, no solo conteos: la tupla (cohorte, persona, fecha índice) coincide en los dos sentidos (0 solo en las banderas, 0 solo en el lab 17, 122 y 81 en común; [`validacion_banderas.sql`](validacion_banderas.sql)). Cada bandera es una fila por persona, así que ningún `JOIN` duplica: filas = personas distintas en todas las cohortes.

**Orden declarado:** el del lab 17. Primero se fija el inicio de estudio y la observación previa, el lavado y la edad (criterios de la ventana); después los clínicos, de la inclusión (hipertensión, visitas) a la exclusión (demencia previa, otro fármaco, combinación). «% del inicial» es contra las 1,522 primeras recetas (decisión 7).

### Lisinopril (1701)

| paso | criterio | N | % del inicial | pérdida respecto al paso anterior |
|---:|---|---:|---:|---:|
| 0 | primera receta (toda la historia) | 1,522 | 100.0 % | — |
| 1 | índice desde 2017-01-01 | 346 | 22.7 % | −1,176 (77.3 %) |
| 2 | + 365 d de observación previa | 346 | 22.7 % | −0 (0.0 %) |
| 3 | + lavado de 365 d | 346 | 22.7 % | −0 (0.0 %) |
| 4 | + edad ≥ 18 | 346 | 22.7 % | −0 (0.0 %) |
| 5 | + hipertensión (−∞, 0] | 320 | 21.0 % | −26 (7.5 %) |
| 6 | + ≥ 2 visitas en [−365, −1] | 173 | 11.4 % | −147 (45.9 %) |
| 7 | − demencia previa | 172 | 11.3 % | −1 (0.6 %) |
| 8 | − otro fármaco previo | 122 | 8.0 % | −50 (29.1 %) |
| 9 | − combinación en el índice | 122 | 8.0 % | −0 (0.0 %) |

### Amlodipino (1702)

| paso | criterio | N | % del inicial | pérdida respecto al paso anterior |
|---:|---|---:|---:|---:|
| 0 | primera receta (toda la historia) | 1,104 | 100.0 % | — |
| 1 | índice desde 2017-01-01 | 238 | 21.6 % | −866 (78.4 %) |
| 2 | + 365 d de observación previa | 238 | 21.6 % | −0 (0.0 %) |
| 3 | + lavado de 365 d | 238 | 21.6 % | −0 (0.0 %) |
| 4 | + edad ≥ 18 | 238 | 21.6 % | −0 (0.0 %) |
| 5 | + hipertensión (−∞, 0] | 237 | 21.5 % | −1 (0.4 %) |
| 6 | + ≥ 2 visitas en [−365, −1] | 165 | 14.9 % | −72 (30.4 %) |
| 7 | − demencia previa | 164 | 14.9 % | −1 (0.6 %) |
| 8 | − otro fármaco previo | 81 | 7.3 % | −83 (50.6 %) |
| 9 | − combinación en el índice | 81 | 7.3 % | −0 (0.0 %) |

**La tabla cuadra:** la suma de pérdidas es 1,176 + 26 + 147 + 1 + 50 = 1,400 = 1,522 − 122 (1701) y 866 + 1 + 72 + 1 + 83 = 1,023 = 1,104 − 81 (1702); ningún paso aumenta el N. El script lo comprueba y se detiene si algo cambia.

### Qué criterio costó más y si ese precio vale la pena

**En la tabla, el que más cuesta es el inicio de estudio** (77.3 % y 78.4 % de las primeras recetas), pero esa cifra es en gran parte un efecto de ir primero: su **costo marginal** (cuántas personas más tendría la cohorte final sin ese criterio) es de solo 120 en 1701 y 50 en 1702 (sección 3), porque casi todos los anteriores a 2017 habrían salido igual por otro criterio. Tampoco es un criterio clínico: es una decisión sobre los datos. Antes de 2016 la base «observa» casi sin registros y las primeras recetas se acumulan en 2015-2016 (665 de las 1,522 en 2016 contra 36 en 2017), así que muchos «nuevos usuarios» de entonces ya tomaban el fármaco (lab 17, decisión 9). Sin ese corte la cohorte dejaría de ser de nuevos usuarios, así que el precio vale la pena para esta pregunta. Tiene un costo que aquí se ve: con índice desde 2017 el seguimiento máximo posible es de unos 9.8 años, y para un desenlace de aparición lenta como la demencia eso limita lo que la base puede mostrar (sección 1).

**Entre los criterios clínicos el más caro en la tabla fue «≥ 2 visitas en el año previo»** en lisinopril (147 de 320, el 45.9 %), y «otro fármaco previo» en amlodipino (83 de 164, el 50.6 %). Por costo marginal el orden es el mismo: las visitas (+133) en 1701 y «otro fármaco» (+82) en 1702. El de las visitas es el más discutible: su propósito es asegurar que se observaba a la persona (una sola visita puede ser la del propio diagnóstico), pero es un sustituto de la observación real y cuesta casi la mitad de quienes llegaban. Con N = 1 el lab 17 midió que habría quitado 80 en vez de 147 (decisión 11 de ese lab); con N = 3, 207. La exclusión del otro fármaco sí tiene una razón de diseño fuerte (quien inicia los dos no es nuevo usuario de uno solo), así que su costo, aunque alto, es el precio del diseño.

**Tres criterios no quitaron a nadie** (observación previa, lavado y edad ≥ 18), ni siquiera en las 1,522 personas con primera receta: la observación previa de 365 días no filtra porque `observation_period` abarca toda la historia (lab 17, control 0a), y el lavado no quita a nadie por construcción porque el índice es la primera receta de toda la historia. Son criterios correctos de la definición que, en esta base, no cambian el resultado.

**Advertencia sobre estas lecturas:** el costo de cada criterio en la tabla depende del orden en que se aplicó. La sección 3 lo comprueba reordenando y mide el costo marginal, que no depende del orden: el inicio de estudio, que parece costar 1,176 personas, solo cuesta 120.

---

## 3. El orden importa

Código: [`orden_b.sql`](orden_b.sql), [`consulta_aislado.sql`](consulta_aislado.sql), [`consulta_marginal.sql`](consulta_marginal.sql), [`contraejemplo_indice.sql`](contraejemplo_indice.sql) y [`tabla_orden.py`](tabla_orden.py), que genera [`atricion_ordenes.md`](atricion_ordenes.md) (con 1702 completo) y comprueba lo que se afirma aquí.

### Qué se reordenó

Dos criterios clínicos: **«≥ 2 visitas en [−365, −1]»** y **«sin otro fármaco previo»** (decisión 8). En el orden A (el del lab 17) las visitas van en el paso 6 y el otro fármaco en el 8; en el orden B se intercambian. Los demás pasos no se mueven, así que las tablas son idénticas hasta el paso 5.

### Las dos tablas, lado a lado (lisinopril, 1701)

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

### Verificación: el N final es el mismo

**El N final es 122 en los dos órdenes** (y 81 en 1702, donde el orden B da 135 → 81 en lugar de 165 → 81). La pérdida total también coincide (1,400). Los criterios son **independientes** en el sentido que importa: cada bandera depende solo de la persona y de su fecha índice, no de quién más se quedó antes. El N final es el tamaño de la **intersección** de los nueve conjuntos de personas que cumplen cada criterio, y una intersección no depende del orden en que se calcula. Si el N final cambiara al reordenar, algún criterio estaría usando información de los pasos previos (por ejemplo, contar visitas solo entre quienes ya sobrevivieron un filtro) y la definición dependería del orden, no solo la tabla.

### Lo que sí cambia: el «costo» de cada criterio

| criterio (1701) | falla solo, de las 1,522 | pérdida en orden A | pérdida en orden B | costo marginal |
|---|---:|---:|---:|---:|
| índice desde 2017-01-01 | 1,176 | 1,176 | 1,176 | +120 |
| hipertensión (−∞, 0] | 75 | 26 | 26 | +22 |
| **≥ 2 visitas en [−365, −1]** | 1,035 | **147** | **133** | +133 |
| demencia previa | 18 | 1 | 2 | +1 |
| **otro fármaco previo** | 576 | **50** | **63** | +49 |
| combinación en el índice | 14 | 0 | 0 | +0 |

*Observación previa, lavado y edad (0 en todas las columnas) no se muestran. **Costo marginal** = personas que se sumarían a la cohorte final (122) si ese criterio, y solo ese, se quitara de la definición. No depende del orden. La tabla completa y 1702 están en [`atricion_ordenes.md`](atricion_ordenes.md).*

- Los dos criterios intercambiados cambian: «otro fármaco» pasa de costar 50 a 63 al ir antes, y las visitas de 147 a 133 al ir después. En amlodipino el efecto es mayor: «otro fármaco» pasa de 83 a 102 y las visitas de 72 a 54.
- **También cambia un criterio que no se movió:** «demencia previa» pasa de −1 a −2 (en amlodipino, de −1 a 0). Se explica por el único paso distinto antes de ella, el 6: en el orden A ahí van las visitas, y una persona con demencia previa y pocas visitas salía ya en ese paso; en el B ahí va «otro fármaco», y esa persona sigue hasta que la quita la demencia. En amlodipino ocurre lo contrario: la persona con demencia previa ya había salido por «otro fármaco», que ahora va antes. Esto es lo que impide hablar de un costo «propio» de cada criterio.
- La columna «falla solo» es el otro extremo: sin importar el orden, las visitas dejarían fuera a **1,035** de las 1,522 personas. En secuencia solo cuestan 147 o 133 porque la mayoría ya salió por el inicio de estudio (muchas de las primeras recetas son anteriores a 2017, cuando casi no hay visitas registradas). El costo en una tabla de atrición **no es una propiedad del criterio**: es la parte de su efecto que los pasos anteriores no habían ya producido.

### El costo marginal: la medida que no depende del orden

Las tres columnas responden preguntas distintas. «Falla solo» dice cuánta gente incumple el criterio (1,035 para las visitas). La pérdida en la tabla dice cuánta quita **después de los pasos anteriores** (147 o 133, según la ruta). El **costo marginal** dice cuánta gente ganaría la cohorte final si se quitara ese criterio y se dejaran los demás: **+133** en las visitas. Es lo que contesta «¿cuánto cuesta realmente este criterio?», y se puede reproducir sin saber en qué orden se aplicó.

- **La relación entre las tres:** el costo marginal es siempre menor o igual que lo que el criterio quita en la tabla, en cualquier posición, y es igual cuando va **último**. Por eso las visitas muestran exactamente +133 en el orden B (donde van al final, salvo «combinación», que quita 0) y «otro fármaco» muestra 50 contra +49 (la diferencia de 1 es una persona que falla «otro fármaco» y «combinación» a la vez). El script comprueba estas dos propiedades.
- **El inicio de estudio es el caso extremo:** parece costar 1,176 personas (77 %), pero quitarlo solo recuperaría **120** (la cohorte pasaría de 122 a 242, la cohorte 1711 del lab 17). Los otros 1,056 que salen en ese paso habrían salido igual por visitas, otro fármaco u otro criterio. Su costo en la tabla es casi todo solapamiento por ir primero.
- **En 1702 el ranking es otro:** el mayor costo marginal es «otro fármaco» (+82), seguido de las visitas (+54) y el inicio de estudio (+50).

**Por eso el orden se declara**: «las visitas costaron 147 personas» sin decir en qué paso se aplicaron no se puede reproducir ni comparar. Para hablar del costo de un criterio, lo que se reporta es el **costo marginal** (y el orden de la tabla, si se muestra).

### Lo que no es reordenar: el índice

Hay un cambio que **sí** alteraría el N final y que no es un criterio más: filtrar por fecha **antes** de tomar la primera receta. Cambia cuál es el índice: 1,233 personas en 1701 y 934 en 1702 tendrían alguna receta desde 2017, contra 346 y 238 con la primera de toda la historia. La diferencia (887 y 696) son usuarios previos que pasarían por «nuevos». Por eso en la actividad 2 la primera receta es el paso 0 y no una bandera.
