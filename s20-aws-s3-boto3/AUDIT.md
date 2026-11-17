# Auditoría — Lab 20: Data lake clínico en S3 con boto3 (`s20-aws-s3-boto3`)

**Fecha:** 2026-11-17  
**Rol:** Fase 3 — Auditor (Argon)  
**Alcance revisado:** `AGENTS.md`, `ENUNCIADO.md`, `SPECS.md`, `MEMORIA.md`, `tu-entrega/DECISIONES.md`, `tu-entrega/README.md`, `tu-entrega/arquitectura_datalake.md`, `tu-entrega/operaciones.md`, `tu-entrega/benchmark.ipynb`, `tu-entrega/s3util/`, `tu-entrega/tests/`, `tu-entrega/scripts/`, `tu-entrega/capturas/`, `.gitignore` e historial Git.

---

## 1. Resumen ejecutivo

| Severidad | Cantidad | IDs | Estado |
|---|---:|---|---|
| **Alta** | 1 | `A1` | `[CORREGIDO]` |
| **Media** | 3 | `A2`, `A3`, `A4` | `[CORREGIDO]` |
| **Baja** | 2 | `A5`, `A6` | `[CORREGIDO]` |
| **Total** | **6** | `A1`–`A6` | **Listo para Reauditoría** |

---

## 2. Verificación contra criterios de evaluación, reglas no negociables y errores silenciosos (`SPECS.md` §5 y §6)

| Rubro / Error silencioso (`SPECS.md` §5) | Veredicto | Evidencia verificada |
|---|---|---|
| Identidad IAM (`user/`, no `:root`) antes de operar | **Cumplido** | `arquitectura_datalake.md:31-36` (`arn:aws:iam::<ACCOUNT_ID>:user/jorge-labs`) |
| Bucket no público (BPA cuenta + bucket + prueba negativa) | **Cumplido** | `arquitectura_datalake.md:41-63`, `110-118` (`curl -I` → `403 Forbidden`), `capturas/bucket_permisos.png` |
| Versionado y cifrado activos desde la creación + tag `Proyecto=tesis` | **Cumplido** | `arquitectura_datalake.md:12-25`, `67-106`, `capturas/bucket_propiedades.jpg` |
| Zonas documentadas, convención de llaves y porqué del particionado | **Con observación (`A5`)** | `arquitectura_datalake.md:124-170` (documentación completa; discrepancia entre estimación de ~12 particiones en §4 y 110 reales en §5) |
| Ingesta idempotente con `aws s3 sync` (`--dryrun`, corrida 1 y corrida 2 vacía) | **Cumplido** | `operaciones.md:14-101` (15 tablas clínicas, `1.4 GiB`, segunda corrida sin transferencias) |
| `listar()` con paginador de `boto3` (> 1 000 objetos en `moto` y en AWS real) | **Cumplido** | `s3util/nucleo.py:108-113` (`get_paginator("list_objects_v2")`), `tests/test_s3util.py:100-115` (1 500 objetos + control `IsTruncated=True`), `operaciones.md:109-118` (`1200` objetos) |
| `existe()` distingue `404` (`False`) de `403` (`AccesoDenegado`) | **Cumplido** | `s3util/nucleo.py:91-103`, probado con `Stubber` en `tests/test_s3util.py:68-78` |
| Traducción completa de `ClientError` (`NoSuchKey`, `NoSuchBucket`, `AccessDenied`) | **Fallido en `subir()` (`A1`) y ARN en `listar()` (`A2`)** | `subir()` usa `upload_file`, que lanza `S3UploadFailedError` (no `ClientError`); `listar()` arma ARN de objeto con prefijo para `s3:ListBucket` |
| Sin excepciones tragadas (`except Exception: pass`) y uso de `logging` | **Cumplido** | `s3util/nucleo.py:12, 35-117` (encadenamiento `raise ... from exc` y `logger.info`) |
| Pruebas unitarias aisladas de AWS real (`conftest.py` + `pytest.ini`) | **Cumplido** | `tests/conftest.py:12-26` (credenciales falsas y `/dev/null`), `pytest.ini:6` (`-m "not integracion"`), `9 passed` verificado en auditoría |
| Conversión CSV a Parquet particionado Hive (`anio=`) y conteo exacto | **Cumplido** | `scripts/convertir_parquet.py:19-66`, `arquitectura_datalake.md:176-295` (`5,719,327` filas CSV == Parquet, `128.3 MiB` en `curated/`) |
| Benchmark local con números medidos, mediana de ≥ 3 corridas (`n=5`) y gráfica | **Cumplido** | `benchmark.ipynb` celdas 1–5 (`n=5`, mediana + min/max, tabla generada por código y figura de 3 paneles) |
| Lectura directa desde S3 sin descargar (`pandas+s3fs` y `duckdb` con `EXPLAIN ANALYZE`) | **Cumplido** | `benchmark.ipynb` celdas 6–8 (`pandas+s3fs` `1.602 s`, `Archivos creados: []`; DuckDB `0.144 s` con `WHERE anio = 2025` vs `24.686 s` sin filtro; `Scanning Files: 1/110`, `#GET: 1`) |
| Reglas de ciclo de vida en un único JSON sin pisar reglas previas | **Cumplido** | `scripts/lifecycle.json:1-55` y `operaciones.md:135-201` (5 reglas `Enabled`: R1, R2a, R2b, R3a, R3b; `raw/` excluida) |
| Presigned URL probada vigente (`200`) y caducada (`403 Request has expired`), con `X-Amz-Credential` censurado | **Cumplido** | `scripts/demo_presigned.py:22-63` y `operaciones.md:208-243` |
| Secuencia de 6 pasos de borrado y recuperación con `VersionId` y *delete marker* | **Cumplido** | `operaciones.md:249-340` |
| Bono D9: Política de bucket solo-HTTPS (`aws:SecureTransport=false`) | **Cumplido** | `scripts/politica_solo_https.json:1-20` y `operaciones.md:351-378` |
| Limpieza de objetos y versiones de prueba en `tmp/` | **Incompleto (`A4`)** | `operaciones.md:120` no pega la salida de `list-object-versions`; en `README.md:142-148` siguen vivas `1204` versiones y `1204` *delete markers* pendientes del ciclo de R2a/R2b |
| Cero credenciales, Account IDs o ARNs con ID en archivos y capturas | **Cumplido en archivos, escaneo `gitleaks` incompleto (`A3`)** | Búsqueda por regex y revisión visual de las 3 capturas limpias; sin embargo, `gitleaks detect` se corrió antes de hacer commit de los Pasos 3–12 |
| Código versionado con commits descriptivos | **Incumplido (`A3`)** | Solo existe 1 commit (`032731f`, Pasos 0–2) en la rama `s20/preparacion`; los archivos de los Pasos 3–12 están sin confirmar (*untracked* / *modified*) |

