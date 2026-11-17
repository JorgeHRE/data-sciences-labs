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
- **Siguiente:** Paso 3 — Subir las 15 tablas clínicas de Synthea a `raw/` con `aws s3 sync` (`--dryrun`, corrida real y segunda corrida idempotente) (`SPECS.md` §3, Paso 3).
