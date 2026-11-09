# Registro de decisiones — Lab 12 (OMOP CDM)

Formato: qué se decidió, qué alternativas había y por qué se eligió esta.

## 1. Estructura del repo y archivos pesados
- **Decisión:** el `ENUNCIADO.md` y los vocabularios de ATHENA quedan fuera de git (`.gitignore`); `tu-entrega/` guarda solo código, documentación y resultados.
- **Alternativas:** subir los vocabularios (descartado: licencia no redistribuible y ~3 GB) o guardarlos dentro de `tu-entrega/` (descartado: se confunde con la entrega).
- **Por qué:** reproducibilidad vía comandos documentados, no vía datos subidos.

## 2. Orden de las actividades
- **Decisión:** vocabularios (act. 3) antes de la conversión (act. 2).
- **Alternativa:** seguir el orden numérico del enunciado.
- **Por qué:** el propio enunciado advierte que sin vocabularios todo mapea a `concept_id = 0`; convertir primero obligaría a repetir el ETL.

## 3. Ruta de conversión (actividad 1)
- **Decisión:** ETL-Synthea (R, paquete oficial de OHDSI, v2.1.1).
- **Alternativas:** dbt-synthea (descartada: su README solo soporta Synthea v3.0.0 y mis CSV son v3.3.0, habría que regenerar los 5,000 pacientes; además se declara no apta para producción) y mapeo a mano de 4 tablas (descartada: con un solo dominio no se puede medir `concept_id = 0` por dominio en la actividad 5).
- **Por qué:** es la única ruta que acepta los CSV tal como están (ETL-Synthea v2.1.1 soporta Synthea 2.7.0 y 3.0.0–3.3.0) y cubre todas las tablas clínicas.
- **Costo asumido:** la base queda en PostgreSQL y no en DuckDB.

## 4. Dónde vive la base OMOP (actividad 3)
- **Decisión:** un Postgres 16 propio del lab (`tu-entrega/compose.yml`, proyecto `lab12-omop`, puerto 5433).
- **Alternativas:** reutilizar el Postgres de `proyecto-rag-omop` (descartada: mezcla proyectos y el entregable dejaría de ser reproducible por sí solo) y DuckDB (descartada: ETL-Synthea no escribe en DuckDB, contradice la decisión 3).
- **Por qué:** ETL-Synthea necesita los vocabularios en la misma base donde escribe, y el aislamiento evita que un error aquí dañe el otro proyecto.

## 5. Paquete único de vocabularios (actividad 3)
- **Decisión:** pedir en ATHENA una descarga nueva con SNOMED, ICD10CM, RxNorm, LOINC y ATC marcados juntos, en lugar de unir dos paquetes (base: SNOMED/RxNorm/LOINC; segundo: ICD10CM/ATC).
- **Alternativa:** unir ambos paquetes y documentar la limitación. La unión era técnicamente posible (208,107 conceptos compartidos, idénticos), pero ATHENA solo incluye una relación si sus dos extremos están en la misma descarga: solo 130 relaciones `Maps to` salen de ICD10CM (todas hacia `Episode`), así que no existía ningún mapeo ICD10CM → SNOMED.
- **Por qué:** un paquete coherente evita la unión manual y deja los mapeos completos. Mientras llega, el script de carga se prueba con el paquete base.

## 6. Ampliar la descarga de ATHENA con Gender, Race, Ethnicity y CVX (actividad 3)
- **Decisión:** pedir una segunda descarga con los 5 vocabularios del enunciado más Gender, Race, Ethnicity y CVX, y recargar `cdm` (borrar el esquema, recrear tablas, `COPY`, índices).
- **Alternativas:** insertar a mano los conceptos de sexo, raza y etnia (descartada: parche no oficial y CVX no se puede inventar) o seguir sin ellos y documentar la pérdida (descartada: `person` quedaría sin demografía y ETL-Synthea descartaría las vacunas sin avisar).
- **Por qué:** al medir `CONCEPT.csv` antes de correr el ETL no existían los conceptos 8507, 8532, 8527, 8516 ni 38003563, ni el vocabulario CVX. El enunciado pide el subconjunto «mínimo», así que ampliarlo es compatible. Misma release (v5.0 29-AUG-26).
- **Resultado:** 2,028,013 conceptos (847,999 estándar, 93,424 de clasificación, 1,086,590 de origen); 14,138,100 relaciones; 12,077,497 ancestros; 0 huérfanos en `concept_relationship`.

