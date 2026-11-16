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

## 10. Cómo se dibuja el diagrama de flujo (actividad 4)
- **Decisión:** `matplotlib` con un script (`figura_consort.py`) y un PNG de 300 dpi por cohorte, a partir de la tabla de atrición del lab 17. Los pasos que no quitan a nadie van como una nota junto a la flecha, no como cajas. Se genera 1701 (la cohorte auditada) y 1702 con la misma función.
- **Alternativas:** Mermaid (se escribe en texto y renderiza en GitHub, pero el control de la posición, de las cajas laterales y de la calidad de impresión es mucho menor y la figura no sale de las cifras de la base); dibujarla a mano en una herramienta de diagramas (queda bien, pero no es regenerable y puede divergir de la tabla).
- **Por qué:** el enunciado pide una figura «en calidad presentable» que «va a la tesis tal cual», y «las figuras regenerables desde el código». Un script con `assert` impide publicar una figura cuyas cifras no coincidan con la tabla. Los pasos con 0 pérdidas como nota evitan cajas repetidas sin ocultar que esos criterios se aplicaron.
- **Detalle:** la figura quedó con una columna de exclusiones separada de la central; la primera versión tenía las cajas laterales invadiendo la columna del flujo y la última exclusión se superponía con la caja final. Se corrigió tras revisar la imagen.

## 11. Qué «entradas» se grafican por año (actividad 5)
- **Decisión:** dos paneles: (A) las **1,522 primeras recetas** de lisinopril (el evento inicial, antes de los criterios) y (B) las cohortes **1711** (todos los criterios clínicos, sin inicio de estudio) y **1701** (la cohorte final).
- **Alternativas:** solo la cohorte final (122), que es literalmente «la incidencia de entrada a tu cohorte» pero solo cubre 2017-2026 y no puede mostrar el pico; solo las primeras recetas, que muestra el artefacto pero no responde qué pasa con quienes sí entraron.
- **Por qué:** la cohorte final excluye por construcción el periodo donde está el artefacto (índice desde 2017). El panel B añade algo que no se sabía: el pico de 2016 sobrevive a los criterios clínicos (61 entradas en 1711 contra 2 a 4 por año antes), y solo el inicio de estudio lo elimina.

## 12. Denominador de la tasa (actividad 5)
- **Decisión:** **dos denominadores en el mismo gráfico**: personas-año de `observation_period` (el estándar OHDSI) y personas con al menos una visita en el año. En el último año (parcial) el segundo se pondera por la fracción del año cubierta por los datos (0.82).
- **Alternativas:** solo `observation_period`; solo personas con visita.
- **Por qué:** divergen justo donde hay artefactos. Al inicio, `observation_period` declara 3,545 personas-año en 2005 y solo 966 personas tienen una visita; en 2026 sus personas-año caen a 2,285 (el periodo termina en la última visita) y la tasa se dispara a 14.4 (9.2 con visitas). Con un solo denominador esa diferencia no se vería, y ella misma es el hallazgo.

## 13. Decisiones menores de la actividad 5 (de forma)
- **Edad** = año calendario − `year_of_birth` en el numerador y en el denominador. La misma aproximación en los dos lados mantiene consistente la tasa; la tabla 1 del lab 17 usa edad exacta (difiere en 58 de 203 personas). Solo adultos (≥ 18) en el denominador, porque la cohorte los exige.
- **Grupos** de 10 años (18-29, …, 70+) en 2017-2026, y **IC 95 % exactos de Poisson**: con 8 a 34 entradas por grupo, una tasa sin intervalo da una precisión que no existe.
- **Antes de 2005** (250 primeras recetas) no se grafica: la base casi no tiene visitas registradas. **2026** sí se grafica, como año parcial (círculo vacío).
- **Limitación declarada:** el denominador incluye a quienes ya habían usado lisinopril (no están «en riesgo» de ser nuevos usuarios); subestima sobre todo las tasas de los grupos mayores. No se corrigió: requeriría personas-año en riesgo (excluir lo posterior a la primera receta) y no es lo que pide el enunciado.

## 14. Qué es «entrar por un código» y cómo se mide (actividad 6)
- **Decisión:** el producto (`drug_concept_id`) de la receta del **día índice**, dentro del concept set del lab 17 (ingrediente + descendientes), contando **personas distintas**. Se hace para las dos cohortes, y se añaden tres controles que explican el resultado: cuánto del concept set se usa, el peso del producto más frecuente en cuatro etapas (todas las recetas, primeras recetas, cohorte sin inicio de estudio, cohorte final) y por qué sube de 93.0 % a 98.4 % en lisinopril.
- **Alternativas:** contar recetas (una persona con muchas recetas pesaría más: es otra pregunta, la de uso, no la de entrada); agrupar por ingrediente (daría 100 % trivialmente); solo la tabla pedida, sin las etapas.
- **Por qué:** el enunciado pide «por cuántos concept_id entró la gente» y el porcentaje del más frecuente, pero un 98.4 % solo se interpreta sabiendo si lo crea la definición o ya está en la base. Las etapas lo muestran: 98.1 % de **todas** las recetas de lisinopril y 99.97 % de las de amlodipino ya son del mismo producto, así que es una propiedad de cómo la base codifica el fármaco.
- **Hallazgo adicional:** el concept set de amlodipino tiene 303 conceptos y solo 6 con recetas (1 como índice); el de lisinopril, 98 con 9 (2). Ninguna marca (*Branded Drug*) tiene una receta.

