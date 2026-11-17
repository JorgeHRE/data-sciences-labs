# SPECS — Lab 20: Data lake clínico en S3 con boto3

> **Para el Constructor (Fase 2, Hydrogen o Sonnet).** Lee este archivo y
> `MEMORIA.md` antes de empezar. Ejecuta los pasos **en orden**, aplicando el
> MODO INTERMEDIO de `AGENTS.md`: trozos de 30–50 líneas, verificación tras cada
> trozo, **pausa en cada `[DECISIÓN PENDIENTE]`** (presenta opciones y
> recomendación, espera la elección del usuario), registro en
> `tu-entrega/DECISIONES.md` y en `MEMORIA.md`, y una pregunta de comprensión
> al cerrar cada sección. Todo en español.
>
> El usuario ejecuta los comandos contra AWS; tú escribes código, comandos y
> documentación.

---

## 0. Contexto verificado por el Arquitecto (2026-11-16)

| Hecho | Valor | Fuente |
|---|---|---|
| Perfil AWS | `tesis`, región `us-east-2` | `s19-aws-fundamentos-aim/tu-entrega/aws-setup.md` |
| Permisos del usuario IAM | `AmazonS3FullAccess`, `IAMFullAccess`, `AWSBillingReadOnlyAccess` (no hay que ampliar nada para S3) | `s19/.../DECISIONES.md` §2 |
| Plan de la cuenta | Plan Gratuito nuevo (créditos de 100 USD); presupuesto de 5 USD con alertas 50/80 % real y previsto | `s19/.../aws-setup.md` |
| Bucket previo | `lab19-jorge-prueba-20261116` (lab 19, ya no se necesita) | `s19/.../politica_minima.json` |
| Herramientas | AWS CLI 2.40.3, gitleaks en `~/.local/bin`, Python 3.12.3, 46 GB RAM, 16 núcleos, 1.4 TB libres | comprobado |
| Datos sintéticos del curso | Synthea CSV, **4.3 GB**, en `s10-sql-fundamentals/tu-entrega/data/synthea/csv/` (ignorado por Git) | comprobado |
| CSV más grandes | `claims_transactions.csv` 2.4 GB · `observations.csv` 974 MB (5.7 M filas) · `claims.csv` 300 MB · `imaging_studies.csv` 219 MB · `procedures.csv` 167 MB · `encounters.csv` 135 MB (429 k filas) | comprobado |
| Columnas de fecha | `observations.DATE`, `encounters.START` (ISO 8601 con `Z`) | encabezados |
| Distribución temporal | encuentros 1916–2026, ~85 % en 2016–2026; `observations` 2015–2026 (~0.4 M filas/año) | comprobado |
| Sitios | 1 026 `ORGANIZATION` distintas en `encounters` | comprobado |
| No disponibles localmente | `recursos/s20-aws-s3-boto3.md` y `tools/figuras_s20.py` (citados por el enunciado) | comprobado |

> **Conflicto a resolver en D1:** las reglas de `AGENTS.md` dicen "nunca datos
> de pacientes reales **ni sintéticos de hospital**", y el enunciado pide subir
> "los datos sintéticos del curso" (Synthea). Synthea es 100 % sintético, pero
> el usuario debe confirmarlo explícitamente.

---

## 1. Estructura de entrega

```text
s20-aws-s3-boto3/                 # raíz: archivos de control del flujo
├── AGENTS.md  CLAUDE.MD  ENUNCIADO.md  GUIA_ESTUDIO.md  SPECS.md  MEMORIA.md  (AUDIT.md lo crea Argon)
└── tu-entrega/
    ├── README.md                   # índice de entregables, cómo reproducir, checklist de criterios
    ├── DECISIONES.md               # registro de decisiones (2-3 líneas cada una)
    ├── requirements.txt            # versiones fijadas
    ├── arquitectura_datalake.md    # entregable 1 (Act. 2) + config del bucket (Act. 1)
    ├── s3util/                     # entregable 2 (Act. 4-5)
    │   ├── __init__.py
    │   └── nucleo.py               # subir, descargar, listar, existe + manejo de errores
    ├── tests/
    │   ├── conftest.py
    │   └── test_s3util.py
    ├── scripts/
    │   ├── convertir_parquet.py    # Act. 6
    │   └── demo_paginacion.py      # Act. 5 contra el bucket real
    ├── benchmark.ipynb             # entregable 3 (Act. 7 y 8)
    ├── operaciones.md              # entregable 4 (Act. 3, 9 y 10)
    └── capturas/                   # PNG censurados (sin Account ID)
```

