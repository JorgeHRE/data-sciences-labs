# Diagnóstico de la cohorte del lab 17

Auditoría de la cohorte de **nuevos usuarios de lisinopril con hipertensión** (`cohort_definition_id` 1701, índice desde 2017-01-01, N = 122) construida en el lab 17 sobre la base OMOP sintética del lab 12 (PostgreSQL, vocabulario v5.0 29-AUG-26). La cohorte 1702 (amlodipino, N = 81) se mide en paralelo cuando no cuesta nada. Todo el SQL es de solo lectura sobre `results.cohort` y `cdm`; las decisiones están en `DECISIONES.md`.

Contenido de este documento (se completa actividad por actividad):

1. [Factibilidad a posteriori](#1-factibilidad-a-posteriori)

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
