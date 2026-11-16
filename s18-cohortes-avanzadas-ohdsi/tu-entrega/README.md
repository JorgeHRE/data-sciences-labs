# Lab 18 — Auditoría de una definición de cohorte

Auditoría de las cohortes de **nuevos usuarios de lisinopril** (1701) y **amlodipino** (1702) con hipertensión, construidas en el lab 17 sobre la base OMOP sintética del lab 12 (PostgreSQL, vocabulario ATHENA v5.0 29-AUG-26). Todo es de **solo lectura** sobre `cdm` y `results.cohort`: no se modifica ninguna cohorte. El entregable es [`diagnostico_cohorte.md`](diagnostico_cohorte.md); las decisiones están en [`DECISIONES.md`](DECISIONES.md) (22).

**Resultado en una línea por pregunta**

- **¿Es factible estudiar demencia con estas cohortes?** No: 0 eventos de demencia incidente en 122 personas (lisinopril); la regla de ~10 eventos por variable pide al menos 10 (sección 1).
- **¿Qué decisión de diseño pesa más?** El inicio de estudio en 2017: sin él, la cohorte pasa de 122 a 242 personas. El lavado mueve a lo sumo una persona y el orden de los criterios no cambia el N final (secciones 3, 9 y 11).
- **Definición principal declarada en el paso 0:** cohorte 1701, lavado de 365 días, inicio de estudio 2017-01-01.

## Criterios de evaluación y dónde se cumple cada uno

| Criterio del enunciado | Dónde |
|---|---|
| Los tres conteos de factibilidad, y se discute el de **eventos** | sección 1 (`factibilidad.sql`) |
| La tabla de atrición suma y el orden está declarado | sección 2 (`atricion_lab17.md`) |
| El N final no cambia al reordenar criterios | sección 3 (`atricion_ordenes.md`; el script se detiene si cambia) |
| Diagrama de flujo presentable | sección 4 (`figura_consort_1701.png`, `figura_consort_1702.png`) |
| La incidencia se interpreta como información sobre **los datos** | sección 5 (`figura_incidencia_anio.png`, `figura_incidencia_edad.png`) |
| Huérfanos: al menos un candidato real, con decisión escrita | sección 7 (presión arterial elevada sin diagnóstico: no entra y se declara; decisión 15) |
| Tres casos borde que CIRCE cubre y mi implementación no | sección 8 (`comparacion_atlas.md`) |
| Las tres variantes están anidadas | sección 10 (`tabla_traslape.py` falla si no se cumple) |
| La definición principal se declara y se justifica | secciones 9 y 11; decisiones 3, 19 y 20 |
| La discusión reconoce limitaciones propias | sección 11 |
| Código versionado con commits descriptivos | un PR por actividad (`lab18: …`) |

## Archivos

| Archivo | Contenido |
|---|---|
| `diagnostico_cohorte.md` | El entregable: las 11 secciones (factibilidad, atrición en dos órdenes, diagrama, incidencia, códigos del índice, huérfanos, ATLAS/CIRCE, variantes, traslape, discusión). |
| `DECISIONES.md` | Las 22 decisiones: qué se eligió, qué alternativas había y por qué. |
| `factibilidad.sql` | Los tres conteos de factibilidad y las pruebas del cero (actividad 1). |
| `atricion.sql`, `orden_lab17.sql`, `orden_b.sql`, `consulta_atricion.sql` | Banderas por persona (un `true/false` por criterio, entre `-- [INICIO banderas]` y `-- [FIN banderas]`), los dos órdenes y la consulta de atrición acumulada (actividades 2 y 3). |
| `consulta_aislado.sql`, `consulta_marginal.sql`, `contraejemplo_indice.sql`, `validacion_banderas.sql` | Pérdida de cada criterio aislado, costo marginal, qué **no** es reordenar (filtrar antes de la primera receta) y comprobación de las banderas contra `results.cohort` persona por persona. |
| `tabla_atricion.py`, `tabla_orden.py`, `figura_consort.py` | Generan `atricion_lab17.md`, `atricion_ordenes.md` y las dos figuras de flujo. |
| `incidencia.sql`, `control_fin_observacion.sql`, `figura_incidencia.py` | Incidencia por año y edad (dos denominadores), control de cómo termina `observation_period`; genera `incidencia_tablas.md` y las dos figuras. |
| `codigos_indice.sql`, `tabla_codigos.py` | Qué códigos metieron a la gente; genera `codigos_indice.md`. |
| `huerfanos*.sql`, `tabla_huerfanos.py` | Conceptos huérfanos y su impacto en la cohorte; genera `huerfanos.md`. |
| `atlas_impacto.sql`, `comparar_atlas.py` | Ejecuta el SQL exportado de ATLAS contra la base (tabla temporal) y lo compara con `results.cohort`; genera `comparacion_atlas.md`. |
| `variantes.sql`, `variantes_caracterizacion.sql`, `tabla_variantes.py` | Las variantes de lavado de 180, 365 y 730 días y su caracterización; genera `variantes_tablas.md`. |
| `tabla_traslape.py` | Traslape y anidamiento de las variantes; genera `traslape_tablas.md` y `figura_traslape.png`. |
| `atricion_lib.py` | Utilidades compartidas (conexión de solo lectura, lectura de SQL). |
| `requirements.txt` | Dependencias de Python. |

