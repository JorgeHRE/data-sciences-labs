# Arquitectura del Data Lake Clínico en S3 — Lab 20

**Bucket:** `omop-tesis-jhr-2026` (`us-east-2`)  
**Alcance:** almacenamiento base para las sesiones 20–25 del proyecto final con datos sintéticos Synthea (OMOP / tablas clínicas).

---

## 1. Configuración del bucket (Actividad 1)

El bucket se creó por AWS CLI con cinco comandos consecutivos ([D2](./DECISIONES.md#d2-c%C3%B3mo-crear-el-bucket-omop-tesis-jhr-2026)) para garantizar que el bloqueo de acceso público, el versionado y el cifrado quedaran activos antes de subir el primer objeto:

```bash
aws s3api create-bucket --bucket omop-tesis-jhr-2026 --region us-east-2 \
  --create-bucket-configuration LocationConstraint=us-east-2 --profile tesis
aws s3api put-public-access-block --bucket omop-tesis-jhr-2026 \
  --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
  --profile tesis
aws s3api put-bucket-versioning --bucket omop-tesis-jhr-2026 \
  --versioning-configuration Status=Enabled --profile tesis
aws s3api put-bucket-encryption --bucket omop-tesis-jhr-2026 \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' \
  --profile tesis
aws s3api put-bucket-tagging --bucket omop-tesis-jhr-2026 \
  --tagging 'TagSet=[{Key=Proyecto,Value=tesis}]' --profile tesis
```

### Evidencia de verificación (salidas reales censuradas)

- **Identidad IAM (`aws sts get-caller-identity --profile tesis`):**

```json
{
    "UserId": "<USER_ID>",
    "Account": "<ACCOUNT_ID>",
    "Arn": "arn:aws:iam::<ACCOUNT_ID>:user/jorge-labs"
}
```

- **Block Public Access a nivel de cuenta (`aws s3control get-public-access-block --account-id <ACCOUNT_ID> --profile tesis`):**

```json
{
    "PublicAccessBlockConfiguration": {
        "BlockPublicAcls": true,
        "IgnorePublicAcls": true,
        "BlockPublicPolicy": true,
        "RestrictPublicBuckets": true
    }
}
```

- **Block Public Access del bucket (`aws s3api get-public-access-block --bucket omop-tesis-jhr-2026 --profile tesis`):**

```json
{
    "PublicAccessBlockConfiguration": {
        "BlockPublicAcls": true,
        "IgnorePublicAcls": true,
        "BlockPublicPolicy": true,
        "RestrictPublicBuckets": true
    }
}
```

- **Versionado (`aws s3api get-bucket-versioning --bucket omop-tesis-jhr-2026 --profile tesis`):**

```json
{
    "Status": "Enabled"
}
```

- **Cifrado en reposo (`aws s3api get-bucket-encryption --bucket omop-tesis-jhr-2026 --profile tesis`):**

```json
{
    "ServerSideEncryptionConfiguration": {
        "Rules": [
            {
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                },
                "BucketKeyEnabled": false,
                "BlockedEncryptionTypes": {
                    "EncryptionType": [
                        "SSE-C"
                    ]
                }
            }
        ]
    }
}
```

- **Etiqueta de costo (`aws s3api get-bucket-tagging --bucket omop-tesis-jhr-2026 --profile tesis`):**

```json
{
    "TagSet": [
        {
            "Key": "Proyecto",
            "Value": "tesis"
        }
    ]
}
```

- **Prueba negativa sin credenciales (`curl -I https://omop-tesis-jhr-2026.s3.us-east-2.amazonaws.com/prueba-no-existe.txt`):**

```text
HTTP/1.1 403 Forbidden
Server: AmazonS3
x-amz-request-id: 5R2YMW56E9ZWNA7T
x-amz-id-2: Qs/TNPmLLxmfhEEtJ9v1sGkEYKfzhbDNwVVS066j9WzIlKdeywhIUO1JAye2GT3p+6o9RHnIHelf0TcC/vIdSZdjgqSPGTS5
Content-Type: application/xml
Transfer-Encoding: chunked
Date: Tue, 17 Nov 2026 13:48:02 GMT
```

- **Capturas de consola:** [Propiedades del bucket](./capturas/bucket_propiedades.jpg) · [Permisos del bucket](./capturas/bucket_permisos.png)

---

## 2. Zonas del Data Lake y minimización de datos (Actividad 2)

| Zona | Qué va | Quién escribe | ¿Regenerable? | Formato |
|---|---|---|---|---|
| `raw/` | Datos fuente de las **15 tablas clínicas** de Synthea tal como llegaron (inmutable; nadie la reescribe) | Pipeline de ingesta / `aws s3 sync` (Paso 3) | **No** (es la fuente de verdad; conserva versiones no actuales en S3) | CSV original |
| `staging/` | Tablas tipadas, limpias y con **minimización de columnas** en `patients` (sin PII simulada innecesaria) | Scripts ETL (sesiones 20–25) | **Sí**, a partir de `raw/` | Parquet sin particionar |
| `curated/` | Tablas analíticas particionadas y optimizadas para consultas de cohorte (`observations` en este lab) | `scripts/convertir_parquet.py` / ETL (Paso 6) | **Sí**, a partir de `raw/` o `staging/` | Parquet particionado (Hive) |
| `tmp/` | Objetos efímeros de prueba (demo de paginación, *presigned URL*, pruebas de integración) | Scripts de prueba y `pytest -m integracion` | **Sí** (expira en 1 día por ciclo de vida, D8) | Texto / binario efímero |

### Alcance de `raw/` (Decisión D1)
De los 18 CSV de Synthea locales (4.3 GB), en `raw/` se suben únicamente las **15 tablas clínicas** (~1.41 GiB) y se excluyen explícitamente mediante `--exclude`:
- `claims.csv` (300 MB) y `claims_transactions.csv` (2.4 GB): tablas financieras/facturación sin uso en el proyecto clínico.
- `imaging_studies.csv` (219 MB): metadatos de estudios de imagen fuera del alcance del proyecto.

Por principio de **minimización de datos**, lo que no se necesita no se sube ni se custodia; si en el futuro hiciera falta incorporar `claims`, la partición `fecha_carga=` permite agregarlas sin reescribir cargas previas. Además, `patients.csv` entra íntegro en `raw/` para preservar inmutabilidad, aplicando la eliminación de identificadores al generar `staging/` y `curated/`.

---

## 3. Convención de nombres de llaves

```text
raw/synthea/fecha_carga=YYYY-MM-DD/<tabla>.csv
staging/synthea/<tabla>/<tabla>.parquet
curated/synthea/<tabla>/anio=YYYY/part-*.parquet
tmp/<proposito>/<archivo>
```

- **`fecha_carga=YYYY-MM-DD`** en `raw/`: permite cargas incrementales o re-ingestas en fechas distintas con un único `aws s3 sync` sin sobrescribir archivos previos, manteniendo trazabilidad (*lineage*) de qué llegó y cuándo.
- **Formato `clave=valor` (estilo Hive)** en `curated/` (`anio=YYYY/`): es imprescindible con `=` para que DuckDB (`hive_partitioning = true`) y otros motores reconozcan las carpetas como particiones y apliquen *partition pruning* (poda de particiones).
- **Minúsculas y guiones bajos** en `<tabla>` y prefijos, evitando espacios o caracteres especiales.

---

## 4. Esquema de particionado y su porqué (Decisión D3)

- **Tabla convertida:** `observations` (`observations.csv`, 974 MB, ~5.7 M filas, columnas `DATE,PATIENT,ENCOUNTER,CATEGORY,CODE,DESCRIPTION,VALUE,UNITS,TYPE`). Es la tabla clínica más grande que ingresa a `raw/` (tras excluir `claims_transactions`) y la fuente principal de mediciones/signos vitales y laboratorios.
- **Partición elegida:** `anio=YYYY` derivada de la columna `DATE` (ISO 8601 en UTC), ubicada en `curated/synthea/observations/anio=YYYY/`.
- **Por qué coincide con los filtros de las sesiones 21–25:** las consultas analíticas de cohortes OMOP filtran casi siempre por **ventanas temporales** (periodos de inclusión, *washout* previo a la exposición y ventanas de seguimiento). Con ~12 años de datos principales en `observations` (2015–2026), se generan ~12 particiones de tamaño equilibrado (del orden de ~10–15 MB cada una en Parquet, que se medirá exactamente en el Paso 7), evitando el problema de *small files* y reduciendo las peticiones `GET` en S3. Para filtros por `CODE` (LOINC) o `CATEGORY`, las estadísticas min/max de los *row groups* de Parquet permiten *predicate pushdown* sin añadir más carpetas.

### Por qué NO particioné por X

- **¿Por qué no `anio=/mes=`?** Multiplicaría las particiones a ~140 carpetas con archivos de ~1 MB o menos (*small files problem*): aumenta la latencia de listado (`LIST`) y el número de peticiones `GET` en S3 más de lo que ahorra en lectura.
- **¿Por qué no por `CATEGORY` (`anio=/CATEGORY=`)?** Acoplaría el diseño físico a una sola pregunta (`laboratory` vs. `vital-signs`) con cardinalidad muy desigual entre categorías. Para filtrar por categoría bastan los metadatos columnares de Parquet.
- **¿Por qué no por sitio (`ORGANIZATION`)?** En Synthea hay 1 026 organizaciones distintas y, además, `observations.csv` **no contiene** la columna `ORGANIZATION` (vive en `encounters.csv`): particionar por sitio obligaría a desnormalizar mediante `JOIN` previo y produciría >1 000 archivos diminutos, degradando el rendimiento en S3.
- **¿Por qué `observations` y no `claims_transactions`?** `claims_transactions.csv` (2.4 GB) es más grande en disco, pero es una tabla de facturación excluida en [D1](./DECISIONES.md#d1-qu%C3%A9-datos-subir-a-raw) y habría comprometido el margen de 5 GB del Free Tier al convivir con Parquet y versiones.

---

## 5. Estructura resultante en `curated/` y conteo (Paso 6)

*(Se completará tras ejecutar `scripts/convertir_parquet.py` en el Paso 6 con la salida real de `aws s3 ls --recursive` y el conteo CSV vs. Parquet).*
