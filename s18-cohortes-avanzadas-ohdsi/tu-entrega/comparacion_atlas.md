# Comparación con el SQL exportado de ATLAS

Generado por `comparar_atlas.py` (no editar a mano). El SQL exportado (`atlas_export.sql`) no se versiona.

## Cohorte de ATLAS contra la 1701 (lisinopril), persona por persona

| surveillance window (días añadidos al fin de la exposición) | personas ATLAS | personas 1701 | en ambas | solo ATLAS | solo 1701 | misma fecha índice | misma fecha de salida |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 0 | 122 | 122 | 122 | 0 | 0 | 122 | 67 |
| 30 | 122 | 122 | 122 | 0 | 0 | 122 | 122 |

Con 0, la salida coincide en 67 de 122: en 23 difiere exactamente 30 días y en 32 la salida de 1701 es el fin del periodo de observación y la de ATLAS queda entre 1 y 28 días antes. Con 30 coinciden las 122 (fecha índice y fecha de salida).

## Impacto de las diferencias de código en la cohorte final (122)

| diferencia | medida | valor |
|---|---|---:|
| A. ventanas recortadas al periodo de observación | con diagnóstico de hipertensión anterior al periodo | 0 |
| | cumplirían hipertensión solo por esos | 0 |
| B. «la primera» entre eventos con 365 días previos | primera receta sin 365 días de observación previa | 0 |
| | con ≥ 2 recetas el día índice (empate) | 44 |
| C. fin de receta | recetas de lisinopril sin fin | 0 |
| | recetas con fin anterior al inicio (CIRCE no las corrige) | 83 |
| E. conceptos válidos | conceptos inválidos en los concept sets | 0 |
