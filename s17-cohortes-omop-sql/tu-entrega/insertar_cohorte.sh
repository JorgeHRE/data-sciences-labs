#!/usr/bin/env bash
# Actividad 7: arma la sentencia (plantilla + cadena de CTE) y la corre en el
# Postgres del lab 12. ON_ERROR_STOP=1: ante un error se detiene y, como todo
# va dentro de BEGIN/COMMIT, no queda nada a medias.
set -euo pipefail
cd "$(dirname "$0")"

# La cadena de CTE de la cohorte: desde [INICIO cohorte] hasta [CONTEO].
cadena=$(mktemp)
trap 'rm -f "$cadena"' EXIT
sed -n '/^-- \[INICIO cohorte\]/,/^-- \[CONTEO\]/p' cohorte_definicion.sql > "$cadena"

# Sustituye la línea de la plantilla por la cadena (r = pega el archivo; d =
# borra la línea marcador).
sed -e "/^-- {{CADENA}}/{r $cadena" -e 'd}' insertar_cohorte.sql \
  | docker exec -i lab12-omop-db-1 psql -U omop -d omop_lab12 -v ON_ERROR_STOP=1
