# Registro de decisiones — Lab 17 (Cohorte de nuevo usuario en OMOP con SQL)

Formato: qué se decidió, qué alternativas había y por qué se eligió esta.

## 1. Motor y base de datos
- **Decisión:** construir la cohorte sobre el Postgres del lab 12 (contenedor `lab12-omop-db-1`, esquema `cdm` de solo lectura, vocabulario v5.0 29-AUG-26), con `psql` dentro del contenedor. La cohorte se escribe en `results.cohort`.
- **Alternativas:** DuckDB con jupysql, como sugiere el enunciado. Se descartó porque habría que copiar `drug_exposure`, `condition_occurrence`, `visit_occurrence`, `measurement`, `observation_period` y `concept_ancestor` (12 millones de filas), volver a validar los conteos y rehacer el concept set del lab 14.
- **Por qué:** el concept set de T2DM (`results.cs_t2dm`, lab 14) y el esquema `results` ya están en esa base. Además, es como se trabaja con OMOP en la industria: una base SQL compartida, con las cohortes en un esquema de resultados aparte.

## 2. Dónde se hacen las gráficas (actividades 3 y 9)
- **Decisión:** scripts `.py` con un `.venv` propio en `tu-entrega/`, como `figura_impacto.py` del lab 14. Se conectan en solo lectura (`default_transaction_read_only=on`), comprueban con `assert` las cifras del reporte y guardan un PNG que se versiona.
- **Alternativas:** un notebook con jupysql, como en el lab 13 (consultas y gráficas juntas, pero el diff de un `.ipynb` es difícil de revisar en un PR), o decidirlo al llegar a la actividad 3.
- **Por qué:** cada figura queda en un archivo corto que se revisa línea por línea, y el `assert` impide publicar una figura con cifras distintas a las de `atricion.md` o `caracterizacion.md`.

## 3. Exposición: nuevos usuarios de lisinopril
- **Decisión:** la cohorte principal (*target*) son los nuevos usuarios de **lisinopril** (RxNorm 1308216 y descendientes, recetas `drug_type_concept_id = 32838`), el mismo ingrediente del lab 13.
- **Alternativas:** metformina (1503297), que enlaza con el concept set de T2DM del lab 14, pero tiene 231 nuevos usuarios y ningún comparador activo en la base (solo hay insulinas).
- **Por qué:** 1,522 nuevos usuarios (6 veces más) y un comparador activo posible. Nuevo usuario + comparador activo es el diseño estándar en farmacoepidemiología.

## 4. Desenlace: demencia incidente
- **Decisión:** primer diagnóstico de **demencia** (SNOMED 4182210 *Dementia* y descendientes) después del índice, en personas sin demencia previa. Retoma la pregunta que quedó pendiente en el lab 14.
- **Alternativas:** enfermedad renal crónica (229 casos incidentes en lisinopril) o cardiopatía isquémica (200).
- **Por qué:** es una pregunta abierta en la literatura (antihipertensivos y demencia) y tiene 60 casos incidentes en lisinopril y 38 en amlodipino (antes de criterios). Con pocos casos, este lab **define y describe**, no estima un efecto.

## 5. Comparador activo: nuevos usuarios de amlodipino, implementado como segunda cohorte
- **Decisión:** construir también la cohorte de nuevos usuarios de **amlodipino** (RxNorm 1332418 y descendientes) con la misma definición, en lugar de solo describirla en la prosa.
- **Alternativas:** hidroclorotiazida (1,234 nuevos usuarios, 56 demencias, pero hay recetas combinadas lisinopril/HCTZ que cuentan para los dos fármacos); solo describir el comparador sin implementarlo; no tener comparador.
- **Por qué:** es otra clase (calcioantagonista frente a IECA, la comparación del ensayo ALLHAT). Ningún producto de la base contiene a la vez lisinopril y amlodipino (0 productos, 0 recetas). Caso borde: 3 de los 1,104 empiezan con una combinación (2 con benazepril, otro IECA; 1 con olmesartán/HCTZ); se trata en la actividad 5.
- **Hallazgo que condiciona el diseño:** 507 personas empiezan lisinopril y amlodipino **el mismo día**, y 69 nuevos usuarios de lisinopril ya tomaban amlodipino antes. Cómo excluir a quien inicia los dos fármacos se decide en la actividad 5.

