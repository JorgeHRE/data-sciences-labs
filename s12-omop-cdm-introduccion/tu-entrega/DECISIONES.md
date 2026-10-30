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