## 15. Presión arterial elevada sin diagnóstico: no entra a la definición (actividad 7)
- **Decisión:** el candidato real (personas con presión sistólica ≥ 140 o diastólica ≥ 90 en ≥ 2 fechas y sin diagnóstico de hipertensión) **no entra**; se reporta como limitación. Para medirlo se usó 140/90 con ≥ 2 fechas (umbral habitual de la guía clínica), y se probaron 130/80 y 160/100.
- **Alternativas:** entrar solo como variante de sensibilidad (criterio alterno «diagnóstico O presión elevada», 122 → 125); entrar a la definición principal.
- **Por qué:** la definición principal está declarada sin cambios (decisión 3) y el criterio de población es por diagnóstico. Un criterio de presión es otra definición con un umbral arbitrario: con ≥ 2 fechas, las 22 personas que fallan solo hipertensión darían 7, 3 o 0 según 130/80, 140/90 o 160/100. Impacto: +3 de 122 con el umbral habitual. Se declara como limitación que el 44 % de quienes tienen presión elevada (915 de 2,078) no tiene diagnóstico.
- **Qué quedó sin hacer:** la variante de sensibilidad. No se implementó para no añadir una definición con un umbral elegido después de ver los datos.

## 16. Intruso «Pre-eclampsia» (439393) dentro del set de hipertensión: se mantiene y se declara (actividad 7)
- **Decisión:** el set de hipertensión del lab 17 (316866 y descendientes) se **mantiene sin cambios**, y se documenta que incluye «Pre-eclampsia». Se recomienda excluir 439393 si el concept set se reutiliza en otra cohorte.
- **Alternativas:** excluir 439393 de la definición ahora (cohorte idéntica por impacto 0, pero cambia el concept set declarado del lab 17 y habría que re-ejecutar y validar contra `results.cohort`).
- **Por qué:** el impacto es 0 (62 personas de la base cumplirían el criterio solo por ese código; 0 llegan a las primeras recetas, a 2017 o a la cohorte final). Cambiar el set no mejora esta cohorte y sí modifica una definición ya declarada.
- **Decisiones menores de esta actividad** (de forma): se descartan como falsos positivos «Blood pressure within reference range» (presión normal), la microalbuminuria y la proteinuria por diabetes (complicaciones renales, no hipertensión) y «Eclampsia in pregnancy» (trastorno del embarazo, impacto 0); los otros IECA no son huérfanos porque la pregunta es lisinopril y no la clase.
- **Corrección respecto al plan:** al planear se había anotado ramipril 14, enalapril 13 y benazepril 9 como otros IECA; la consulta versionada encuentra también quinapril (2 personas).

## 17. Cómo se compara el SQL de ATLAS con el propio (actividad 8)
- **Decisión:** en lugar de leer el SQL exportado línea por línea, se **ejecuta** contra la base del lab 12 (sustituyendo `@cdm_database_schema`, `@vocabulary_database_schema`, `@target_database_schema.@target_cohort_table` y `@target_cohort_id`), con el destino en una **tabla temporal de la sesión** (`pg_temp`), y se compara persona por persona con `results.cohort` 1701. Las diferencias de código se identifican leyendo el SQL y se **miden** con `atlas_impacto.sql`. El archivo exportado no se versiona; el script avisa y sale si no existe.
- **Alternativas:** solo leer el SQL y listar casos borde (como pide el enunciado, pero sin saber si importan); comparar solo los conteos; escribir el resultado en un esquema de la base.
- **Por qué:** una lista de «diferencias» sin medir no dice cuáles importan. Ejecutarlo mostró que la entrada coincide exactamente (122 y 122, misma fecha índice) y localizó la única diferencia real (el desplazamiento de la salida). La tabla temporal garantiza que la base queda igual.
- **Corrección:** la guía de esta actividad decía «surveillance window 0», pero el SQL del lab 17 añade 30 días al fin de la exposición, y eso es el *surveillance window* de ATLAS (el *persistence window* solo une recetas). Con el *surveillance* en 30, las 122 salidas coinciden.

## 18. Las tres diferencias elegidas (actividad 8)
- **Decisión:** (A) ventanas recortadas al periodo de observación, (B) «la primera» entre eventos con observación previa y con desempate fijo, (C) saneamiento del fin de receta. Elegidas por el usuario entre cinco candidatas medidas (las otras dos: *surveillance window* separado de la brecha, y conceptos válidos solamente).
- **Por qué importan aunque aquí valgan 0:** A, B y C solo cambian la cohorte en otra fuente (registros fuera de cobertura, varios periodos de observación, fines de receta nulos); aquí el impacto medido es 0 en las tres. Una corrección a la redacción inicial: `COALESCE` solo rellena fines nulos; el `greatest(fin, inicio)` que corrige fines anteriores al inicio (83 recetas) lo hacía el SQL del lab 17 y no CIRCE.
