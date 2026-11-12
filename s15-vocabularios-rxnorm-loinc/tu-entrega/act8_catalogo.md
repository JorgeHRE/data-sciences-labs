# Actividad 8 — Mapear un catálogo local

Archivo entregable: `mapeo_catalogo_local.csv` (15 filas). Consultas: `actividades.sql`, actividades 8a (búsqueda de candidatos) y 8b (tabla final con controles). Decisiones 11 (herramienta) y 12 (reglas de confianza) en `DECISIONES.md`.

**Catálogo.** 15 claves ficticias (`FH-`, «farmacia hospitalaria»; no se copia el formato real de las claves del Compendio Nacional de Insumos para la Salud para que no se confundan con códigos oficiales), escritas como en una farmacia hospitalaria mexicana: mayúsculas, abreviaturas, sal y presentación pegadas al nombre. Incluye lo que pide el enunciado: abreviatura (HCTZ, TMP/SMX), combinaciones (TMP/SMX, amoxicilina/clavulánico, butilhioscina/metamizol), una presentación que no existe en RxNorm (diclofenaco con complejo B) y algo que no es un fármaco (gasa).

**Método (decisión 11).** Búsqueda por SQL sobre el vocabulario cargado (RxNorm 20260601), la misma versión que los datos. La traducción de cada descripción local al nombre de RxNorm queda escrita como patrón en la consulta 8a; la consulta comprueba qué existe. El `concept_name` de la tabla final no se teclea: sale de `cdm.concept`, y cada fila se valida como estándar, vigente y del dominio Drug. Las propuestas se hicieron con asistencia de Claude; la revisión y aprobación de cada mapeo es de JorgeHRE.

**Reglas de confianza (decisión 12).** *Alta*: existe un Clinical Drug estándar con mismo ingrediente, dosis y forma (tras convertir unidades). *Dudosa*: se mapea a algo menos específico o el candidato exige un supuesto no verificable. *No mapeable*: ningún concepto estándar del dominio Drug lo representa (`concept_id = 0`).

## Tabla de mapeo

| clave_local | descripcion_local | concept_id | concept_name | confianza | quién y por qué |
|---|---|---|---|---|---|
| FH-0101 | PARACETAMOL TAB 500MG C/10 | 19020053 | acetaminophen 500 MG Oral Tablet | alta | JorgeHRE 2026-11-12: paracetamol = acetaminophen (DCI vs USAN); dosis y forma exactas. |
| FH-0102 | HCTZ TAB 25MG C/30 | 19078106 | hydrochlorothiazide 25 MG Oral Tablet | alta | JorgeHRE 2026-11-12: HCTZ = hydrochlorothiazide; dosis y forma exactas. |
| FH-0103 | METFORMINA CLORH TAB 850MG C/30 | 40164946 | metformin hydrochloride 850 MG Oral Tablet | alta | JorgeHRE 2026-11-12: CLORH = clorhidrato; dosis y forma exactas. |
| FH-0104 | GLIBENCLAMIDA TAB 5MG C/50 | 19077682 | glyburide 5 MG Oral Tablet | alta | JorgeHRE 2026-11-12: glibenclamida = glyburide (DCI vs USAN); dosis y forma exactas. |
| FH-0105 | LOSARTAN POT TAB 50MG C/30 | 40185304 | losartan potassium 50 MG Oral Tablet | alta | JorgeHRE 2026-11-12: POT = potásico; dosis y forma exactas. |
| FH-0106 | ENALAPRIL MAL TAB 10MG C/30 | 40165762 | enalapril maleate 10 MG Oral Tablet | alta | JorgeHRE 2026-11-12: MAL = maleato; dosis y forma exactas. |
| FH-0107 | OMEPRAZOL CAP 20MG C/14 | 19019418 | omeprazole 20 MG Delayed Release Oral Capsule | alta | JorgeHRE 2026-11-12: la cápsula de omeprazol es de liberación retardada; se descarta 923720 (omeprazol + bicarbonato, otro producto). |
| FH-0108 | KETOROLACO TROMET SOL INY 30MG/1ML AMP | 40164851 | ketorolac tromethamine 30 MG/ML Injectable Solution | alta | JorgeHRE 2026-11-12: TROMET = trometamina; 30 mg/1 mL = 30 MG/ML. |
| FH-0109 | METAMIZOL SOD SOL INY 1G/2ML AMP | 19031455 | dipyrone 500 MG/ML Injectable Solution | alta | JorgeHRE 2026-11-12: metamizol = dipyrone; 1 g/2 mL = 500 MG/ML. No se vende en EE. UU. pero está en RxNorm. |
| FH-0110 | TMP/SMX TAB 80/400MG | 1836433 | sulfamethoxazole 400 MG / trimethoprim 80 MG Oral Tablet | alta | JorgeHRE 2026-11-12: combinación abreviada y en orden inverso; ambos ingredientes y dosis coinciden. |
| FH-0111 | AMOXI/AC CLAV SUSP 400/57MG/5ML 70ML | 19123605 | amoxicillin 80 MG/ML / clavulanate 11.4 MG/ML Oral Suspension | alta | JorgeHRE 2026-11-12: 400/57 mg por 5 mL = 80/11.4 MG/ML; el volumen del frasco no forma parte del Clinical Drug. |
| FH-0112 | BUTILHIOSCINA/METAMIZOL SOL INY 20MG/2.5G/5ML | 965844 | dipyrone 500 MG/ML / scopolamine 4 MG/ML Injectable Solution | **dudosa** | JorgeHRE 2026-11-12: concentraciones idénticas (4 y 500 MG/ML) pero RxNorm dice scopolamine, no butylscopolamine (ingrediente distinto, 40234201). Probable error de etiqueta en el vocabulario; usar con cuidado. |
| FH-0113 | DICLOFENACO/COMPLEJO B TAB 50MG | 1124300 | diclofenac | **dudosa** | JorgeHRE 2026-11-12: la combinación no existe en RxNorm (iría en RxNorm Extension, no cargada). Se mapea al ingrediente diclofenac; se pierden B1/B6/B12. Descartado betamethasone/diclofenac/vitamin B12 (añade un corticoide). |
| FH-0114 | SOL HARTMANN 1000ML | 19135374 | calcium chloride 0.2 MG/ML / potassium chloride 0.3 MG/ML / sodium chloride 6 MG/ML / sodium lactate 3.1 MG/ML Injectable Solution | **dudosa** | JorgeHRE 2026-11-12: la descripción no da la composición; se infiere de la fórmula estándar de Hartmann (NaCl 6, lactato 3.1, KCl 0.3, CaCl2 0.2 mg/mL), que coincide. Verificar contra la etiqueta. |
| FH-0115 | GASA SECA EST 10X10CM C/200 | 0 | No matching concept | **no mapeable** | JorgeHRE 2026-11-12: no es un fármaco sino un dispositivo médico; no hay concepto Drug. En OMOP iría a device_exposure con SNOMED 4224017 Gauze swab. |

