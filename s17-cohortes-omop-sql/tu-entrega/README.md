# Lab 17 — Cohorte de nuevo usuario en OMOP con SQL

Cohortes de **nuevos usuarios de lisinopril** (IECA) y de **amlodipino** (calcioantagonista) con hipertensión, construidas solo con SQL sobre la base OMOP sintética del lab 12 (PostgreSQL, vocabulario ATHENA v5.0 29-AUG-26). El desenlace de interés es la demencia incidente. Se definen evento inicial, observación previa, lavado, criterios, salida y censura; se insertan en `results.cohort`, se mide la atrición, se caracterizan y se revisa el immortal time.

**Resultado:** 122 personas de lisinopril y 81 de amlodipino (8.0 % y 7.3 % de quienes tenían un evento inicial). En ellas hay **0 demencias incidentes** en 373 y 216 años-persona, así que esta base **no permite estudiar el desenlace**. Se reporta así; no se aflojó ningún criterio para conseguir casos.

## Entregables

| Archivo | Contenido |
|---|---|
| `cohorte_definicion.md` | La definición en prosa: pregunta, PICOT, justificación de cada ventana, los cuatro componentes y los resultados de cada actividad (incluida la revisión de immortal time, actividad 10). |
| `cohorte_definicion.sql` | La definición en SQL: controles de `observation_period` (paso 0), tabla de parámetros y **una sola sentencia `WITH`** con un CTE por componente, entre los marcadores `-- [INICIO cohorte]` y `-- [FIN cohorte]`; cada CTE explica el porqué de su ventana y el resultado obtenido. |
| `atricion.md` | Tabla de atrición paso a paso (generada por SQL, copiada por script) y análisis del criterio más costoso. |
| `caracterizacion.md` | Tabla 1 de las dos cohortes con SMD y la figura del seguimiento (`figura_seguimiento.png`). |
| `DECISIONES.md` | Las **20 decisiones** del lab: qué se eligió, qué alternativas había y por qué. |
| `insertar_cohorte.sql` / `insertar_cohorte.sh` | Plantilla del `INSERT` y script que la une con la cadena de CTE y la corre dentro de una transacción (actividad 7). |
| `distribucion_salida.sql` | Duración del seguimiento por motivo de salida, con las validaciones (actividad 6). |
| `caracterizacion.sql`, `tabla1.py`, `tabla1.md` | Consultas, script y salida de la tabla 1 (actividad 9). |
| `figura_primeras_recetas.py` / `.png` | Primeras recetas por año antes y después de los filtros de entrada (actividad 3); la figura se muestra en `cohorte_definicion.md`. |
| `inmortal_time.sql` | Comprobaciones con datos de la actividad 10. |
| `requirements.txt` | Dependencias de los dos scripts de Python. |
| `README.md` | Este archivo. |

## Cómo reproducirlo

Requiere la base del lab 12 con el vocabulario cargado (contenedor `lab12-omop-db-1`, credenciales en `../../s12-omop-cdm-introduccion/tu-entrega/.env`). El esquema `cdm` solo se lee. El lab crea **dos objetos** en `results`: `cohorte_parametros` (al correr `cohorte_definicion.sql`, re-ejecutable) y `cohort` (al correr `insertar_cohorte.sh`).

```bash
# 1. Encender la base del lab 12
cd s12-omop-cdm-introduccion/tu-entrega && docker compose up -d && cd -
set -a; . s12-omop-cdm-introduccion/tu-entrega/.env; set +a
T=s17-cohortes-omop-sql/tu-entrega
PSQL="docker exec -i lab12-omop-db-1 psql -U $POSTGRES_USER -d $POSTGRES_DB -v ON_ERROR_STOP=1"

# 2. Todo el SQL de definición (controles, parámetros, cadena de CTE y atrición; ~26 s)
$PSQL < $T/cohorte_definicion.sql

# 3. Solo la cadena de CTE de la cohorte (sin controles), con su SELECT de atrición
sed -n '/^-- \[INICIO cohorte\]/,/^-- \[FIN cohorte\]/p' $T/cohorte_definicion.sql | $PSQL

# 4. Insertar las cuatro cohortes en results.cohort (576 filas; DELETE + INSERT en una transacción)
$T/insertar_cohorte.sh

# 5. Consultas que se pegan a la misma cadena de CTE (cada una añade UN SELECT)
for f in distribucion_salida inmortal_time; do
  sed -n '/^-- \[INICIO cohorte\]/,/^-- \[CONTEO\]/p' $T/cohorte_definicion.sql | cat - $T/$f.sql | $PSQL
done

# 6. Tabla 1 y figuras (solo lectura; ver «Entorno de Python»)
$T/.venv/bin/python $T/tabla1.py
$T/.venv/bin/python $T/figura_primeras_recetas.py
```

