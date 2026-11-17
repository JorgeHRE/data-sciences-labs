# MEMORIA — Lab 20 (estado del proyecto)

> El Constructor actualiza este archivo tras cada trozo verificado (2-3 líneas:
> qué se completó, resultado clave, siguiente punto de `SPECS.md`).

## 2026-11-16 — Fase 0/1 (Arquitecto)
- Generados `GUIA_ESTUDIO.md` y `SPECS.md`. Revisado el enunciado, los
  entregables del lab 19 y los datos Synthea locales (4.3 GB, sin modificar).
- 9 decisiones pendientes (D1-D9) marcadas en `SPECS.md` §2; ninguna resuelta.
- Protocolo ajustado (rama s20/ajustes-protocolo): Fase 4 de corrección y reauditoría, escalado de decisiones al Arquitecto, evidencia obligatoria (SPECS §6), un dueño por tipo de información, regla de datos remitida a D1.
- Plan aprobado por el usuario; SPECS, MEMORIA y AGENTS versionados (PR #142).
- D1 decidida (B: 15 tablas clínicas de Synthea, 1.41 GiB; minimización de datos). Registrada en SPECS §2 y tu-entrega/DECISIONES.md.
- D2 decidida (B: CLI, bucket `omop-tesis-jhr-2026` en us-east-2).
- D3 decidida (`observations` particionada por `anio=`; filtros por fecha).
- D4 (A: excepciones propias, 403 ≠ no existe) y D5 (B: perfil + cliente cacheado) decididas.
- D6 decidida (D: moto + Stubber para AccessDenied + integración marcada, sin subida masiva).
- D7 (A: `tmp/paginacion/` + expiración) y D8 (R1+R2+R3 sin `raw/`, R4 documentada) decididas.
- D9 decidida (política solo-HTTPS en el paso 11). **D1-D9 cerradas.**
- **Siguiente:** Fase 2 (Constructor), `SPECS.md` Paso 0, desde `main` tras mergear el PR del protocolo y las decisiones.

## 2026-11-17 — Fase 2 (Constructor)
- **Paso 0 completado:** rama `s20/preparacion` creada, `.gitignore` actualizado con exclusiones locales de `tu-entrega/`, `.venv` creado y `tu-entrega/requirements.txt` fijado (`boto3==1.43.117`, `s3fs==2026.9.0`, `pandas==3.1.1`, `pyarrow==26.0.1`, `duckdb==2.0.0`, `moto[s3]==5.2.5`, `pytest==9.2.0`). Verificación `import boto3, pandas, pyarrow, s3fs, duckdb` → `ok`.
- **Paso 1 (Trozo 1) completado:** identidad `user/jorge-labs` verificada (no `:root`), BPA a nivel cuenta activado y verificado (4 banderas en `true`), presupuesto de 5 USD activo (4 alertas; email del destinatario ya validado).
- **Paso 1 (Trozo 2) completado:** bucket `omop-tesis-jhr-2026` creado en `us-east-2` por CLI con BPA, versionado, cifrado `AES256` y etiqueta `Proyecto=tesis`.
- **Paso 1 (Trozo 3) completado:** verificados BPA de bucket (4×`true`), versionado (`Enabled`), cifrado (`AES256`), etiqueta (`Proyecto=tesis`), `curl -I` → `403 Forbidden` y capturas guardadas en `tu-entrega/capturas/`. Evidencia censurada registrada en `tu-entrega/arquitectura_datalake.md` §1.
- **Paso 2 completado:** documentadas las zonas (`raw/`, `staging/`, `curated/`, `tmp/`), minimización D1, convención de llaves Hive (`fecha_carga=`, `anio=`), particionado de `observations` por `anio=` (D3) y sección "Por qué no particioné por X" en `tu-entrega/arquitectura_datalake.md` §2–4. Nota: la cuenta en AWS Free Plan no permite activar Cost Allocation Tags sin migrar de plan; se mantiene el Free Plan y en Paso 12 se revisará Cost Explorer por servicio S3.
- **Paso 3 completado:** subidas 15 tablas clínicas Synthea (1.4 GiB) a `raw/synthea/fecha_carga=2026-11-17/` con `aws s3 sync`; segunda corrida vacía (idempotente). Evidencia registrada en `tu-entrega/operaciones.md` §1.
- **Paso 4 (Trozo 1) completado:** creados `s3util/__init__.py` y base de `s3util/nucleo.py` (jerarquía `S3UtilError`, `_cliente(perfil)` con `lru_cache`, `_traducir_client_error`). Verificado mapeo de `ProfileNotFound`, `404`/`NoSuchKey`, `NoSuchBucket`, `403`/`AccessDenied` y código genérico.
- **Paso 4 (Trozo 2) completado:** implementados `subir`, `descargar`, `existe` (404→`False`, 403→`AccesoDenegado`) y `listar` (con `get_paginator("list_objects_v2")`). Verificación smoke con `moto`: ida/vuelta, `existe`, `listar` vacío/con prefijo → OK.
- **Paso 4 (Trozo 3) completado:** creados `pytest.ini` (`addopts = -m "not integracion"`), `tests/conftest.py` (credenciales falsas y limpieza de `_cliente.cache_clear()`) y 8 pruebas unitarias en `tests/test_s3util.py` (`moto` + `Stubber` para `403`/`AccessDenied` y `NoSuchKey`). Verificación `.venv/bin/pytest -v` → `8 passed in 1.45s`.
- **Paso 4 (Trozo 4) completado:** añadidas en `tests/test_s3util.py` la prueba de paginación con 1 500 objetos + control `IsTruncated=True` y 4 pruebas `@pytest.mark.integracion`. Unitarias `.venv/bin/pytest -v` → `9 passed, 4 deselected in 4.28s`; integración `.venv/bin/pytest -m integracion -v` → `4 passed, 9 deselected in 1.57s`. Evidencia registrada en `tu-entrega/README.md`.
- **Paso 5 completado:** ejecutado `scripts/demo_paginacion.py` contra AWS real: `Subidos: 1200 | Listados por s3util.listar: 1200`, `aws s3 ls ... | wc -l` → `1200`, y `--limpiar` creó 1 200 delete markers (D7; versiones quedan pendientes de regla R2). Evidencia registrada en `tu-entrega/operaciones.md` §2.
- **Paso 6 (Trozo 1) completado:** creado y ejecutado `scripts/convertir_parquet.py` (`DATE` UTC, `VALUE` string, Hive `anio=YYYY`, Snappy). Verificación local: `5,719,327` filas CSV == `5,719,327` filas Parquet; tamaño local `129M` (vs `974M` CSV).
- **Paso 6 (Trozo 2) completado:** subido `curated/synthea/observations/` a S3 (`Total Objects: 110`, `Total Size: 128.3 MiB`). Evidencia registrada en `tu-entrega/arquitectura_datalake.md` §5.
- **Paso 7 completado:** ejecutado benchmark local en `tu-entrega/benchmark.ipynb` (`n=5` corridas, i5-14400F / 46.9 GiB RAM): disco `973.60 MiB` CSV vs `128.25 MiB` Parquet (`7.59x`); lectura completa mediana `3.859s` vs `1.173s` (`3.29x`); 1 columna `CODE` mediana `0.708s` vs `0.517s` (`1.37x`). Tabla y gráfica guardadas.
- **Paso 8 completado:** ejecutadas consultas directas a S3 en `benchmark.ipynb` sin descargar archivos locales (`[]`): `pandas+s3fs` (`433,936` filas, 4 cols, `anio=2025`) en `1.602 s`; `duckdb` sin filtro `24.686 s` vs `WHERE anio = 2025` en `0.144 s` (**171.4×** más rápido; `EXPLAIN ANALYZE`: `Scanning Files: 1/110`, `in: 36.9 KiB`, `#GET: 1`).
- **Paso 9 (Trozo 1) completado:** aplicado `scripts/lifecycle.json` (R1+R2a+R2b+R3a+R3b, sin `raw/`; R4 documentada) y verificado con `get-bucket-lifecycle-configuration` (5 reglas `Enabled`). Evidencia en `tu-entrega/operaciones.md` §3.1.
- **Paso 9 (Trozo 2) completado:** ejecutado `scripts/demo_presigned.py`: `curl` vigente → `200 OK` (con cabecera `x-amz-expiration` de `R2a` ya aplicada); tras 12 s con URL de 10 s → `403 Forbidden` (`Request has expired`). Evidencia censurada en `tu-entrega/operaciones.md` §3.2.
- **Paso 10 completado:** ejecutados los 6 pasos de borrado y recuperación sobre `tmp/recuperacion/nota.txt` (`P4CzRxqyJiaY_ED2fra_ndcKydFa7NF7` recuperado con mismo ETag `"6a5db33c75c2ed9c14d60d47661ab42d"` tras borrar el DeleteMarker `P_U2BwyGhjgl5nPVXh24v5bvNS6MrVRj`). Evidencia en `tu-entrega/operaciones.md` §4.
- **Paso 11 completado:** aplicada `scripts/politica_solo_https.json` (Bono D9); prueba negativa HTTP (`--endpoint-url http://...`) → `AccessDenied` (`explicit deny in a resource-based policy`) y `pytest -m integracion -v` → `4 passed in 1.62s`. Evidencia censurada en `tu-entrega/operaciones.md` §5.
- **Paso 12 completado (Cierre Fase 2):** `tmp/` sin objetos actuales (`1204` versiones/markers programados para expirar con R2a/R2b en 2026-11-19), captura de Cost Explorer guardada en `tu-entrega/capturas/cost_explorer_cierre.png` (presupuesto 5 USD activo, Free Plan preservado), `README.md` completado con checklist 11/11 + bono, y `gitleaks` limpio (`no leaks found`).
- **Reutilizable en Sesión 21:** bucket `<bucket>` = `omop-tesis-jhr-2026` (`us-east-2`, perfil `tesis`, solo-HTTPS activo); `raw/` = `s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/<tabla>.csv` (15 tablas); Parquet `observations` = `s3://omop-tesis-jhr-2026/curated/synthea/observations/anio=YYYY/part-0.parquet` (110 particiones); módulo `tu-entrega/s3util/`.
- **Siguiente:** Fase 3 — Auditoría por Argon (`AUDIT.md`) sobre `s20-aws-s3-boto3/`.

## 2026-11-17 — Fase 4 (Constructor: corrección de hallazgos)
- **Trozo 1 (`A1` + `A2`) completado:** `subir()` en `s3util/nucleo.py` ahora captura `S3UploadFailedError` y traduce su `ClientError` subyacente a `BucketNoExiste` / `AccesoDenegado`; `_traducir_client_error` usa ARN de bucket (`arn:aws:s3:::<bucket>`) para `s3:ListBucket`. Pruebas unitarias ampliadas en `tests/test_s3util.py` → `9 passed, 4 deselected in 4.47s`.
- **Trozo 2 (`A5` + `A6`) completado:** reconciliada §4 con §5 en `tu-entrega/arquitectura_datalake.md` (110 particiones reales: 11 recientes de `4.8–8.6 MiB` y 99 históricas de `3.4 KiB–1.8 MiB`, conectadas con el tiempo de escaneo en DuckDB) y eliminada la nota obsoleta en `tu-entrega/README.md:12`.
- **Trozo 3 (`A4`) completado:** añadido `--purgar-tmp` en `scripts/demo_paginacion.py`, purgadas 2 408 entradas (`1204` versiones + `1204` delete markers) bajo `tmp/`, y pegada la salida real `{"Versiones": 0, "DeleteMarkers": 0}` en `tu-entrega/operaciones.md` §2 (enlazada desde `README.md`).
- **Trozo 4 (`A3`) completado:** confirmados los entregables de los Pasos 3–12 en 3 commits descriptivos (Conventional Commits) y re-ejecutados `gitleaks detect` sobre el historial completo de `s20-aws-s3-boto3` y `gitleaks dir` sobre todos los entregables (`no leaks found`).
- **Reauditoría Fase 4 (Argon) completada:** verificados y cerrados los 6 hallazgos (`A1`–`A6` → `[CERRADO]`) en `AUDIT.md` §4 (`9 passed` unitarias, `git status` limpio, `gitleaks` 0 fugas sobre 8 commits). **Lab 20 cerrado y aprobado.**
