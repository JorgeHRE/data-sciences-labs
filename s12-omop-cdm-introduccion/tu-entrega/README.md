# Lab 12 — Introducción al OMOP CDM

Conversión de los CSV de Synthea del lab 10 al **OMOP CDM v5.4** con ETL-Synthea, carga de los
vocabularios de ATHENA y medición de la calidad del resultado: qué se mapeó, qué se perdió y por qué.
La base no se sube a git; este directorio documenta cómo reconstruirla y qué se midió en ella.

## Archivos

| Archivo | Contenido |
|---|---|
| `consultas_omop.sql` | Todas las consultas, por actividad (5 a 10), con el porqué en comentarios y el resultado esperado |
| `reporte_calidad.md` | Hallazgos de calidad: no mapeados por dominio, completitud contra la fuente, población, estándar contra origen, `observation_period`, ATHENA y bases de referencia |
| `diagrama_er.md` | Diagrama ER (Mermaid) del CDM cargado, generado desde `information_schema` y comparado con la v5.4 |
| `DECISIONES.md` | Las 32 decisiones del lab: opciones, la elegida y por qué |
| `compose.yml`, `.env.example` | Postgres 16.15 propio del lab (puerto 5433) y el servicio `etl` |
| `sql/`, `cargar_vocab.sh` | DDL, carga e índices de los vocabularios (actividad 3) |
| `etl/` | Imagen de ETL-Synthea, script de conversión y su `README.md` (versiones, pasos, problemas) |
| `referencia/cargar_referencia.sh` | Descarga y carga de GiBleed y MIMIC-IV demo (actividad 10) |

## Cómo reproducirlo

Desde `s12-omop-cdm-introduccion/tu-entrega/`, con Docker:

```bash
cp .env.example .env                 # y pon una contraseña
docker compose up -d db              # Postgres 16.15 en 127.0.0.1:5433

# 1. Vocabularios (actividad 3). Requiere una descarga propia de ATHENA (licencia: no se
#    redistribuye) extraída en vocab/completo/: SNOMED, ICD10CM, RxNorm, LOINC, ATC, CVX,
#    Gender, Race y Ethnicity.
docker compose exec -T db psql -U omop -d omop_lab12 < sql/01_ddl_vocabularios.sql
./cargar_vocab.sh concept concept_relationship concept_ancestor concept_synonym \
                  vocabulary domain concept_class relationship drug_strength
docker compose exec -T db psql -U omop -d omop_lab12 < sql/02_indices_vocabularios.sql

# 2. Conversión (actividad 2): ~45 min; construye la imagen la primera vez.
docker compose run --rm etl

# 3. Bases de referencia (actividad 10): ~17 MB.
bash referencia/cargar_referencia.sh
```

Las consultas se ejecutan con `psql` sobre la misma base, por ejemplo
`docker compose exec -T db psql -U omop -d omop_lab12 -f -  < consultas_omop.sql`.
Para detener la base sin perder los datos: `docker compose down` (sin `-v`).

**Entrada:** CSV de Synthea v3.3.0 del lab 10 (5,000 vivos + 904 fallecidos = 5,904 pacientes) en
`../../s10-sql-fundamentals/tu-entrega/data/synthea/csv/`, montados en solo lectura.
**Versiones:** ETL-Synthea v2.1.1, CommonDataModel v5.4.3, R 4.5.3, Postgres 16.15, vocabularios
ATHENA v5.0 de 29-AUG-26. Detalle en `etl/README.md`.

Son datos sintéticos: ningún resultado describe pacientes reales, salvo los de MIMIC-IV demo
(actividad 10), que son reales y anonimizados.

## Actividades