## 7. Cómo se ejecuta ETL-Synthea (actividad 2)
- **Decisión:** en Docker (`etl/Dockerfile`, R 4.5.3, CommonDataModel v5.4.3, ETL-Synthea v2.1.1), con los vocabularios que ya están en `cdm` (no se recargan) y solo las tablas clínicas creadas por el ETL.
- **Alternativas:** R local 4.6.1 (descartada: sin probar con ETL-Synthea v2.1.1, `rJava` suele fallar y es menos reproducible); esquema aparte `cdm_etl` con recarga de vocabularios (descartada: duplica ~3 GB y deja dos copias) y borrar `cdm` para el flujo estándar (descartada: tira la actividad 3).
- **Por qué:** la imagen aísla Java, `psql` y los paquetes OHDSI con versiones fijas, y conserva una sola copia de vocabularios cargada por `cargar_vocab.sh`. El script se monta desde el host para editarlo sin reconstruir. `psql` es necesario solo para `bulkLoad`; las consultas van por JDBC.

## 8. Ceros iniciales perdidos al cargar los CSV de Synthea (actividad 2)
- **Decisión:** reparar en `native`, justo después de `LoadSyntheaTables`, con `UPDATE ... lpad`: `immunizations.code` de 1 dígito a 2 (CVX `03`, `08`) y los `zip` (1-4 dígitos a 5; 6-8 a 9, por los ZIP+4 de `organizations` y `providers`). Está en `etl/run_etl_synthea.R` e imprime conteos antes y después.
- **Alternativas:** cargar los CSV con `\copy` propio como texto (descartada: reemplaza un paso oficial y hay que cuidar tipos y fechas) o dejarlo y documentarlo (descartada: 2,866 vacunas, 3.3%, irían a concepto 0 por un fallo de la herramienta y no de los datos).
- **Por qué:** `LoadSyntheaTables` lee con `data.table::fread`, que adivina tipos; una columna solo con números pasa a entero y `08` queda `8`. Los conteos de filas coincidían y no lo detectaron: se vio al buscar en `native` los códigos de `immunizations` que no existían en CVX. Verificado con la distribución completa (2,324 valores) idéntica a la de los CSV.
- **Lección:** comparar conteos no basta; también hay que comparar el contenido de las columnas clave.

## 9. Omitir `cost` en la carga de eventos (actividad 2)
- **Decisión:** `LoadEventTables(sqlOnly = TRUE)` escribe el SQL oficial de cada paso y el script los ejecuta todos, en el orden del paquete, **menos** `insert_cost_v300.sql`. `cdm.cost` queda vacía. Un `stopifnot` compara la lista de pasos del paquete con la del script para que un cambio de versión falle en voz alta.
- **Alternativas:** esperar (descartada: más de 70 min sin terminar, al 100 % de CPU y con 430 MB de temporales); un `statement_timeout` para el rol (descartada: afecta a todas las consultas de las act. 4-10); subir `work_mem` e indexar para que termine (descartada: sin garantía de tiempo razonable).
- **Por qué:** el enunciado no usa `cost` en ninguna actividad y es el último paso, por lo que lo anterior ya está confirmado. `cost` es una tabla económica (HEOR), no clínica. Se puede generar más adelante (con índices y más `work_mem`) si las sesiones 13-18 la piden.
- **Causa probable de la lentitud:** `insert_cost_v300.sql` une `claims` y `claims_transactions` (5.6 M de filas) con tablas de `cdm` sin índices de clave. En `rag-omop` el ETL entero tardó ~28 min porque el volumen de datos era otro.

