# Hallazgos — Lab 16 (Jerarquías: concept_relationship y concept_ancestor)

Vocabulario ATHENA v5.0 29-AUG-26, Postgres del lab 12. Las consultas están en `jerarquias.sql` (la actividad N corresponde a los bloques Na, Nb…).

## Actividad 3. La tabla `RELATIONSHIP`

### Conteos (3a)
| Tipos de relación | `is_hierarchical = 1` | `defines_ancestry = 1` | Ambos | Solo jerárquicos | Solo ascendencia |
|---|---|---|---|---|---|
| 724 | 124 | 63 | 55 | 69 | 8 |

**¿Coinciden?** No. 69 relaciones jerárquicas no definen ascendencia y 8 la definen sin ser jerárquicas. Las banderas son texto (`'0'`/`'1'`), no números.

### Relaciones que salen de metformina, RxNorm 1503297 (3b)
9 tipos, 247 relaciones, todas vigentes: *Mapped from* (120), *RxNorm ing of* (75), *Has brand name* (23), *RxNorm - ATC pr lat* (23), *RxNorm - SNOMED eq* (2), *Has form* (1), *Maps to* (1, a sí misma), *RxNorm - ATC sec up* (1, a A12AA20 calcio: dato raro del vocabulario) y *Value mapped from* (1, *Allergy to metformin*).

### Cinco relaciones explicadas
1. **RxNorm ing of** (1/1, 75 destinos directos): al ser jerárquica y definir ascendencia, esta relación conecta a metformina con 75 clases intermedias de productos que la contienen, y a través de ellas `concept_ancestor` la registra como ancestro de 482 descendientes. Por eso, al pedir los descendientes del ingrediente en un concept set, se capturan todos sus productos.
2. **Has brand name** (1/0, 23 destinos): aunque es jerárquica, no define ascendencia porque una marca comercial (como *Actoplus Met*) no es una subclase clínica del fármaco. Así, los descendientes de metformina no incluyen marcas como etiqueta (0 conceptos Brand Name); los productos de marca sí entran (91 Branded Drug), pero por otras relaciones.
3. **Mapped from** (0/0, 120 destinos): funciona como el embudo de estandarización del ETL (inversa de *Maps to*). Reúne 120 conceptos de otros vocabularios (96 no estándar de SNOMED y RxNorm, 23 códigos ATC y la propia metformina) que se traducen al concepto estándar de metformina, sin crear jerarquía.
4. **RxNorm - ATC pr lat** (0/0, 23 destinos): cruza lateralmente hacia 23 códigos ATC de 5.º nivel (sustancia química; principalmente A10BA02 «metformin; oral» y combinaciones A10BD). Aunque sus banderas son 0/0, en `concept_ancestor` esos 23 códigos aparecen como ancestros de metformina a nivel 0, y por encima de ellos la jerarquía ATC (A10BA *Biguanides* → A10B → A10 → A). Esto permite buscar productos de metformina partiendo de una clase ATC (comprobado en 3c).
5. **Has form** (0/0, 1 destino): vincula de forma puramente atributiva el ingrediente base con su sal química real (*metformin hydrochloride*, Precise Ingredient), aportando precisión farmacéutica sin generar relaciones de ascendencia.

### Conexión con la actividad 2
**`concept_ancestor` es curada, no depende solo de banderas.**

Evidencia:
- En T2DM, `'Subsumes'` es 1/1 y aun así 3 conceptos de la recursiva no entran en `concept_ancestor`, porque son no estándar: *Disorder by body site* y *Finding by site* están retirados desde 2021 (`invalid_reason = 'U'`, reemplazados por *Disease* y *Clinical finding*), aunque sus aristas 'Is a' siguen vigentes, y *SNOMED CT Concept* es la raíz de metadatos. Ninguno tiene registros en `condition_occurrence`.
- En metformina ocurre lo contrario: *RxNorm - ATC pr lat* es 0/0 y aun así los 23 códigos ATC sí son ancestros en `concept_ancestor` (3c).

## Actividad 4. Poli-jerarquía

### El par (4a)
En `concept_ancestor`, T2DM (201826, 444 pacientes en `condition_occurrence`) tiene dos ancestros con `min_levels_of_separation ≠ max_levels_of_separation`: *Disease* (4274025) 4/5 y *Clinical finding* (441840) 5/6. Se eligió **T2DM → Disease** (decisión 6).

### Los dos caminos, reconstruidos con `concept_relationship` (4b)
Recursión por 'Is a' con aristas vigentes **y conceptos destino vigentes** (sin el segundo filtro aparece un tercer camino de 5 pasos por *Disorder by body site*, retirado en 2021).

| Largo | Camino |
|---|---|
| 4 | Type 2 diabetes mellitus › Diabetes mellitus › Disorder of endocrine system › Disorder of body system › Disease |
| 5 | Type 2 diabetes mellitus › Diabetes mellitus › Disorder of glucose metabolism › Disorder of carbohydrate metabolism › Metabolic disease › Disease |

Los largos coinciden con `concept_ancestor` (4/5). Los caminos se separan en *Diabetes mellitus*, que tiene dos padres.

### Frase clínica
Es esperable y tiene sentido que la diabetes pertenezca a ambas ramas. Por un lado, la rama endocrina refleja su origen: en la tipo 2, las células β del páncreas no secretan suficiente insulina y los tejidos responden mal a ella (resistencia a la insulina). Por otro, la rama metabólica refleja su consecuencia: sin una acción adecuada de la insulina se altera directamente el metabolismo de los carbohidratos, y por eso se diagnostica midiendo glucosa o HbA1c.