## 6. Cómo recibe el SQL los fármacos de cada cohorte
- **Decisión:** una tabla de parámetros `results.cohorte_parametros` con una fila por cohorte (`cohort_definition_id`, nombre, ingrediente de exposición, ingrediente «otro»): 1701 lisinopril y 1702 amlodipino. Un solo SQL construye las dos cohortes; cada CTE lleva `cohort_definition_id`.
- **Alternativas:** los mismos parámetros en un CTE con `VALUES` (sin objeto en la base, pero hay que editar el archivo para otra cohorte); variables de `psql` (`\set`, una corrida por cohorte, solo funciona en psql); dos copias del SQL (las correcciones habría que hacerlas dos veces y las copias acabarían divergiendo).
- **Por qué:** es como lo hace ATLAS/CIRCE (los concept sets entran al SQL como tablas), garantiza que las dos cohortes usan exactamente la misma lógica (condición para compararlas) y cumple el bono 1 del enunciado. Se guarda el ingrediente, y los productos se obtienen con `concept_ancestor`.

## 7. Estructura del SQL: una sola sentencia WITH que crece
- **Decisión:** la construcción de la cohorte es un único bloque `WITH`, delimitado por los marcadores `-- [INICIO cohorte]` y `-- [FIN cohorte]`. Cada actividad añade un CTE que lee solo del anterior (`recetas` → `evento_inicial` → …), y el `SELECT` final cuenta cada paso por cohorte: es la tabla de atrición en construcción.
- **Alternativas:** una vista por componente en `results` (cada paso se prueba solo, pero ya no son CTE y deja varios objetos en la base); una tabla temporal por paso (rápido de depurar, pero el resultado depende de haber corrido los pasos anteriores en la misma sesión).
- **Por qué:** es lo que pide el enunciado («un CTE por componente») y la forma del SQL que genera ATLAS. Como cada CTE lee solo del anterior, quien sale en un paso no puede volver a entrar. La cadena completa corre en menos de un segundo, así que repetirla en cada prueba no cuesta nada.

## 8. Observación previa con JOIN (y no EXISTS)
- **Decisión:** el CTE `obs_previa` une `evento_inicial` con `observation_period` exigiendo, sobre **el mismo** periodo, inicio ≤ índice − 365 y fin ≥ índice, y se lleva `op_inicio` y `op_fin`.
- **Alternativas:** `EXISTS` con la misma condición (no puede multiplicar nunca, pero no trae columnas: la actividad 6 tendría que volver a unir `observation_period` repitiendo la condición).
- **Por qué:** la censura de la actividad 6 necesita `op_fin`. El JOIN no multiplica porque en OMOP los periodos de una persona no se solapan y como mucho uno contiene la fecha índice; se comprueba en cada corrida con filas = personas distintas.

## 9. Qué hacer con un OBSERVATION_PERIOD que no corrige el pico de 2016
- **Decisión:** fecha de **inicio del estudio en 2017-01-01** para la definición principal (1701 lisinopril, 1702 amlodipino), como columna `inicio_estudio` de la tabla de parámetros y CTE `periodo_estudio` aplicado después del evento inicial. Como sensibilidad, las mismas cohortes sin esa fecha (1711, 1712).
- **Alternativas medidas** (lisinopril / amlodipino, antes de los demás criterios):

  | Opción | Personas | En 2016 | Demencias incidentes |
  |---|---|---|---|
  | a · periodo tal cual | 1,522 / 1,104 | 665 / 545 | 60 / 38 |
  | b · periodo reconstruido desde visitas (hueco ≤ 365 d) | 420 / 286 | 106 / 84 | — |
  | c · además ≥ 1 visita en [−365, −1] | 785 / 576 | 260 / 224 | 25 / 18 |
  | **d · índice desde 2017-01-01** | **346 / 238** | **0 / 0** | **3 / 2** |

- **Por qué:** el periodo dura décadas (mediana 31.6 años), así que «365 días de observación» se cumple siempre (pérdida 0) sin probar observación real: antes de 2016 solo ~1 de cada 4 «observados» tiene visitas (control 0c). El pico de primeras recetas de 2015-2016 son usuarios previos que aparecen como nuevos cuando empieza el registro detallado. Solo d lo elimina, y por construcción: el año previo de todo índice desde 2017 cae en 2016 o después (84-94 % con visitas). c no lo corrige (una visita en 2015 no prueba ausencia de recetas cuando no se exportaban) y b inventa una regla y deja 106/84 en 2016. Es lo que se hace con datos reales: limitar el estudio a los años en que la fuente es confiable.
- **Costo, reportado y no corregido:** quedan 3 / 2 demencias incidentes. Elegir a o c para conservar casos sería aflojar la definición hasta obtener un número bonito, el sesgo que el diseño quiere evitar. Conclusión: la cohorte es válida, pero esta base no permite estudiar la demencia.

