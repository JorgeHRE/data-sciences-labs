# ETL-Synthea -> OMOP CDM v5.4 sobre el Postgres del lab 12 (decisión 7).
# Configuración por variables de entorno (las pone compose.yml). Los vocabularios ya están
# cargados en `cdm` (actividad 3), así que este script NO llama a LoadVocabFromCsv.

cdmSchema     <- "cdm"
tmpSchema     <- "cdm_tmp"   # andamio: aquí CreateCDMTables crea las 39 tablas, luego se mueven
nativeSchema  <- "native"    # donde se cargan los CSV de Synthea tal cual
cdmVersion    <- "5.4"
syntheaVersion <- "3.3.0"    # debe coincidir con la versión que generó los CSV

# Tablas de vocabulario ya cargadas por cargar_vocab.sh: el ETL nunca debe tocarlas.
vocabTables <- c("concept", "vocabulary", "domain", "concept_class", "concept_relationship",
                 "relationship", "concept_synonym", "concept_ancestor", "drug_strength")

cd <- DatabaseConnector::createConnectionDetails(
  dbms         = "postgresql",
  server       = paste0(Sys.getenv("DB_HOST"), "/", Sys.getenv("POSTGRES_DB")),
  user         = Sys.getenv("POSTGRES_USER"),
  password     = Sys.getenv("POSTGRES_PASSWORD"),
  port         = 5432,   # puerto DENTRO de la red de compose (el 5433 es solo del host)
  pathToDriver = Sys.getenv("DATABASECONNECTOR_JAR_FOLDER")
)

# Cronometra cada paso: el ETL completo tarda decenas de minutos y conviene ver dónde.
step <- function(label, expr) {
  message(format(Sys.time(), "%H:%M:%S"), " START ", label)
  t0 <- Sys.time()
  force(expr)
  message(format(Sys.time(), "%H:%M:%S"), " DONE  ", label, " (",
          round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), " min)")
}

# CreateCDMTables intentaría crear TODAS las tablas (incluidas las 9 de vocabulario, que ya
# existen) y fallaría. Se corre en un esquema temporal y solo las clínicas se mueven a `cdm`.
create_clinical_tables <- function() {
  con <- DatabaseConnector::connect(cd)
  on.exit(DatabaseConnector::disconnect(con))
  run <- function(sql) DatabaseConnector::executeSql(con, sql, progressBar = FALSE, reportOverallTime = FALSE)

  run(paste0("DROP SCHEMA IF EXISTS ", tmpSchema, " CASCADE; CREATE SCHEMA ", tmpSchema, ";"))
  ETLSyntheaBuilder::CreateCDMTables(cd, tmpSchema, cdmVersion)

  tablas   <- DatabaseConnector::querySql(con, paste0(
    "SELECT tablename FROM pg_tables WHERE schemaname = '", tmpSchema, "'"))[[1]]
  clinicas <- setdiff(tolower(tablas), vocabTables)
  for (t in clinicas) {
    # DROP IF EXISTS hace el script repetible; solo toca nombres que NO son de vocabulario.
    run(paste0("DROP TABLE IF EXISTS ", cdmSchema, ".", t, " CASCADE; ",
               "ALTER TABLE ", tmpSchema, ".", t, " SET SCHEMA ", cdmSchema, ";"))
  }
  run(paste0("DROP SCHEMA ", tmpSchema, " CASCADE;"))
  message("Tablas clínicas movidas a ", cdmSchema, ": ", length(clinicas))
}

step("create clinical CDM tables", create_clinical_tables())

# --- Carga de los CSV de Synthea en `native` (staging) --------------------------------------
# Empezar de cero cada vez: si `native` conservara filas de una corrida anterior, el ETL
# las convertiría otra vez y `cdm` acabaría con duplicados.
reset_native <- function() {
  con <- DatabaseConnector::connect(cd)
  on.exit(DatabaseConnector::disconnect(con))
  DatabaseConnector::executeSql(con, paste0("DROP SCHEMA IF EXISTS ", nativeSchema,
    " CASCADE; CREATE SCHEMA ", nativeSchema, ";"), progressBar = FALSE, reportOverallTime = FALSE)
}

step("reset native schema", reset_native())
step("create Synthea tables", ETLSyntheaBuilder::CreateSyntheaTables(cd, nativeSchema, syntheaVersion))
# bulkLoad = TRUE usa `psql \copy` (por eso la imagen lleva postgresql-client): mucho más
# rápido que insertar fila a fila por JDBC.
step("load Synthea CSVs", ETLSyntheaBuilder::LoadSyntheaTables(
  cd, nativeSchema, Sys.getenv("SYNTHEA_CSV_DIR"), bulkLoad = TRUE))

