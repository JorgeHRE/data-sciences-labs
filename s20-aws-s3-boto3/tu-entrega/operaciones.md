# Operaciones y Mantenimiento del Data Lake S3 — Lab 20

**Bucket:** `omop-tesis-jhr-2026` (`us-east-2`)  
**Perfil CLI:** `tesis`

---

## 1. Ingesta idempotente a `raw/` con `aws s3 sync` (Actividad 3)

Siguiendo [D1](./DECISIONES.md#d1-qu%C3%A9-datos-subir-a-raw), se suben las 15 tablas clínicas sintéticas de Synthea (~1.41 GiB) excluyendo `claims.csv`, `claims_transactions.csv` e `imaging_studies.csv`.

### 1.1 Simulación (`--dryrun`)

```text
$ aws s3 sync s10-sql-fundamentals/tu-entrega/data/synthea/csv/ \
  s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/ \
  --exclude "claims.csv" \
  --exclude "claims_transactions.csv" \
  --exclude "imaging_studies.csv" \
  --dryrun \
  --profile tesis
(dryrun) upload: s10-sql-fundamentals/tu-entrega/data/synthea/csv/allergies.csv to s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/allergies.csv
(dryrun) upload: s10-sql-fundamentals/tu-entrega/data/synthea/csv/careplans.csv to s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/careplans.csv
(dryrun) upload: s10-sql-fundamentals/tu-entrega/data/synthea/csv/conditions.csv to s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/conditions.csv
(dryrun) upload: s10-sql-fundamentals/tu-entrega/data/synthea/csv/devices.csv to s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/devices.csv
(dryrun) upload: s10-sql-fundamentals/tu-entrega/data/synthea/csv/encounters.csv to s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/encounters.csv
(dryrun) upload: s10-sql-fundamentals/tu-entrega/data/synthea/csv/immunizations.csv to s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/immunizations.csv
(dryrun) upload: s10-sql-fundamentals/tu-entrega/data/synthea/csv/medications.csv to s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/medications.csv
(dryrun) upload: s10-sql-fundamentals/tu-entrega/data/synthea/csv/observations.csv to s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/observations.csv
(dryrun) upload: s10-sql-fundamentals/tu-entrega/data/synthea/csv/organizations.csv to s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/organizations.csv
(dryrun) upload: s10-sql-fundamentals/tu-entrega/data/synthea/csv/patients.csv to s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/patients.csv
(dryrun) upload: s10-sql-fundamentals/tu-entrega/data/synthea/csv/payer_transitions.csv to s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/payer_transitions.csv
(dryrun) upload: s10-sql-fundamentals/tu-entrega/data/synthea/csv/payers.csv to s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/payers.csv
(dryrun) upload: s10-sql-fundamentals/tu-entrega/data/synthea/csv/procedures.csv to s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/procedures.csv
(dryrun) upload: s10-sql-fundamentals/tu-entrega/data/synthea/csv/providers.csv to s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/providers.csv
(dryrun) upload: s10-sql-fundamentals/tu-entrega/data/synthea/csv/supplies.csv to s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/supplies.csv
```

### 1.2 Primera corrida real (`aws s3 sync`)

```text
$ aws s3 sync s10-sql-fundamentals/tu-entrega/data/synthea/csv/ \
  s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/ \
  --exclude "claims.csv" \
  --exclude "claims_transactions.csv" \
  --exclude "imaging_studies.csv" \
  --profile tesis
upload: s10-sql-fundamentals/tu-entrega/data/synthea/csv/allergies.csv to s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/allergies.csv
upload: s10-sql-fundamentals/tu-entrega/data/synthea/csv/careplans.csv to s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/careplans.csv
upload: s10-sql-fundamentals/tu-entrega/data/synthea/csv/devices.csv to s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/devices.csv
upload: s10-sql-fundamentals/tu-entrega/data/synthea/csv/organizations.csv to s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/organizations.csv
upload: s10-sql-fundamentals/tu-entrega/data/synthea/csv/patients.csv to s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/patients.csv
upload: s10-sql-fundamentals/tu-entrega/data/synthea/csv/immunizations.csv to s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/immunizations.csv
upload: s10-sql-fundamentals/tu-entrega/data/synthea/csv/payer_transitions.csv to s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/payer_transitions.csv
upload: s10-sql-fundamentals/tu-entrega/data/synthea/csv/payers.csv to s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/payers.csv
upload: s10-sql-fundamentals/tu-entrega/data/synthea/csv/conditions.csv to s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/conditions.csv
upload: s10-sql-fundamentals/tu-entrega/data/synthea/csv/providers.csv to s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/providers.csv
upload: s10-sql-fundamentals/tu-entrega/data/synthea/csv/supplies.csv to s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/supplies.csv
upload: s10-sql-fundamentals/tu-entrega/data/synthea/csv/encounters.csv to s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/encounters.csv
upload: s10-sql-fundamentals/tu-entrega/data/synthea/csv/medications.csv to s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/medications.csv
upload: s10-sql-fundamentals/tu-entrega/data/synthea/csv/procedures.csv to s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/procedures.csv
upload: s10-sql-fundamentals/tu-entrega/data/synthea/csv/observations.csv to s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/observations.csv
```

### 1.3 Segunda corrida sin cambios (idempotencia)

```text
$ aws s3 sync s10-sql-fundamentals/tu-entrega/data/synthea/csv/ \
  s3://omop-tesis-jhr-2026/raw/synthea/fecha_carga=2026-11-17/ \
  --exclude "claims.csv" \
  --exclude "claims_transactions.csv" \
  --exclude "imaging_studies.csv" \
  --profile tesis
(sin salida: 0 archivos subidos)
```

**¿Por qué la segunda corrida sale vacía?** `aws s3 sync` compara el tamaño y la fecha de última modificación (*last modified*) de cada archivo local contra el objeto correspondiente en S3; como ninguno cambió, no transfiere nada ni genera nuevas versiones ni peticiones `PUT`, haciendo la operación **idempotente**.

### 1.4 Verificación final en `raw/`

```text
$ aws s3 ls s3://omop-tesis-jhr-2026/raw/ --recursive --summarize --human-readable --profile tesis
2026-11-17 08:24:54  906.2 KiB raw/synthea/fecha_carga=2026-11-17/allergies.csv
2026-11-17 08:24:54    3.7 MiB raw/synthea/fecha_carga=2026-11-17/careplans.csv
2026-11-17 08:24:53   32.2 MiB raw/synthea/fecha_carga=2026-11-17/conditions.csv
2026-11-17 08:24:54    2.2 MiB raw/synthea/fecha_carga=2026-11-17/devices.csv
2026-11-17 08:24:53  134.9 MiB raw/synthea/fecha_carga=2026-11-17/encounters.csv
2026-11-17 08:24:53   12.1 MiB raw/synthea/fecha_carga=2026-11-17/immunizations.csv
2026-11-17 08:24:53   96.5 MiB raw/synthea/fecha_carga=2026-11-17/medications.csv
2026-11-17 08:24:53  973.6 MiB raw/synthea/fecha_carga=2026-11-17/observations.csv
2026-11-17 08:24:54  166.5 KiB raw/synthea/fecha_carga=2026-11-17/organizations.csv
2026-11-17 08:24:54    1.7 MiB raw/synthea/fecha_carga=2026-11-17/patients.csv
2026-11-17 08:24:53   10.1 MiB raw/synthea/fecha_carga=2026-11-17/payer_transitions.csv
2026-11-17 08:24:53    1.9 KiB raw/synthea/fecha_carga=2026-11-17/payers.csv
2026-11-17 08:24:53  166.5 MiB raw/synthea/fecha_carga=2026-11-17/procedures.csv
2026-11-17 08:24:54  198.9 KiB raw/synthea/fecha_carga=2026-11-17/providers.csv
2026-11-17 08:24:53    8.1 MiB raw/synthea/fecha_carga=2026-11-17/supplies.csv

Total Objects: 15
   Total Size: 1.4 GiB
```

---

## 2. Demostración real de paginación (> 1 000 objetos, Actividad 5)

Siguiendo [D7](./DECISIONES.md#d7-objetos-de-prueba-de-paginación), [scripts/demo_paginacion.py](./scripts/demo_paginacion.py) subió 1 200 objetos diminutos a `tmp/paginacion/` en 16 hilos, verificó el conteo total con `s3util.listar()` (que internamente usa `get_paginator("list_objects_v2")`), lo contrastó contra `aws s3 ls --recursive | wc -l` y finalmente borró los objetos actuales en lotes de 1 000 sin `VersionId` (dejando la expiración de versiones y *delete markers* a la regla R2 en §3).

```text
$ .venv/bin/python scripts/demo_paginacion.py
Subidos: 1200 | Listados por s3util.listar: 1200

$ aws s3 ls s3://omop-tesis-jhr-2026/tmp/paginacion/ --recursive --profile tesis | wc -l
1200

$ .venv/bin/python scripts/demo_paginacion.py --limpiar
Delete markers creados en tmp/paginacion/: 1200 (la regla R2 expira versiones)

$ .venv/bin/python scripts/demo_paginacion.py --purgar-tmp
Versiones + delete markers purgados en tmp/: 2408

$ aws s3 ls s3://omop-tesis-jhr-2026/tmp/ --recursive --profile tesis
(sin salida: 0 objetos actuales)

$ aws s3api list-object-versions --bucket omop-tesis-jhr-2026 --prefix tmp/ \
  --query '{Versiones: length(Versions || `[]`), DeleteMarkers: length(DeleteMarkers || `[]`)}' \
  --profile tesis --no-cli-pager
{
    "Versiones": 0,
    "DeleteMarkers": 0
}
```

*(Nota: `--limpiar` demostró el borrado sin `VersionId` bajo D7, donde S3 aplicó la regla `R2a` con cabecera `x-amz-expiration: Thu, 19 Nov 2026 00:00:00 GMT`; al cierre del laboratorio se ejecutó `--purgar-tmp` paginando `list_object_versions` con `VersionId` para dejar `tmp/` inmediatamente en `0` versiones y `0` delete markers, manteniendo `R2a`/`R2b` activas como red de seguridad).*

---

## 3. Ciclo de vida y Presigned URL (Actividad 9)

### 3.1 Reglas de ciclo de vida aplicadas ([`scripts/lifecycle.json`](./scripts/lifecycle.json), D8)

Se aplicaron 5 reglas en un único JSON (ya que `put-bucket-lifecycle-configuration` reemplaza el conjunto completo y `ExpiredObjectDeleteMarker` debe ir separado de `Days`):

- **R1 (`abortar-multipart-incompletos-7d`):** todo el bucket (`Filter: {}`) aborta cargas *multipart* incompletas a los 7 días.
- **R2a y R2b (`tmp/`):** expira objetos actuales y no actuales a 1 día, y limpia *delete markers* huérfanos (incluidos los 1 200 de `tmp/paginacion/`).
- **R3a y R3b (`staging/` y `curated/`):** expira versiones no actuales a los 30 días. **`raw/` se excluye a propósito** para no perder el dato fuente ante una sobrescritura accidental.
- **R4 (`raw/` → `STANDARD_IA` a 30 días) — analizada, NO aplicada:** S3 Standard-IA cobra un tamaño mínimo de 128 KB por objeto, permanencia mínima de 30 días y tarifa por recuperación (`GB` leídos); además el proyecto leerá `raw/` en las sesiones 21–25, por lo que el ahorro sería nulo o negativo.

```text
$ aws s3api put-bucket-lifecycle-configuration \
  --bucket omop-tesis-jhr-2026 \
  --lifecycle-configuration file://scripts/lifecycle.json \
  --profile tesis

$ aws s3api get-bucket-lifecycle-configuration \
  --bucket omop-tesis-jhr-2026 \
  --profile tesis \
  --no-cli-pager
{
    "TransitionDefaultMinimumObjectSize": "all_storage_classes_128K",
    "Rules": [
        {
            "ID": "R1-abortar-multipart-incompletos-7d",
            "Filter": {},
            "Status": "Enabled",
            "AbortIncompleteMultipartUpload": {
                "DaysAfterInitiation": 7
            }
        },
        {
            "Expiration": {
                "Days": 1
            },
            "ID": "R2a-tmp-expirar-actuales-y-no-actuales-1d",
            "Filter": {
                "Prefix": "tmp/"
            },
            "Status": "Enabled",
            "NoncurrentVersionExpiration": {
                "NoncurrentDays": 1
            }
        },
        {
            "Expiration": {
                "ExpiredObjectDeleteMarker": true
            },
            "ID": "R2b-tmp-limpiar-delete-markers-huerfanos",
            "Filter": {
                "Prefix": "tmp/"
            },
            "Status": "Enabled"
        },
        {
            "ID": "R3a-staging-expirar-no-actuales-30d",
            "Filter": {
                "Prefix": "staging/"
            },
            "Status": "Enabled",
            "NoncurrentVersionExpiration": {
                "NoncurrentDays": 30
            }
        },
        {
            "ID": "R3b-curated-expirar-no-actuales-30d",
            "Filter": {
                "Prefix": "curated/"
            },
            "Status": "Enabled",
            "NoncurrentVersionExpiration": {
                "NoncurrentDays": 30
            }
        }
    ]
}
```

### 3.2 Presigned URL vigente y caducada ([`scripts/demo_presigned.py`](./scripts/demo_presigned.py))

- **Cómo funciona:** `generate_presigned_url` firma una operación (`get_object`) con la firma SigV4 de quien la genera: **hereda exactamente sus permisos** (si el usuario no tuviera `s3:GetObject`, la URL fallaría aunque estuviera bien firmada), tiene una **vigencia máxima de 7 días** y actúa como un **secreto al portador** (cualquier tercero con la URL puede descargar el objeto hasta que expire).
- **Seguridad:** el parámetro `X-Amz-Credential` contiene el Access Key ID del firmante (`gitleaks` lo detecta), por lo que solo se documenta la URL **después de caducada** y con `X-Amz-Credential` censurado.

```text
$ .venv/bin/python scripts/demo_presigned.py
=== 1. Prueba curl con presigned URL vigente (ExpiresIn=3600) ===
HTTP/1.1 200 OK
x-amz-request-id: P7PNX88HZQHQT86H
x-amz-id-2: WrUCI4u8IyTJn76xMkMQWXWhug6lLxK5Cv38H0HVzh/dvsz6PeSZKnS10wmWqSLDTph3B9lJXjjQbJVDRSLiUt3D4vHgzULS
Content-Length: 55
Accept-Ranges: bytes
Date: Tue, 17 Nov 2026 15:46:32 GMT
Server: AmazonS3
x-amz-expiration: expiry-date="Thu, 19 Nov 2026 00:00:00 GMT", rule-id="R2a-tmp-expirar-actuales-y-no-actuales-1d"
Last-Modified: Tue, 17 Nov 2026 15:46:32 GMT
ETag: "c1d590ad999d41b907d5a7b036ec0c8f"
x-amz-version-id: Y7UBYKPQN74e_lVVote42IYyFpE_31Mr
Content-Type: text/plain
x-amz-server-side-encryption: AES256

Objeto sintetico de prueba para presigned URL (Lab 20)

Esperando 12 segundos para que caduque la URL de prueba (ExpiresIn=10)...

=== 2. Prueba curl con presigned URL caducada (ExpiresIn=10) ===
HTTP/1.1 403 Forbidden
x-amz-request-id: A036VVTJM92E0GXA
x-amz-id-2: tJiVuwOpp5dLs9IpWWqUTqC6QoGqNK9qS5cVJmFunTLNtsbV6qbA3+fUTKDKihsG/E1bXIpEkVc=
Date: Tue, 17 Nov 2026 15:46:44 GMT
Content-Type: application/xml
Server: AmazonS3
Transfer-Encoding: chunked

<?xml version="1.0" encoding="UTF-8"?>
<Error><Code>AccessDenied</Code><Message>Request has expired</Message><X-Amz-Expires>10</X-Amz-Expires><Expires>2026-11-17T15:46:41Z</Expires><ServerTime>2026-11-17T15:46:44Z</ServerTime><RequestId>A036VVTJM92E0GXA</RequestId><HostId>tJiVuwOpp5dLs9IpWWqUTqC6QoGqNK9qS5cVJmFunTLNtsbV6qbA3+fUTKDKihsG/E1bXIpEkVc=</HostId></Error>

URL caducada (censurada):
https://omop-tesis-jhr-2026.s3.amazonaws.com/tmp/presigned/hola.txt?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=<ACCESS_KEY_ID>%2F<FECHA>%2Fus-east-2%2Fs3%2Faws4_request&X-Amz-Date=20261117T154631Z&X-Amz-Expires=10&X-Amz-SignedHeaders=host&X-Amz-Signature=328fb0e36bcb87f4ea93a62624e4606a3abb7d885eaa23cda67d7f5bd46c3fcd
```

---

## 4. Borrado y recuperación con versionado (Actividad 10)

### Qué es un *delete marker* y por qué el objeto no se había borrado
Con el versionado habilitado, `delete-object` sin `--version-id` **no destruye el objeto**: crea un marcador ligero llamado *delete marker* con su propio `VersionId` y lo vuelve la versión actual (`IsLatest: true`), ocultando el archivo ante `head-object` (`404`) y `aws s3 ls`. La versión original permanece intacta (`IsLatest: false`), por lo que basta eliminar el *delete marker* por su `VersionId` para recuperar el objeto exactamente con su `ETag` y `VersionId` originales.

En un entorno farmacéutico regulado (GxP / 21 CFR Part 11), esta protección se complementa con **S3 Object Lock** (modo *Compliance* o *Governance*, WORM) y **MFA Delete**, de modo que ni un administrador con acceso de escritura pueda borrar versiones definitivas sin una segunda autorización o antes del período de retención.

### Secuencia completa de los 6 pasos (salidas reales)

```text
# 1. put-object -> VersionId original y ETag
$ printf 'protocolo-recuperacion-s20\n' > /tmp/nota_s20.txt
$ aws s3api put-object --bucket omop-tesis-jhr-2026 --key tmp/recuperacion/nota.txt --body /tmp/nota_s20.txt --profile tesis --no-cli-pager
{
    "Expiration": "expiry-date=\"Thu, 19 Nov 2026 00:00:00 GMT\", rule-id=\"R2a-tmp-expirar-actuales-y-no-actuales-1d\"",
    "ETag": "\"6a5db33c75c2ed9c14d60d47661ab42d\"",
    "ChecksumCRC64NVME": "WVS3yHlj6wM=",
    "ChecksumType": "FULL_OBJECT",
    "ServerSideEncryption": "AES256",
    "VersionId": "P4CzRxqyJiaY_ED2fra_ndcKydFa7NF7"
}

# 2. delete-object sin version-id -> crea DeleteMarker
$ aws s3api delete-object --bucket omop-tesis-jhr-2026 --key tmp/recuperacion/nota.txt --profile tesis --no-cli-pager
{
    "DeleteMarker": true,
    "VersionId": "P_U2BwyGhjgl5nPVXh24v5bvNS6MrVRj"
}

# 3. head-object -> 404 y aws s3 ls -> vacío
$ aws s3api head-object --bucket omop-tesis-jhr-2026 --key tmp/recuperacion/nota.txt --profile tesis --no-cli-pager || true
An error occurred (404) when calling the HeadObject operation: Not Found
$ aws s3 ls s3://omop-tesis-jhr-2026/tmp/recuperacion/ --profile tesis
(sin salida)

# 4. list-object-versions -> versión original intacta + DeleteMarker
$ aws s3api list-object-versions --bucket omop-tesis-jhr-2026 --prefix tmp/recuperacion/nota.txt --profile tesis --no-cli-pager
{
    "Versions": [
        {
            "ETag": "\"6a5db33c75c2ed9c14d60d47661ab42d\"",
            "ChecksumAlgorithm": [
                "CRC64NVME"
            ],
            "ChecksumType": "FULL_OBJECT",
            "Size": 27,
            "StorageClass": "STANDARD",
            "Key": "tmp/recuperacion/nota.txt",
            "VersionId": "P4CzRxqyJiaY_ED2fra_ndcKydFa7NF7",
            "IsLatest": false,
            "LastModified": "2026-11-17T15:48:42+00:00",
            "Owner": {
                "ID": "<CANONICAL_USER_ID>"
            }
        }
    ],
    "DeleteMarkers": [
        {
            "Owner": {
                "ID": "<CANONICAL_USER_ID>"
            },
            "Key": "tmp/recuperacion/nota.txt",
            "VersionId": "P_U2BwyGhjgl5nPVXh24v5bvNS6MrVRj",
            "IsLatest": true,
            "LastModified": "2026-11-17T15:48:43+00:00"
        }
    ],
    "RequestCharged": null,
    "Prefix": "tmp/recuperacion/nota.txt"
}

# 5. delete-object sobre el VersionId del DeleteMarker
$ aws s3api delete-object --bucket omop-tesis-jhr-2026 --key tmp/recuperacion/nota.txt --version-id "P_U2BwyGhjgl5nPVXh24v5bvNS6MrVRj" --profile tesis --no-cli-pager
{
    "DeleteMarker": true,
    "VersionId": "P_U2BwyGhjgl5nPVXh24v5bvNS6MrVRj"
}

# 6. head-object -> 200 con mismo ETag y VersionId, y contenido intacto
$ aws s3api head-object --bucket omop-tesis-jhr-2026 --key tmp/recuperacion/nota.txt --profile tesis --no-cli-pager
{
    "AcceptRanges": "bytes",
    "Expiration": "expiry-date=\"Thu, 19 Nov 2026 00:00:00 GMT\", rule-id=\"R2a-tmp-expirar-actuales-y-no-actuales-1d\"",
    "LastModified": "2026-11-17T15:48:42+00:00",
    "ContentLength": 27,
    "ETag": "\"6a5db33c75c2ed9c14d60d47661ab42d\"",
    "VersionId": "P4CzRxqyJiaY_ED2fra_ndcKydFa7NF7",
    "ContentType": "binary/octet-stream",
    "ServerSideEncryption": "AES256",
    "Metadata": {}
}
$ aws s3 cp s3://omop-tesis-jhr-2026/tmp/recuperacion/nota.txt - --profile tesis
protocolo-recuperacion-s20
```

---

## 5. Política de bucket solo-HTTPS (Bono, Actividad 11 / D9)

Se aplicó [`scripts/politica_solo_https.json`](./scripts/politica_solo_https.json) con `Effect: Deny`, `Principal: "*"`, `Action: "s3:*"` sobre el ARN del bucket (`arn:aws:s3:::omop-tesis-jhr-2026`) y sus objetos (`arn:aws:s3:::omop-tesis-jhr-2026/*`) cuando `aws:SecureTransport` es `"false"`.

- **Por qué no viola privilegio mínimo:** al ser `Deny`, solo restringe (no otorga permisos a nadie); como es un *Explicit Deny*, prevalece sobre cualquier `Allow` de IAM.
- **Reversión si bloqueara por error:** `aws s3api delete-bucket-policy --bucket omop-tesis-jhr-2026 --profile tesis`.

```text
$ aws s3api put-bucket-policy --bucket omop-tesis-jhr-2026 --policy file://scripts/politica_solo_https.json --profile tesis

$ aws s3api get-bucket-policy --bucket omop-tesis-jhr-2026 --profile tesis --no-cli-pager
{
    "Policy": "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"DenegarTraficoSinTLS\",\"Effect\":\"Deny\",\"Principal\":\"*\",\"Action\":\"s3:*\",\"Resource\":[\"arn:aws:s3:::omop-tesis-jhr-2026\",\"arn:aws:s3:::omop-tesis-jhr-2026/*\"],\"Condition\":{\"Bool\":{\"aws:SecureTransport\":\"false\"}}}]}"
}

$ aws s3api list-objects-v2 --bucket omop-tesis-jhr-2026 --prefix raw/ --endpoint-url http://s3.us-east-2.amazonaws.com --profile tesis --no-cli-pager || true
aws: [ERROR]: An error occurred (AccessDenied) when calling the ListObjectsV2 operation: User: arn:aws:iam::<ACCOUNT_ID>:user/jorge-labs is not authorized to perform: s3:ListBucket on resource: "arn:aws:s3:::omop-tesis-jhr-2026" with an explicit deny in a resource-based policy

$ .venv/bin/pytest -m integracion -v
================================= test session starts =================================
platform linux -- Python 3.12.3, pytest-9.2.0, pluggy-1.7.0 -- /home/jorge/Documentos/data-sciences-labs/s20-aws-s3-boto3/tu-entrega/.venv/bin/python
cachedir: .pytest_cache
rootdir: /home/jorge/Documentos/data-sciences-labs/s20-aws-s3-boto3/tu-entrega
configfile: pytest.ini
testpaths: tests
plugins: platformdirs-4.14.5, anyio-4.16.0
collected 13 items / 9 deselected / 4 selected                                        

tests/test_s3util.py::test_integracion_subir_existe_listar_descargar PASSED     [ 25%]
tests/test_s3util.py::test_integracion_existe_false_en_llave_inexistente PASSED [ 50%]
tests/test_s3util.py::test_integracion_descargar_llave_no_existe PASSED         [ 75%]
tests/test_s3util.py::test_integracion_listar_raw_real PASSED                   [100%]

=========================== 4 passed, 9 deselected in 1.62s ===========================
```
