# Entrega Lab 20 — Data lake clínico en S3 con boto3

**Bucket:** `omop-tesis-jhr-2026` (`us-east-2`)  
**Perfil AWS CLI / boto3:** `tesis`

---

## Índice de entregables

1. [`arquitectura_datalake.md`](./arquitectura_datalake.md) — Configuración del bucket (Act. 1), zonas, nombres, particionado `anio=` y conteos (Act. 2 y 6)
2. [`s3util/`](./s3util/) — Módulo Python (`subir`, `descargar`, `listar`, `existe`) con excepciones propias y pruebas en [`tests/`](./tests/) (Act. 4 y 5)
3. [`benchmark.ipynb`](./benchmark.ipynb) — Comparación medida CSV vs. Parquet y lectura directa desde S3 con `pandas`/`s3fs` y DuckDB (Act. 7 y 8)
4. [`operaciones.md`](./operaciones.md) — `sync` idempotente, demo de paginación, ciclo de vida, *presigned URL*, recuperación de borrado y bono HTTPS (Act. 3, 5, 9, 10 y 11)
5. [`DECISIONES.md`](./DECISIONES.md) — Registro de decisiones D1–D9

---

## Evidencia de pruebas (`s3util/`)

### Pruebas unitarias (`moto` + `Stubber`, sin tocar AWS)

```text
$ .venv/bin/pytest -v
============================= test session starts ==============================
platform linux -- Python 3.12.3, pytest-9.2.0, pluggy-1.7.0 -- /home/jorge/Documentos/data-sciences-labs/s20-aws-s3-boto3/tu-entrega/.venv/bin/python
cachedir: .pytest_cache
rootdir: /home/jorge/Documentos/data-sciences-labs/s20-aws-s3-boto3/tu-entrega
configfile: pytest.ini
testpaths: tests
plugins: platformdirs-4.14.5, anyio-4.16.0
collecting ... 
collected 13 items / 4 deselected / 9 selected                                 

tests/test_s3util.py::test_subir_y_descargar_ida_y_vuelta PASSED         [ 11%]
tests/test_s3util.py::test_subir_archivo_local_inexistente PASSED        [ 22%]
tests/test_s3util.py::test_existe_true_y_false PASSED                    [ 33%]
tests/test_s3util.py::test_descargar_llave_no_existe_404_y_nosuchkey PASSED [ 44%]
tests/test_s3util.py::test_listar_y_subir_bucket_no_existe PASSED        [ 55%]
tests/test_s3util.py::test_access_denied_en_existe_descargar_subir_y_listar_con_stubber PASSED [ 66%]
tests/test_s3util.py::test_perfil_invalido PASSED                        [ 77%]
tests/test_s3util.py::test_listar_con_prefijo_y_prefijo_vacio PASSED     [ 88%]
tests/test_s3util.py::test_listar_pagina_1500_objetos_y_control_truncado PASSED [100%]

======================= 9 passed, 4 deselected in 4.47s ========================
```

### Pruebas de integración contra `omop-tesis-jhr-2026`

```text
$ .venv/bin/pytest -m integracion -v
================================= test session starts =================================
platform linux -- Python 3.12.3, pytest-9.2.0, pluggy-1.7.0 -- /home/jorge/Documentos/data-sciences-labs/s20-aws-s3-boto3/tu-entrega/.venv/bin/python
cachedir: .pytest_cache
rootdir: /home/jorge/Documentos/data-sciences-labs/s20-aws-s3-boto3/tu-entrega
configfile: pytest.ini
testpaths: tests
plugins: platformdirs-4.14.5, anyio-4.16.0
collecting ... 
collected 13 items / 9 deselected / 4 selected                                        

tests/test_s3util.py::test_integracion_subir_existe_listar_descargar PASSED     [ 25%]
tests/test_s3util.py::test_integracion_existe_false_en_llave_inexistente PASSED [ 50%]
tests/test_s3util.py::test_integracion_descargar_llave_no_existe PASSED         [ 75%]
tests/test_s3util.py::test_integracion_listar_raw_real PASSED                   [100%]

=========================== 4 passed, 9 deselected in 1.57s ===========================
```