Los nombres de módulos internos (`nucleo.py`, `scripts/`) son decisiones menores:
el Constructor puede ajustarlos. Los cuatro entregables del enunciado no se
renombran.

**Nunca en Git:** `.venv/`, datos locales (`datos/`, `*.parquet`, `*.csv`
generados), `.ipynb_checkpoints/`, `__pycache__/`, `.pytest_cache/`, `~/.aws/`.

---

## 2. Decisiones pendientes (resumen)

| ID | Tema | Paso | Recomendación del Arquitecto |
|---|---|---|---|
| D1 | Qué datos subir a `raw/` | 3 | Synthea, subconjunto sin `claims*` ni `imaging_studies` |
| D2 | Crear el bucket por consola o por CLI | 1 | CLI con comandos documentados + captura de consola |
| D3 | Tabla y esquema de particionado | 2, 6 | `observations`, particionado por `anio=` |
| D4 | Contrato de errores de `s3util` | 4 | Excepciones propias; `existe` devuelve `bool` |
| D5 | Manejo de sesión/cliente | 4 | `perfil` como argumento + cliente cacheado |
| D6 | Estrategia de pruebas | 4, 5 | moto para unitarias + marcador `integracion` |
| D7 | Prefijo y limpieza de los > 1 000 objetos | 5 | `tmp/paginacion/` + regla que expira versiones |
| D8 | Reglas de ciclo de vida | 9 | 3 reglas: multipart, `tmp/` y versiones no actuales |
| D9 | Bono: política de bucket solo-HTTPS | 11 | Sí, al final |

El detalle de cada una está en su paso. **Ninguna se implementa sin la elección
del usuario.**

---

## 3. Plan paso a paso

### Paso 0 — Preparación (sin tocar AWS)

1. Rama de trabajo: `s20/<tema>` desde `main` (un PR por actividad o por bloque,
   como en labs anteriores). El usuario indica cuándo hacer commit.
2. `.gitignore` de la raíz: añadir `s20-aws-s3-boto3/ENUNCIADO.md` y
   `s20-aws-s3-boto3/GUIA_ESTUDIO.md` (mismo criterio que el lab 19) y los datos
   locales de `tu-entrega/`. **Confirmar con el usuario** si `SPECS.md`,
   `MEMORIA.md` y `AGENTS.md` se versionan (en el lab 19 se versionó `GEMINI.md`).
3. `.venv` en `tu-entrega/` con `boto3`, `pandas`, `pyarrow`, `s3fs`, `duckdb`,
   `pytest`, `moto[s3]` (si D6 lo confirma), `matplotlib`, `jupyter`,
   `ipykernel`. Fijar versiones en `requirements.txt` (`pip freeze` filtrado a
   las directas).
4. Crear `tu-entrega/DECISIONES.md` y `MEMORIA.md` (ya existe el esqueleto).

**Verificación:** `python -c "import boto3, pandas, pyarrow, s3fs, duckdb; print('ok')"`.

### Paso 1 — Checklist de seguridad y bucket (Act. 1)

**Antes de crear nada** (reglas no negociables):
- `aws sts get-caller-identity --profile tesis` → el ARN debe ser
  `...:user/<usuario>`, **no** `:root`. No pegar el Account ID en el repo.
- El presupuesto de 5 USD sigue activo con sus 4 alertas (consola → Budgets).
- BPA a nivel **cuenta**: `aws s3control get-public-access-block --account-id
  <ID> --profile tesis` → las 4 banderas en `true`. El Account ID se usa solo en
  la terminal; en la documentación va `<ACCOUNT_ID>`.

**[DECISIÓN PENDIENTE D2] — Cómo crear el bucket**

