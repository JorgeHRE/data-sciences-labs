# Laboratorio 19 — Configurar una cuenta AWS de forma segura

Entrega correspondiente a `s19-aws-fundamentos-aim` (ver [../ENUNCIADO.md](../ENUNCIADO.md)).

## Contenido de la entrega

- `aws-setup.md` — Procedimiento reproducible paso a paso (con capturas censuradas).
- `politica_minima.json` — Política IAM de privilegio mínimo para lectura en `publico/`.
- `simulador.md` — Resultados reales de los 4 casos en el IAM Policy Simulator.
- `verificacion.ipynb` — Notebook con `boto3` usando perfil nombrado (`tesis`), cero credenciales en el código.
- `DECISIONES.md` — Registro de decisiones técnicas y alternativas evaluadas.

## Infraestructura creada (Actividad 4)

- **Región:** `us-east-2` (EE. UU. Este — Ohio)
- **Bucket S3:** `lab19-jorge-prueba-20261116` (espacio de nombres global)
- **Bloqueo de acceso público (*Block Public Access*):** activado (el prefijo `publico/` es solo organización lógica).
- **Estructura de objetos ficticios:**
  - `publico/archivo.txt`
  - `privado/archivo.txt`

## Política mínima comentada (Actividad 5)

El archivo [`politica_minima.json`](./politica_minima.json) contiene JSON puro (AWS IAM no admite comentarios dentro de la política). Explicación renglón por renglón de cada clave:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PermitirLecturaSoloPrefijoPublico",
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::lab19-jorge-prueba-20261116/publico/*"
    }
  ]
}
```

- **`Version` (`"2012-10-17"`):** indica al motor de AWS IAM la versión de la especificación del lenguaje de políticas (siempre debe usarse `"2012-10-17"` para habilitar las capacidades actuales; no es la fecha de creación).
- **`Statement` (`[ ... ]`):** lista que agrupa las reglas de permiso (`Sid` es un identificador descriptivo opcional para la regla).
- **`Effect` (`"Allow"`):** establece que esta regla **concede** acceso; cualquier acción o recurso no cubierto aquí queda rechazado por omisión (*Implicit Deny*).
- **`Action` (`"s3:GetObject"`):** autoriza únicamente descargar/leer objetos cuya clave exacta se conoce. Evita comodines como `s3:*` y omite `s3:ListBucket` (la cual requeriría otro `Statement` sobre el ARN del bucket sin `/*`).
- **`Resource` (`"arn:aws:s3:::lab19-jorge-prueba-20261116/publico/*"`):** limita el alcance exclusivamente a los objetos dentro de `publico/`. Lleva `/*` al final porque `s3:GetObject` opera sobre **objetos**, no sobre el bucket completo ni sobre `privado/*`.

## Verificación de seguridad

- `aws sts get-caller-identity --profile tesis`: verificado como usuario IAM `jorge-labs` (nunca `:root`), con `Account` y `UserId` censurados:

```json
{
    "UserId": "AIDA****************",
    "Account": "************",
    "Arn": "arn:aws:iam::************:user/jorge-labs"
}
```

- Confirmación `~/.aws/`: la configuración y credenciales viven en `/home/jorge/.aws/`, fuera del repositorio Git.
- `gitleaks`:
  - `gitleaks dir s19-aws-fundamentos-aim/tu-entrega/verificacion.ipynb --no-banner`: **0 hallazgos (`no leaks found`)**.
  - `gitleaks detect --source . --no-banner` sobre los 193 commits previos del monorepo: **0 credenciales reales** (únicamente 2 falsos positivos históricos de `pageToken` en `s08-apis-rest-consumo`). Se volverá a correr sobre los commits del lab 19 tras el `git commit`.

## Cierre y costos ("apagar la luz")

- **Bucket de prueba eliminado:** `lab19-jorge-prueba-20261116` y sus objetos ficticios fueron removidos al terminar las pruebas.
- **Cost Explorer:** `$0.00 USD` en costo total y promedio mensual ([capturas/cost_explorer_cierre.png](./capturas/cost_explorer_cierre.png)).
- **Presupuesto activo:** el presupuesto de `$5.00 USD` (alertas 50 % y 80 %, real y previsto) permanece activo para las sesiones 20 y 21.
