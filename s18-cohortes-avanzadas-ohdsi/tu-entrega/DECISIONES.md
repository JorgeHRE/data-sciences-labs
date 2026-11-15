# Registro de decisiones — Lab 18 (Auditoría de una definición de cohorte)

Formato: qué se decidió, qué alternativas había y por qué se eligió esta.

## 1. Motor y herramientas
- **Decisión:** trabajar sobre el Postgres del lab 12 (contenedor `lab12-omop-db-1`, esquema `cdm` de solo lectura) con `psql` y scripts `.py` en un `.venv` propio de `tu-entrega/`. Este lab **solo lee**: las cohortes ya están en `results.cohort` desde el lab 17.
- **Alternativas:** DuckDB con jupysql (lo que sugiere el enunciado) o Google Colab.
- **Por qué:** es la misma decisión 1 y 2 del lab 17. Las cohortes y el vocabulario ya están en Postgres; copiar 12 millones de filas a DuckDB obligaría a revalidar todo. Los scripts `.py` con `assert` se revisan línea por línea en un PR y regeneran cada figura.

## 2. Qué cohorte se audita
- **Decisión:** la cohorte **1701** (nuevos usuarios de lisinopril con hipertensión, índice desde 2017-01-01, N = 122) es «mi cohorte» y la que se discute en la prosa. La **1702** (amlodipino, N = 81) se calcula en paralelo cuando no cuesta nada (el SQL ya va por `cohort_definition_id`). **1711/1712** son la sensibilidad sin inicio de estudio del lab 17.
- **Alternativas:** auditar solo la 1701; auditar las cuatro con el mismo detalle.
- **Por qué:** el enunciado pide auditar *una* cohorte. La 1702 sirve como comprobación (¿el hallazgo es de la definición o de esta cohorte?) sin duplicar la prosa. No se rehace ninguna cohorte para que salga más grande (lo pide el enunciado).

## 3. Definición principal, declarada antes de las variantes
- **Decisión:** la definición principal del análisis de sensibilidad es la del lab 17 **sin cambios**: cohorte 1701, ventana de observación previa y de lavado de **365 días**, inicio de estudio **2017-01-01**, criterios y salida del lab 17. Las variantes de 180 y 730 días (actividad 9) son sensibilidad, no candidatas a reemplazarla.
- **Alternativas:** elegir como principal la variante que resulte con mejor N o mejor caracterización después de verlas.
- **Por qué:** declararla antes de mirar las variantes es lo que separa un análisis de sensibilidad de un p-hacking (actividad 11). Esta decisión queda en un commit anterior a cualquier tabla de la actividad 9.
- **Transparencia:** al planear el lab (2026-11-15) se miraron conteos preliminares de las variantes, solo de la observación previa y del índice relajado (346 / 346 / 344 y 348 / 348 / 348 personas antes de aplicar los demás criterios). La definición principal ya estaba fijada desde el lab 17 y esos números no la cambiaron; se deja dicho para que quien audite el repositorio lo sepa.

## 4. Desenlace de la factibilidad (actividad 1)
- **Decisión:** el veredicto se dicta con la **demencia** (la pregunta del lab 17): 0 eventos → no factible. Se añade una tabla **exploratoria**, marcada como tal, con otros desenlaces (ERC 13, diabetes tipo 2 2, infarto 1, ACV 0) solo para argumentar qué cambiar.
- **Alternativas:** usar solo la demencia sin tabla; cambiar el desenlace principal a la ERC (13 eventos).
- **Por qué:** cambiar el desenlace después de ver que el original sale en 0 es elegir la pregunta según el resultado, lo que la decisión 3 quiere evitar. La tabla exploratoria informa la recomendación (qué cambiar) sin convertirse en el análisis principal; el documento aclara que los otros desenlaces se miraron después.

## 5. Qué es «seguimiento» y «evento» en los tres conteos
- **Decisión:** seguimiento = fecha de salida − fecha índice (`results.cohort`); evento = primera demencia en (índice, salida] en personas sin demencia previa. Como contraste, no como definición, se mide también el seguimiento hasta el fin del `observation_period`.
- **Alternativas:** medir hasta el fin del periodo de observación (más seguimiento, pero ya no es la cohorte del lab 17); contar registros en lugar de personas.
- **Por qué:** los conteos auditan la cohorte tal como quedó. El contraste mostró algo que el conteo solo no veía: 2 personas de 1701 tienen demencia después de salir (por el corte al empezar el otro fármaco, decisión 14 del lab 17). El veredicto no cambia (2 eventos < 10), pero el 0 era en parte censura. Se cuentan personas distintas porque un diagnóstico se repite en cada visita.