## 10. Lavado de 365 días: qué cuenta como «exposición» y por qué quita 0
- **Decisión:** el índice sigue siendo la primera receta de toda la historia y se añade un CTE `lavado` explícito: `NOT EXISTS` de una receta que empezó antes del índice y no terminó antes de la ventana [−365, −1] (`inicio < índice` y `greatest(fin, inicio) ≥ índice − 365`). Pérdida: 0 en las cuatro cohortes (346 / 238 y 1,522 / 1,104).
- **Alternativas:** (a) relajar el evento inicial a «primera receta con ≥ 365 días sin exposición» (348 / 238: +2 personas que reinician tras un hueco largo; el lavado quitaría gente de verdad, pero contaría como nuevo a quien ya lo usó); (b) lavado mirando solo la fecha de **inicio** de las recetas en la ventana (1,125 / 847).
- **Por qué:** (b) es un error medido: deja pasar a 779 / 609 usuarios previos cuya receta anterior empezó hace más de un año pero sigue vigente (duran años), así que el lavado debe medir exposición activa, no inicios. Entre (a) y mantener, se mantiene el diseño estricto de «nuevo usuario» por 2 personas de diferencia.
- **Cómo se sabe que el filtro no es vacío:** control 4a (fuera del bloque). Aplicado a un índice más flojo (cualquier receta desde 2017), el lavado por exposición activa deja 348 / 238 y el de solo-inicio 1,125 / 847. Se escribió con funciones de ventana porque la versión con `NOT EXISTS` por candidato tardó más de 2 minutos (~40,000 subconsultas).

## 11. Criterio «al menos N en la ventana W»: ≥ 2 visitas en [−365, −1]
- **Decisión:** N = 2 visitas (`visit_occurrence`) en [−365, −1], escrito con JOIN + `GROUP BY` + `HAVING count(*) >= 2`. Los otros tres criterios (HTA, demencia, otro fármaco) van con `EXISTS` / `NOT EXISTS`, más la edad ≥ 18 como comprobación.
- **Alternativas medidas** (sobre las 346 / 238 tras el lavado; quitan): N = 1 → 80 / 35; **N = 2 → 147 / 72**; N = 3 → 207 / 141 (60 % / 59 %). Otro candidato, ≥ 2 diagnósticos de HTA, no es viable: la HTA se registra una sola vez (339 de 346 tienen menos de 2 registros).
- **Por qué:** `EXISTS` responde «¿hay alguna?», no «¿hay dos?»; para contar hace falta el JOIN, que multiplica filas a propósito y el `GROUP BY` las devuelve a una por persona. N = 2 exige continuidad (una sola visita puede ser la del diagnóstico) sin dejar cohortes tan chicas como N = 3. La ventana termina en −1 porque el día 0 es la visita donde se receta. Es el criterio más costoso (42 % de lisinopril, 30 % de amlodipino) y se reporta como tal. Contar por fila o por día distinto da lo mismo en las cohortes principales (173 / 165).

## 12. Combinaciones en el día índice
- **Decisión:** excluir a quien inicia con un producto de más de un ingrediente (se cuentan ingredientes distintos en `drug_strength`), como criterio aparte tras el del otro fármaco.
- **Alternativas:** mantenerlas y reportarlas como limitación.
- **Por qué:** lisinopril/HCTZ y amlodipino/benazepril inician dos clases a la vez, aunque la otra no sea el comparador, y amlodipino/benazepril contamina el comparador con un IECA. En las cohortes principales el criterio quita 0 (122 y 81 antes y después) porque las dos personas afectadas que llegaban hasta ahí ya salían por tomar el otro fármaco; se comprobó persona por persona (4289 y 4506). Se deja explícito porque la definición debe decirlo, y porque en la sensibilidad (1711) quita 4. Cohorte tras la actividad 5: **122 / 81**.