## 10. Conciliación de `condition_occurrence` y `death` (actividad 2)
- **Decisión:** no corregir nada; documentar que una fila de origen no equivale a una fila de destino, y reportar la conciliación en el reporte de calidad.
- **`condition_occurrence` = 101,699:** 96,438 (SNOMED → Condition) + 5,261 (ICD10CM → Condition, posible solo gracias a que la descarga incluye ICD10CM con sus relaciones a SNOMED). Incluye 108 filas duplicadas por multi-mapeo (7 códigos ICD10CM con 2 conceptos estándar, p. ej. `K06.9`). 129,201 condiciones SNOMED van a `observation` (dominio *Observation*: situaciones y hallazgos como estrés o empleo).
- **Impacto en pacientes:** 5,826 de 5,904 (98.7 %) aparecen en `condition_occurrence`; el efecto es sobre filas, no sobre pacientes.
- **`death` = 829:** 904 fallecidos − 32 sin encuentro de certificación − 43 con causa no mapeable (`55680006` obsoleto, `94260004` no estándar sin `Maps to`, `48333001` de dominio *Observation*). El `JOIN` interno del ETL descarta esas filas sin error.
- **Por qué:** el ETL enruta cada código al dominio de su concepto estándar. Comparar totales de filas esconde esto; hay que conciliar por dominio.

## 11. Reproducibilidad de la conversión: límite conocido en `visit_occurrence` (actividad 2)
- **Decisión:** aceptar y documentar que la conversión es reproducible salvo por unas decenas de visitas, sin intentar corregir ETL-Synthea.
- **Evidencia:** dos corridas con los mismos datos de entrada dieron conteos idénticos en todas las tablas excepto `visit_occurrence` y `visit_detail` (385,938 frente a 385,971; +33, 0.009 %). Las tablas auxiliares (`all_visits`, `assign_all_visit_ids`, `final_visit_ids`) tienen los mismos totales; dentro de una corrida ningún JOIN pierde visitas.
- **Causa probable (no demostrada):** el SQL de ETL-Synthea numera visitas con ordenamientos con empates (`row_number() over (order by patient)` en `AllVisitTable.sql`; `ORDER BY PRIORITY` y `ORDER BY start, stop` sin desempate), lo que deja la fusión de visitas dependiendo del orden arbitrario de Postgres.
- **Alternativas:** parchear el SQL del paquete para añadir desempates (descartada: modifica la herramienta oficial y no es el objetivo del lab) o repetir la carga para confirmar la causa (pendiente, 40 min, no cambia la entrega).
- **Por qué:** el efecto es de 0.009 % y no altera ninguna conclusión de calidad; lo importante es no afirmar «idéntico» cuando se midió una diferencia.

## 12. Alcance y herramienta del diagrama ER (actividad 4)
- **Decisión:** dibujar el núcleo clínico y el vocabulario (14 tablas) en tres bloques Mermaid, y listar las otras 31 en una tabla con filas y estado (con datos, vacía o auxiliar). Archivo: `diagrama_er.md`.
- **Alternativas:** las 39 tablas del CDM en un solo diagrama (ilegible); dbdiagram.io o Graphviz (servicio externo o scripts extra, y la imagen ya no se edita como texto).
- **Por qué:** Mermaid es texto versionado en git y GitHub lo renderiza. Las columnas y PK se extrajeron de `information_schema`, y un script cruzó las 81 columnas dibujadas contra la base (0 discrepancias de nombre, tipo o PK). `device_exposure` (9,255 filas) quedó fuera del diagrama; consta en la tabla de tablas restantes.

## 13. Relaciones hacia `concept`: una línea por tabla (actividad 4)
- **Decisión:** dibujar solo la línea del concepto principal de cada tabla clínica (`condition_concept_id`, `drug_concept_id`, etc.) y anotar que las demás columnas `*_concept_id` también apuntan a `concept`.
- **Alternativas:** una línea por columna (unas 40 hacia una sola caja, ilegible); línea estándar más línea de origen por tabla (duplica las líneas; se reconsidera en la act. 7 si hace falta).
- **Por qué:** muestra el patrón central (todo evento cuelga de un concepto estándar) sin perder legibilidad.

