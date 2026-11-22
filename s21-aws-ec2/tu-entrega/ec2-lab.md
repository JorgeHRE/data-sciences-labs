# Laboratorio 21: ejecutar un análisis en la nube con EC2

**Región:** `us-east-2` (la misma del bucket `omop-tesis-jhr-2026`)
**Pipeline:** auditoría de plausibilidad de `observations` con `clinlab` ([pipeline/](./pipeline/))
**Instancia:** `t3.small` con créditos `standard`

Las decisiones están justificadas en [DECISIONES.md](./DECISIONES.md).

---

## 1. Justificación de la instancia y tipo elegido

**Memoria.** El pipeline usa un pico de **0.80 GiB** (803–806 MiB en 3 corridas, *Maximum resident set size* de `/usr/bin/time -v`). Lo sé porque lo medí, no porque lo estimara. Leer la tabla completa (10 columnas, 5.7 M filas) usaba unos 3.0 GiB. Leer solo 6 columnas y filtrar los 6 códigos en Arrow antes de pasar a pandas (*projection* y *predicate pushdown*: 508 322 filas) lo redujo casi 4 veces. Si sumo unos 300–400 MiB del sistema y unos 100 MiB del demonio de Docker, la instancia necesita alrededor de 1.3 GiB.

**Tiempo en la laptop.** Son entre 19 y 37 s leyendo desde S3 (3 corridas), de los que el cálculo es solo unos 3 s: el resto es la latencia de 110 peticiones HTTP desde casa hasta `us-east-2`, el mismo *small files problem* medido en el lab 20. Con los datos en disco local, la tabla completa se audita en 2.9 s.

**¿Por qué EC2?** Siendo honesto, **mi laptop alcanza de sobra** (16 núcleos y 46 GiB de RAM frente a 0.8 GiB necesarios). Por perfil, el trabajo encaja mejor en **Lambda** (menos de un minuto y menos de 1 GiB, dentro de sus límites de 15 min y 10 GB, y se paga por invocación) o en **Fargate** (un contenedor sin servidor que administrar). **Batch** sobra: sirve para orquestar muchos trabajos en cola. Uso EC2 porque el laboratorio también necesita una máquina interactiva (Jupyter por túnel SSH, `tmux`) y porque es la base para entender a los otros servicios. EC2 se justificaría de verdad si los datos crecieran hasta no caber en memoria en la laptop, o si la corrida durara horas.

