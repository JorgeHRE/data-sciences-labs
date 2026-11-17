# Guía reproducible de configuración segura en AWS (`aws-setup.md`)

Instrucciones paso a paso para que otra persona configure **su propia cuenta de AWS**, opere desde la AWS CLI y `boto3` **sin recibir credenciales ajenas** y aplique frenos de costo y privilegio mínimo desde el inicio.

---

## Prerrequisitos locales

- Python 3.10+ con entorno virtual (`boto3`, `jupyter`, `ipykernel`).
- **AWS CLI v2** instalada (`aws --version`).
- **`gitleaks`** instalado (`gitleaks version`).
- Una app autenticadora TOTP (Google Authenticator, Authy, Bitwarden, etc.).
- **Regla de oro:** nunca copies credenciales reales, Account IDs ni `~/.aws/` dentro del repositorio.

---

## Parte A — Cuenta, MFA y presupuesto (antes de crear recursos)

### 1. Crear cuenta AWS y activar MFA
1. Regístrate en AWS con un **correo dedicado y contraseña única** (en el portal nuevo de AWS Free Plan cuentas con \$100 USD en créditos por 6 meses y límite sin cobros a la tarjeta mientras sigas en el Plan Gratuito).
2. Activa **MFA (TOTP)** antes de cualquier otra acción:
   - En la consola clásica: menú superior derecho → *Security credentials* → *Assign MFA device*.
   - En la consola nueva por Proyectos (*Big Ideas Live Here*): ve a **`Perfil ↗`** → *Dispositivos con autenticación multifactor (MFA)* → **Registrar dispositivo** (TOTP) e ingresa dos códigos consecutivos.
3. Evidencia censurada de referencia: [capturas/mfa_raiz_activo.png](./capturas/mfa_raiz_activo.png).

### 2. Configurar presupuesto de \$5 USD (sin cambiar al plan de pago)
> **Nota importante:** en el portal de Facturación de Proyectos existe una pantalla de *"Límite de gasto mensual"* cuyo mínimo es \$20 USD y pertenece al asistente de actualización a plan de pago. **Omite/vuelve atrás** ahí para quedarte en el Plan Gratuito y configura las alertas en **AWS Budgets**:

1. Abre **Billing and Cost Management → Budgets → Create a budget**.
2. Elige **Customize (advanced)** → **Cost budget** (NO plantilla simplificada).
3. Configura período **Monthly**, **Recurring budget**, monto fijo **`5`** USD sobre todos los servicios.
4. Agrega **4 alertas** hacia tu correo:
   - `50 %` — **Actual** (gasto real)
   - `80 %` — **Actual** (gasto real)
   - `50 %` — **Forecasted** (gasto previsto)
   - `80 %` — **Forecasted** (gasto previsto)
5. Evidencia censurada de referencia: [capturas/presupuesto_5usd_config.png](./capturas/presupuesto_5usd_config.png).

### 3. Crear tu usuario IAM acotado
1. En la consola, abre **IAM → Usuarios → Crear usuario** (en español puede aparecer como *Crear persona*).
2. Crea un usuario (ej. `<tu-usuario>-labs`).
3. En **Permisos** → **Asociar políticas directamente**, elige permisos acotados al alcance del trabajo (en lugar de `AdministratorAccess`), por ejemplo:
   - `AmazonS3FullAccess`
   - `IAMFullAccess`
   - `AWSBillingReadOnlyAccess`
4. Si tu consola permite acceso de consola para usuarios IAM, habilítale contraseña + MFA, cierra sesión de la raíz y entra con el usuario IAM. *(En el portal por Proyectos actual, los usuarios IAM solo admiten acceso programático y la sesión de consola humana se protege mediante el MFA del perfil).*

---

## Parte B — Bucket S3 privado y política mínima

### 4. Crear bucket S3 con bloqueo público
1. Abre **Amazon S3 → Crear bucket** en tu región elegida (ej. `us-east-2`).
2. Tipo: **Uso general** | Espacio de nombres: **Global** | Nombre único global (ej. `lab19-<tu-nombre>-prueba-YYYYMMDD`).
3. Deja **Bloquear todo el acceso público** activado.
4. Crea dos prefijos (`publico/` y `privado/`) y sube un `archivo.txt` ficticio en cada uno (**cero datos reales de pacientes**).

### 5. Crear y simular `politica_minima.json`
1. Adapta [`politica_minima.json`](./politica_minima.json) cambiando el nombre del bucket al tuyo.
2. En **IAM → Políticas → Crear política → JSON**, créala (sin adjuntarla aún al usuario principal).
3. Ábrela en el **IAM Policy Simulator** (`https://policysim.aws.amazon.com/`, interfaz clásica si la nueva pide actualizar de plan):
   - **Nota sobre `AWS Organizations SCPs`:** si tu cuenta del Plan Gratuito pertenece a una organización gestionada por AWS, desmarca la casilla **`AWS Organizations SCPs`** a la izquierda para evaluar tu política aislada (con la casilla marcada verás `Denied by AWS Organizations`).
   - Verifica los 4 casos (`s3:GetObject` permitido en `publico/*` y denegado implícitamente en `privado/*`, `s3:PutObject` y `s3:DeleteObject`).

---

## Parte C — Operar desde terminal y Python sin credenciales en el repo

### 6. Configurar perfil nombrado en `~/.aws/`
1. En **IAM → Usuarios → `<tu-usuario>-labs` → Credenciales de seguridad → Claves de acceso**, genera una Access Key para **CLI** (nunca la pegues en archivos del repo).
2. En tu terminal local, ejecuta:
   ```bash
   aws configure --profile tesis
   ```
   Ingresa tu Access Key ID, Secret Access Key, región (`us-east-2`) y formato (`json`). Si pregunta por configurar agentes AI adicionales, responde `n`.
3. Verifica identidad y que `~/.aws/` vive fuera del proyecto:
   ```bash
   aws sts get-caller-identity --profile tesis
   ls -la ~/.aws/
   ```
4. Activa el entorno virtual y ejecuta [`verificacion.ipynb`](./verificacion.ipynb) cambiando `BUCKET_NAME` por el nombre de tu bucket:
   ```bash
   python3 -m venv .venv
   .venv/bin/pip install -r requirements.txt
   .venv/bin/jupyter nbconvert --to notebook --execute --inplace verificacion.ipynb
   ```
5. Ejecuta `gitleaks` sobre el repositorio e historial antes de cualquier `git push`.

---

## Cierre y limpieza ("apagar la luz")

Al terminar, elimina el bucket de prueba y verifica que no queden costos activos:

```bash
aws s3 rb s3://<TU-BUCKET> --force --profile tesis
aws s3 ls --profile tesis
```

Revisa **Cost Explorer** para confirmar costo `$0.00` y mantén activo el presupuesto de \$5 USD para los siguientes laboratorios.

---

## Validación por pares (actividad 10)

*(Pendiente de prueba con un compañero del grupo para anotar cualquier paso donde se atore).*
