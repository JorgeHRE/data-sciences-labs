"""Ejecuta sql/carga.sql contra clinica.duckdb (se puede correr varias veces)."""
from pathlib import Path

import duckdb

RAIZ = Path(__file__).parent
con = duckdb.connect(str(RAIZ / "clinica.duckdb"))
for sentencia in (RAIZ / "sql" / "carga.sql").read_text().split(";\n"):
    if sentencia.strip():
        resultado = con.execute(sentencia)
conteos = resultado.fetchall()  # la última sentencia es el conteo por tabla
for tabla, filas in conteos:
    print(f"{tabla:<13}{filas:>10,}")
