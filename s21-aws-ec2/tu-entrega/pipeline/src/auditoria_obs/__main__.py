"""Punto de entrada: lee observations de S3, audita y escribe el resultado en S3.

Uso: python -m auditoria_obs [--bucket B] [--entrada PREFIJO] [--salida PREFIJO]
Credenciales: NINGUNA en el código. pyarrow usa la cadena estándar de AWS:
variables de entorno -> perfil (~/.aws, AWS_PROFILE) -> rol de la instancia (IMDS).
"""

import argparse
import time
from datetime import datetime, timezone

import pyarrow as pa
import pyarrow.dataset as ds
import pyarrow.parquet as pq
from pyarrow import fs

from auditoria_obs.nucleo import RANGOS, auditar

COLUMNAS = ["PATIENT", "DATE", "CODE", "VALUE", "UNITS", "anio"]  # 6 de 10: menos memoria


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--bucket", default="omop-tesis-jhr-2026")
    p.add_argument("--entrada", default="curated/synthea/observations")
    p.add_argument("--salida", default="results/auditoria_obs")
    p.add_argument("--region", default="us-east-2")  # misma región que el bucket: sin cargos entre regiones
    a = p.parse_args()

    t0 = time.perf_counter()
    s3 = fs.S3FileSystem(region=a.region)
    # Se lista el prefijo CON barra final y se pasa la lista de archivos a Arrow. Si se pasa el
    # directorio, pyarrow hace antes un HeadObject sobre la llave sin barra ("observations"), que
    # no envía s3:prefix y por eso el rol de privilegio mínimo recibe 403 (D12).
    base = f"{a.bucket}/{a.entrada.strip('/')}/"
    archivos = sorted(
        i.path for i in s3.get_file_info(fs.FileSelector(base, recursive=True))
        if i.type == fs.FileType.File and i.path.endswith(".parquet")
    )
    # partition_base_dir: sin él, con una lista de archivos Arrow no sabe leer anio=XXXX de la ruta.
    datos = ds.dataset(archivos, filesystem=s3, format="parquet", partitioning="hive", partition_base_dir=base)
    # El filtro se aplica en Arrow, antes de convertir a pandas: solo los 6 códigos llegan a memoria.
    tabla = datos.to_table(columns=COLUMNAS, filter=ds.field("CODE").isin(list(RANGOS)))
    obs = tabla.to_pandas()
    print(f"Leídas {len(obs):,} filas de s3://{a.bucket}/{a.entrada}/ ({len(datos.files)} archivos)")

    resultado = auditar(obs)

    # Un prefijo por ejecución: nunca se sobrescribe una corrida anterior (trazabilidad).
    sello = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    destino = f"{a.bucket}/{a.salida}/ejecucion={sello}/auditoria.parquet"
    pq.write_table(pa.Table.from_pandas(resultado, preserve_index=False), destino, filesystem=s3)

    print(f"Escrito s3://{destino} ({len(resultado)} filas x {resultado.shape[1]} columnas)")
    print(f"Implausibles totales: {resultado.implausibles.sum()} | duplicados: {resultado.duplicados.sum()}")
    print(f"Tiempo total: {time.perf_counter() - t0:.1f} s")


if __name__ == "__main__":
    main()