## Cómo reproducirlo

Requiere la base del lab 12 encendida con el vocabulario cargado (contenedor `lab12-omop-db-1`, credenciales en `../../s12-omop-cdm-introduccion/tu-entrega/.env`) y el `results.cohort` del lab 17. **No crea objetos persistentes**: las variantes y la ejecución del SQL de ATLAS usan tablas temporales de la sesión.

```bash
# desde la raíz del repo
cd s12-omop-cdm-introduccion/tu-entrega && docker compose up -d && cd -
T=s18-cohortes-avanzadas-ohdsi/tu-entrega

# entorno de Python (el .venv no se versiona)
python3 -m venv $T/.venv && $T/.venv/bin/pip install -r $T/requirements.txt

# todas las tablas y figuras (~1.5 min en total; cada script se detiene si una cifra cambia)
for f in tabla_atricion tabla_orden figura_consort figura_incidencia tabla_codigos \
         tabla_huerfanos comparar_atlas tabla_variantes tabla_traslape; do
  $T/.venv/bin/python $T/$f.py
done

# SQL que corre solo, con psql (factibilidad, control de observación, atrición)
set -a; . s12-omop-cdm-introduccion/tu-entrega/.env; set +a
PSQL="docker exec -i lab12-omop-db-1 psql -U $POSTGRES_USER -d $POSTGRES_DB -v ON_ERROR_STOP=1"
$PSQL < $T/factibilidad.sql
$PSQL < $T/control_fin_observacion.sql
$PSQL < $T/atricion.sql
# validación de las banderas contra results.cohort (esperado: 0 y 0 en solo_banderas y solo_lab17)
cat <(sed -n '/^-- \[INICIO banderas\]/,/^-- \[FIN banderas\]/p' $T/atricion.sql) $T/validacion_banderas.sql | $PSQL
```

**Un archivo no se versiona:** `atlas_export.sql`, el SQL que ATLAS exporta (el enunciado pide no copiarlo; está en `.gitignore`). Sin él, `comparar_atlas.py` avisa y sale sin escribir nada; todo lo demás corre igual. Para regenerarlo hay que reconstruir la cohorte en la demo pública (atlas-demo.ohdsi.org) y exportarlo desde la pestaña *Export → SQL*.

Comprobado el 2026-11-16: los nueve scripts de Python terminan sin errores y regeneran sus archivos **sin cambios** (`git status` limpio); `factibilidad.sql`, `control_fin_observacion.sql`, `atricion.sql`, `incidencia.sql` y `codigos_indice.sql` corren con `exit 0`; la validación de banderas da 0 y 0 en las diferencias (122 y 81 personas en ambas).

## Qué no se hizo

Los extras opcionales del enunciado (CohortDiagnostics, protocolo HARPER, LEGEND) no se hicieron. Tampoco se comparó con la definición de la Phenotype Library de OHDSI: la definición propia se audita contra sí misma y contra el SQL de ATLAS, no contra una definición validada por la comunidad.