---

## Cómo reproducir

```bash
cd s20-aws-s3-boto3/tu-entrega
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt

# Pruebas unitarias offline (moto + Stubber, no requieren AWS)
.venv/bin/pytest -v

# Pruebas de integración contra el bucket real (requieren perfil tesis)
.venv/bin/pytest -m integracion -v

# Conversión local CSV -> Parquet particionado por anio=
.venv/bin/python scripts/convertir_parquet.py
```

---

## Checklist de criterios de evaluación

| # | Criterio | Estado | Dónde se demuestra |
|---|---|---|---|
| 1 | Bucket **no** públicamente accesible | Cumplido | [`arquitectura_datalake.md` §1](./arquitectura_datalake.md#1-configuración-del-bucket-actividad-1) (BPA cuenta + bucket, `curl -I` → `403`, captura [`bucket_permisos.png`](./capturas/bucket_permisos.png)) |
| 2 | Versionado y cifrado activos desde la creación | Cumplido | [`arquitectura_datalake.md` §1](./arquitectura_datalake.md#1-configuración-del-bucket-actividad-1) (`get-bucket-versioning`: `Enabled`, `get-bucket-encryption`: `AES256`, captura [`bucket_propiedades.jpg`](./capturas/bucket_propiedades.jpg)) |
| 3 | Estructura de zonas documentada, con el porqué del particionado | Cumplido | [`arquitectura_datalake.md` §2–5](./arquitectura_datalake.md#2-zonas-del-data-lake-y-minimizaci%C3%B3n-de-datos-actividad-2) (`raw/`, `staging/`, `curated/`, `tmp/`, partición `anio=` y *"Por qué NO particioné por X"*) |
| 4 | `listar` pagina correctamente, demostrado con > 1 000 objetos | Cumplido | [`tests/test_s3util.py`](./tests/test_s3util.py) (test `moto` de 1 500 objetos + control `IsTruncated=True`) y [`operaciones.md` §2](./operaciones.md#2-demostración-real-de-paginación--1-000-objetos-actividad-5) (`demo_paginacion.py`: 1 200 subidos y listados) |
| 5 | El módulo distingue al menos tres códigos de `ClientError` | Cumplido | [`s3util/nucleo.py`](./s3util/nucleo.py) (`NoSuchKey`/`404` → `LlaveNoExiste`, `NoSuchBucket` → `BucketNoExiste`, `AccessDenied`/`403` → `AccesoDenegado`, más `PerfilInvalido`) |
| 6 | Hay pruebas con `pytest` y pasan | Cumplido | Arriba: `9 passed` unitarias (`moto`/`Stubber`) y `4 passed` integración (`omop-tesis-jhr-2026`) |
| 7 | Comparación CSV/Parquet con números medidos, mediana de ≥ 3 corridas | Cumplido | [`benchmark.ipynb` §1–3](./benchmark.ipynb) (5 corridas locales, mediana + min/max, tabla generada por código y gráfica) |
| 8 | Lectura desde S3 sin descargar el archivo completo | Cumplido | [`benchmark.ipynb` §4](./benchmark.ipynb) (`pandas`+`s3fs` en `1.602 s` sin archivos locales; DuckDB `WHERE anio = 2025` en `0.144 s` vs `24.686 s`, `EXPLAIN ANALYZE`: `1/110` archivos, `36.9 KiB`) |
| 9 | Recuperación de un objeto borrado mediante versionado | Cumplido | [`operaciones.md` §4](./operaciones.md#4-borrado-y-recuperación-con-versionado-actividad-10) (secuencia completa de 6 pasos con `VersionId` y explicación de *delete marker*) |
| 10 | Cero credenciales en el repositorio (`gitleaks` limpio) | Cumplido | Ver sección `gitleaks` abajo (0 hallazgos en entregables e historial de `s20-aws-s3-boto3`) |
| 11 | Código versionado con commits descriptivos | Cumplido | Rama `s20/preparacion` con commits estilo Conventional Commits |
| Bono | Política de bucket solo-HTTPS (`aws:SecureTransport`) | Cumplido | [`operaciones.md` §5](./operaciones.md#5-política-de-bucket-solo-https-bono-actividad-11--d9) (`--endpoint-url http://...` → `AccessDenied`, `pytest -m integracion` `4 passed`) |

---

## Evidencia de cierre (`gitleaks`, `tmp/` y Cost Explorer)

### `gitleaks` sobre historial de `s20-aws-s3-boto3` y entregables

```text
$ ~/.local/bin/gitleaks detect --source . --log-opts="--all -- s20-aws-s3-boto3"
10:57AM INF 8 commits scanned.
10:57AM INF scanned ~264249 bytes (264.25 KB) in 187ms
10:57AM INF no leaks found

$ ~/.local/bin/gitleaks dir s20-aws-s3-boto3/tu-entrega/s3util
10:54AM INF scanned ~14970 bytes (14.97 KB) in 5.02ms
10:54AM INF no leaks found

$ ~/.local/bin/gitleaks dir s20-aws-s3-boto3/tu-entrega/tests
10:54AM INF scanned ~41768 bytes (41.77 KB) in 11.2ms
10:54AM INF no leaks found

$ ~/.local/bin/gitleaks dir s20-aws-s3-boto3/tu-entrega/scripts
10:54AM INF scanned ~9278 bytes (9.28 KB) in 4.46ms
10:54AM INF no leaks found

$ ~/.local/bin/gitleaks dir s20-aws-s3-boto3/tu-entrega/operaciones.md
10:54AM INF scanned ~22117 bytes (22.12 KB) in 13.9ms
10:54AM INF no leaks found

$ ~/.local/bin/gitleaks dir s20-aws-s3-boto3/tu-entrega/benchmark.ipynb
10:54AM INF scanned ~106629 bytes (106.63 KB) in 54.4ms
10:54AM INF no leaks found

$ ~/.local/bin/gitleaks dir s20-aws-s3-boto3/tu-entrega/arquitectura_datalake.md
10:54AM INF scanned ~19633 bytes (19.63 KB) in 7.94ms
10:54AM INF no leaks found

$ ~/.local/bin/gitleaks dir s20-aws-s3-boto3/tu-entrega/README.md
10:54AM INF scanned ~8562 bytes (8.56 KB) in 9.54ms
10:54AM INF no leaks found
```

### Limpieza de `tmp/` y Cost Explorer ("apagar la luz" sin borrar el bucket)

- El bucket **`omop-tesis-jhr-2026`** se conserva activo para las sesiones 21–25.
- La zona efímera `tmp/` quedó completamente vacía: `0` objetos actuales (`aws s3 ls`), `0` versiones y `0` *delete markers* (`list-object-versions --prefix tmp/` → `{"Versiones": 0, "DeleteMarkers": 0}` tras purgar las 2 408 entradas de prueba con `--purgar-tmp`, además de quedar activas las reglas `R2a`/`R2b` a 1 día). Ver comandos y salida completa en [`operaciones.md` §2](./operaciones.md#2-demostración-real-de-paginación--1-000-objetos-actividad-5).
- **Cost Explorer:** filtrado por servicio **Amazon S3** (la cuenta está en AWS Free Plan, donde *Cost Allocation Tags* requiere migrar de plan, por lo que se mantiene el Free Plan y el presupuesto de **5 USD** con sus 4 alertas). Evidencia: [`capturas/cost_explorer_cierre.png`](./capturas/cost_explorer_cierre.png).
