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
