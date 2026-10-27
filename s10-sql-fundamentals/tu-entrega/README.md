# Lab 10 — SQL fundamentals

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

## 5. Auditoría y consultas básicas e intermedias (fase 2, actividades 5 y 6.1-6.10)

- `sql/auditoria.sql`: cuatro auditorías, todas limpias en esta carga (0 `Id` duplicados, 0 encuentros anteriores al nacimiento, 0 % de `observations.value` nulo o vacío, 0 encuentros con paciente inexistente).
- `sql/consultas.sql`: preguntas 6.1 a 6.10, cada una con su comentario clínico y su verificación.

Hallazgos sobre los datos sintéticos que conviene tener presentes:

- `encounters` por año tiene un escalón entre 2016 (12 940) y 2017 (26 892), con meseta de ~27 000 después. No se encontró la causa (hay encuentros desde 1916 y la mezcla de tipos de encuentro es casi igual antes y después); se trata como artefacto del generador. 2026 está incompleto.
- **Criterio adoptado para la tendencia anual (6.5):** la tendencia se analiza formalmente de 2017 a 2025, que es la ventana principal de estudio. Los años previos solo se presentan en un gráfico complementario con una advertencia explícita del quiebre estructural. 2026 se excluye del análisis de tendencias anuales cerradas o, si se muestra, se marca explícitamente como incompleto; no se anualiza con una regla de tres.
- El top de diagnósticos está dominado por hallazgos y situaciones (`finding`, `situation`), no por enfermedades; "Medication review due" está en el 100 % de los pacientes.
- La HbA1c (LOINC 4548-4) tiene mediana 4.0 % y el 48.6 % de las mediciones por debajo de 4.0 %, lo cual no es fisiológico; se reporta como limitación del generador.
- La edad (6.10) se calcula a la fecha de la muerte para fallecidos y a la fecha de corte (último encuentro, 2026-10-26) para vivos. Un corte fijo anterior dejaba edades negativas.

## 6. Joins y experimentos (fase 3, actividades 6.11-6.15, 7 y 8)

- `sql/consultas.sql`, 6.11 a 6.15: cohorte de diabetes tipo 2 con hipertensión (309 pacientes), 0 diabéticos sin HbA1c, medicamento más frecuente entre diabéticos (metformina 500 mg ER, por 1 paciente sobre nitroglicerina) y urgencias sin diagnóstico (5 272 de 15 958, 33.04 %).
- `sql/experimentos.sql`, act. 7: un join por paciente multiplica las filas por 84.6. El costo medio baja de 2 206.65 a 1 648.87 y el total sube 63 veces. Se corrige con `EXISTS`.
- `sql/experimentos.sql`, act. 8: con el filtro en `WHERE` salen 444 filas y con el filtro en `ON` salen 5 904. El `WHERE` convierte el `LEFT JOIN` en `INNER JOIN`.

## 7. Rendimiento y comparación con pandas (fase 4, actividades 9 y 10)

Todo se ejecuta también en el notebook [`lab10_auditoria_rendimiento_pandas.ipynb`](lab10_auditoria_rendimiento_pandas.ipynb), que reúne la auditoría, las mediciones y la comparación.

### Actividad 9: rendimiento de 6.15 (`sql/rendimiento.sql`)

Se reemplazó el `NOT EXISTS` correlacionado por `LEFT JOIN ... WHERE c.encounter IS NULL`. Ambas versiones devuelven 5 272 encuentros y 1 873 pacientes.

| | A: `NOT EXISTS` | B: `LEFT JOIN ... IS NULL` |
|---|---|---|
| Mediana (31 corridas) | 14.8 ms | 6.9 ms |
| Pico de memoria (RSS) | 92 MB (+26 sobre la base de 66) | 85 MB (+19) |
| Join en el plan | `MARK` + filtro | `RIGHT_ANTI` |

La predicción de que B usaría más memoria resultó falsa. Reordenar filtros o reducir columnas no habría cambiado nada: DuckDB ya lee solo las columnas necesarias y aplica el filtro dentro del escaneo, algo que se explica por su almacenamiento columnar. La causa de la mejora (el vector marcador de `MARK`) es una lectura del plan, no un experimento aislado.

### Actividad 10: SQL contra pandas (`pandas_comparacion.py`)

Consultas 6.2, 6.6 y 6.15, con las tablas ya cargadas a DataFrames (la carga, ~80 ms, se reporta aparte):

| Consulta | DuckDB | pandas | Líneas SQL / pandas |
|---|---|---|---|
| 6.2 (distribución por sexo) | 0.99 ms | 0.79 ms | 7 / 8 |
| 6.6 (encuentros por paciente) | 3.01 ms | 24.78 ms | 15 / 15 |
| 6.15 (anti-join) | 13.87 ms | 83.54 ms | 16 / 11 |

Las razones entre motores varían entre corridas; se leen como órdenes de magnitud (~6x a ~9x en 6.6 y 6.15).

**Conclusión:** para este volumen se elige DuckDB: fue superior o igual en las tres consultas (hasta 8.2x más rápido en 6.6) y no carga las tablas en memoria como pandas (98 MB solo en 3 columnas de `encounters`). Se pasaría a pandas únicamente en la última milla, si el resultado agregado (<10 mil filas) debe integrarse con scikit-learn o seaborn; y se reconsideraría el uso exclusivo de pandas si el dataset nunca superara los 100 mil registros y los tiempos se mantuvieran por debajo de 50 ms.
