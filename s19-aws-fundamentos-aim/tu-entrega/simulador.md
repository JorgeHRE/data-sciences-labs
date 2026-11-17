# Resultados en el IAM Policy Simulator (Actividad 6)

Se evaluó la política [`politica_minima.json`](./politica_minima.json) (creada en IAM como `Minima`) de forma aislada sobre un usuario de prueba temporal (`simulador-minima`) sin otras políticas adjuntas, usando la interfaz clásica del IAM Policy Simulator (`policysim.aws.amazon.com`). Al concluir las pruebas, el usuario temporal `simulador-minima` se elimina de IAM.

## Tabla de casos probados (evaluación aislada de `Minima`)

| Debe | Acción | Recurso ARN simulado | Resultado real en el simulador | Regla / Explicación |
| :--- | :--- | :--- | :--- | :--- |
| permitir | `s3:GetObject` | `arn:aws:s3:::lab19-jorge-prueba-20261116/publico/archivo.txt` | **Allowed** (`1 matching statements`) | Coincide con el `Statement` `Allow` sobre `.../publico/*`. |
| denegar | `s3:GetObject` | `arn:aws:s3:::lab19-jorge-prueba-20261116/privado/archivo.txt` | **Denied** (`Implicitly denied (no matching statements)`) | El prefijo `privado/` no está incluido en `Resource`. |
| denegar | `s3:PutObject` | `arn:aws:s3:::lab19-jorge-prueba-20261116/publico/archivo.txt` | **Denied** (`Implicitly denied (no matching statements)`) | La acción `s3:PutObject` no está permitida en la política. |
| denegar | `s3:DeleteObject` | `*` (cualquiera) | **Denied** (`Implicitly denied (no matching statements)`) | La acción `s3:DeleteObject` no está permitida en la política. |

## Hallazgo observado: impacto de `AWS Organizations SCPs`

En la primera corrida de simulación (con la casilla **`AWS Organizations SCPs`** marcada por defecto en el simulador clásico), los cuatro casos devolvieron **`Denied by AWS Organizations`**, incluyendo `s3:GetObject` sobre `publico/archivo.txt`.

- **Por qué ocurrió:** en la nueva experiencia de **Plan Gratuito por Proyectos de AWS**, la cuenta reside dentro de una organización gestionada por AWS. En la jerarquía de evaluación de IAM, las **SCPs (*Service Control Policies*)** de AWS Organizations actúan como límite superior por encima de las políticas de identidad; al mantener activa la simulación contra esa capa organizacional en el simulador clásico, bloqueó la petición.
- **Cómo se validó sin modificar la política a ciegas:** se desmarcó la evaluación de `AWS Organizations SCPs` para aislar la lógica propia de la política `Minima`, confirmando que los cuatro casos coinciden exactamente con el diseño de privilegio mínimo.

## Evidencia visual

- Corrida con `publico/archivo.txt` (casos 1, 3 y 4): [capturas/simulador_publico.png](./capturas/simulador_publico.png)
- Corrida con `privado/archivo.txt` (caso 2): [capturas/simulador_privado.png](./capturas/simulador_privado.png)
- Hallazgo previo con `AWS Organizations SCPs` activado: [capturas/simulador_scp_organizacion.png](./capturas/simulador_scp_organizacion.png)
