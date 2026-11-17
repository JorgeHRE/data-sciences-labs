# Registro de decisiones — Lab 19 (Configurar una cuenta AWS de forma segura)

Formato: qué se decidió, qué alternativas había y por qué se eligió esta.

## 1. Entorno local aislado para Python y herramientas del laboratorio
- **Decisión:** crear un entorno virtual dedicado (`tu-entrega/.venv/`, ignorado por Git en `.gitignore`) con `boto3` y `jupyter`/`ipykernel`, en lugar de instalar paquetes en el Python del sistema, y utilizar las herramientas oficiales `aws` (AWS CLI v2) y `gitleaks` instaladas a nivel usuario/sistema.
- **Alternativas:** usar el Python global del sistema o un contenedor Docker con AWS CLI y Python.
- **Por qué:** Pop!_OS / Ubuntu 24.04 protege el Python del sistema (PEP 668), por lo que `.venv` evita conflictos y mantiene reproducible el `requirements.txt`. La AWS CLI v2 nativa opera directamente con `~/.aws/` fuera del repositorio sin montar credenciales dentro de contenedores.

## 2. Permisos iniciales del usuario IAM (Actividad 3)
- **Decisión:** asignar únicamente tres políticas administradas acotadas al alcance del laboratorio (`AmazonS3FullAccess`, `IAMFullAccess` y `AWSBillingReadOnlyAccess`) en lugar de `AdministratorAccess`.
- **Alternativas:** otorgar `AdministratorAccess` completo (más cómodo pero excesivo) o redactar una política JSON custom mínima desde cero antes de probar S3/IAM.
- **Por qué:** bloquea desde el inicio la creación accidental o por compromiso de llaves de servicios costosos (EC2, RDS, SageMaker) y cumple con el principio de privilegio mínimo a nivel de servicios, permitiendo crear buckets en S3, diseñar y simular políticas en IAM y revisar Cost Explorer al cierre.
- **Nota del entorno (Plan Gratuito / Proyectos AWS):** en esta interfaz de AWS por Proyectos, los usuarios de IAM solo admiten credenciales programáticas (*Claves de acceso* para CLI/`boto3`) y no contraseña de consola ni MFA por usuario; la autenticación humana en consola se protege mediante el MFA TOTP (`MFA1`) del perfil del proyecto, sin credenciales raíz activas.

## 3. Alcance de `politica_minima.json`: solo `s3:GetObject` sin `s3:ListBucket` (Actividad 5)
- **Decisión:** restringir `politica_minima.json` exclusivamente a la acción `s3:GetObject` sobre el ARN de objetos `arn:aws:s3:::lab19-jorge-prueba-20261116/publico/*`, sin incluir `s3:ListBucket`.
- **Alternativas:** agregar un segundo `Statement` con `s3:ListBucket` sobre el ARN del bucket (`arn:aws:s3:::lab19-jorge-prueba-20261116`, sin `/*`) acotado con una condición `s3:prefix` para `publico/*`.
- **Por qué:** cumple estrictamente con el criterio de privilegio mínimo pedido (una sola acción sobre un prefijo conocido) e impide enumerar qué otros objetos existen en el bucket; si en otro caso de uso se necesitara descubrir archivos nuevos, bastaría añadir `s3:ListBucket` apuntando al ARN del bucket (no de objetos).

## 4. Autenticación en `verificacion.ipynb` con perfil nombrado y salidas limpias (Actividad 8)
- **Decisión:** instanciar `boto3.Session(profile_name="tesis")` de forma explícita, enmascarar `Account` y `UserId` al imprimir la respuesta de `sts.get_caller_identity()` y descargar `publico/archivo.txt` dentro de `tempfile.TemporaryDirectory()` (fuera del repositorio).
- **Alternativas:** usar `boto3.client("s3")` sin `profile_name` dependiendo de `AWS_PROFILE` en la shell, o descargar el archivo directamente dentro de `tu-entrega/`.
- **Por qué:** pasar `profile_name="tesis"` permite que el notebook corra de forma autónoma en Jupyter/VS Code sin configuración previa del entorno y cumple literalmente con dejar solo el nombre del perfil en el código. Enmascarar los identificadores evita que las salidas guardadas del `.ipynb` expongan el `Account` ID en Git, y usar `TemporaryDirectory()` evita ensuciar el repositorio con archivos descargados.






