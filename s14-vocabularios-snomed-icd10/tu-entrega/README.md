# Lab 14 — Construir y defender un concept set: diabetes mellitus tipo 2

Definición de la **diabetes mellitus tipo 2 (T2DM)** con vocabularios estándar OMOP (SNOMED CT e ICD-10-CM), medición de cuánto cambia la cohorte según la definición y justificación escrita de cada decisión. Pregunta de investigación: **uso de la metformina en pacientes con T2DM**; el concept set se reutiliza en la sesión 17 para construir la cohorte.

## Archivos

| Archivo | Contenido |
|---|---|
| `concept_set.sql` | Todo el lab, por actividad (encabezados `-- Actividad Xy.`), con el porqué en comentarios. Crea la vista `results.cs_t2dm` y la tabla `results.cs_t2dm_exclusiones`; el esquema `cdm` no se modifica. |
| `justificacion_concept_set.md` | **Entregable principal**: condición y pregunta, semilla, traducción ICD-10-CM, las tres versiones, impacto en pacientes, revisión manual, tabla de decisiones y discusión de sensibilidad frente a VPP. |
| `figura_impacto.py` / `.png` | Gráfica de pacientes distintos por versión. Lee la vista en modo solo lectura y comprueba las cifras con `assert`. |
| `DECISIONES.md` | Las 10 decisiones del lab: qué se eligió, qué alternativas había y por qué. |
| `requirements.txt` | Entorno de la figura (pandas, SQLAlchemy, psycopg2, matplotlib, python-dotenv, jupysql, jupyter). |

## Cómo reproducirlo

Requiere la base del lab 12 con el vocabulario de ATHENA cargado (contenedor `lab12-omop-db-1`, Postgres en `127.0.0.1:5433`, BD `omop_lab12`, esquema `cdm`). Ver `../../s12-omop-cdm-introduccion/tu-entrega/README.md`.

```bash
# 1. Encender la base del lab 12
cd s12-omop-cdm-introduccion/tu-entrega && docker compose up -d db && cd -

# 2. Ejecutar todo el concept set de principio a fin (~3 s; se puede repetir)
set -a; . s12-omop-cdm-introduccion/tu-entrega/.env; set +a
docker exec -i lab12-omop-db-1 psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 \
  < s14-vocabularios-snomed-icd10/tu-entrega/concept_set.sql
#    Un solo trozo:  sed -n '/Actividad 5a\./,$p' …/concept_set.sql | docker exec -i lab12-omop-db-1 psql …

# 3. Figura
cd s14-vocabularios-snomed-icd10/tu-entrega
python -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python figura_impacto.py
```

Comprobado el 2026-11-11: borrando la vista y la tabla de exclusiones y ejecutando `concept_set.sql` completo, todo se reconstruye sin errores (C = 131 conceptos, 1,085 pacientes).

## Actividades

| # | Pregunta | Resultado medido |
|---|---|---|
| 0 | ¿El vocabulario está completo? | `concept_ancestor` 12,077,497 filas; las 587,392 aristas «Is a» entre SNOMED estándar tienen su pareja (0 faltantes). Vocabulario v5.0 29-AUG-26. |
| 1 | Condición | T2DM: 444 pacientes distintos con `201826` (una fila por paciente). Pregunta: uso de metformina, error prioritario = falsos positivos. |
| 2 | Semilla | `201826` Type 2 diabetes mellitus: SNOMED, Condition, Disorder, estándar, vigente. Padre `201820`; 14 descendientes. Las complicaciones cuelgan de un hermano, `443732`. |
| 3 | ICD-10-CM → estándar | 16 códigos con `'Maps to'` y los cuatro filtros: 10 mapean a más de un estándar, 1 a ninguno (E11.640, retirado). Categoría E11: 113 de 118 son 1:N. Todos los destinos de complicación caen en la rama `443732`. |
| 4 | Tres versiones | Vista `results.cs_t2dm`: A 1 concepto, B 15, C 131 (semilla + rama `443732` − 3 exclusiones con sus descendientes). |
| 5 | Impacto en pacientes | A 444 · B 444 (+0 %) · C 1,085 (+144.4 %). Prevalencia bruta sobre 5,904 personas: 7.5 % · 7.5 % · 18.4 %. |
| 6 | Revisión manual | 14 de B (todos) + 20 de la rama con muestra reproducible por `md5`. Falsos positivos: 3/14 (embarazo ×2, remisión) y 0/20. |
| 7 | Justificación | Tabla de 3 exclusiones, 4 inclusiones no obvias y 5 conceptos no añadidos. Los 641 pacientes que entran solo por la rama no se comportan como diabéticos en Synthea (0 con metformina, 1 con HbA1c ≥ 6.5 %). |

## Decisiones principales

Detalle completo en `DECISIONES.md`.

- **Semilla única `201826` y rama de complicaciones solo en C** (decisión 4): la jerarquía de SNOMED no coincide con la definición clínica; «semilla + descendientes» no recoge las complicaciones «due to type 2 diabetes».
- **La traducción ICD-10-CM audita el concept set, no lo construye** (decisión 5): construirlo desde ICD metería «First trimester pregnancy», «Diabetes mellitus» y «Prediabetes».
- **Vista + tabla de exclusiones con motivo** (decisión 6): el concept set es una regla que se recalcula desde el vocabulario; las únicas IDs escritas a mano son las exclusiones, cada una con su razón clínica.
- **Exclusiones: embarazo y remisión** (decisión 9); se mantienen la T2DM tratada con insulina, la controlada con dieta y «Pre-existing T2DM».
- **C se mantiene pese al artefacto de Synthea** (decisión 10): para la cohorte de la sesión 17 se exigirá una segunda evidencia, que no puede ser la metformina (sería circular).

## Limitación principal

Los datos son **sintéticos** (Synthea). Las diferencias entre versiones dependen de cómo el simulador genera los diagnósticos: los 14 descendientes de la semilla no tienen ningún paciente (A = B), y la rama de complicaciones mete 641 pacientes sin metformina y casi sin HbA1c diagnóstica. Además no hay historias clínicas para medir el VPP. La base sirve para validar el método, no para estimar la prevalencia ni el uso real de la metformina.

## Revisión de los criterios de evaluación

| Criterio | Estado | Dónde |
|---|---|---|
| El concepto semilla es estándar, del dominio correcto y está vigente | Cumple | `concept_set.sql` 2a; justificación §2 |
| La traducción de ICD-10 usa `'Maps to'` con los cuatro filtros y reporta los casos 1:N | Cumple | `concept_set.sql` 3a-3c; justificación §3 |
| Las tres versiones son reproducibles desde SQL, no listas pegadas a mano | Cumple | Vista `results.cs_t2dm` (4a); reconstrucción desde cero comprobada |
| Se reporta el impacto numérico de cada decisión en pacientes distintos | Cumple | 5a-5d, 6c, 7a-7b; justificación §5-§7 |
| Cada exclusión tiene una justificación clínica escrita | Cumple | Justificación §7; columna `motivo` de `results.cs_t2dm_exclusiones` |
| La discusión de sensibilidad vs VPP está conectada con la pregunta de investigación | Cumple | Justificación §7, «Sensibilidad y valor predictivo positivo» |
| El código está versionado con commits descriptivos | Cumple | Un PR por actividad (#81-#88) con títulos `lab14: …` |

**Bono (opcional):** pendiente de decidir (comparación con la OHDSI Phenotype Library y actividad 5 sobre `condition_era`).