## 14. Dos diferencias frente al estándar v5.4: sin FK y `cost` vacía (actividad 4)
- **Decisión:** anotar como diferencias (A) 0 llaves foráneas declaradas y (D) `cost` con 0 filas.
- **Corrección propia:** descarté la candidata «`death` y `concept_ancestor` sin PK». La especificación v5.4 marca Primary Key = FALSE en todos sus campos, así que coinciden con el estándar.
- **Veredicto:** (A) simplificación legítima, las FK suelen añadirse después de la carga masiva; (D) hueco real, causado por una decisión mía documentada (decisión 9).
- **Alternativas descartadas:** PK compuesta de `concept_relationship` (la añadí en `02_indices_vocabularios.sql:21`; el estándar no la marca) y las 6 tablas auxiliares (no son del CDM); ambas con veredicto «legítima», que no mostraba contraste.
- **Límite:** la especificación se leyó con un resumen automático; la celda de `concept_relationship` no se citó en el entregable.

## 15. Qué columnas cuentan en el porcentaje de `concept_id = 0` (actividad 5)
- **Decisión:** medir el concepto principal de cada dominio (estándar) y su `*_source_concept_id` (origen), con **todas las filas** como denominador. No se miden las columnas opcionales (`*_type_`, `*_status_`, etc.).
- **Alternativas:** solo el concepto principal (no explica por qué un dominio sale peor); todas las columnas `*_concept_id` (los ceros de columnas opcionales vacías inflan el porcentaje).
- **Por qué:** el estándar mide la calidad del mapeo; el origen distingue «código fuera de los vocabularios» de «sin destino estándar».

## 16. Los ceros no miden completitud: se compara contra la fuente (actividad 5)
- **Hallazgo:** casi todos los dominios dan 0 %, porque ETL-Synthea descarta lo que no mapea y no lo escribe con 0. Excepciones: raza 2.79 % (165 personas) y `visit_source_concept_id` 100 % (columna opcional que el ETL no llena; no es fallo).
- **Decisión:** medir la pérdida comparando `native.*` con el CDM, clasificando por **código distinto** (un JOIN directo al mapa multiplica filas de códigos con varios destinos) y comprobando que la suma sea el total de la fuente.
- **Resultado en `conditions`:** 235,504 filas = 5,153 + 96,438 → `condition_occurrence`, 129,201 → `observation`, 4,712 sin escribir (2.00 %). Cuadra con el CDM (101,699 − 108 por multi-mapeo + 129,201). Esta cifra sustituye a las «4,601 por confirmar».
- **Límite:** la cuadratura es aritmética (conteos), no identidad fila a fila; y no se ha verificado que las filas de `observation` sean las de conditions.

## 17. Diagnóstico de los 27 códigos de `conditions` sin destino (actividad 5)
- **Hallazgo:** los 27 existen en `concept` (ninguno estándar) y ninguno tiene `Maps to` ni `Concept replaced by`. Los 7 ICD10 (metástasis C77/C79) solo tienen `Is a`; 15 SNOMED tienen `Maps to value` (mapeo poscoordinado) pero no `Maps to`, que es la única relación que usa ETL-Synthea. Pérdida concentrada: sobredosis (907 filas), dependencia de drogas (323), concusión (314), metástasis (43).
- **No determinado:** si el `Maps to` falta en el vocabulario oficial o solo en esta descarga (hipótesis b: el destino está en un vocabulario no descargado). La BD no lo decide; se contrasta en ATHENA (act. 9).
- **Control sin poder:** `concept_relationship` tiene 0 filas inválidas, así que filtrar por `invalid_reason` no distingue nada en esta descarga.