**Tipo elegido: `t3.small` (2 vCPU, 2 GiB) con créditos `standard`.** `t3.micro` (1 GiB) no deja margen para unos 1.3 GiB. `c7i-flex.large` (4 GiB) cuesta 4 veces más ($0.0848 frente a $0.0208 por hora on-demand en `us-east-2`) para una memoria que no necesito. El trabajo es corto, así que no agota los créditos de CPU. Aun así elegí el modo `standard` (que frena) en lugar del `unlimited` por defecto (que cobra el excedente), para que el costo sea predecible. Detalle en [D2](./DECISIONES.md#d2-tipo-de-instancia).

## 2. Rol IAM de privilegio mínimo y evidencia del simulador

Rol **`lab21-instancia`**, con un *instance profile* del mismo nombre (es lo que EC2 recibe en realidad). Ninguna política administrada: ni `AmazonS3FullAccess` ni ninguna otra. Decisión: [D5](./DECISIONES.md#d5-alcance-del-rol-de-la-instancia-lab21-instancia).

**Confianza** ([iam/rol_confianza.json](./iam/rol_confianza.json)): solo el servicio `ec2.amazonaws.com` puede asumir el rol.

**Permisos** (inline `s3-auditoria-obs`, [iam/rol_permisos.json](./iam/rol_permisos.json)):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListarSoloLosDosPrefijosDelPipeline",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::omop-tesis-jhr-2026",
      "Condition": {
        "StringLike": {
          "s3:prefix": ["curated/synthea/observations/*", "results/auditoria_obs/*"]
        }
      }
    },
    {
      "Sid": "LeerSoloObservations",
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::omop-tesis-jhr-2026/curated/synthea/observations/*"
    },
    {
      "Sid": "EscribirSoloResultadosDeEstePipeline",
      "Effect": "Allow",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::omop-tesis-jhr-2026/results/auditoria_obs/*"
    }
  ]
}
```

`ListBucket` se aplica al **bucket** (ARN sin `/`) y se acota con `s3:prefix`; `GetObject` y `PutObject` se aplican a **objetos** (`…/prefijo/*`).

### Evidencia del simulador

**1. Política aislada (CLI, `simulate-custom-policy`)**, con [iam/simular_rol.sh](./iam/simular_rol.sh): 12/12 casos según lo esperado.

| Debe poder | | No debe poder | |
|---|---|---|---|
| Listar `curated/synthea/observations/` | allowed | Listar la raíz del bucket | implicitDeny |
| Leer un Parquet de `observations` | allowed | Listar `raw/` | implicitDeny |
| Escribir en `results/auditoria_obs/…` | allowed | Leer `raw/…/patients.csv` (PII simulada) | implicitDeny |
| Listar `results/auditoria_obs/` | allowed | Leer otra tabla de `curated/` | implicitDeny |
| | | Escribir en `results/otro/` | implicitDeny |
| | | Escribir en `curated/` (alterar la fuente) | implicitDeny |
| | | Borrar un resultado | implicitDeny |
| | | Leer otro bucket | implicitDeny |

**2. El rol real en el simulador de la consola** (`policysim.aws.amazon.com`, rol `lab21-instancia`, **casilla "AWS Organizations SCPs" desmarcada**):

- Permitido (GetObject en `observations/`, PutObject en `results/auditoria_obs/`): ![Simulador: casos permitidos](./capturas/simulador_rol_permitido.png)
- Denegado (GetObject en `raw/…/patients.csv`, PutObject en `curated/…`): ![Simulador: casos denegados](./capturas/simulador_rol_denegado.png)

En ambas capturas, la columna *Simulation Resource* dice `object`, es decir, se evaluaron los ARN escritos y no el comodín `*` por defecto. Un primer intento se descartó porque mostraba `*`: con el comodín, "allowed" no demuestra nada sobre un prefijo concreto. Con "Include Resource Policy" marcada, también se evalúa la política del bucket (solo HTTPS).

**Por qué hay que desmarcar las SCP (el mismo hallazgo del lab 19).** La cuenta del Plan Gratuito por Proyectos pertenece a una organización de AWS Organizations gestionada por AWS. Con las SCP incluidas, el simulador responde `explicitDeny` con `AllowedByOrganizations: false` **a todo**, incluso a acciones que en la realidad funcionan: simulando a `jorge-labs`, `s3:GetObject` da `explicitDeny`, pero un `head-object` real devuelve el objeto. Es un falso negativo de la capa organizacional, que el simulador no puede evaluar desde una cuenta miembro (tampoco se pueden leer las SCP: `ListPoliciesForTarget` da `AccessDenied`). Por eso, `simulate-principal-policy` de la CLI, que siempre incluye las SCP, no sirve en esta cuenta.

**3. Prueba real desde la instancia:** _pendiente (actividades 5 y 6)_. Es la prueba definitiva, porque atraviesa todas las capas, SCP incluidas.

## 3. Instancia y grupo de seguridad
_Pendiente (actividad 3)._

## 4. Script de `user data`
_Pendiente (actividad 4)._

## 5. Ejecución del pipeline: de S3 a S3
_Pendiente (actividad 5)._

## 6. Demostración de que no hay credenciales en la máquina
_Pendiente (actividad 6)._

## 7. Jupyter por túnel SSH
_Pendiente (actividad 7)._

## 8. Trabajo que sobrevive a la desconexión (`tmux`)
_Pendiente (actividad 8)._

## 9. Spot frente a on-demand
_Pendiente (actividad 9)._

## 10. Alarma de apagado, evidencia de apagado y costo medido
_Pendiente (actividad 10)._

---

## Criterios de evaluación

- [ ] Ninguna credencial de AWS está almacenada en la instancia (demostrado)
- [ ] El puerto 22 no está abierto a `0.0.0.0/0`
- [ ] Jupyter nunca estuvo expuesto a internet
- [ ] El rol de instancia es de privilegio mínimo, no `AmazonS3FullAccess`
- [ ] El `user data` deja la máquina lista sin intervención manual
- [ ] El pipeline lee y escribe en S3, no en el disco de la instancia
- [ ] La instancia quedó terminada o detenida al final
- [ ] Hay una alarma de apagado automático configurada
- [ ] El costo reportado viene de Cost Explorer, no de una estimación
- [ ] Cero credenciales en el repositorio (`gitleaks` limpio)
