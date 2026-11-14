# Lab 16 — Jerarquías en acción: `concept_relationship` y `concept_ancestor`

Las dos formas de representar la jerarquía del vocabulario OMOP (aristas en `concept_relationship`, recorridas con `WITH RECURSIVE`, y el cierre transitivo precalculado en `concept_ancestor`), sus diferencias, la poli-jerarquía y el daño que causa al contar, la depuración paciente por paciente, los conceptos retirados y el rendimiento. Base OMOP sintética del lab 12 en PostgreSQL (decisión 1), vocabulario ATHENA v5.0 29-AUG-26.

## Entregables

| Archivo | Contenido |
|---|---|
| `jerarquias.sql` | Las **ocho** actividades, en bloques `-- Actividad Na.`, cada uno con qué responde, por qué está escrito así y el resultado obtenido. Incluye los controles 0 y 0b (tablas e índices). |
| `tiempos.md` | Actividad 8: tiempos de las dos versiones (mediana de tres corridas), comparación de planes y los dos planes completos. |
| `hallazgos.md` | Actividades 3 a 7: la tabla `RELATIONSHIP`, el caso real de poli-jerarquía, los tres conteos A/B/C, la depuración de pacientes y los conceptos retirados con su efecto. |
| `DECISIONES.md` | Las 10 decisiones del lab: qué se eligió, qué alternativas había y por qué. |
| `README.md` | Este archivo. |

## Cómo reproducirlo

Requiere la base del lab 12 con el vocabulario de ATHENA cargado (contenedor `lab12-omop-db-1`, BD y credenciales en `../../s12-omop-cdm-introduccion/tu-entrega/.env`, esquema `cdm`). El esquema `cdm` solo se lee. El único objeto que el lab crea es la función `results.por_que_entro` (actividad 6, `CREATE OR REPLACE`); la tabla de la actividad 8 es temporal y desaparece al cerrar la sesión.

```bash
# 1. Encender la base del lab 12
cd s12-omop-cdm-introduccion/tu-entrega && docker compose up -d && cd -
set -a; . s12-omop-cdm-introduccion/tu-entrega/.env; set +a
T=s16-jerarquias-concept-ancestor/tu-entrega

# 2. Todo el lab (~15 s; la prueba 6c es la más lenta)
docker exec -i lab12-omop-db-1 psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 < $T/jerarquias.sql

# 3. Un solo bloque (de su comentario al siguiente)
sed -n '/^-- Actividad 5a\./,/^-- Actividad 6\./p' $T/jerarquias.sql | docker exec -i lab12-omop-db-1 psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"

# 4. ¿Por qué entró un paciente? (después de correr el bloque 6a)
docker exec -i lab12-omop-db-1 psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT * FROM results.por_que_entro(79);"
```

El bloque 8 (8a a 8c) debe correr entero en una misma sesión, porque la tabla temporal `cs_ic` solo existe en la sesión que la creó.

Comprobado el 2026-11-14: `jerarquias.sql` completo corre sin errores (`exit 0`, 14 s).

## Resultados por actividad

| # | Pregunta | Resultado |
|---|---|---|
| 1 | Subir de T2DM (201826) a la raíz con `WITH RECURSIVE` | 20 filas, 4 caminos a la raíz, profundidad mínima 6 y máxima 7. Freno `nivel < 20`, solo `'Is a'` vigentes, ruta en un `ARRAY` contra ciclos. |
| 2 | Lo mismo con `concept_ancestor` | T2DM + 8 ancestros, contra T2DM + 11 de la recursiva: 9 conceptos en ambas con los mismos niveles, 3 solo en la recursiva (dos conceptos retirados en 2021 y la raíz de metadatos *SNOMED CT Concept*), 0 solo en `concept_ancestor`. |
| 3 | La tabla `RELATIONSHIP` | 724 tipos: 124 jerárquicos, 63 definen ascendencia, 55 ambos → las banderas no coinciden. Metformina: 9 tipos y 247 relaciones salientes. `concept_ancestor` es curada: incluye ATC aunque *RxNorm - ATC pr lat* sea 0/0. |
| 4 | Poli-jerarquía real | T2DM → *Disease*: min 4 / max 5. Dos caminos, por la rama endocrina y por la metabólica, que se separan en *Diabetes mellitus*. |
| 5 | Medir el daño | Insuficiencia cardiaca (padre + 2 ramas traslapadas): **A 568 / B 2 / C 194**. Solo C responde «¿cuántos pacientes?». |
| 6 | ¿Por qué entró este paciente? | Función `results.por_que_entro(person_id)`. 79: 3 ramas; 892: 1 rama; 273 (elegido por un compañero): 0 filas, ninguno de sus 12 diagnósticos está en el set. Aplicada a toda la base reproduce 568 / 194. |
| 7 | Conceptos muertos | Nuestros sets: 0 retirados (por construcción con `concept_ancestor`). Códigos de origen: 4 retirados (3 'U', 1 'D'); una lista literal vieja encuentra 0 pacientes y la actualizada con `'Concept replaced by'`, **2,240**. Dos sin reemplazo, que no se sustituyen. |
| 8 | `IN` contra tabla materializada | Medianas 8.08 contra 7.88 ms: **sin diferencia medible a esta escala**. El plan pasa de Hash Semi Join a Hash Join, pero el paso dominante (Seq Scan de `condition_occurrence`) no cambia. |

## Criterios de evaluación

| Criterio | Dónde |
|---|---|
| La recursiva y la de ancestros devuelven el mismo conjunto, o se explica por qué no | `jerarquias.sql` 2b; explicación en `hallazgos.md`, actividad 3 («Conexión con la actividad 2»). |
| La recursiva tiene freno de profundidad y filtra por `relationship_id` | `jerarquias.sql` 1a, 1b y 4b (`nivel < 20`, `relationship_id = 'Is a'`). |
| Al menos un caso real de poli-jerarquía en la base propia | `hallazgos.md`, actividad 4 (T2DM → *Disease*), y actividad 5 (4229440 bajo 3 ramas). |
| Se explica por qué `COUNT(*)`, `COUNT(DISTINCT concept_id)` y `COUNT(DISTINCT person_id)` difieren | `hallazgos.md`, actividad 5. |
| La consulta de depuración funciona para cualquier paciente | `jerarquias.sql` 6c: aplicada a las 5,904 personas, reproduce A y C. |
| Tiempos como mediana de tres corridas, con el plan | `tiempos.md`. |
| Si no hubo mejora medible, se dice | `tiempos.md`: «No medí diferencia a esta escala». |
| Código versionado con commits descriptivos | Un PR por actividad (#101 a #109), commits `feat(s16): …`. |

**No hecho:** los dos bonos opcionales (CohortDiagnostics y la recursiva hacia abajo en fármacos).

**Limitación general:** en Synthea cada paciente tiene un solo evento de insuficiencia cardiaca y los códigos de origen son casi siempre el mismo concepto estándar, así que la depuración de la actividad 6 no muestra traducciones ICD-10 → SNOMED, aunque la función las soporta. Con 101,699 filas en `condition_occurrence`, las diferencias de rendimiento de la actividad 8 quedan por debajo del ruido de medición.