## 18. `medications` y `immunizations`: completitud (actividad 5)
- **medications:** 0 pérdida. 345 códigos RxNorm → `Drug`; un código con 2 destinos duplica 42 filas (388,616 + 84 = 388,700 = filas de tipo 32838 en `drug_exposure`). Filtrar `source_vocabulary_id = 'RxNorm'` es obligatorio: hay colisiones numéricas con OSM (Geography).
- **immunizations:** 86,068 → 78,890; **7,178 filas (8.3 %) perdidas, todas de 3 códigos COVID-19 (CVX 207: 3,133; 208: 3,845; 212: 200), 100 % de cada uno**. Los otros 19 códigos pierden 0 %.
- **Causa (leída en el código del ETL, no inferida):** el INSERT de vacunas exige `target_vocabulary_id = 'CVX'`; las COVID se mapean de CVX a RxNorm, así que el INNER JOIN las descarta en silencio.
- **Lección de método:** el mapa solo habría predicho 0 % de pérdida (los 22 códigos tienen destino `Drug` estándar). La pérdida se vio al cuadrar fuente contra CDM. Cuadrar la salida es la comprobación que no depende de suponer qué hace el ETL.
- **No decidido:** si corregir el ETL (aceptar destinos RxNorm) o solo documentarlo. Afecta a cualquier cohorte de vacunación COVID, que saldría vacía.

## 19. `procedures`: la mayor pérdida del lab (actividad 5)
- **Resultado:** de 869,518 filas llegan 701,419 (454,821 a `procedure_occurrence` + 246,598 a `measurement`); **168,099 perdidas (19.3 %)**. Cuadra exacto: ambos destinos coinciden con el CDM, y el control (0 códigos compartidos con `observations`) podía fallar.
- **Causa 1, 100,892 filas:** destino `Observation` (p. ej. derivación a dental 40,870; cuidados paliativos 20,773). Los INSERT que leen `procedures` son solo `insert_procedure_occurrence.sql` e `insert_measurement.sql`; ninguno escribe en `observation`. Más 1,507 Drug, 497 Device y 118 Condition, por lo mismo.
- **Causa 2, 65,085 filas sin destino:** 442 códigos (63,383 filas) con patrón `D####` (p. ej. D0120 «periodic oral evaluation», D7140 extracción), ninguno existe en `concept` y la base no tiene ningún vocabulario CDT. Son códigos dentales CDT (vocabulario con licencia, no incluido en la descarga). **Inferido por patrón y descripción, no confirmado en ATHENA** (act. 9). Otros 5 códigos (1,702 filas) existen pero no son estándar.
- **Decisión (usuario):** solo documentar; no tocar el ETL (ver 18).

## 20. `devices`: completitud (actividad 5)
- **Resultado:** 9,973 filas de origen → 9,255 en `device_exposure`; **718 perdidas (7.2 %)**, cuadra exacto. Son 3 códigos con 100 % de pérdida: cama de hospital (485), andador (194, deprecado `D`) y máquina de hemodiálisis (39).
- **Causa:** existen en `concept` pero no son estándar ni tienen `Maps to`/`Concept replaced by`/`Maps to value`; el INSERT exige destino `Device/SNOMED` estándar. Mismo patrón que `conditions` (decisión 17): causa en el vocabulario, no en el ETL. Si falta el `Maps to` en el vocabulario oficial o solo en la descarga: pendiente de ATHENA (act. 9).

## 21. `observations` y `allergies`: completitud (actividad 5)
- **observations (5,719,327 filas):** 3,761,682 → `measurement` (cuadra: 4,008,280 − 246,598 de procedures); 1,795,820 → `observation` (cuadra: filas con `observation_source_value` en códigos de observations; control sin solapes con conditions/allergies/procedures). **Perdidas 161,825 (2.83 %):** 161,527 sin destino + 194 Note + 104 Procedure (el ETL no los escribe).
- **Concentración:** 159,864 de las 161,527 sin destino son QOLS, QALY y DALY (53,288 cada una), métricas de calidad de vida de Synthea sin código LOINC. Además 1,028 de dos códigos locales `X9999-x`. El resto (~635 filas) son LOINC de oncología (estadio clínico, HER2, receptores de estrógeno/progesterona) sin destino estándar: pocas filas pero clínicamente relevantes; refuerza el patrón de metástasis (decisión 17).
- **allergies (5,262):** 4,604 → `observation` (cuadra); **658 perdidas (12.5 %)**: 484 sin destino y 174 con destino `Drug`, que el INSERT de alergias no escribe.
- **Fuentes que ETL-Synthea no carga (por diseño):** `careplans` 20,770, `imaging_studies` 658,769, `supplies` 58,104 y `claims`/`claims_transactions`; no se miden porque el CDM v5.4 de este ETL no tiene destino para ellas (excepto `cost`, omitida). Es un límite de la completitud global.