---

## 3. Hallazgos detallados

### `A1` — [Severidad: ALTA] `[CORREGIDO]` `subir()` no traduce `ClientError` (`NoSuchBucket`, `AccessDenied`) a excepciones propias porque `upload_file` lanza `S3UploadFailedError`

- **Archivo y línea:** [nucleo.py](file:///home/jorge/Documentos/data-sciences-labs/s20-aws-s3-boto3/tu-entrega/s3util/nucleo.py#L63-L75) y [test_s3util.py](file:///home/jorge/Documentos/data-sciences-labs/s20-aws-s3-boto3/tu-entrega/tests/test_s3util.py#L23-L83)
- **Escenario de falla:** En `s3util.nucleo.subir()`, la llamada `_cliente(perfil).upload_file(str(ruta), bucket, llave)` delega en `S3Transfer.upload_file` (`boto3/s3/inject.py`), el cual captura internamente `botocore.exceptions.ClientError` y lanza `boto3.exceptions.S3UploadFailedError` (que hereda de `Boto3Error`, **no** de `ClientError`, guardando el `ClientError` original en `exc.__context__` / `exc.__cause__`). Como resultado, el bloque `except ClientError as exc:` en `nucleo.py:73-74` es código muerto para `upload_file`: cuando `subir()` falla por un bucket inexistente (`NoSuchBucket`) o por falta de permisos (`AccessDenied` / `403` en `s3:PutObject`), escapa `boto3.exceptions.S3UploadFailedError` crudo en lugar de lanzar `BucketNoExiste` o `AccesoDenegado` (violando D4 en `SPECS.md` y el requisito de la Actividad 4 en `ENUNCIADO.md`). Las pruebas unitarias en `tests/test_s3util.py` probaron `BucketNoExiste` únicamente sobre `listar()` y `AccesoDenegado` únicamente sobre `existe()` y `descargar()`, dejando sin cubrir los caminos de error de `subir()`.
- **Corrección sugerida:**
  1. En `s3util/nucleo.py`, importar `from boto3.exceptions import S3UploadFailedError` y capturar `S3UploadFailedError` en `subir()`: extraer la causa subyacente (`causa = exc.__cause__ or exc.__context__`); si `causa` es instancia de `ClientError`, hacer `raise _traducir_client_error(causa, "s3:PutObject", bucket, llave) from exc`; si es `(NoCredentialsError, PartialCredentialsError)`, lanzar `PerfilInvalido(...) from exc`; en cualquier otro caso, lanzar `S3UtilError(...) from exc`.
  2. En `tests/test_s3util.py`, agregar pruebas unitarias para `subir()` cuando el bucket no existe (`pytest.raises(BucketNoExiste)`) y cuando ocurre `AccessDenied` con `Stubber` (`pytest.raises(AccesoDenegado)` verificando que el mensaje incluya `s3:PutObject` y `arn:aws:s3:::<bucket>/<llave>`).

---

### `A2` — [Severidad: MEDIA] `[CORREGIDO]` `_traducir_client_error` reporta un ARN de objeto (`arn:aws:s3:::bucket/prefijo`) para la acción a nivel de bucket `s3:ListBucket` en `listar()`

- **Archivo y línea:** [nucleo.py](file:///home/jorge/Documentos/data-sciences-labs/s20-aws-s3-boto3/tu-entrega/s3util/nucleo.py#L47-L60) y [nucleo.py](file:///home/jorge/Documentos/data-sciences-labs/s20-aws-s3-boto3/tu-entrega/s3util/nucleo.py#L116-L117)
- **Escenario de falla:** Cuando `listar(bucket, prefijo="raw/")` recibe un `ClientError` (por ejemplo, `AccessDenied`), la línea 117 invoca `_traducir_client_error(exc, "s3:ListBucket", bucket, prefijo)` pasando `prefijo` en el argumento `llave`. La línea 50 construye entonces `arn = f"arn:aws:s3:::{bucket}/{llave}"`, generando el mensaje:
  > `Acceso denegado (AccessDenied) al ejecutar 's3:ListBucket' sobre arn:aws:s3:::omop-tesis-jhr-2026/raw/. Verifica los permisos en el IAM Policy Simulator (sesión 19) antes de ampliar la política.`
  
  En AWS IAM (`AGENTS.md:100-102`, `ENUNCIADO.md:92-94`), `s3:ListBucket` es una acción a nivel de **bucket** cuyo `Resource` ARN debe ser siempre `arn:aws:s3:::<bucket>` (mientras que el prefijo se restringe mediante `Condition: {"StringLike": {"s3:prefix": [...]}}`), jamás un ARN de objeto `arn:aws:s3:::<bucket>/<prefijo>`. Indicarle al usuario un ARN con `/<prefijo>` para `s3:ListBucket` lo induciría a un error en el IAM Policy Simulator o al redactar la política IAM.
- **Corrección sugerida:**
  1. En `nucleo.py:117`, pasar `llave=""` al traducir errores de `s3:ListBucket` (o tratar `accion == "s3:ListBucket"` en `_traducir_client_error` para que el ARN sea siempre `arn:aws:s3:::{bucket}`, añadiendo opcionalmente en el texto `(prefijo={prefijo!r})` como contexto separado del ARN).
  2. Añadir en `tests/test_s3util.py` un caso con `Stubber` para `AccessDenied` en `listar("omop-tesis-test", "raw/")` comprobando que el mensaje contiene `"s3:ListBucket"` y `"arn:aws:s3:::omop-tesis-test"` sin `"/raw/"` pegado al ARN.

---

### `A3` — [Severidad: MEDIA] `[CORREGIDO]` Código y entregables de los Pasos 3–12 sin confirmar en Git y escaneo de `gitleaks` ejecutado sobre historial incompleto

- **Archivo y línea:** [README.md](file:///home/jorge/Documentos/data-sciences-labs/s20-aws-s3-boto3/tu-entrega/README.md#L103-L126) (y estado de Git en la rama `s20/preparacion`)
- **Escenario de falla:**
  1. El criterio 11 de `ENUNCIADO.md:208` exige *"El código está versionado con commits descriptivos"* y la tabla de `README.md:104` lo marca como `Cumplido`. No obstante, al auditar el repositorio (`git status` / `git log`), en la rama `s20/preparacion` solo existe un único commit (`032731f`, correspondiente a los Pasos 0–2). Todo el trabajo de los Pasos 3 al 12 (`tu-entrega/s3util/`, `tu-entrega/tests/`, `tu-entrega/scripts/`, `tu-entrega/benchmark.ipynb`, `tu-entrega/operaciones.md`, `tu-entrega/README.md`, `tu-entrega/pytest.ini`, `tu-entrega/capturas/cost_explorer_cierre.png`, y `tu-entrega/arquitectura_datalake.md` §5) está sin confirmar en Git (*untracked* o *modified*).
  2. Debido a que `gitleaks detect --source . --log-opts="--all -- s20-aws-s3-boto3"` (`README.md:114`) solo analiza commits confirmados en Git, dicho comando escaneó únicamente los 5 commits iniciales (`67.03 KB`) y no analizó ninguno de los archivos creados en los Pasos 3–12. Adicionalmente, los comandos `gitleaks dir` en `README.md:119-125` solo se corrieron sobre 2 archivos (`operaciones.md` y `benchmark.ipynb`), omitiendo `s3util/`, `tests/`, `scripts/` y `README.md` (`SPECS.md` Paso 12.1 y §6).
- **Corrección sugerida:**
  1. Confirmar en Git todos los archivos de entrega de `s20-aws-s3-boto3/` mediante commits descriptivos (Conventional Commits separados por bloque lógico: módulo `s3util` + pruebas, conversión Parquet + benchmark, operaciones S3 + cierre).
  2. Tras realizar los commits, ejecutar nuevamente `~/.local/bin/gitleaks detect --source . --log-opts="--all -- s20-aws-s3-boto3"` y `~/.local/bin/gitleaks dir s20-aws-s3-boto3/tu-entrega` (excluyendo `.venv/` o pasando las rutas rastreadas) y actualizar la evidencia en `tu-entrega/README.md`.

---

### `A4` — [Severidad: MEDIA] `[CORREGIDO]` Falta pegar la salida real de `list-object-versions --prefix tmp/` en `operaciones.md` y persisten 1 204 versiones vivas en `tmp/` al momento del cierre

- **Archivo y línea:** [operaciones.md](file:///home/jorge/Documentos/data-sciences-labs/s20-aws-s3-boto3/tu-entrega/operaciones.md#L120) y [README.md](file:///home/jorge/Documentos/data-sciences-labs/s20-aws-s3-boto3/tu-entrega/README.md#L131-L148) (frente a `SPECS.md` D7 l. 326, Paso 12.3 l. 449–450, §5 l. 485 y §6 l. 498)
- **Escenario de falla:**
  1. `SPECS.md` §6 (fila Paso 5) exige pegar en `operaciones.md` la salida real de `list-object-versions --prefix tmp/` (*"Pega la salida real, no un resumen"*), y `AGENTS.md:33` establece un dueño por tipo de información. En `operaciones.md:120` no se pegó la salida del comando, sino solo una nota en prosa que remite a `README.md`.
  2. En `README.md:142-148`, la salida muestra `{"Versiones": 1204, "DeleteMarkers": 1204}`. Aunque la regla de ciclo de vida `R2a`/`R2b` está correctamente configurada a 1 día y S3 ya estampó `expiry-date="Thu, 19 Nov 2026 00:00:00 GMT"` (por el redondeo de S3 Lifecycle a la medianoche UTC posterior a cumplir 24 h), al cerrarse la entrega el mismo día de la subida (`2026-11-17`), las 1 204 versiones y 1 204 *delete markers* siguen presentes en el bucket (`SPECS.md` §5: *"Objetos de prueba borrados pero con versiones vivas"* y Paso 12.3: *"confirmar que `tmp/` quedó vacío incluidas versiones"*).
- **Corrección sugerida:**
  1. Pegar la salida real de `aws s3api list-object-versions --bucket omop-tesis-jhr-2026 --prefix tmp/ ...` directamente en `tu-entrega/operaciones.md` §2 (dejando en `README.md` un enlace a `operaciones.md` §2 para evitar duplicar bloques de evidencia).
  2. En Fase 4, presentar al usuario las dos opciones para cerrar la verificación de `tmp/` vacío: (a) esperar a la ejecución de `R2a`/`R2b` o purgar las versiones de `tmp/` (`tmp/paginacion/`, `tmp/presigned/`, `tmp/recuperacion/`, `tmp/pruebas/`) para pegar `{"Versiones": 0, "DeleteMarkers": 0}` de inmediato, o (b) aprobar explícitamente el cierre con las cabeceras `x-amz-expiration` vigentes dada la ventana asíncrona de 24–36 h de S3 Lifecycle bajo la decisión D7.

---

### `A5` — [Severidad: BAJA] `[CORREGIDO]` Inconsistencia interna en `arquitectura_datalake.md` (§4 vs. §5) entre las `~12` particiones estimadas y las `110` particiones reales (*small files* en cola histórica `1917–2015`)

- **Archivo y línea:** [arquitectura_datalake.md](file:///home/jorge/Documentos/data-sciences-labs/s20-aws-s3-boto3/tu-entrega/arquitectura_datalake.md#L161) frente a [arquitectura_datalake.md](file:///home/jorge/Documentos/data-sciences-labs/s20-aws-s3-boto3/tu-entrega/arquitectura_datalake.md#L177-L294)
- **Escenario de falla:** En `arquitectura_datalake.md:161` (§4, escrita en el Paso 2) quedó redactado en futuro: *"Con ~12 años de datos principales en `observations` (2015–2026), se generan ~12 particiones de tamaño equilibrado (del orden de ~10–15 MB cada una en Parquet, que se medirá exactamente en el Paso 7), evitando el problema de small files y reduciendo las peticiones GET en S3"*. Sin embargo, en §5 (`arquitectura_datalake.md:177-294`), la conversión real de `observations.csv` produjo **110 particiones anuales** (`anio=1917` a `anio=2026`): mientras que las 11 particiones recientes (`2016–2026`) pesan entre `4.8 MiB` y `8.6 MiB` (~87.6 MiB, ~68 % del total), las 99 particiones históricas (`1917–2015`) pesan entre `3.4 KiB` y `1.8 MiB` (81 de ellas `< 1 MiB`). Esa cola histórica de archivos diminutos explica por qué en `benchmark.ipynb` (Celda 7) la consulta de DuckDB sobre S3 sin filtro tardó `24.686 s` (110 archivos escaneados por HTTP) mientras que con `WHERE anio = 2025` tardó `0.144 s` (`1/110` archivos, `#GET: 1`).
- **Corrección sugerida:** Actualizar `arquitectura_datalake.md:161` (y añadir una nota breve en §5) eliminando la frase en tiempo futuro (*"que se medirá exactamente en el Paso 7"*) y explicando el resultado medido: el grueso clínico reciente (`2016–2026`, 11 particiones) mantiene tamaños de `4.8–8.6 MiB` ideales para consultas de cohorte, mientras que la cola histórica de antecedentes (`1917–2015`, 99 particiones de `3.4 KiB–1.8 MiB`) ilustra empíricamente el *small files problem* en lecturas completas desde S3 (`24.686 s`) y cómo la poda de particiones (`WHERE anio = 2025`, `0.144 s`) lo neutraliza en consultas acotadas por ventana temporal.

---

### `A6` — [Severidad: BAJA] `[CORREGIDO]` Nota provisional obsoleta `*(se completa en Pasos 7–8)*` en el índice de `tu-entrega/README.md`

- **Archivo y línea:** [README.md](file:///home/jorge/Documentos/data-sciences-labs/s20-aws-s3-boto3/tu-entrega/README.md#L12)
- **Escenario de falla:** En `tu-entrega/README.md:12` permanece el texto `*(se completa en Pasos 7–8)*` junto al enlace de `benchmark.ipynb`, contradiciendo la tabla de criterios en `README.md:100-101` y el propio archivo `benchmark.ipynb`, que ya cuenta con todas sus celdas ejecutadas y salidas guardadas.
- **Corrección sugerida:** Eliminar `*(se completa en Pasos 7–8)*` de `tu-entrega/README.md:12`.
