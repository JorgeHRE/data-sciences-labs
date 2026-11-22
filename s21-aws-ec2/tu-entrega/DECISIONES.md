# Decisiones del laboratorio 21

Por cada decisión: qué se decidió, qué alternativas había y por qué se eligió esta.

| # | Decisión | Estado |
|---|---|---|
| D1 | Qué pipeline correr en el contenedor | **Decidida: A** (auditoría con `clinlab`) |
| D2 | Tipo de instancia | **Decidida: `t3.small`, créditos `standard`** |
| D3 | AMI (sistema operativo) | Pendiente |
| D4 | Cómo llegan las credenciales del rol al contenedor (IMDSv2, *hop limit*) | Pendiente |
| D5 | Alcance exacto de la política IAM | **Decidida: A**, escritura solo en `results/auditoria_obs/*` |
| D6 | Dónde corre Jupyter | Pendiente |
| D7 | Qué es el "trabajo largo" de `tmux` | Pendiente |
| D8 | Terminar o detener al final | Pendiente |
| D10 | Cómo se construye y publica la imagen del pipeline | **Decidida: A** (GitHub Actions → ghcr público) |
| D9 | Cómo obtiene el usuario humano (`jorge-labs`) permisos de EC2 y CloudWatch | **Decidida: B** |

---

## D9. Permisos de EC2 para el usuario que opera (`jorge-labs`)

**Decisión:** una política propia, `lab21-operador` ([iam/politica_operador.json](./iam/politica_operador.json)), con barandales: solo `us-east-2`, solo `t3.micro`/`t3.small`/`t3.medium`, solo discos gp3 de hasta 30 GB, `iam:PassRole` solo para roles `lab21-*` entregados a EC2, y alarmas de CloudWatch.
**Alternativas:** (A) `AmazonEC2FullAccess`: simple, pero permite cualquier tipo de instancia en cualquier región; (C) un rol de operador asumido con MFA: más seguro, pero añade complejidad que el lab no evalúa.
**Por qué:** el presupuesto de $5 solo *avisa* cuando ya se gastó; la condición sobre `ec2:InstanceType` *impide* el gasto antes de que ocurra. Se probó en el simulador antes de asignarla (15/15 casos, [iam/simular_operador.sh](./iam/simular_operador.sh)).
**Salvedad:** mientras `jorge-labs` conserve `IAMFullAccess` (que incluye `iam:*`), la restricción de `PassRole` está escrita pero no limita en la práctica. `IAMFullAccess` equivale a ser administrador (uno puede asignarse cualquier política), así que conviene retirarla al cerrar el lab.

### Hallazgos de la verificación previa (2026-11-21)
- **Presupuesto:** `Lab19-limite5usd` activo, $5 al mes, gastado $0.00, alertas reales y de pronóstico al 50 % y 80 %.
- **Plan de la cuenta:** `FREE`, con $119.98 de créditos hasta 2027-05. Cost Explorer probablemente mostrará un costo neto de $0, así que habrá que reportar el costo bruto y los créditos aplicados.
- **Tipos permitidos por el Plan Gratuito en `us-east-2`:** `t3`/`t8i` micro y small (x86, burstable), `t4g`/`t9g` micro y small (ARM), y `c7i-flex.large` (4 GiB) y `m7i-flex.large` (8 GiB), estos dos **no burstable**. `t3.medium` **no** está permitido.
- **Precios por hora, Linux:** `t3.micro` $0.0104 on-demand / $0.0016 spot; `t3.small` $0.0208 / $0.0043; `t3.medium` $0.0416 / $0.0116 (spot más barato por zona, consultado el 2026-11-21).

## D1. Qué pipeline corre en el contenedor

**Decisión:** auditoría de plausibilidad de `observations` ([pipeline/](./pipeline/)) que reutiliza `clinlab` (s05): lee de `curated/synthea/observations/`, aplica `marcar_valores_implausibles` y `contar_duplicados` a 6 analitos y escribe una fila por (año, código) en `results/auditoria_obs/ejecucion=<sello UTC>/`.
**Alternativas:** (B) eGFR con CKD-EPI: dos entradas, `patients` solo en `raw/` con PII simulada, y un JOIN; (C) agregados con DuckDB: no usa `clinlab`; (D) imagen 0.1.0 con un script montado: rompe la reproducibilidad.
**Por qué:** es "mi" pipeline de verdad (código probado en la s05), tiene una sola entrada (rol mínimo sin tocar `raw/`) y su consumo de memoria es real, lo que hace que elegir instancia tenga sentido.