# --- Reparación de ceros iniciales perdidos por LoadSyntheaTables ---------------------------
# LoadSyntheaTables lee los CSV con data.table::fread, que adivina tipos: una columna solo con
# números pasa a entero y '08' queda como '8'. Afecta a immunizations.code (CVX usa '03', '08')
# y a los códigos postales. Se repara aquí, justo tras la carga, con lpad. Los códigos CVX
# tienen 2 o 3 dígitos, así que rellenar los de 1 dígito a 2 es seguro. Los zip son de 5
# dígitos o ZIP+4 de 9 (organizations y providers): 1-4 dígitos -> 5; 6-8 dígitos -> 9.
# Se imprime el conteo de filas afectadas antes y después.
zip_corto <- "zip ~ '^[0-9]{1,4}$'"
zip_largo <- "zip ~ '^[0-9]{6,8}$'"
repair_leading_zeros <- function() {
  con <- DatabaseConnector::connect(cd)
  on.exit(DatabaseConnector::disconnect(con))
  tablas_zip <- c("patients", "providers", "organizations")
  malas <- function() {
    cols <- vapply(tablas_zip, function(t) paste0(
      "(SELECT count(*) FROM native.", t, " WHERE ", zip_corto, " OR ", zip_largo, ") AS zip_", t),
      character(1))
    DatabaseConnector::querySql(con, paste0(
      "SELECT (SELECT count(*) FROM native.immunizations WHERE length(code) = 1) AS cvx_1_digito, ",
      paste(cols, collapse = ", ")))
  }
  message("Antes:");   print(malas())
  DatabaseConnector::executeSql(con, paste0(
    "UPDATE native.immunizations SET code = lpad(code, 2, '0') WHERE length(code) = 1; ",
    paste0("UPDATE native.", tablas_zip, " SET zip = CASE WHEN ", zip_corto,
           " THEN lpad(zip, 5, '0') ELSE lpad(zip, 9, '0') END WHERE ", zip_corto, " OR ", zip_largo,
           ";", collapse = " ")), progressBar = FALSE, reportOverallTime = FALSE)
  message("Después:"); print(malas())
}
step("repair leading zeros", repair_leading_zeros())

# --- Tablas de mapeo y roll-up --------------------------------------------------------------
# Pre-calculan 'código de origen -> concepto estándar' (JOIN concept + concept_relationship
# 'Maps to') y las jerarquías de visitas, para que LoadEventTables no repita ese JOIN por fila.
step("create map and rollup tables", ETLSyntheaBuilder::CreateMapAndRollupTables(
  cd, cdmSchema, nativeSchema, cdmVersion, syntheaVersion))
# Índices opcionales de ETL-Synthea sobre las tablas de mapeo, person, provider y native.
# No tocan vocabularios. Ojo: la función atrapa los errores y solo los imprime
# ("Error in SQL"), así que hay que buscarlos en el log.
step("create extra indices", ETLSyntheaBuilder::CreateExtraIndices(
  cd, cdmSchema, nativeSchema, syntheaVersion))

# --- Conversión: native -> tablas de eventos del CDM -----------------------------------------
# El paso pesado (~35 min): person, visit_occurrence, condition_occurrence, etc.
# Lee los mapeos precalculados de arriba. Ojo: lo que no encuentra en el vocabulario se
# descarta o queda en concept_id = 0, sin error; por eso se verifica por tabla después.
#
# LoadEventTables ejecuta `insert_cost_v300.sql` como último paso, y con estos datos (claims_transactions
# ~5.6 M de filas, JOINs sin índices, work_mem de 4 MB) no terminó en más de 70 min (decisión 9).
# El lab no usa `cost`, así que se omite: LoadEventTables(sqlOnly = TRUE) escribe el SQL oficial
# de cada paso y aquí se ejecutan todos, en el orden del paquete, MENOS el de cost.
pasos_eventos <- c(
  "insert_location.sql", "insert_care_site.sql", "insert_person.sql",
  "insert_observation_period.sql", "insert_provider.sql", "insert_visit_occurrence.sql",
  "insert_visit_detail.sql", "insert_condition_occurrence.sql", "insert_observation.sql",
  "insert_measurement.sql", "insert_procedure_occurrence.sql", "insert_drug_exposure.sql",
  "insert_condition_era.sql", "insert_drug_era.sql", "insert_cdm_source.sql",
  "insert_device_exposure.sql", "insert_death.sql", "insert_payer_plan_period.sql")
paso_omitido <- "insert_cost_v300.sql"

load_event_tables_sin_cost <- function() {
  # /etl es de solo lectura y sqlOnly escribe en ./output: se trabaja en un directorio temporal.
  trabajo <- file.path(tempdir(), "sql_eventos")
  dir.create(trabajo, showWarnings = FALSE)
  anterior <- setwd(trabajo)
  on.exit(setwd(anterior), add = TRUE)
  ETLSyntheaBuilder::LoadEventTables(cd, cdmSchema, nativeSchema, cdmVersion, syntheaVersion,
                                     sqlOnly = TRUE)
  # Si otra versión del paquete añade, quita o renombra un paso, falla aquí en vez de omitir algo.
  stopifnot(setequal(list.files("output"), c(pasos_eventos, paso_omitido)))
  con <- DatabaseConnector::connect(cd)
  on.exit(DatabaseConnector::disconnect(con), add = TRUE)
  for (f in pasos_eventos) {
    message(format(Sys.time(), "%H:%M:%S"), " Running: ", f)
    DatabaseConnector::executeSql(con, SqlRender::readSql(file.path("output", f)),
                                  progressBar = FALSE, reportOverallTime = FALSE)
  }
  message("Omitido a propósito (decisión 9): ", paso_omitido, " -> cdm.cost queda vacía")
}
step("load event tables (sin cost)", load_event_tables_sin_cost())