| Opción | Ventajas | Desventajas |
|---|---|---|
| A. Consola | Visual, fácil de capturar | No reproducible; fácil olvidar un interruptor |
| B. CLI (`s3api create-bucket` + `put-bucket-versioning` + `put-bucket-encryption` + `put-public-access-block` + `put-bucket-tagging`) | Reproducible, documentable, auditable (en pharma se espera *infraestructura como código* o al menos procedimientos escritos) | 5 comandos; en `us-east-2` hay que pasar `--create-bucket-configuration LocationConstraint=us-east-2` |
| C. Script boto3 | Reproducible y reutilizable | Más código para algo que se hace una vez |

*Recomendación:* **B**, ejecutando los 5 comandos seguidos para que versionado
y cifrado estén activos "desde la creación", y luego una captura de la consola
(pestaña *Properties* y *Permissions*) como evidencia. Nombre:
`omop-tesis-<iniciales>-<4 dígitos>` (lo elige el usuario).

**Verificación (comandos de solo lectura, sus salidas van a
`arquitectura_datalake.md` o a `operaciones.md`):**
`get-bucket-versioning` → `Enabled`; `get-bucket-encryption` → `AES256`;
`get-public-access-block` → 4 × `true`; `get-bucket-tagging` →
`Proyecto=tesis`; y prueba negativa: `curl -I
https://<bucket>.s3.us-east-2.amazonaws.com/<llave>` → `403`.

**Recordatorios:** activar la etiqueta `Proyecto` en *Billing → Cost allocation
tags* (tarda hasta 24 h). Preguntar al usuario si borra el bucket del lab 19
(vaciar versiones primero si tuviera).

### Paso 2 — Arquitectura de zonas (Act. 2) → `arquitectura_datalake.md`

Contenido mínimo: tabla de zonas (qué va, quién escribe, si es regenerable,
formato), convención de nombres de llaves, esquema de particionado **con su
porqué** (qué filtros se harán en las sesiones 21–25), y una sección explícita
"por qué no particioné por X".

Convención propuesta (decisión menor, ajustable):
```text
raw/synthea/<tabla>/fecha_carga=YYYY-MM-DD/<tabla>.csv
staging/synthea/<tabla>/<tabla>.parquet
curated/synthea/<tabla>/anio=YYYY/part-*.parquet
tmp/...                       (efímero, se expira por ciclo de vida)
```
`fecha_carga=` en `raw/` permite cargas sucesivas sin reescribir nada
(inmutabilidad) y saber qué llegó cuándo (*lineage*).

**[DECISIÓN PENDIENTE D3] — Tabla a convertir y esquema de particionado**
(se decide aquí porque el documento lo necesita; se implementa en el paso 6)

*Tabla* — el enunciado dice "el CSV más grande que tengas":

| Opción | Ventajas | Desventajas |
|---|---|---|
| `claims_transactions` (2.4 GB) | Cumple la letra del enunciado; benchmark más contundente | Tabla financiera, poco útil para el proyecto clínico; 2.4 GB × versiones complica el Free Tier (5 GB); benchmark lento |
| `observations` (974 MB, 5.7 M filas) | Tabla clínica central (labs, signos vitales), la que se filtra en las sesiones 21–25; tiene fecha; sigue siendo el CSV clínico más grande | No es literalmente el más grande → hay que justificarlo en `DECISIONES.md` |
| `encounters` (135 MB) | Rápida | Demasiado pequeña para que el benchmark sea significativo |

*Partición:*

| Opción | Particiones | Ventajas | Desventajas |
|---|---|---|---|
| `anio=` | ~12 (2015–2026) | ~40–80 MB de Parquet por año (tamaño sano); coincide con filtros de ventana temporal típicos de cohortes | Filtrar un mes lee el año entero (row groups ayudan) |
| `anio=/mes=` | ~140 | Filtros mensuales más finos | Archivos de ~3–6 MB (*small files*); más GET |
| `anio=/CATEGORY=` | ~12 × 8 | Útil si casi siempre se filtra `laboratory` vs. `vital-signs` | Cardinalidad desigual; acopla el layout a una pregunta |
| Por sitio (`ORGANIZATION`) | ~1 000 | Útil para estudios multicéntricos por hospital | `observations` no tiene la organización (requiere JOIN con `encounters`); 1 000 archivos diminutos |

