# Lab 13 — `DRUG_EXPOSURE` y `MEASUREMENT` en OMOP

Caracterización farmacoepidemiológica y de laboratorio de la base OMOP del lab 12 (Synthea convertida con
ETL-Synthea): qué tipo de exposición hay, búsqueda por ingrediente, eras y adherencia (PDC) de lisinopril,
unidades, valores implausibles, dónde dejó el ETL cada hecho clínico y cobertura del laboratorio basal.

## Archivos

| Archivo | Contenido |
|---|---|
| `farmacoepi.sql` | Todas las consultas por actividad (encabezados `-- Actividad Xy.`), con el porqué en comentarios. Crea las tablas de `results`. |
| `farmacoepi.ipynb` | 6 figuras de distribuciones (act. 2, 4, 5, 7, 8, 10). Lee `results.*` y `cdm` en solo lectura, con `assert` de las cifras del reporte. |
| `reporte_calidad.md` | Hallazgos por actividad, fuentes citadas, **limitación principal** y checklist para reutilizar Synthea. |
| `DECISIONES.md` | Las 13 decisiones del lab: qué se eligió, alternativas y por qué. |
| `figura_globulina.py` / `.png` | Figura de la actividad 7 (antes y después de normalizar). |
| `requirements.txt` | Entorno del notebook (pandas, SQLAlchemy, psycopg2, matplotlib, jupyter, python-dotenv). |

## Cómo reproducirlo

Requiere la base del lab 12 (contenedor `lab12-omop-db-1`, Postgres en `127.0.0.1:5433`, BD `omop_lab12`,
esquema `cdm`). Ver `../../s12-omop-cdm-introduccion/tu-entrega/README.md`.

```bash
# 1. Encender la base del lab 12
cd s12-omop-cdm-introduccion/tu-entrega && docker compose up -d db && cd -

# 2. Ejecutar todas las consultas (crea el esquema results y sus 8 tablas)
cd s13-omopdrug-measurement/tu-entrega
set -a; . ../../s12-omop-cdm-introduccion/tu-entrega/.env; set +a
docker exec -i lab12-omop-db-1 psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 < farmacoepi.sql
#    Un solo trozo:  sed -n '/Actividad 8a\./,$p' farmacoepi.sql | docker exec -i lab12-omop-db-1 psql ...

# 3. Notebook y figura
python -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/jupyter nbconvert --to notebook --execute --inplace farmacoepi.ipynb
.venv/bin/python figura_globulina.py
```

Tablas que crea `farmacoepi.sql` en `results`: `lisinopril_exposicion`, `lisinopril_era`,
`lisinopril_pdc_cohorte`, `lisinopril_pdc`, `globulina_normalizada`, `criterios_plausibilidad`,
`measurement_plausibilidad` y `creatinina_basal`. El esquema `cdm` no se modifica.

## Actividades

