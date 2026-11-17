# Registro de decisiones — Lab 20 (Data lake clínico en S3)

Formato: qué se decidió, qué alternativas había y por qué se eligió esta.
El estado de cada decisión vive en `../SPECS.md` §2; aquí va el porqué.

## D1. Qué datos subir a `raw/`
- **Decisión:** usar Synthea (100 % sintético) como el dato privado a proteger y subir solo las 15 tablas clínicas (1.41 GiB), excluyendo `claims`, `claims_transactions` e `imaging_studies`.
- **Alternativas:** las 18 tablas (4.28 GiB); solo 5 tablas núcleo (1.21 GiB); archivos inventados (sin CSV grande para las actividades 6-8).
- **Por qué:** el proyecto final es clínico. Por **minimización de datos** (GDPR art. 5.1.c, *minimum necessary* de HIPAA), lo que no se sube no se puede filtrar ni hay que custodiar. El costo casi no cambia (centavos), así que no fue el criterio. La ingesta parcial queda documentada, y `fecha_carga=` permite agregar `claims` después sin reescribir `raw/`. Matiz: `patients` (PII simulada) sí entra; la minimización por columnas se hace en `staging/`/`curated/`.

## D2. Cómo crear el bucket `omop-tesis-jhr-2026`
- **Decisión:** crearlo por AWS CLI con 5 comandos seguidos (`create-bucket`, `put-public-access-block`, `put-bucket-versioning`, `put-bucket-encryption`, `put-bucket-tagging`), documentados para repetirlos, y una captura de consola como evidencia visual.
- **Alternativas:** consola web (visual, pero no repetible igual y fácil de olvidar un interruptor); script boto3 (reproducible, pero más código para algo que se hace una vez).
- **Por qué:** el procedimiento queda escrito y es auditable (la idea detrás de IaC y de GAMP 5 para sistemas validados); versionado y cifrado quedan activos antes de subir el primer objeto; no depende de una consola que en el lab 19 fue lenta y cambiante. El cifrado se fija explícito para no depender de un valor por defecto.

## D3. Tabla a convertir y particionado
- **Decisión:** convertir `observations` (974 MB, 5.7 M filas) a Parquet particionado solo por `anio=` (Hive, derivado de `DATE` en UTC).
- **Alternativas:** `claims_transactions` (el CSV más grande del disco, pero excluido de `raw/` en D1 y no clínico); particionar por `anio=/mes=` (~140 archivos de ~1 MB), por `anio=/categoria=` (ata el diseño a una pregunta) o por sitio (~1 000 archivos diminutos y requiere JOIN con `encounters`).
- **Por qué:** el proyecto clínico filtra sobre todo por fecha (periodos de inclusión, *washout* y seguimiento de cohortes); unas 12 particiones de ~10 MB evitan el *small files problem*. Para filtrar por categoría o código LOINC bastan las estadísticas min/max de Parquet (*predicate pushdown*), sin partición extra.

## D4. Contrato de errores de `s3util`
- **Decisión:** excepciones propias (`S3UtilError` → `LlaveNoExiste`, `BucketNoExiste`, `AccesoDenegado`, `PerfilInvalido`), encadenadas con `raise ... from e`; `existe()` devuelve `False` solo ante 404 y lanza `AccesoDenegado` ante 403.
- **Alternativas:** imprimir y devolver `None`/`False`; dejar pasar `ClientError` sin traducir.
- **Por qué:** un `None` silencioso en un pipeline clínico puede producir una cohorte vacía sin que nadie lo note; las excepciones tipadas dejan decidir al llamador y se pueden probar. Un 403 no prueba que la llave no exista (S3 oculta la existencia si falta `s3:ListBucket`), así que devolver `False` sería un error silencioso.

## D5. Sesión y cliente de boto3
- **Decisión:** cada función recibe `perfil` (nombre, nunca llaves) y obtiene el cliente de un helper `_cliente(perfil)` cacheado con `lru_cache`; `perfil=None` usa la *credential chain*.
- **Alternativas:** crear una `Session` en cada llamada (lento en la demo de > 1 000 objetos); una clase `ClienteS3` (más estructura de la necesaria).
- **Por qué:** cumple el requisito del enunciado, evita recrear sesiones en bucles y permite que el mismo código corra después con un rol de AWS sin perfil. Costo: limpiar la caché en las pruebas.

## D6. Estrategia de pruebas
- **Decisión:** pruebas unitarias con moto (S3 simulado, incluida la paginación con 1 500 objetos), Stubber solo para `AccessDenied`, y 4-5 pruebas de integración contra el bucket real marcadas `integracion` y excluidas por defecto.
- **Alternativas:** solo moto (no prueba AWS real); solo Stubber (frágil); solo bucket real (cuesta, necesita credenciales y puede tocar datos reales).
- **Por qué:** es el patrón de la industria: las unitarias son gratis, offline y reproducibles por cualquiera (incluido el auditor); la integración confirma lo que moto no puede. Costo económico casi nulo (~0.0001 USD por corrida) porque la subida masiva queda fuera de la integración y `tmp/` se expira por ciclo de vida.

## D7. Objetos de prueba de paginación
- **Decisión:** subirlos a `tmp/paginacion/`, borrarlos con `delete_objects` sin `VersionId` y dejar que la regla de ciclo de vida de `tmp/` elimine versiones y *delete markers*.
- **Alternativas:** `aws s3 rm` sin regla (con versionado quedan ~3 000 entradas vivas); borrar cada versión por `VersionId` (inmediato pero irreversible).
- **Por qué:** limpia de verdad sin escribir código de borrado permanente; un prefijo mal escrito en ese código podría destruir `raw/` sin vuelta atrás. El costo es esperar ~1 día.

## D8. Reglas de ciclo de vida
- **Decisión:** R1 abortar multipart incompletos a 7 días (todo el bucket); R2 expirar todo lo de `tmp/` a 1 día; R3 expirar versiones no actuales a 30 días solo en `staging/` y `curated/`. R4 (`raw/` → Standard-IA) solo documentada.
- **Alternativas:** R3 en todo el bucket; aplicar R4 como sugiere el enunciado.
- **Por qué:** `raw/` es inmutable y una versión no actual ahí sería el dato original sobrescrito por error: expirarla rompería esa promesa (retención de datos fuente). R4 casi no ahorra porque `raw/` se leerá en las sesiones 21-25, y Standard-IA cobra mínimos de 30 días y 128 KB más cada lectura.

## D9. Bono: política de bucket solo-HTTPS
- **Decisión:** aplicar al final una política de bucket con `Deny` para `s3:*` cuando `aws:SecureTransport` es `false`, sobre el ARN del bucket y el de sus objetos.
- **Alternativas:** no hacer el bono.
- **Por qué:** el cifrado en tránsito es un control habitual en datos de salud y complementa el cifrado en reposo; no cuesta nada. Es un *Explicit Deny*: gana a cualquier Allow, y el comodín no viola privilegio mínimo porque quita permisos. Si bloqueara al usuario, se revierte con `delete-bucket-policy`.
