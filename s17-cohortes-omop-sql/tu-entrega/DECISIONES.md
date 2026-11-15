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
