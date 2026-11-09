#!/usr/bin/env bash
# Carga dos CDM de referencia (OHDSI/EunomiaDatasets) en esquemas aparte del
# Postgres del lab, sin tocar `cdm`. Solo las tablas que usa la actividad 6.
#   ref_gibleed: GiBleed_5.3 (Synthea, ~2,700 personas)
#   ref_mimic:   MIMIC-IV demo 5.3 (100 pacientes reales de UCI, anonimizados)
# Uso (desde tu-entrega/, con el contenedor `db` encendido):
#   bash referencia/cargar_referencia.sh
# Los ZIP y los CSV extraídos quedan en referencia/ y están en .gitignore.
set -euo pipefail
cd "$(dirname "$0")"
URL=https://raw.githubusercontent.com/OHDSI/EunomiaDatasets/main/datasets
[ -f GiBleed_5.3.zip ] || curl -sL -o GiBleed_5.3.zip "$URL/GiBleed/GiBleed_5.3.zip"
[ -f MIMIC_5.3.zip ]   || curl -sL -o MIMIC_5.3.zip   "$URL/MIMIC/MIMIC_5.3.zip"
unzip -q -o GiBleed_5.3.zip -x '__MACOSX/*' -d gibleed
unzip -q -o MIMIC_5.3.zip -d mimic

PSQL="docker compose -f ../compose.yml exec -T db psql -U omop -d omop_lab12 -v ON_ERROR_STOP=1 -q"
TABLAS="person observation_period condition_occurrence visit_occurrence concept"

cargar () {   # $1 = esquema, $2 = carpeta con los CSV
  $PSQL -c "DROP SCHEMA IF EXISTS $1 CASCADE; CREATE SCHEMA $1;"
  for t in $TABLAS; do
    f=$(ls "$2" | grep -i "^$t.csv$")
    # Columnas desde la cabecera, en minúsculas y como texto: los dos CSV
    # difieren en mayúsculas y en tipos (MIMIC usa ids de 64 bits negativos).
    cols=$(head -1 "$2/$f" | tr -d '\r' | tr 'A-Z' 'a-z' | sed 's/,/ text, /g; s/$/ text/')
    $PSQL -c "CREATE TABLE $1.$t ($cols);"
    $PSQL -c "\copy $1.$t FROM STDIN WITH (FORMAT csv, HEADER true)" < "$2/$f"
  done
  # Tipar solo lo que usan las consultas, para que sean idénticas a las de cdm
  # (división entera de year_of_birth, resta de fechas, JOIN por ids).
  $PSQL <<SQL
ALTER TABLE $1.person ALTER person_id TYPE bigint USING person_id::bigint,
  ALTER gender_concept_id TYPE int USING gender_concept_id::int,
  ALTER year_of_birth TYPE int USING year_of_birth::int;
ALTER TABLE $1.observation_period ALTER person_id TYPE bigint USING person_id::bigint,
  ALTER observation_period_start_date TYPE date USING observation_period_start_date::date,
  ALTER observation_period_end_date TYPE date USING observation_period_end_date::date;
ALTER TABLE $1.condition_occurrence ALTER person_id TYPE bigint USING person_id::bigint,
  ALTER condition_concept_id TYPE int USING condition_concept_id::int,
  ALTER condition_start_date TYPE date USING condition_start_date::date;
ALTER TABLE $1.visit_occurrence ALTER person_id TYPE bigint USING person_id::bigint,
  ALTER visit_occurrence_id TYPE bigint USING visit_occurrence_id::bigint,
  ALTER visit_concept_id TYPE int USING visit_concept_id::int;
ALTER TABLE $1.concept ALTER concept_id TYPE int USING concept_id::int;
SQL
}
cargar ref_gibleed gibleed/GiBleed_5.3
cargar ref_mimic   mimic
echo "Carga terminada."
