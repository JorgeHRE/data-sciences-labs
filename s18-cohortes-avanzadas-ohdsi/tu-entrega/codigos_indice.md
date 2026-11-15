# Códigos de entrada a la cohorte

Generado por `tabla_codigos.py` desde `codigos_indice.sql` (no editar a mano).

## Lisinopril (1701): producto de la receta del día índice (N = 122)

| concept_id | producto | clase | personas | % | % acumulado |
|---:|---|---|---:|---:|---:|
| 19080128 | lisinopril 10 MG Oral Tablet | Clinical Drug | 120 | 98.4 | 98.4 |
| 1308251 | lisinopril 5 MG Oral Tablet | Clinical Drug | 2 | 1.6 | 100.0 |

## Amlodipino (1702): producto de la receta del día índice (N = 81)

| concept_id | producto | clase | personas | % | % acumulado |
|---:|---|---|---:|---:|---:|
| 19073094 | amlodipine 2.5 MG Oral Tablet | Clinical Drug | 81 | 100.0 | 100.0 |

## Cuánto del concept set se usa

| cohorte | conceptos en el set | con recetas en la base | producto del índice |
|---|---:|---:|---:|
| Lisinopril (1701) | 98 | 9 | 2 |
| Amlodipino (1702) | 303 | 6 | 1 |

## Peso del producto más frecuente en cada etapa

| cohorte | etapa | unidad | total | productos distintos | % del más frecuente |
|---|---|---|---:|---:|---:|
| Lisinopril (1701) | 1. todas las recetas | receta | 42,085 | 9 | 98.1 |
| Lisinopril (1701) | 2. primera receta (toda la historia) | persona | 1,522 | 9 | 93.0 |
| Lisinopril (1701) | 3. cohorte sin inicio de estudio | persona | 242 | 5 | 94.6 |
| Lisinopril (1701) | 4. cohorte final | persona | 122 | 2 | 98.4 |
| Amlodipino (1702) | 1. todas las recetas | receta | 34,475 | 6 | 100.0 |
| Amlodipino (1702) | 2. primera receta (toda la historia) | persona | 1,104 | 4 | 99.7 |
| Amlodipino (1702) | 3. cohorte sin inicio de estudio | persona | 131 | 1 | 100.0 |
| Amlodipino (1702) | 4. cohorte final | persona | 81 | 1 | 100.0 |

## Lisinopril: quién inicia con el producto más frecuente y quién llega a la cohorte final

| primer producto | primeras recetas | índice desde 2017 | índice antes de 2017 | en la cohorte final |
|---|---:|---:|---:|---:|
| 10 mg | 1,415 | 318 | 1,097 | 120 |
| otro producto | 107 | 28 | 79 | 2 |
