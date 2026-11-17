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
- **Por qué coincide con los filtros de las sesiones 21–25:** las consultas analíticas de cohortes OMOP filtran casi siempre por **ventanas temporales** (periodos de inclusión, *washout* previo a la exposición y ventanas de seguimiento). En el conjunto sintético (`1917–2026`, **110 particiones anuales** en total), el grueso clínico reciente (`2016–2026`, 11 particiones) concentra ~87.6 MiB (~68 % del volumen) en archivos equilibrados de **4.8 a 8.6 MiB** por año, mientras que los antecedentes históricos (`1917–2015`, 99 particiones) generan una cola de archivos pequeños (`3.4 KiB` a `1.8 MiB`, 81 de ellos `< 1 MiB`). Esta distribución demuestra en la práctica tanto el costo del *small files problem* al escanear las 110 carpetas sin filtro por HTTP (`24.686 s` en DuckDB sobre S3) como la eficacia de la poda de particiones (`WHERE anio = 2025`: `0.144 s`, `1/110` archivos y `#GET: 1`). Para filtros adicionales por `CODE` (LOINC) o `CATEGORY`, las estadísticas min/max de los *row groups* de Parquet permiten *predicate pushdown* sin subdividir aún más las carpetas.

### Por qué NO particioné por X

- **¿Por qué no `anio=/mes=`?** Multiplicaría las particiones a ~140 carpetas con archivos de ~1 MB o menos (*small files problem*): aumenta la latencia de listado (`LIST`) y el número de peticiones `GET` en S3 más de lo que ahorra en lectura.
- **¿Por qué no por `CATEGORY` (`anio=/CATEGORY=`)?** Acoplaría el diseño físico a una sola pregunta (`laboratory` vs. `vital-signs`) con cardinalidad muy desigual entre categorías. Para filtrar por categoría bastan los metadatos columnares de Parquet.
- **¿Por qué no por sitio (`ORGANIZATION`)?** En Synthea hay 1 026 organizaciones distintas y, además, `observations.csv` **no contiene** la columna `ORGANIZATION` (vive en `encounters.csv`): particionar por sitio obligaría a desnormalizar mediante `JOIN` previo y produciría >1 000 archivos diminutos, degradando el rendimiento en S3.
- **¿Por qué `observations` y no `claims_transactions`?** `claims_transactions.csv` (2.4 GB) es más grande en disco, pero es una tabla de facturación excluida en [D1](./DECISIONES.md#d1-qu%C3%A9-datos-subir-a-raw) y habría comprometido el margen de 5 GB del Free Tier al convivir con Parquet y versiones.

---

## 5. Estructura resultante en `curated/` y conteo (Actividad 6)

Conversión ejecutada con [scripts/convertir_parquet.py](./scripts/convertir_parquet.py) (`DATE` como `timestamp("s", tz="UTC")`, `VALUE` como `string`, compresión `snappy`, formato Hive `anio=YYYY`):

- **Conteo de filas (`observations.csv` vs. Parquet):** `5,719,327` filas leídas del CSV (5,719,328 líneas menos 1 encabezado) == **`5,719,327`** filas en el dataset Parquet.
- **Reducción de tamaño en S3:** `973.6 MiB` (CSV en `raw/`) → **`128.3 MiB`** (Parquet Snappy particionado en `curated/`), distribuidos en **110 particiones anuales** (`anio=1917` a `anio=2026`): 11 particiones recientes (`2016–2026`, `4.8–8.6 MiB`) y 99 particiones históricas (`1917–2015`, `3.4 KiB–1.8 MiB`).

```text
$ aws s3 ls s3://omop-tesis-jhr-2026/curated/synthea/observations/ \
  --recursive --summarize --human-readable --profile tesis
2026-11-17 08:46:41    4.1 KiB curated/synthea/observations/anio=1917/part-0.parquet
2026-11-17 08:46:41   12.2 KiB curated/synthea/observations/anio=1918/part-0.parquet
2026-11-17 08:46:41   18.0 KiB curated/synthea/observations/anio=1919/part-0.parquet
2026-11-17 08:46:41   35.4 KiB curated/synthea/observations/anio=1920/part-0.parquet
2026-11-17 08:46:41   38.9 KiB curated/synthea/observations/anio=1921/part-0.parquet
2026-11-17 08:46:41   33.6 KiB curated/synthea/observations/anio=1922/part-0.parquet
2026-11-17 08:46:41   27.6 KiB curated/synthea/observations/anio=1923/part-0.parquet
2026-11-17 08:46:41   31.3 KiB curated/synthea/observations/anio=1924/part-0.parquet
2026-11-17 08:46:41   27.4 KiB curated/synthea/observations/anio=1925/part-0.parquet
2026-11-17 08:46:41    8.3 KiB curated/synthea/observations/anio=1926/part-0.parquet
2026-11-17 08:46:41    3.9 KiB curated/synthea/observations/anio=1927/part-0.parquet
2026-11-17 08:46:41    6.9 KiB curated/synthea/observations/anio=1928/part-0.parquet
2026-11-17 08:46:41    3.8 KiB curated/synthea/observations/anio=1929/part-0.parquet
2026-11-17 08:46:41    3.7 KiB curated/synthea/observations/anio=1930/part-0.parquet
2026-11-17 08:46:41    3.8 KiB curated/synthea/observations/anio=1931/part-0.parquet
2026-11-17 08:46:41    6.1 KiB curated/synthea/observations/anio=1932/part-0.parquet
2026-11-17 08:46:41    5.8 KiB curated/synthea/observations/anio=1933/part-0.parquet
2026-11-17 08:46:41    6.6 KiB curated/synthea/observations/anio=1934/part-0.parquet
2026-11-17 08:46:41    5.8 KiB curated/synthea/observations/anio=1935/part-0.parquet
2026-11-17 08:46:41    5.7 KiB curated/synthea/observations/anio=1936/part-0.parquet
2026-11-17 08:46:41    5.7 KiB curated/synthea/observations/anio=1937/part-0.parquet
2026-11-17 08:46:41    5.3 KiB curated/synthea/observations/anio=1938/part-0.parquet
2026-11-17 08:46:41    8.2 KiB curated/synthea/observations/anio=1939/part-0.parquet
2026-11-17 08:46:41    3.4 KiB curated/synthea/observations/anio=1940/part-0.parquet
2026-11-17 08:46:41    3.6 KiB curated/synthea/observations/anio=1941/part-0.parquet
2026-11-17 08:46:41    5.4 KiB curated/synthea/observations/anio=1942/part-0.parquet
2026-11-17 08:46:41    7.4 KiB curated/synthea/observations/anio=1943/part-0.parquet
2026-11-17 08:46:41    7.4 KiB curated/synthea/observations/anio=1944/part-0.parquet
2026-11-17 08:46:41   11.7 KiB curated/synthea/observations/anio=1945/part-0.parquet
2026-11-17 08:46:41   15.0 KiB curated/synthea/observations/anio=1946/part-0.parquet
2026-11-17 08:46:41   21.0 KiB curated/synthea/observations/anio=1947/part-0.parquet
2026-11-17 08:46:41   34.3 KiB curated/synthea/observations/anio=1948/part-0.parquet
2026-11-17 08:46:41   59.4 KiB curated/synthea/observations/anio=1949/part-0.parquet
2026-11-17 08:46:41   73.0 KiB curated/synthea/observations/anio=1950/part-0.parquet
2026-11-17 08:46:41   69.0 KiB curated/synthea/observations/anio=1951/part-0.parquet
2026-11-17 08:46:41   66.7 KiB curated/synthea/observations/anio=1952/part-0.parquet
2026-11-17 08:46:41   59.0 KiB curated/synthea/observations/anio=1953/part-0.parquet
2026-11-17 08:46:41   48.3 KiB curated/synthea/observations/anio=1954/part-0.parquet
2026-11-17 08:46:41   58.7 KiB curated/synthea/observations/anio=1955/part-0.parquet
2026-11-17 08:46:41   78.9 KiB curated/synthea/observations/anio=1956/part-0.parquet
2026-11-17 08:46:41   78.3 KiB curated/synthea/observations/anio=1957/part-0.parquet
2026-11-17 08:46:41   88.5 KiB curated/synthea/observations/anio=1958/part-0.parquet
2026-11-17 08:46:41  109.8 KiB curated/synthea/observations/anio=1959/part-0.parquet
2026-11-17 08:46:41   84.4 KiB curated/synthea/observations/anio=1960/part-0.parquet
2026-11-17 08:46:41  100.2 KiB curated/synthea/observations/anio=1961/part-0.parquet
2026-11-17 08:46:41  121.9 KiB curated/synthea/observations/anio=1962/part-0.parquet
2026-11-17 08:46:41  131.2 KiB curated/synthea/observations/anio=1963/part-0.parquet
2026-11-17 08:46:41  131.3 KiB curated/synthea/observations/anio=1964/part-0.parquet
2026-11-17 08:46:41  134.0 KiB curated/synthea/observations/anio=1965/part-0.parquet
2026-11-17 08:46:41  111.9 KiB curated/synthea/observations/anio=1966/part-0.parquet
2026-11-17 08:46:41  121.4 KiB curated/synthea/observations/anio=1967/part-0.parquet
2026-11-17 08:46:41  146.2 KiB curated/synthea/observations/anio=1968/part-0.parquet
2026-11-17 08:46:41  129.2 KiB curated/synthea/observations/anio=1969/part-0.parquet
2026-11-17 08:46:41  131.3 KiB curated/synthea/observations/anio=1970/part-0.parquet
2026-11-17 08:46:41  145.6 KiB curated/synthea/observations/anio=1971/part-0.parquet
2026-11-17 08:46:41  199.9 KiB curated/synthea/observations/anio=1972/part-0.parquet
2026-11-17 08:46:41  211.1 KiB curated/synthea/observations/anio=1973/part-0.parquet
2026-11-17 08:46:41  248.7 KiB curated/synthea/observations/anio=1974/part-0.parquet
2026-11-17 08:46:41  262.3 KiB curated/synthea/observations/anio=1975/part-0.parquet
2026-11-17 08:46:41  307.6 KiB curated/synthea/observations/anio=1976/part-0.parquet
2026-11-17 08:46:41  385.0 KiB curated/synthea/observations/anio=1977/part-0.parquet
2026-11-17 08:46:41  349.9 KiB curated/synthea/observations/anio=1978/part-0.parquet
2026-11-17 08:46:41  382.8 KiB curated/synthea/observations/anio=1979/part-0.parquet
2026-11-17 08:46:41  425.7 KiB curated/synthea/observations/anio=1980/part-0.parquet
2026-11-17 08:46:41  435.8 KiB curated/synthea/observations/anio=1981/part-0.parquet
2026-11-17 08:46:41  419.5 KiB curated/synthea/observations/anio=1982/part-0.parquet
2026-11-17 08:46:41  516.2 KiB curated/synthea/observations/anio=1983/part-0.parquet
2026-11-17 08:46:41  542.7 KiB curated/synthea/observations/anio=1984/part-0.parquet
2026-11-17 08:46:41  486.2 KiB curated/synthea/observations/anio=1985/part-0.parquet
2026-11-17 08:46:41  461.6 KiB curated/synthea/observations/anio=1986/part-0.parquet
2026-11-17 08:46:41  432.4 KiB curated/synthea/observations/anio=1987/part-0.parquet
2026-11-17 08:46:41  482.4 KiB curated/synthea/observations/anio=1988/part-0.parquet
2026-11-17 08:46:41  492.4 KiB curated/synthea/observations/anio=1989/part-0.parquet
2026-11-17 08:46:41  534.7 KiB curated/synthea/observations/anio=1990/part-0.parquet
2026-11-17 08:46:41  631.8 KiB curated/synthea/observations/anio=1991/part-0.parquet
2026-11-17 08:46:41  657.2 KiB curated/synthea/observations/anio=1992/part-0.parquet
2026-11-17 08:46:42  722.0 KiB curated/synthea/observations/anio=1993/part-0.parquet
2026-11-17 08:46:41  789.9 KiB curated/synthea/observations/anio=1994/part-0.parquet
2026-11-17 08:46:41  789.2 KiB curated/synthea/observations/anio=1995/part-0.parquet
2026-11-17 08:46:42  869.9 KiB curated/synthea/observations/anio=1996/part-0.parquet
2026-11-17 08:46:42  931.8 KiB curated/synthea/observations/anio=1997/part-0.parquet
2026-11-17 08:46:42    1.0 MiB curated/synthea/observations/anio=1998/part-0.parquet
2026-11-17 08:46:42    1.1 MiB curated/synthea/observations/anio=1999/part-0.parquet
2026-11-17 08:46:42    1.2 MiB curated/synthea/observations/anio=2000/part-0.parquet
2026-11-17 08:46:42    1.3 MiB curated/synthea/observations/anio=2001/part-0.parquet
2026-11-17 08:46:42    1.3 MiB curated/synthea/observations/anio=2002/part-0.parquet
2026-11-17 08:46:42    1.3 MiB curated/synthea/observations/anio=2003/part-0.parquet
2026-11-17 08:46:42    1.4 MiB curated/synthea/observations/anio=2004/part-0.parquet
2026-11-17 08:46:42    1.3 MiB curated/synthea/observations/anio=2005/part-0.parquet
2026-11-17 08:46:42    1.3 MiB curated/synthea/observations/anio=2006/part-0.parquet
2026-11-17 08:46:42    1.4 MiB curated/synthea/observations/anio=2007/part-0.parquet
2026-11-17 08:46:42    1.4 MiB curated/synthea/observations/anio=2008/part-0.parquet
2026-11-17 08:46:42    1.5 MiB curated/synthea/observations/anio=2009/part-0.parquet
2026-11-17 08:46:42    1.6 MiB curated/synthea/observations/anio=2010/part-0.parquet
2026-11-17 08:46:42    1.6 MiB curated/synthea/observations/anio=2011/part-0.parquet
2026-11-17 08:46:42    1.6 MiB curated/synthea/observations/anio=2012/part-0.parquet
2026-11-17 08:46:42    1.6 MiB curated/synthea/observations/anio=2013/part-0.parquet
2026-11-17 08:46:42    1.7 MiB curated/synthea/observations/anio=2014/part-0.parquet
2026-11-17 08:46:42    1.8 MiB curated/synthea/observations/anio=2015/part-0.parquet
2026-11-17 08:46:42    4.8 MiB curated/synthea/observations/anio=2016/part-0.parquet
2026-11-17 08:46:42    8.1 MiB curated/synthea/observations/anio=2017/part-0.parquet
2026-11-17 08:46:42    8.2 MiB curated/synthea/observations/anio=2018/part-0.parquet
2026-11-17 08:46:42    8.2 MiB curated/synthea/observations/anio=2019/part-0.parquet
2026-11-17 08:46:42    8.6 MiB curated/synthea/observations/anio=2020/part-0.parquet
2026-11-17 08:46:42    8.6 MiB curated/synthea/observations/anio=2021/part-0.parquet
2026-11-17 08:46:42    8.3 MiB curated/synthea/observations/anio=2022/part-0.parquet
2026-11-17 08:46:42    8.3 MiB curated/synthea/observations/anio=2023/part-0.parquet
2026-11-17 08:46:42    8.4 MiB curated/synthea/observations/anio=2024/part-0.parquet
2026-11-17 08:46:42    8.4 MiB curated/synthea/observations/anio=2025/part-0.parquet
2026-11-17 08:46:42    7.7 MiB curated/synthea/observations/anio=2026/part-0.parquet

Total Objects: 110
   Total Size: 128.3 MiB
```