| # | Pregunta | Resultado medido |
|---|---|---|
| 1 | ¿Qué tipo de exposición hay? | Prescripciones (32838: 388,700 filas, RxNorm) y vacunas registradas en visita (32827: 78,890, CVX). No hay dispensaciones: «expuesto» = «recetado». Las act. 2-5 usan solo prescripciones. |
| 2 | Caracterizar `drug_exposure` | Top 20 de ingredientes por pacientes (vía `concept_ancestor`). `days_supply` derivado del ETL: 35.3 % ceros, 479 negativos, 41,980 recetas de exactamente 371 días. 0 fechas de fin nulas y 0 conceptos sin mapear. |
| 3 | Buscar por ingrediente | Lisinopril: búsqueda exacta 0 pacientes frente a 1,522 con descendientes (9 productos en los datos). |
| 4 | `drug_era` a mano | Gaps and islands con gap de 30 días y reglas OHDSI: 1,541 eras, idénticas era por era a `cdm.drug_era`. Mediana de 9.9 años. |
| 5 | Adherencia | PDC a un año (1,461 pacientes): principal 1.000 (100 % adherentes); sensibilidad con reglas del ETL 0.954 (65 con PDC = 0); MPR 1.060 (1,390 > 1). |
| 6 | Caracterizar `measurement` | 255 analitos, 8 con más de una unidad (5 por unidad sin mapear). Globulina: 20,412 valores «g/L» que son g/dL. 22.8 % sin valor numérico (cualitativos y cribados). `operator` 100 % = 0. |
| 7 | Normalizar unidades | Globulina a g/L con la unidad decidida por el rango del valor: 20,428 filas convertidas, 20,412 reetiquetadas. Factor de UCUM, rango de MedlinePlus, original conservado. |
| 8 | Valores implausibles | Rangos citados (DQD de OHDSI, manual de NHANES). Fuera: colesterol 2, creatinina 5,227 (2,985 con contexto renal previo), HbA1c 23,485. 0 centinelas. Se marca sin borrar; la HbA1c < 3.5 % se pone a NULL. |
| 9 | `MEASUREMENT` frente a `OBSERVATION` | 100 % de las filas en la tabla de su dominio. Peso ✔; tabaquismo con el valor solo en texto; raza en `person` y `observation` (concordancia total), con 96 personas «hawaiian»/«native» sin mapear. |
| 10 | Valor basal más cercano al índice | Creatinina antes del primer lisinopril: 208 de 1,522 (13.7 %) en [−90, 0]; 317 (20.8 %) con ±90, de los cuales 110 son posteriores al índice (fuga). |

## Decisiones principales

Detalle completo en `DECISIONES.md`.

- **Base:** el Postgres del lab 12; tablas propias en el esquema `results`, sin tocar `cdm`.
- **Solo prescripciones** para las métricas de fármacos; las vacunas se excluyen explícitamente.
- **Lisinopril** como fármaco de ejemplo (act. 3-5 y 10). Eras con las reglas OHDSI sin acumulación.
- **PDC:** índice en la primera receta, ventana de 365 días, recetas en curso extendidas hasta el fin de la observación, con las reglas del ETL como sensibilidad.
- **Globulina a g/L**, con la unidad real decidida por el valor y no por la etiqueta.
- **Marcar, no borrar:** los valores fuera de rango se clasifican y solo los imposibles por método pasan a NULL.
- **Valor basal sin valores posteriores al índice** (fuga de información); ±90 solo como contraste.

## Limitación principal

Son **datos sintéticos de prescripción** cuyas distribuciones reflejan el generador, no la práctica clínica.
Ejemplos: PDC = 1.0 en todos los pacientes, eras de ~10 años sin huecos, HbA1c imposibles en el 39.8 %, 0 valores
censurados. Sirve para construir y probar el pipeline, no para estimar parámetros clínicos. Detalle en
`reporte_calidad.md`.

## Criterios de evaluación

| Criterio | Estado | Dónde |
|---|---|---|
| Se identifica el tipo de exposición y se explica qué implica | Cumple | Reporte §1, act. 1 |
| La búsqueda por ingrediente usa `CONCEPT_ANCESTOR` y se compara con la directa | Cumple | Reporte §3 (0 frente a 1,522) |
| Las eras construidas a mano se comparan con la tabla derivada | Cumple | Reporte §4 (1,541 idénticas) |
| El PDC declara sus supuestos y se distingue de MPR | Cumple | Reporte §5, decisión 7 |
| Toda conversión de unidades cita su fuente y conserva el original | Cumple | Reporte §7 (UCUM, MedlinePlus; `valor_original`) |
| Los rangos plausibles están citados, no inventados | Cumple | Reporte §8a (DQD v2.9.1, manual de NHANES) |
| Se distinguen implausibles, centinelas y extremos reales | Cumple | Reporte §8b-8c |
| Ninguna consulta muestra `concept_id` sin `concept_name` | Cumple | Auditado: se ejecutaron las 49 sentencias y en las 32 que devuelven filas todo `concept_id` va con su nombre |
| El reporte declara la limitación principal de la base | Cumple | Reporte, «Limitación principal de la base» |

**Bono (opcional, no hecho):** Achilles o Data Quality Dashboard, y `condition_era` con el mismo patrón.

Son datos sintéticos: ningún resultado describe pacientes reales.