| # | Pregunta | Resultado medido |
|---|---|---|
| 1 | ¿Qué ruta de conversión usar? | ETL-Synthea (R). dbt-synthea solo admite Synthea 3.0.0 y los CSV son 3.3.0; un mapeo a mano cubriría un solo dominio. Vocabularios antes que la conversión (orden 3 → 2). |
| 2 | Convertir Synthea a OMOP | 43 min, sin errores. `person` 5,904 · `visit_occurrence` 385,971 · `condition_occurrence` 101,699 · `measurement` 4,008,280 · `observation` 1,929,625 · `drug_exposure` 467,590 · `procedure_occurrence` 454,821 · `death` 829. `cost` omitida (su INSERT no terminó en 70 min). |
| 3 | Cargar los vocabularios | 2,028,013 conceptos (847,999 estándar), 14,138,100 relaciones, 12,077,497 pares de ancestros, 46 vocabularios. La primera descarga no traía Gender, Race, Ethnicity ni CVX; se repitió. |
| 4 | Diagrama ER contra la v5.4 | 14 tablas y 81 columnas verificadas contra `information_schema`. Dos diferencias: 0 llaves foráneas declaradas y `cost` vacía. |
| 5 | % de `concept_id = 0` por dominio | ~0 % en todos los dominios, **pero no mide completitud**: ETL-Synthea descarta lo que no mapea. Cuadrando la fuente con el CDM se perdieron 343,190 de 7,314,310 filas (4.7 %); `procedures` 19.3 %, `immunizations` 8.3 % (todas las vacunas COVID). Cuatro causas diagnosticadas. |
| 6 | Describir la población | 5,904 personas (50.3 % hombres), nacidas entre 1916 y 2026; observación mediana de 31.6 años. Top 1: Gingivitis (82.8 %). Visitas por persona: media 65.4, mediana 37. |
| 7 | Estándar contra origen | Dental caries: 4,721 registros por concepto estándar frente a 3,498 (SNOMED) + 1,223 (ICD-10) por código de origen. Con descendientes (`concept_ancestor`): 5,482. |
| 8 | Respetar `observation_period` | 101,699 condiciones sin filtrar, 101,085 dentro (0.60 % fuera). Los 614 de fuera son un desfase de zona horaria de Synthea (encuentros en UTC, condiciones en fecha local). |
| 9 | Explorar en ATHENA | Los hijos SNOMED coinciden con ATHENA (27, 8, 35); las diferencias son vocabularios no descargados. Synthea genera códigos SNOMED ya retirados; 1,230 filas perdidas serían recuperables. |
| 10 | Comparar con una base de referencia | Frente a GiBleed (Synthea 2019) la conversión es equivalente y más íntegra; frente a MIMIC-IV demo (real) el contenido es claramente sintético: observación de 65 días frente a décadas. |

## Decisiones principales

El registro completo está en `DECISIONES.md`. Las que más cambian los resultados:

- **Medir completitud contra la fuente, no solo contar ceros (16):** los ceros daban ~0 % y ocultaban
  un 4.7 % de filas perdidas.
- **Documentar los fallos del ETL, no corregirlos (18):** volver a correrlo tarda 43 min y ETL-Synthea
  no es determinista (+33 visitas entre corridas, decisión 11).
- **Contar personas, no registros (23):** `count(DISTINCT person_id)` en el top 20; con registros, el
  embarazo sube del puesto 20 al 9.
- **Denominador de toda la población, ceros incluidos (24):** `CROSS JOIN` persona × tipo más `LEFT JOIN`
  y `count(columna)`; con `count(*)` se inventan 4,523 visitas.
- **Regla estricta para `observation_period` (26)** y `LEFT JOIN` para que un evento sin periodo cuente
  como fuera en lugar de desaparecer.
- **Dos bases de referencia, sintética y real (32),** porque GiBleed solo compara Synthea con Synthea.

## Hallazgos que cambiaron el plan

- **Faltaban vocabularios (act. 3):** ATHENA solo exporta una relación si ambos conceptos están en la
  descarga; sin CVX ni Gender, el ETL habría dejado sin concepto el sexo y las vacunas.