**Entorno de Python:** el `.venv` no se versiona. Para crearlo: `python3 -m venv $T/.venv && $T/.venv/bin/pip install -r $T/requirements.txt`. Los scripts leen la conexión del `.env` del lab 12.

Comprobado el 2026-11-15: `cohorte_definicion.sql` completo corre sin errores (`exit 0`, 26 s); `results.cohort` tiene 122 / 81 / 242 / 131 filas (1701 / 1702 / 1711 / 1712); `tabla1.py` y `figura_primeras_recetas.py` regeneran sus archivos sin cambios.

**Las cuatro cohortes.** 1701 lisinopril y 1702 amlodipino son la definición principal (índice desde 2017-01-01). 1711 y 1712 son las mismas sin ese inicio de estudio: un análisis de sensibilidad para ver cuánto pesa esa decisión, no resultados.

## La definición, en una línea por componente

| Componente | Definición |
|---|---|
| Evento inicial | Primera receta del fármaco en toda la historia (cualquier producto con el ingrediente, vía `concept_ancestor`); fecha índice ≥ 2017-01-01. |
| Observación previa | El **mismo** periodo contiene el índice y empieza ≥ 365 días antes. |
| Lavado | Ninguna exposición activa en [−365, −1] (por fin de receta, no solo por inicio). |
| Inclusión | Edad ≥ 18 en el índice; hipertensión en (−∞, 0]; ≥ 2 visitas en [−365, −1]. |
| Exclusión | Demencia en (−∞, 0]; el otro fármaco en (−∞, 0]; producto combinado en el índice. |
| Salida | El **mínimo** entre fin del tramo continuo (hueco ≤ 30 d) + 30 d, inicio del otro fármaco y fin de la observación. |

## Resultados por actividad

Cifras de lisinopril / amlodipino en la definición principal.

| # | Actividad | Resultado |
|---|---|---|
| 0 | Controles de `observation_period` | 1 periodo por persona (5,904), mediana de 31.6 años y empieza en la primera visita: el filtro de 365 días no quita a nadie. En 2005-2013 solo 27-38 % de las personas «observadas» tienen visita en el año. 614 diagnósticos caen antes del periodo. |
| 1 | Definición en prosa y PICOT | Lisinopril contra amlodipino, desenlace demencia incidente. 507 personas inician los dos el mismo día. |
| 2 | Evento inicial | 1,522 / 1,104 personas con primera receta. Parámetros en `results.cohorte_parametros`. |
| 3 | Observación previa | Quita 0 por construcción. Se añade el inicio de estudio 2017 (pico de 665 / 545 primeras recetas en 2016, probable artefacto de registro): 346 / 238. |
| 4 | Lavado | Quita 0 por construcción (el índice es la primera receta de la historia). Medido en un índice más flojo: el lavado por exposición activa deja 348 / 238; solo mirar el inicio dejaría 1,125 / 847. |
| 5 | Inclusión y exclusión | 346 → 320 (HTA) → 173 (≥ 2 visitas) → 172 (demencia) → **122** (otro fármaco) → 122 (combinación). Para amlodipino: 238 → 237 → 165 → 164 → **81** → 81. |
| 6 | Salida | Seguimiento mediano de 928 y 401 días; el 33 % y el 32 % salen por empezar el otro fármaco (mediana de 30 días). 0 salidas fuera de rango. |
| 7 | `results.cohort` | 576 filas, con clave primaria y `CHECK`; 0 fechas fuera del periodo de observación. |
| 8 | Atrición | Lo más costoso es el inicio de estudio (77 % y 78 %); entre los clínicos, las visitas (lisinopril) y el otro fármaco (amlodipino). **0 demencias incidentes** en las cohortes finales (3 y 2 en la sensibilidad). |
| 9 | Caracterización | Cohortes jóvenes (mediana de 40 y 44 años), ~58 % mujeres; 8 de 17 filas con \|SMD\| > 0.1, pero con N = 122 / 81 el SMD es ruidoso (error típico ≈ 0.14). El 42 % y el 41 % salen en los primeros 6 meses. |
| 10 | Immortal time | **No hay**: ningún criterio de entrada mira después del día 0 y la exposición se fija en el índice. El 60 % y el 53 % cumplen la HTA solo por un diagnóstico del día 0, que se mantiene y se reporta como limitación (decisión 20). |

