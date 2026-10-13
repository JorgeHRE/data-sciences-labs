"""Intenta UNA conexión a Postgres, sin reintentos, y dice si funcionó.

Se usa para probar el healthcheck (actividad 5): se ejecuta justo después de
"docker compose up -d" y, si la base aún no está lista, falla con
"connection refused". Lee los datos de conexión de las variables PG* que
Compose pasa al contenedor, igual que haría un notebook.

Uso (desde tu máquina):
    docker compose exec jupyter python /home/jovyan/work/conectar.py
"""
import sys

import psycopg

try:
    # connect_timeout: no esperar más de 2 s; el objetivo es ver el fallo, no esconderlo.
    # psycopg lee PGHOST, PGPORT, PGUSER, PGPASSWORD y PGDATABASE del entorno.
    with psycopg.connect(connect_timeout=2) as conexion:
        n = conexion.execute("select count(*) from cdm.person").fetchone()[0]
    print(f"OK: conectó a la primera ({n} filas en cdm.person)")
except Exception as error:
    # Primera línea del error, sin credenciales (psycopg no las incluye).
    print(f"FALLÓ: {str(error).splitlines()[0]}")
    sys.exit(1)
