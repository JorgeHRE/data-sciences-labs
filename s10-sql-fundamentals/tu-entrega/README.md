# Lab 10 — SQL fundamentals (fase 1: datos, carga y esquema)

## 1. Generación de datos (actividad 1)

Synthea v3.3.0, 5000 pacientes vivos, exportación a CSV (el jar está fuera del repo; los CSV no se suben):

```bash
java -jar synthea-with-dependencies-v3.3.0.jar -p 5000 -s 10 -cs 10 \
  --exporter.baseDirectory=./data/synthea \
  --exporter.csv.export=true \
  --exporter.fhir.export=false \
  --exporter.hospital.fhir.export=false \
  --exporter.practitioner.fhir.export=false \
  Massachusetts
```

`patients.csv` trae 5904 filas: 5000 vivos y 904 fallecidos.

## 2. Motor elegido (actividad 2)

DuckDB.

La elección se debe a que trabajo de forma remota por SSH, alternando entre el laboratorio y mi casa,
por lo que una base de datos embebida en un solo archivo evita configurar y mantener servicios de
red o puertos en distintas máquinas.

Al tratarse de un entorno de análisis estrictamente personal, no requiero concurrencia ni que otros usuarios se conecten simultáneamente.

Finalmente, en esta etapa exploratoria no es prioritario replicar la infraestructura cliente-servidor típica de OHDSI (como PostgreSQL), y priorizo en su lugar la velocidad analítica columnar y la portabilidad sin fricciones de despliegue.

## 3. Carga reproducible (actividad 3)

- Script: `sql/carga.sql`, ejecutado por `carga.py`. Se puede correr varias veces.
- Base resultante: `clinica.duckdb` (ignorada por git).
- Fechas con hora (`encounters`, `medications`, `observations`) como `TIMESTAMP`; nacimiento, defunción y `conditions` como `DATE`.

| Tabla | Filas |
|---|---|
| patients | 5904 |
| encounters | 429640 |
| conditions | 235504 |
| medications | 388658 |
| observations | 5719327 |

## 4. Esquema, llaves y diagrama ER (actividad 4)

Las tablas tienen 72 columnas en total (patients 28, encounters 15, medications 13, observations 9, conditions 7).
Las PK y FK **no se declaran** en la carga; se verificaron con consultas sobre los datos.

### Llaves primarias

| Tabla | PK | Tipo | Evidencia |
|---|---|---|---|
| patients | `Id` | natural | 5904 filas, 5904 únicos, 0 nulos |
| encounters | `Id` | natural | 429640 filas, 429640 únicos, 0 nulos |
| conditions | `(patient, code, start, encounter)` | natural compuesta | 235504 combinaciones únicas, 0 nulos. Sin `encounter`, 6 repetidas |
| medications | clave artificial | artificial | `(patient, code, start, encounter)` deja 519 repetidas; `stop` tiene nulos; las filas repetidas difieren en `stop`, `dispenses` y costos |
| observations | clave artificial | artificial | 159864 filas con `encounter` nulo; `(patient, code, date)` deja 14934 grupos repetidos que difieren en `value` (a veces en `description`) |

Criterio: una clave natural se acepta solo si la unicidad y la ausencia de nulos se comprueban con los datos. Si depende de columnas con nulos o de datos que pueden corregirse (`value`, `dispenses`), se usa clave artificial. La validación vale para esta carga concreta.

### Llaves foráneas (7)

| FK | Huérfanas |
|---|---|
| encounters.patient → patients.Id | 0 |
| conditions.patient → patients.Id | 0 |
| medications.patient → patients.Id | 0 |
| observations.patient → patients.Id | 0 |
| conditions.encounter → encounters.Id | 0 |
| medications.encounter → encounters.Id | 0 |
| observations.encounter → encounters.Id | 0 (se excluyen los nulos) |

`observations.encounter` admite nulos (159864 filas, que tampoco tienen `category`): una FK ignora los nulos, así que sigue siendo una FK válida. Sin excluirlos, un `LEFT JOIN` los contaría como 159864 falsas huérfanas.

Referencias fuera del alcance (tablas no cargadas): `encounters.organization`, `encounters.provider`, `encounters.payer` y `medications.payer`.

### Diagrama

Ver [`diagrama_er.md`](diagrama_er.md).
