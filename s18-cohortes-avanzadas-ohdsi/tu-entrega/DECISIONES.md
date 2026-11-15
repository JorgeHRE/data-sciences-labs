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