*Recomendación:* **`observations` particionada por `anio=`**, con la
justificación de tamaño de archivo y de filtros temporales; documentar por qué
no por sitio ni por mes. El Constructor debe preguntar al usuario cómo planea
filtrar en su proyecto final antes de cerrar esta decisión.

### Paso 3 — Subir con `sync` (Act. 3) → sección en `operaciones.md`

**[DECISIÓN PENDIENTE D1] — Qué subir a `raw/`**

| Opción | Tamaño | Ventajas | Desventajas / costo |
|---|---|---|---|
| A. Synthea completo | 4.3 GB | "Todo lo del curso" | Junto con Parquet y versiones **supera los 5 GB** del Free Tier; 2.4 GB de `claims_transactions` sin uso clínico |
| B. Synthea sin `claims`, `claims_transactions`, `imaging_studies` | ~1.5 GB | Cubre todo lo clínico; deja margen para Parquet y versiones | Hay que documentar la exclusión (`--exclude`) |
| C. Solo las tablas del proyecto (`patients`, `encounters`, `conditions`, `medications`, `observations`) | ~1.3 GB | Mínimo necesario | Menos material para sesiones futuras |
| D. Archivos de texto inventados | KB | Cumple la regla literal de `AGENTS.md` | No hay CSV grande para las actividades 6–8 |

*Recomendación:* **B** (si el usuario confirma que Synthea cuenta como dato
permitido, ver conflicto en §0). Sin datos de pacientes reales en ningún caso.

Ejecución: primero `--dryrun`, luego la corrida real, luego la segunda corrida
sin cambios. **Aviso de costo antes de correr:** ~1.5 GB de almacenamiento
(≈ 0.035 USD/mes) y unas decenas de PUT por las partes multipart.
Entregable: las dos salidas (la segunda vacía) y una frase sobre por qué
(`sync` compara tamaño y fecha de modificación → idempotente).
**Verificación:** `aws s3 ls s3://<bucket>/raw/ --recursive --summarize
--human-readable --profile tesis`.

### Paso 4 — Módulo `s3util/` (Act. 4)

Funciones mínimas: `subir`, `descargar`, `listar`, `existe`. Todas reciben
`perfil` (nombre) y `bucket`; nunca llaves.

**[DECISIÓN PENDIENTE D5] — Sesión y cliente**

| Opción | Ventajas | Desventajas |
|---|---|---|
| A. Cada función crea `boto3.Session(profile_name=perfil).client("s3")` | Simple | Crear sesión cuesta ~decenas de ms; lento en bucles (Act. 5) |
| B. `perfil` como argumento + helper `_cliente(perfil)` con `functools.lru_cache` | Cumple "recibe el perfil"; rápido; fácil de *mockear* | Hay que limpiar la caché en las pruebas |
| C. Clase `ClienteS3(perfil)` | Estado explícito, extensible | Más ceremonia de la que pide el enunciado |

*Recomendación:* **B**. Aceptar `perfil=None` para usar la *credential chain*
(útil cuando el código corra en un rol de AWS en sesiones futuras).

**[DECISIÓN PENDIENTE D4] — Contrato de errores**

| Opción | Ventajas | Desventajas |
|---|---|---|
| A. Excepciones propias (`S3UtilError` → `LlaveNoExiste`, `BucketNoExiste`, `AccesoDenegado`) con mensaje útil, encadenadas con `raise ... from e` | El llamador decide; los tests verifican el tipo; se conserva la causa original | Más clases |
| B. Imprimir/loguear y devolver `None`/`False` | Sencillo | Oculta errores (un `None` silencioso en un pipeline clínico es peligroso) |
| C. Dejar pasar `ClientError` | Cero código | No cumple el criterio "distingue y da mensaje útil" |

