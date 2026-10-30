#!/usr/bin/env bash
# Carga los CSV de ATHENA a las tablas cdm.* del Postgres del lab.
# Uso: ./cargar_vocab.sh TABLA [TABLA...]      (p. ej. ./cargar_vocab.sh vocabulary domain)
# Los CSV van separados por tabulador. QUOTE E'\b' desactiva las comillas (un carácter que
# no aparece en los datos): los nombres de conceptos traen comillas sueltas que romperían la carga.
# En modo CSV un campo vacío sin comillas entra como NULL, que es lo que queremos.
set -euo pipefail
cd "$(dirname "$0")"
DIR=vocab/completo

for t in "$@"; do
  f="$DIR/${t^^}.csv"
  esperadas=$(( $(wc -l < "$f") - 1 ))   # menos la fila de encabezado
  docker compose exec -T db psql -U omop -d omop_lab12 -v ON_ERROR_STOP=1 -q \
    -c "COPY cdm.$t FROM STDIN WITH (FORMAT csv, DELIMITER E'\t', HEADER true, QUOTE E'\b')" < "$f"
  cargadas=$(docker compose exec -T db psql -U omop -d omop_lab12 -tAc "SELECT count(*) FROM cdm.$t")
  echo "$t: archivo=$esperadas  tabla=$cargadas  $([ "$esperadas" = "$cargadas" ] && echo OK || echo DIFERENTE)"
done