## 6. Cómo se construye la atrición para poder reordenarla (actividades 2 y 3)
- **Decisión:** **una bandera (verdadero/falso) por criterio**, calculada sobre las 1,522 / 1,104 personas con primera receta (índice ya fijado). La atrición en cualquier orden es un `AND` acumulado; el orden es una lista `VALUES` en un archivo aparte (`orden_lab17.sql`), así que reordenar no toca el SQL de la consulta. Se valida contra `results.cohort` comparando **personas** (0 de diferencia en los dos sentidos), no solo conteos.
- **Alternativas:** banderas solo sobre las 346 con índice desde 2017 (más simple, pero el inicio de estudio quedaba fuera del reordenamiento); copiar la cadena de CTE del lab 17 y reordenar CTE (fiel al original, pero cada orden es otra copia y los CTE encadenados leen solo del anterior).
- **Por qué:** el inicio de estudio es el criterio más caro (77 %) y la demostración de que el orden importa lo necesita. Lo que **no** se puede reordenar es «tomar la primera receta» frente a «filtrar por fecha» (cambia cuál es el índice: 1,233 en vez de 346), y por eso la primera receta queda como paso 0 y no como bandera.
- **Detalle técnico (decisión menor):** las banderas se calculan con la primera fecha por persona de cada diagnóstico o fármaco (una fila por persona) en lugar de `EXISTS` correlacionados, porque `cdm.*` no tiene índices en `person_id` y esas consultas se colgaban en el lab 17. «Hay un diagnóstico en (−∞, índice]» equivale a «su primera fecha ≤ índice».

## 7. «% del inicial» se calcula contra las 1,522 primeras recetas
- **Decisión:** el inicial es el paso 0 (primera receta de toda la historia): 1,522 en 1701 y 1,104 en 1702.
- **Alternativas:** las 346 / 238 con índice desde 2017 (tratar el inicio de estudio como parte de la población, no como criterio).
- **Por qué:** es el mismo inicial que `atricion.md` del lab 17, así las dos tablas son comparables, y deja visible que el criterio más caro es el inicio de estudio y no uno clínico. Con 346 como inicial la cohorte final sería el 35 % en vez del 8.0 %.

## 8. Qué dos criterios se reordenan (actividad 3)
- **Decisión:** intercambiar «≥ 2 visitas en [−365, −1]» y «sin otro fármaco previo» (pasos 6 y 8 del orden del lab 17). El orden B es solo otro archivo (`orden_b.sql`); la consulta no cambia.
- **Alternativas:** inicio de estudio ↔ visitas (la demostración más dramática: el criterio más caro, 77 %, pasaría al final, pero mezcla una decisión sobre los datos con un criterio clínico); hipertensión ↔ demencia previa (dos criterios chicos, la diferencia casi no se vería).
- **Por qué:** son los dos criterios clínicos que más cuestan, así que el cambio de orden se nota (otro fármaco 50 → 63, visitas 147 → 133) sin tocar la definición. La verificación pedida (N final igual) se cumple: 122 y 81 en los dos órdenes.
- **Además se midió** cuántas personas falla cada criterio por sí solo (las visitas, 1,035 de 1,522) y el contraste del índice (filtrar por fecha antes de la primera receta daría 1,233 / 934). No son parte de lo que pide el enunciado: sirven para explicar por qué el costo depende del orden.

## 9. El costo de un criterio se reporta como costo marginal (actividad 3, ampliación)
- **Decisión:** además de la pérdida en la tabla de atrición, cada criterio lleva su **costo marginal**: cuántas personas más tendría la cohorte final si ese criterio, y solo ese, se quitara (N sin el criterio − N final). Es el número que se cita para hablar de «cuánto cuesta» un criterio.
- **Alternativas:** reportar solo la pérdida en la tabla (depende del orden); reportar «falla solo» (cuánta gente incumple el criterio, sin tener en cuenta los otros: 1,035 en las visitas); promediar el costo sobre todos los órdenes posibles (más justo, pero con 9 criterios son 362,880 órdenes).
- **Por qué:** es reproducible sin conocer el orden y responde la pregunta que se hace un revisor («¿qué ganaría si lo quito?»). Cambia una conclusión de la actividad 2: el inicio de estudio parece el criterio más caro (1,176) pero solo recupera 120 personas al quitarlo; las visitas (+133) son el criterio que más cuesta en lisinopril.
- **Control:** el script comprueba que el costo marginal es ≤ la pérdida en cualquier orden y ≤ «falla solo», y que el criterio que va último muestra exactamente su costo marginal.