## 22. Los 165 `race_concept_id = 0` son un fallo del ETL, no del vocabulario (actividad 5)
- **Causa (leída en `insert_person.sql`):** la raza está escrita a mano: solo `white`→8527, `black`→8516, `asian`→8515; todo lo demás → 0. Los IDs usados son correctos (verificados en `concept`); la etnia también (38003564/38003563, suma 5,904).
- **Desglose:** `other` 69, `hawaiian` 58, `native` 38 = 165 (2.79 % de las personas).
- **Recuperable:** 96 personas (58 + 38) tenían concepto estándar disponible, 8557 y 8657, ya presentes en la descarga. Las 69 `other` no tienen categoría OMB estándar equivalente (existe 8522 «Other Race», que no aparece como estándar), así que su 0 es defendible.
- **Efecto:** cualquier análisis estratificado por raza no vería a los pacientes nativo-hawaianos ni indígenas americanos. Consistente con la decisión 18: solo se documenta, no se corrige el ETL.

## 23. Top 20 de diagnósticos: personas por concepto estándar (actividad 6)
- **Opciones:** A) `condition_occurrence` agrupado por `condition_concept_id` con `count(DISTINCT person_id)`; B) A más un ranking aparte de los hallazgos de `observation`; C) agrupar por conceptos padre con `concept_ancestor`.
- **Elegida A.** Mide prevalencia (qué parte de la población tiene el diagnóstico), que es la pregunta de la actividad. Contar registros mide carga de atención: con registros, *Normal pregnancy* sube del puesto 20 al 9 (2,384 registros entre 1,023 mujeres) y los diagnósticos que se re-registran en cada visita (gingivitis, 12,221 registros / 4,891 personas) se inflan. B mezcla dominios; C cambia la granularidad y exige elegir un nivel de la jerarquía, decisión que no pide la actividad.
- **Denominador del %:** las 5,904 personas, no las 5,826 con alguna condición.
- **Control:** el JOIN a `concept` no cambia filas (101,699 = 101,699) y no hay `condition_concept_id = 0`.

## 24. Visitas por persona: denominador = toda la población (actividad 6)
- **Opciones:** A) dividir entre las 5,904 personas, con 0 para quien no tiene visitas de un tipo; B) dividir solo entre quienes tienen al menos una visita de ese tipo.
- **Elegida A**, la forma habitual de describir una cohorte. B responde otra pregunta («cuántas veces va a urgencias quien va»; 3.7 en vez de 2.7).
- **Implementación:** se parte de `person`, se cruza con los tipos (`CROSS JOIN`, 17,712 filas) y se hace `LEFT JOIN` a las visitas, para que los ceros existan como filas y entren en la mediana. Se cuenta con `count(v.visit_occurrence_id)`: `count(*)` contaría la fila NULL del `LEFT JOIN` como una visita (urgencias pasaría de 15,954 a 17,573 y nadie tendría 0).
- **Control:** la suma por tipo da 385,971 = filas de `visit_occurrence`; personas con 0 = 5,904 − personas con visita de ese tipo (1,619 y 2,904).