- **Ceros iniciales perdidos (act. 2):** la carga de ETL-Synthea convierte `08` en `8` (2,866 vacunas).
  Lo detectó la comparación de valores, no el conteo de filas.
- **Los ceros no miden completitud (act. 5):** motivó cuadrar cada tabla de origen contra el CDM.
- **La caries tiene hijos (act. 7):** el concepto estándar no incluye a sus descendientes; sin
  `concept_ancestor` faltaban 339 personas.
- **Corrección propia (act. 8):** dije que algunas condiciones caían "hasta 16 años antes" del periodo;
  era un error de la consulta (mezclaba inicio y fin). Todas caen exactamente 1 día antes.

## Limitaciones

- Datos sintéticos: prevalencias, visitas y duración de la observación reflejan el simulador.
- Las cuadraturas de la act. 5 son aritméticas (conteos y distribuciones), no fila a fila.
- `cost` está vacía y `careplans`, `imaging_studies` y `supplies` no los lee el ETL.
- Sin confirmar: que los códigos `D####` sean CDT; que las fechas locales de Synthea sean de EE. UU.;
  cómo se recortó GiBleed.
- La comparación con MIMIC-IV demo es cualitativa: 100 pacientes de UCI.

## Revisión de los criterios de evaluación

| Criterio | Estado | Dónde / excepciones |
|---|---|---|
| La conversión está documentada y es reproducible | Cumple, con un límite declarado | `etl/README.md` y este README: comandos, versiones, pasos y problemas. Dos corridas idénticas difieren en 33 visitas (0.009 %) porque ETL-Synthea no es determinista (decisión 11). |
| Los vocabularios están cargados y se reporta cuántos conceptos hay | Cumple | 2,028,013 conceptos (847,999 estándar), 46 vocabularios; `cargar_vocab.sh` compara filas del archivo y de la tabla. Actividad 3, decisiones 1-7. |
| El diagrama ER se comparó con la especificación oficial | Cumple | `diagrama_er.md`: columnas verificadas por script contra `information_schema`; diferencias con la v5.4 (0 FK, `cost` vacía). Decisiones 12-14. |
| El % de `concept_id = 0` se reporta por dominio, con diagnóstico | Cumple | `reporte_calidad.md` secciones 1-2: estándar y `*_source_concept_id` por dominio, y cuadratura contra la fuente con cuatro causas. |
| Ninguna consulta muestra `concept_id` sin su `concept_name` | Cumple, con una excepción | Todas las salidas con un `concept_id` llevan su nombre. Excepción: 4 tipos de visita de MIMIC (10d) no tienen nombre en ningún vocabulario disponible; se muestra el id (decisión 31). |
| Toda consulta epidemiológica usa `count(DISTINCT person_id)` | Cumple | Todas las cifras de personas. Los conteos de eventos (registros, visitas, filas fuera del periodo) usan `count(*)` a propósito, porque la pregunta es por eventos. |
| El efecto de `observation_period` está cuantificado | Cumple | Sección 7: 0.60 % de condiciones fuera, con su causa; sección 9: 65 días de observación en MIMIC frente a décadas. |
| La diferencia entre conteo estándar y por origen está explicada | Cumple | Sección 6: dos orígenes → un concepto, 83 personas con ambos códigos, descendientes y multi-mapeo. |
| Los hallazgos de ATHENA están documentados | Cumple | Sección 8: tabla de los tres conceptos comparada con la web y causa de los 27 códigos sin destino. |

Ajustes de esta revisión: en 7 consultas los conteos de personas pasaron de `count(*)` a
`count(DISTINCT person_id)` y la consulta de raza muestra el nombre del concepto 0. Se ejecutó
`consultas_omop.sql` completo antes y después (sin errores, ~6 s): las salidas solo difieren en la
columna nueva y en un encabezado; todas las cifras son idénticas.
