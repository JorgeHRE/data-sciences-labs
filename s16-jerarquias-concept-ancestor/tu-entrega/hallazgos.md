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

## Actividad 5. Medir el daño

### Concept set (decisión 7)
*Heart failure* 316139 (padre) + *Congestive heart failure* 319835 + *Chronic heart failure* 444031, todos con descendientes. Las dos ramas se traslapan: en la base solo aparecen *Chronic congestive heart failure* 4229440 (187 pacientes), que es descendiente de los tres miembros del set, y 316139 directo (7 pacientes). Cada paciente tiene 1 evento.

### Los tres números (5a)
| | Qué cuenta | Resultado |
|---|---|---|
| A | `COUNT(*)` sobre el JOIN con `concept_ancestor` | 568 (= 187 × 3 + 7) |
| B | `COUNT(DISTINCT condition_concept_id)` | 2 |
| C | `COUNT(DISTINCT person_id)` | **194** |

Comprobación: sin el JOIN (filtrando con `IN`), `condition_occurrence` tiene 194 eventos de 194 pacientes; las 374 filas extra de A son pura multiplicación del JOIN.

### Por qué difieren
Es una sola consulta con tres formas de contar sobre el mismo JOIN. A usa `COUNT(*)` y cuenta todas las filas del JOIN, por lo que el mismo diagnóstico se repite una vez por cada miembro del set que lo tiene debajo (3 veces para 4229440). B usa `COUNT(DISTINCT condition_concept_id)` y cuenta solo los códigos del set que realmente aparecen en los diagnósticos, por eso da 2: describe las enfermedades registradas, no a los pacientes. Finalmente, C usa `COUNT(DISTINCT person_id)` y es el único que responde «¿cuántos pacientes tienen insuficiencia cardiaca?»: **194**.

## Actividad 6. «¿Por qué entró este paciente?»

### La consulta (6a)
Función `results.por_que_entro(person_id)` (decisión 10) para la cohorte de insuficiencia cardiaca de la actividad 5. Devuelve una fila por evento × miembro del concept set que lo cubre: evento → concepto de origen → concepto estándar → rama → niveles hasta la rama. Se llama con `SELECT * FROM results.por_que_entro(79);` desde psql, Python o R.

### Salida para tres pacientes (6b)
| Paciente | Quién lo eligió | Concepto estándar | Ramas por las que entra |
|---|---|---|---|
| 79 | yo | 4229440 Chronic congestive heart failure (origen SNOMED 88805009) | 3: *Congestive* (1 nivel), *Chronic* (1 nivel), *Heart failure* (2 niveles) |
| 892 | yo | 316139 Heart failure (origen SNOMED 84114007) | 1: *Heart failure* (0 niveles: es el miembro del set) |
| 273 | un compañero del grupo | — | 0 filas: no pertenece a la cohorte |

Control adicional: el paciente 1, fuera de la cohorte, también devuelve 0 filas.

### ¿Por qué no entró el 273? (6d)
Existe en `cdm.person` y tiene 12 diagnósticos. No entró porque ninguno de sus 12 diagnósticos es insuficiencia cardiaca: ninguno es descendiente, en `concept_ancestor`, de los 3 miembros del concept set. Tiene prediabetes e hipertensión esencial, factores de riesgo de insuficiencia cardiaca, pero no el diagnóstico. Su *Prediabetes* es 37018196, el reemplazo del concepto retirado de la actividad 7.

### Funciona para cualquier paciente (6c)
Aplicada a las 5,904 personas de `cdm.person`: 568 filas, 194 pacientes, 194 eventos (187 con 3 ramas + 7 con 1). Reproduce exactamente A y C de la actividad 5. Tarda ~12 s (la función recorre `condition_occurrence` en cada una de las 5,904 llamadas); para un paciente, ~12 ms.

## Actividad 7. Cazar conceptos muertos

### Nuestros concept sets (7a)
| Concept set | Conceptos | `'D'` | `'U'` |
|---|---|---|---|
| IC de la actividad 5 (expandido) | 124 | 0 | 0 |
| `results.cs_t2dm` C (lab 14) | 131 | 0 | 0 |

0 retirados por construcción: `concept_ancestor` solo contiene conceptos estándar vigentes, así que un set expandido con ella no arrastra conceptos muertos.

### Conceptos de origen retirados en `condition_occurrence` (7b)
| Origen | Nombre | `invalid_reason` | Eventos | Reemplazo (`'Concept replaced by'`) | Pac. lista vieja | Pac. lista nueva |
|---|---|---|---|---|---|---|
| 40316773 | Prediabetes | U | 2,239 | 37018196 Prediabetes | 0 | 2,239 |
| 4166590 | Brain damage - traumatic | U | 26 | — (solo *same_as* → 4132546 Traumatic brain injury) | 0 | no se sustituye |
| 4196262 | Metastasis from malignant tumor of prostate | D | 18 | — (solo *Maps to* → 200962 Primary malignant neoplasm of prostate) | 0 | no se sustituye |
| 135333 | Pressure ulcer | U | 1 | 37159532 Pressure injury | 0 | 1 |

**Efecto de la corrección:** una lista literal con los códigos viejos encuentra 0 pacientes; actualizada con `'Concept replaced by'` encuentra **2,240** (2,239 + 1).

### Por qué falla en silencio
La lista anterior se escribió con IDs viejos, por lo que devuelve 0 pacientes sin generar un error ni una consulta fallida: simplemente no encuentra nada. El ETL guarda el código original en `condition_source_concept_id` y el estándar al que lo tradujo en `condition_concept_id`, que es donde se buscan los concept sets; ahí el ID viejo nunca aparece.

### Por qué no se sustituyen automáticamente los otros dos
*Brain damage - traumatic* solo tiene *Concept same_as to*: probablemente equivalente, pero el vocabulario no lo declara reemplazo y debe confirmarlo una persona. La metástasis de próstata fue borrada sin sucesor, y su *Maps to* apunta al tumor primario: una metástasis no es lo mismo que un tumor primario, así que sustituirla cambiaría la definición de la cohorte (mezclaría enfermedad diseminada con localizada).

**Antecedente:** el código ICD10CM E11.640 de la lista del lab 14 también está retirado (`'D'`, desde 2009-12-31).