## 25. Estándar contra origen: Dental caries (actividad 7)
- **Opciones:** A) Dental caries (dos códigos de origen → un concepto); B) Essential hypertension (mapeo 1:1, mismo número: sirve de control pero no muestra diferencia); C) un código con multi-mapeo (`S02.5XXA`, 98 filas: poco frecuente); D) una condición perdida por falta de mapeo (sobredosis: 0 filas en el CDM, nada que contar por estándar).
- **Elegida A:** es frecuente (puesto 3 del top 20) y muestra con cifras limpias por qué OMOP cuenta por concepto estándar.
- **Control contra la fuente:** `native.conditions` tiene 3,498 (`80967001`) y 1,223 (`K02.9`), igual que el CDM; la diferencia entre conteos es de agrupación, no de pérdida.
- **Ampliación 7d:** se añade el conteo con descendientes vía `concept_ancestor` (5,482 filas, 3,636 personas, 9 conceptos), para separar los dos niveles de agrupación: `Maps to` (lo aplica el ETL) y jerarquía (la aplica quien consulta).

## 26. Qué cuenta como "dentro" de `observation_period` (actividad 8)
- **Opciones:** A) estricto, `condition_start_date BETWEEN inicio AND fin`; B) tolerancia de 1 día antes del inicio; C) dar ambas cifras.
- **Elegida A:** es la regla de ATLAS y del Data Quality Dashboard y la que pide el enunciado. B añadiría una regla propia que ninguna herramienta OHDSI aplica y escondería el hallazgo. La tolerancia de 1 día se usa solo como **control de la causa** (8b): con ella entran las 101,699.
- **`LEFT JOIN` a `observation_period`:** un evento de una persona sin periodo debe contar como fuera, no desaparecer del total. Aquí no cambia nada (0 personas sin periodo), pero en una simulación quitando el periodo a 50 personas, el `JOIN` habría dado 0.60 % fuera (el total baja a 100,908) frente al 1.38 % real con `LEFT JOIN` (791 eventos sin periodo).
- **% fuera = (total − dentro) / total**, no `NOT BETWEEN`, que con un periodo NULL da NULL y no cuenta el evento como fuera.
- **Causa de los 614 fuera:** desfase de zona horaria de Synthea, verificado en los CSV (ver `reporte_calidad.md`, sección 7). No se corrige (decisión 18).

## 27. Qué tres conceptos explorar en ATHENA (actividad 9)
- **Opciones:** A) los más usados en las consultas: Dental caries (act. 7), Essential hypertension (control en act. 7, incidencia en act. 8) y Gingivitis (n.º 1 del top 20); B) el top 3 por frecuencia de la act. 6 (Gingivitis, Viral sinusitis, Dental caries).
- **Elegida A:** el enunciado dice "los que más usaste", y la hipertensión aparece en más análisis que la sinusitis.

## 28. Qué cuenta como "hijo" (actividad 9)
- **Opciones:** A) hijos directos estándar (`concept_ancestor` a distancia 1), con todos los descendientes en otra columna; B) solo descendientes.
- **Elegida A:** coincide con lo que ATHENA muestra en *Hierarchy* (solo estándar). La relación `Subsumes` da más (29 y 42 en caries y gingivitis) porque incluye hijos no estándar; ATHENA los lista en *Related concepts*. Los descendientes preparan la sesión 16 (*include descendants*, consulta 7d).
- **Comparación:** la parte SNOMED coincide exactamente con ATHENA (27, 8, 35); la diferencia (28, 8, 37) son hijos de OMOP Extension y SNOMED Veterinary, vocabularios que no se descargaron (0 conceptos en la base).

## 29. Causa de los 27 códigos de `conditions` sin destino (actividad 9, cierra pendiente de la act. 5)
- **Verificación en ATHENA (web; la API devuelve 403 a clientes automáticos):** `4208104` *Drug overdose* abre por URL directa, figura como **Deprecated** y relacionado con *Overdose* `607147`; los conceptos retirados no salen en la búsqueda. `D7140` y `D0120` no aparecen.
- **Desglose medido en la base (4,465 filas, la causa B de `conditions`):**
  - 4 SNOMED **retirados** (`D`), 1,771 filas: sobredosis (retirado 2021-07-31), dependencia de drogas (2024-10-01), concusión (2026-01-01), *History of single seizure*. Synthea v3.3.0 sigue generando códigos que SNOMED ya retiró.
  - 1 SNOMED **actualizado** (`U`), 271 filas: *Served in armed forces*.
  - 15 SNOMED válidos no estándar sin `Maps to`, 2,393 filas: casi todos antecedentes (*History of…*, *H/O:*), más *Refugee* y *Smokes tobacco daily*.
  - 7 ICD10CM válidos sin `Maps to`, 30 filas: metástasis.
