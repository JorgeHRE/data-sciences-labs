"""Convierte observations.csv (Synthea) a Parquet particionado por anio= en estilo Hive (Act. 6)."""

from __future__ import annotations

import shutil
from pathlib import Path

import pyarrow as pa
import pyarrow.compute as pc
import pyarrow.csv as pv
import pyarrow.dataset as ds

RAIZ_REPO = Path(__file__).resolve().parents[3]
CSV_ORIGEN = RAIZ_REPO / "s10-sql-fundamentals/tu-entrega/data/synthea/csv/observations.csv"
DESTINO_LOCAL = Path(__file__).resolve().parents[1] / "datos/curated/synthea/observations"

# VALUE mezcla mediciones numéricas y categorías textuales en Synthea (p. ej. tabaquismo);
# fijarlo explícitamente como string evita fallos de inferencia por bloques.
ESQUEMA_OBSERVATIONS = {
    "DATE": pa.timestamp("s", tz="UTC"),
    "PATIENT": pa.string(),
    "ENCOUNTER": pa.string(),
    "CATEGORY": pa.string(),
    "CODE": pa.string(),
    "DESCRIPTION": pa.string(),
    "VALUE": pa.string(),
    "UNITS": pa.string(),
    "TYPE": pa.string(),
}


def convertir(csv_origen: Path = CSV_ORIGEN, destino: Path = DESTINO_LOCAL) -> int:
    """Lee observations.csv con tipos explícitos, deriva anio (UTC) y escribe Parquet Hive."""
    if not csv_origen.is_file():
        raise FileNotFoundError(f"No se encontró el CSV origen: {csv_origen}")

    opciones_conv = pv.ConvertOptions(
        column_types=ESQUEMA_OBSERVATIONS,
        strings_can_be_null=True,
    )
    tabla = pv.read_csv(csv_origen, convert_options=opciones_conv)

    # DATE está en UTC; pc.year extrae el año calendario en UTC (int64 -> int32 para partición).
    anios = pc.cast(pc.year(tabla["DATE"]), pa.int32())
    tabla = tabla.append_column("anio", anios)

    if destino.exists():
        shutil.rmtree(destino)
    destino.mkdir(parents=True, exist_ok=True)

    particion = ds.partitioning(pa.schema([("anio", pa.int32())]), flavor="hive")
    ds.write_dataset(
        tabla,
        base_dir=destino,
        format="parquet",
        partitioning=particion,
        file_options=ds.ParquetFileFormat().make_write_options(compression="snappy"),
        existing_data_behavior="overwrite_or_ignore",
    )

    dataset_escrito = ds.dataset(destino, format="parquet", partitioning="hive")
    filas_parquet = dataset_escrito.count_rows()
    filas_csv = tabla.num_rows
    assert filas_parquet == filas_csv, f"Diferencia de filas: CSV={filas_csv} vs Parquet={filas_parquet}"
    print(f"CSV leídas: {filas_csv:,} | Parquet escritas: {filas_parquet:,}")
    return filas_parquet


if __name__ == "__main__":
    convertir()