Sub-decisiones tomadas con los datos a la vista (consultas de exploración del 2026-11-21):
- **Solo sangre** para creatinina (`38483-4`) y glucosa (`2339-0`), sin `2160-0`/`2345-7` de suero: un código por analito y sin mezclar muestras bajo un mismo rango.
- **Agrupar por `CODE`, nunca por `DESCRIPTION`:** `38483-4` y `2339-0` aparecen con dos descripciones cada uno.
- **Rangos (inclusivos):** sistólica 50–250 mmHg; FC 30–220 /min; peso 0.5–300 kg (incluye recién nacidos: mínimo observado 1.8 kg); IMC 10–80; glucosa 20–600 mg/dL; creatinina 0.1–20 mg/dL. Son amplios a propósito, para buscar errores de dato y no pacientes enfermos (la idea de *plausibleValueLow/High* del DQD de OHDSI).
- **Duplicados: contar y reportar, sin borrar (A).** Una auditoría no altera la fuente (trazabilidad, ALCOA). La alternativa B (borrarlos antes) cambiaba los denominadores y ocultaba el problema.
- **Lectura y escritura con `pyarrow.fs.S3FileSystem` (A).** Lee directamente de S3 sin pasar por el disco y toma sola las credenciales del rol vía IMDS. Alternativas: `s3fs` (más dependencias en la imagen) y boto3 con `/tmp` (toca el disco de la instancia, contra el criterio de evaluación).

Hallazgos de la auditoría: no hay nulos, ni valores no numéricos, ni unidades inconsistentes en los 6 códigos; no hay centinelas (los "99" contados son valores fisiológicos; ningún máximo llega a 999); 748 implausibles (719 creatininas > 20 mg/dL, con una mediana de 2.5 mg/dL, probablemente un artefacto de cómo Synthea simula la ERC; 29 sistólicas < 50); 164 duplicados exactos. Fuera de alcance, pero detectado: el eGFR `33914-3` viene con dos unidades (`mL/min/{1.73_m2}` y `mL/min`).

## D2. Tipo de instancia

**Decisión:** `t3.small` (2 vCPU, 2 GiB) con `CpuCredits=standard`.
**Alternativas:** `t3.micro` (1 GiB: no cabe el pico de unos 1.3 GiB entre sistema, Docker y pipeline); `c7i-flex.large` (4 GiB, sin créditos de CPU, pero 4× más caro y requiere ampliar la política).
**Por qué:** el pico medido del pipeline es de 0.80 GiB y la CPU trabaja menos de un minuto, así que los créditos no se agotan. Elegí `standard` en lugar del `unlimited` por defecto de los t3: si se agotan los créditos, la instancia se frena en vez de cobrar el excedente (unos $0.05 por vCPU-hora). Con un presupuesto de $5 prefiero un costo predecible.

## D10. Construcción y publicación de la imagen `auditoria-obs:0.2.0`

**Decisión:** un workflow `.github/workflows/publish-s21.yml` (con el patrón de la s06) que en cada PR corre pytest y construye la imagen sin publicarla, y al mergear a `main` publica `ghcr.io/jorgehre/auditoria-obs` con las etiquetas `0.2.0` y `sha-xxxxxxx`. La imagen es **pública**.
**Alternativas:** (B) *push* manual desde la laptop: requiere crear y guardar un token personal (PAT) y la imagen no queda ligada a un commit; (C) Amazon ECR privado: lo más parecido a una pharma (el rol cubre el `pull`), pero exige repositorio, permisos de ECR y OIDC desde Actions.
**Por qué:** si la imagen fuera privada en ghcr, la instancia necesitaría un token de GitHub, es decir, una credencial guardada en la máquina, contra el criterio principal del lab. Pública es aceptable porque la imagen contiene código, no datos: los datos están en S3 y solo los alcanza el rol. ECR queda como mejora documentada.

Detalles de la imagen: *multi-stage* con `uv` y venv creado en `/app/.venv` (la misma ruta en las dos etapas), usuario `appuser` (uid 1000), solo `linux/amd64`, 609 MB (`pyarrow` ocupa 170 MB). Se quitó `boto3` porque el código no lo usa (`pyarrow.fs` trae su propio cliente S3), lo que ahorró 55 MB. Se verificó que la imagen no contiene `~/.aws`, ni variables `AWS_*`, ni llaves en `docker history`.

## D5. Alcance del rol de la instancia (`lab21-instancia`)

**Decisión:** solo la base que el pipeline necesita: `s3:ListBucket` sobre el bucket con la condición `s3:prefix` limitada a `curated/synthea/observations/*` y `results/auditoria_obs/*`; `s3:GetObject` en `curated/synthea/observations/*`; `s3:PutObject` en `results/auditoria_obs/*`. Es una política inline (vive y muere con el rol) y la confianza se limita a `ec2.amazonaws.com`.
**Alternativas:** (B) añadir `AmazonSSMManagedInstanceCore` para Session Manager: rompe el "nada más" del enunciado, así que se deja para el bono como ampliación aparte; (C) `GetObject` en todo `curated/*`: viola "solo tu prefijo de datos". Para la escritura, `results/*` también cumplía el enunciado, pero se eligió `results/auditoria_obs/*` ("un rol, un trabajo": si el rol se filtra, no puede pisar resultados de otros pipelines).
**Por qué:** es el privilegio mínimo real. El rol ni siquiera puede borrar sus propios resultados, y con el versionado del bucket una escritura maliciosa no destruye las corridas anteriores. `ListBucket` es necesario porque pyarrow lista los archivos y hace un `HeadObject` previo sobre la llave del prefijo: sin `ListBucket`, S3 responde 403 en lugar de 404 a una llave inexistente.
