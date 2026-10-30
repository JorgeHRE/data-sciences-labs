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
