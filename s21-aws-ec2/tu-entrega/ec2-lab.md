# Laboratorio 21: ejecutar un análisis en la nube con EC2

**Región:** `us-east-2` (la misma del bucket `omop-tesis-jhr-2026`)
**Imagen:** _pendiente (D1)_
**Instancia:** _pendiente (D2)_

Las decisiones están justificadas en [DECISIONES.md](./DECISIONES.md).

---

## 1. Justificación de la instancia y tipo elegido
_Pendiente (actividad 1)._

## 2. Rol IAM de privilegio mínimo y evidencia del simulador
_Pendiente (actividad 2)._

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
