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