*Recomendación:* **A**, y `existe()` devuelve `True/False` solo para 404; para
403 lanza `AccesoDenegado` (no se puede afirmar que no existe). Distinguir
también `ProfileNotFound`/`NoCredentialsError`. El mensaje de `AccesoDenegado`
debe nombrar la acción y el ARN probables (p. ej. "`s3:GetObject` sobre
`arn:aws:s3:::<bucket>/<llave>`") y sugerir el simulador de la sesión 19.
Usar `logging`, no `print`.

Ojo técnico (para la implementación): `head_object` devuelve código `"404"`/
`"403"`, no `NoSuchKey`; `get_object` y `download_file` difieren en el código
que lanzan (`download_file` usa `head_object` por dentro). Las pruebas deben
cubrir ambos caminos.

**[DECISIÓN PENDIENTE D6] — Estrategia de pruebas**

| Opción | Ventajas | Desventajas |
|---|---|---|
| A. moto (`@mock_aws`) | Offline, gratis, rápido; permite 1 500 objetos en segundos; reproducible por el auditor | No valida IAM real |
| B. `botocore.stub.Stubber` | Control fino de errores | Frágil y verboso |
| C. Bucket real | Prueba lo real | Cuesta, necesita credenciales, no corre en CI |
| D. A + pocas de integración con `@pytest.mark.integracion` (excluidas por defecto en `pytest.ini`) | Lo mejor de ambos; patrón de la industria | Dos tipos de pruebas que mantener |

*Recomendación:* **D**. Casos mínimos con moto: subir/descargar ida y vuelta;
`existe` True/False; `NoSuchKey`; `NoSuchBucket`; `AccessDenied` (con moto se
puede simular vía Stubber o una política de bucket; si no, Stubber solo para
ese caso); `listar` con prefijo; y la paginación (paso 5). Región fija y
credenciales falsas en `conftest.py` (`AWS_ACCESS_KEY_ID=testing`) para que
ninguna prueba toque AWS por accidente.

**Verificación:** `pytest -q` en verde; `pytest -m integracion` solo a mano
tras `sts get-caller-identity`.

### Paso 5 — Paginación con > 1 000 objetos (Act. 5)

- `listar` usa `get_paginator("list_objects_v2")`, **no** un `while` con
  `ContinuationToken`. Debe devolver lista (o generador; decisión menor) de
  todas las llaves bajo un prefijo, manejando páginas sin `Contents`.
- Prueba automatizada (moto): subir 1 500 objetos, afirmar
  `len(listar(...)) == 1500`; y una prueba de control que muestre que una sola
  llamada a `list_objects_v2` devuelve 1 000 con `IsTruncated=True` (demuestra
  que la prueba detectaría el bug).
- Demo real (`scripts/demo_paginacion.py`): subir N objetos diminutos (N entre
  1 100 y 1 500) en paralelo (`ThreadPoolExecutor`, ~16 hilos), listar con
  `listar` y comparar con N; comparar también con
  `aws s3 ls --recursive | wc -l`. Guardar la salida en `operaciones.md` o en
  el README.

**[DECISIÓN PENDIENTE D7] — Dónde y cómo limpiar los objetos de prueba**

| Opción | Ventajas | Desventajas |
|---|---|---|
| A. Prefijo `tmp/paginacion/` + borrado con `delete_objects` (lotes de 1 000) + regla de ciclo de vida que expira versiones no actuales y delete markers de `tmp/` a 1 día | Limpia de verdad pese al versionado; muestra entender el versionado | Una regla más |
| B. Borrar con `aws s3 rm --recursive` y nada más | Simple | Con versionado **quedan 1 500 versiones + 1 500 delete markers** ocupando espacio y peticiones LIST |
| C. Borrar cada versión con `VersionId` | Inmediato | Código de borrado permanente: riesgoso si el prefijo está mal |

*Recomendación:* **A**. **Aviso de costo:** ~1 500 PUT + 2 `DeleteObjects`,
del orden de 0.01 USD. Correr la demo una sola vez.

### Paso 6 — CSV a Parquet particionado (Act. 6)

`scripts/convertir_parquet.py` según D3: leer el CSV con tipos explícitos
(fechas `DATE` a timestamp UTC, `VALUE` como texto porque mezcla números y
categorías en Synthea — documentarlo), derivar `anio`, escribir con
`pyarrow.dataset.write_dataset` / `pandas.to_parquet(partition_cols=[...])`
en formato Hive. Para 974 MB cabe en memoria (46 GB RAM); si se eligiera
`claims_transactions`, leer por lotes con `pyarrow.csv.open_csv`.

Escribir primero a disco local (fuera de Git), verificar, y luego subir a
`curated/` con `aws s3 sync` (o directo con s3fs).
**Verificación:** conteo de filas del Parquet == filas del CSV − 1 (encabezado)
== 5 719 327; `aws s3 ls --recursive` muestra `anio=YYYY/`; listado de la
estructura para el entregable.

### Paso 7 — Benchmark CSV vs. Parquet (Act. 7) → `benchmark.ipynb`

- Medir **en local** (no S3): tamaño en disco (`os.path.getsize` / suma del
  directorio Parquet), leer completo, leer una columna (`usecols` vs.
  `columns`).
- `time.perf_counter()`, **5 corridas**, reportar **mediana** (y min/max);
  documentar si se descartó la corrida fría o no.
- Registrar equipo (CPU, RAM, disco) y versiones de pandas/pyarrow.
- Gráfica con matplotlib (barras agrupadas o tres paneles; escala log si la
  diferencia es de órdenes de magnitud). Sin inventar números: la tabla se
  genera desde los datos medidos.
- Opcional (bono): snappy vs. zstd.

### Paso 8 — Leer desde S3 sin descargar (Act. 8) → sección en `benchmark.ipynb`

1. `pandas.read_parquet("s3://.../curated/...", columns=[...],
   storage_options={"profile": "tesis"})`.
2. DuckDB: `INSTALL httpfs; LOAD httpfs;`, `CREATE SECRET (TYPE s3, PROVIDER
   credential_chain, PROFILE 'tesis', REGION 'us-east-2')`, consulta con
   `hive_partitioning = true` y `WHERE anio = <año>`; comparar tiempo con y sin
   filtro y mostrar `EXPLAIN ANALYZE`.
3. Frase final: cuál usaría en el proyecto y por qué.

**Verificación de "sin descargar":** no se crean archivos locales; mostrar que
la consulta con filtro es claramente más rápida (si no, revisar `anio=`).
**Cuidado con las salidas del notebook:** nada de Account ID, ARN completos ni
URLs firmadas vigentes.

### Paso 9 — Ciclo de vida y presigned URL (Act. 9) → `operaciones.md`

**[DECISIÓN PENDIENTE D8] — Reglas de ciclo de vida**

| Regla candidata | Para qué | Costo/trampa |
|---|---|---|
| R1. `AbortIncompleteMultipartUpload` a 7 días, todo el bucket | Partes huérfanas de `sync` | Ninguno; buena práctica universal |
| R2. `tmp/`: expirar actuales a 1 día, versiones no actuales a 1 día, borrar delete markers huérfanos | Limpieza de la demo (D7) | Ninguno |
| R3. Todo el bucket: `NoncurrentVersionExpiration` a 30 días (o conservar N versiones) | Que el versionado no crezca sin límite | Pierdes la recuperación después de 30 días; en datos regulados se fijaría según la política de retención |
| R4. `raw/` → Standard-IA a 30 días | La que sugiere el enunciado | Mínimo 128 KB/objeto y 30 días; cobra recuperación; el proyecto leerá `raw/` en las sesiones 21–25 → ahorro casi nulo |

*Recomendación:* **R1 + R2 + R3**, y documentar R4 como alternativa analizada
(o aplicarla solo a `raw/` si el usuario quiere mostrar la transición, sabiendo
que el lab no llegará a ver el efecto en 30 días). Configurar con
`put-bucket-lifecycle-configuration` y un JSON documentado aparte (sin
comentarios dentro del JSON). **Ojo:** `put-bucket-lifecycle-configuration`
**reemplaza** todas las reglas; siempre enviar el conjunto completo.

**Presigned URL:** con boto3 `generate_presigned_url("get_object", ...,
ExpiresIn=3600)` sobre un objeto de texto inventado (p. ej.
`tmp/presigned/hola.txt`). Probar con `curl` → 200; tras 1 h (o con una URL
extra de `ExpiresIn=60` para no esperar) → 403 `Request has expired`.
Documentar la URL **solo después de caducada**, y aun así censurar el
`X-Amz-Credential` (contiene el Access Key ID) — `gitleaks` lo detectaría.
Explicar: hereda permisos de quien firma, máximo 7 días, secreto al portador.

### Paso 10 — Borrar y recuperar (Act. 10) → `operaciones.md`

Secuencia con un objeto de prueba inventado (no con datos de `raw/`):
1. `put-object` → anotar `VersionId`.
2. `delete-object` sin versión → la respuesta trae `DeleteMarker: true`.
3. `head-object` → 404; `aws s3 ls` ya no lo muestra.
4. `list-object-versions --prefix ...` → se ven la versión con datos y el
   marker.
5. `delete-object --version-id <id del marker>` → el objeto vuelve.
6. `head-object` → 200 y mismo ETag/contenido.

Explicar qué es un delete marker y por qué el objeto no se había borrado.
Mencionar que en producción regulada se añadiría Object Lock / MFA Delete.

### Paso 11 — Bono opcional (D9)

**[DECISIÓN PENDIENTE D9]** — ¿Hacer la política de bucket que niega todo lo
que no venga por HTTPS (`Condition: {"Bool": {"aws:SecureTransport":
"false"}}`, `Effect: Deny`, `Principal: "*"`, ARN de bucket **y** de objetos)?
*Recomendación:* sí (≈ 15 líneas, sin costo, muy relevante en pharma), y volver a
correr `pytest -m integracion`. Recordar: es un **Explicit Deny**, gana a
cualquier Allow; si se escribe mal puede bloquear al propio usuario (se
corrige con `delete-bucket-policy`). Los otros bonos (Registry of Open Data,
snappy vs. zstd) se ofrecen solo si sobra tiempo.

### Paso 12 — Cierre

1. `gitleaks detect --source . --log-opts="--all"` (repo + historial) y
   `gitleaks dir tu-entrega/` → 0 hallazgos.
2. Revisar salidas de notebooks y capturas: sin Account ID, ARNs con ID, llaves
   ni URLs vigentes.
3. "Apagar la luz" **sin borrar el bucket** (se usa en las sesiones 21–25):
   confirmar que `tmp/` quedó vacío incluidas versiones
   (`list-object-versions --prefix tmp/`), revisar Cost Explorer filtrando por
   `Proyecto=tesis` y que el presupuesto siga activo.
4. `README.md` de la entrega con checklist de los 11 criterios de evaluación y
   dónde se demuestra cada uno.
5. Actualizar `MEMORIA.md` con el estado final y lo que se reutiliza en la
   sesión 21 (nombre del bucket como `<bucket>`, convención de llaves, ruta del
   Parquet).

---

## 4. Mapa de criterios de evaluación → evidencia

| Criterio | Dónde se demuestra |
|---|---|
| Bucket no público | Paso 1: BPA cuenta + bucket, `curl` → 403 |
| Versionado y cifrado desde la creación | Paso 1: salidas de `get-bucket-*` + captura |
| Zonas documentadas con porqué | `arquitectura_datalake.md` |
| `listar` pagina con > 1 000 | Paso 5: test moto 1 500 + demo real |
| ≥ 3 códigos de `ClientError` | `s3util` + tests |
| `pytest` pasa | `pytest -q` |
| Números medidos, mediana ≥ 3 | `benchmark.ipynb` |
| Lectura sin descargar | `benchmark.ipynb`, sección S3 |
| Recuperación de borrado | `operaciones.md` |
| `gitleaks` limpio | Paso 12 |
| Commits descriptivos | Ramas `s20/*`, Conventional Commits |

## 5. Riesgos que el Auditor revisará

- `listar` sin paginador o que pierde la última página.
- `existe()` que confunde 403 con "no existe".
- Excepciones tragadas (`except Exception: pass`) o `print` en lugar de lanzar.
- Pruebas que tocan AWS real sin marcador o sin credenciales falsas.
- Benchmark con una sola corrida, sin mediana, o comparando cosas distintas.
- Particionado sin `=` o que DuckDB no aprovecha.
- Account ID, Access Key ID (en presigned URLs) o ARNs completos en el repo.
- Objetos de prueba borrados pero con versiones vivas.
- `put-bucket-lifecycle-configuration` que pisó reglas previas.
