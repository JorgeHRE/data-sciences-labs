# Decisiones del laboratorio 21

Por cada decisión: qué se decidió, qué alternativas había y por qué se eligió esta.

| # | Decisión | Estado |
|---|---|---|
| D1 | Qué pipeline correr en el contenedor | Pendiente |
| D2 | Tipo de instancia | Pendiente |
| D3 | AMI (sistema operativo) | Pendiente |
| D4 | Cómo llegan las credenciales del rol al contenedor (IMDSv2, *hop limit*) | Pendiente |
| D5 | Alcance exacto de la política IAM | Pendiente |
| D6 | Dónde corre Jupyter | Pendiente |
| D7 | Qué es el "trabajo largo" de `tmux` | Pendiente |
| D8 | Terminar o detener al final | Pendiente |
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