## Resultado

| Confianza | Claves | % |
|---|---|---|
| alta | 11 | **73.3 %** |
| dudosa | 3 | 20.0 % |
| no mapeable | 1 | 6.7 % |

Lo que se aprendió del vocabulario por el camino:

- **RxNorm en OMOP trae productos que no son de EE. UU.** (metamizol, ambroxol en decenas de presentaciones), pero de forma parcial: es contenido heredado, no una cobertura sistemática. Lo que falta, como el diclofenaco con complejo B, tendría su lugar en RxNorm Extension, que no está cargado en esta base (decisión 1).
- **Las soluciones sí son fármacos en RxNorm**: la solución Hartmann existe con su composición exacta. Lo que no es fármaco es el material de curación, que en OMOP pertenece al dominio Device.
- **Faltar una combinación no se debe a ser combinación**: RxNorm tiene 19 formas clínicas con diclofenaco combinado (con misoprostol, lidocaína, paracetamol, pridinol…). Falta esa combinación concreta.

## Qué fue lo más difícil

Lo más difícil no fueron las abreviaturas ni los nombres en español: una vez que se sabe que glibenclamida es *glyburide*, HCTZ es hidroclorotiazida o metamizol es *dipyrone*, y que 400/57 mg por 5 mL equivale a 80/11.4 mg/mL, el mapeo es mecánico (aunque exige conocimiento farmacéutico que una herramienta como Usagi no tiene en español). Lo difícil fue **reconocer cuándo un candidato que parece perfecto es incorrecto**. En la butilhioscina con metamizol, RxNorm ofrece un producto con las mismas concentraciones exactas, pero con *scopolamine* en lugar de *butylscopolamine*: una sola palabra de diferencia que cambia la farmacología, porque la butilhioscina casi no cruza la barrera hematoencefálica y la escopolamina sí. Del mismo modo, un patrón de búsqueda laxo trajo «omeprazol + bicarbonato» como candidato para el omeprazol.

La segunda dificultad fue **decidir qué hacer con lo que no existe**. Para el diclofenaco con complejo B había que elegir entre perder al paciente (no mapeable) o perder las vitaminas (dudosa, al ingrediente), y resistir la tentación de *betamethasone / diclofenac / vitamin B12*, que «se parece» pero sería el peor mapeo posible. Primero, crea una exposición que no ocurrió: el paciente aparecería expuesto a un corticoide sistémico, con efectos propios bien documentados (hiperglucemia, osteoporosis, infecciones, supresión suprarrenal y más sangrado digestivo combinado con un AINE); en una base con pacientes diabéticos entraría por error en cualquier estudio de hiperglucemia inducida por corticoides. Segundo, es un error *por comisión*, más grave que uno *por omisión*: mapear al ingrediente pierde las vitaminas y se declara como dudoso, mientras que la betametasona añade un fármaco y el error queda invisible, porque el concepto es estándar, del dominio Drug, y pasa todas las validaciones. Tercero, ni siquiera es completo: le faltan B1 y B6 y es solo una forma clínica, sin dosis.

En todos los casos la regla fue la misma: es preferible un mapeo dudoso declarado que uno falsamente confiado, porque el error de un mapeo se propaga a todos los estudios que usen esa base. En un catálogo real de miles de claves, Usagi serviría para proponer candidatos, pero estas decisiones seguirían necesitando a una persona con criterio farmacológico.