- **Corrección a la act. 5:** dos de los retirados sí tienen un equivalente estándar vía `Concept poss_eq to` (*Overdose* `607147` y *Substance dependence* `37165431`): **1,230 filas recuperables** con un mapeo propio (`source_to_concept_map`). ETL-Synthea solo sigue `Maps to`. Se documenta, no se corrige (decisión 18).
- **CDT:** la base no tiene vocabulario CDT ni HCPCS y ATHENA no devuelve `D7140`/`D0120`: consistente con que sean códigos dentales CDT (licencia de la ADA), **no confirmado**.
- **No verificado:** los 3 códigos de `devices` sin destino (decisión 20) y el resto de los 15 válidos en ATHENA.

## 30. Periodos huérfanos de GiBleed: consultas idénticas con control (actividad 10)
- **Hallazgo:** `ref_gibleed.observation_period` tiene 5,343 filas, 2,649 de personas que no existen en `person` (2,694). Además, sus condiciones apuntan a 65,268 visitas, pero `visit_occurrence` solo tiene 1,037 (todas de hospitalización, de 890 personas). Parece un recorte de una población mayor que no se aplicó igual a todas las tablas (inferido del patrón, no verificado).
- **Opciones:** A) consultas idénticas a la act. 6, con un control que separa los periodos de personas existentes; B) borrar los huérfanos al cargar.
- **Elegida A:** respeta "las mismas consultas" y deja el defecto a la vista. Mezclar los huérfanos bajaría la mediana de GiBleed de 57.1 a ~19 años en esos periodos. Las visitas no tienen arreglo: su media por persona no es comparable.

## 31. Nombres de concepto desde `cdm.concept` en las tres bases (actividad 10)
- **Hallazgo:** el `concept` de MIMIC solo trae 3,885 conceptos locales (`mimiciv_*`): ninguna condición ni sexo encuentra nombre ahí. El de GiBleed sí cubre el 100 %.
- **Opciones:** A) nombres de nuestro `cdm.concept` (vocabulario 2026) en las tres; B) el `concept` de cada base.
- **Elegida A:** los `concept_id` estándar son universales en OMOP, así que el nombre es el mismo en cualquier base; resuelve el 100 % de sexos y condiciones. **Límite:** 4 tipos de visita de MIMIC (`38004207`, `8870`, `581385`, `8883`) no tienen nombre en ninguna de las dos tablas; nuestra descarga no incluye el vocabulario CMS Place of Service. Se dejan sin nombre.

## 32. Bases de referencia: GiBleed y MIMIC-IV demo (actividad 10)
- **Opciones:** A) solo GiBleed (Synthea: compara conversión con conversión); B) solo MIMIC-IV demo (100 pacientes reales de UCI); C) ambas; D) Broadsea (plataforma completa, varios GB; su CDM de demostración es Eunomia).
- **Elegida C:** GiBleed responde "¿nuestra conversión se parece a la de referencia de OHDSI?" y MIMIC "¿en qué difiere Synthea de datos clínicos reales?". Coste pequeño (dos ZIP, 17 MB) y ambas son CDM 5.3, cuyas columnas usadas en la act. 6 no cambian en la 5.4.
- **Carga:** `referencia/cargar_referencia.sh`, en esquemas `ref_gibleed` y `ref_mimic` sin tocar `cdm`; solo las 5 tablas que usa la act. 6, como texto y tipando las columnas que usan las consultas. Datos fuera de git. Conteos tras la carga = filas de los CSV.