## Criterios de evaluación

| Criterio | Dónde y cómo se cumple |
|---|---|
| La definición en prosa coincide con el SQL | `cohorte_definicion.md` y `cohorte_definicion.sql` usan las mismas ventanas, criterio por criterio. Una diferencia documentada: el filtro de edad del SQL usa el año (año del índice − `year_of_birth`); la edad **exacta** se usa solo en la tabla 1 (decisión 19). |
| Cada ventana tiene justificación escrita | `cohorte_definicion.md`, «Por qué estas ventanas» y cada criterio; además comentarios en cada CTE. |
| Observación previa y lavado, por separado | Dos CTE (`obs_previa`, `lavado`) y dos filas en `atricion.md` (las dos quitan 0, y se explica por qué). |
| Todos los criterios respetan `OBSERVATION_PERIOD` | **Parcial, a propósito.** Las ventanas acotadas ([−365, −1]) caen dentro del periodo porque `obs_previa` exige que empiece ≥ 365 días antes del índice; la salida se corta en `op_fin`. Las ventanas abiertas (−∞, 0] de HTA, demencia y otro fármaco miran toda la historia, también la anterior al periodo (el control 0b encontró 614 diagnósticos fuera). |
| `EXISTS` / `NOT EXISTS`, no `JOIN`, salvo agregación | Lavado, HTA, demencia, otro fármaco y combinación usan `EXISTS` / `NOT EXISTS`. Tres `JOIN` justificados: visitas (hay que contar: `GROUP BY` + `HAVING`), `obs_previa` (se necesita `op_fin` para la salida) y edad (`person` por clave primaria, 1 fila por persona). |
| La salida es el mínimo entre la definición y el fin de observación | CTE `salida`: `least(fin_tramo + 30, op_fin, fecha_otro)`; validado con 0 salidas antes del índice y 0 después de `op_fin`. |
| Atrición completa y criterio más costoso | `atricion.md`: 12 pasos por cohorte, el inicio de estudio (77 %) y el criterio clínico más costoso en cada cohorte. |
| La edad se calcula en la fecha índice | Filtro: año del índice − `year_of_birth`. Tabla 1: año, mes y día contra la fecha índice (cambia de grupo 1 persona de 203). |
| Se revisó el immortal time | Actividad 10: `cohorte_definicion.md` (tabla de ventanas), `inmortal_time.sql` y decisión 20. |
| Código versionado con commits descriptivos | Un PR por actividad (#111 a #121), commits `feat(s17): …`. |

## Limitaciones

- **Sin poder para el desenlace.** 0 demencias incidentes en las cohortes finales. Las cohortes son jóvenes (mediana de 40 y 44 años), lo que explica en parte por qué.
- **El inicio de estudio es una decisión, no un dato.** Sin él, la atrición sería otra (1,522 / 1,104), pero el pico de 2016 mezclaría usuarios previos con nuevos.
- **Censura informativa.** El corte por empezar el otro fármaco acorta el seguimiento (mediana de 928 y 401 días contra 1,514 y 1,484 sin cortar) y puede sesgar si quien necesita un segundo fármaco tiene la presión peor controlada (decisión 14).
- **El día 0.** 73 de 122 y 43 de 81 cumplen la HTA solo por un registro del día índice; el ETL no permite saber su orden respecto a la receta.
- **La ventana de 365 días subestima las enfermedades crónicas** en la tabla 1 (prediabetes: 82 personas con la historia completa, 1 con la ventana; decisión 18).
- **Tamaños pequeños.** Con 122 y 81 personas, el SMD de la tabla 1 tiene un error típico de ≈ 0.14.

**No hecho:** los tres bonos opcionales (SQL parametrizado por tabla de concept set, comparación con el SQL de ATLAS/CIRCE y plantilla HARPER). Lo más cercano al primero es `results.cohorte_parametros`, que ya guía las cuatro cohortes con la misma lógica, pero el concept set del desenlace y de la hipertensión sigue escrito en el SQL.
