"""Lab 18: lee la tabla de atrición de results.cohort / cdm con las banderas de
atricion.sql y un archivo de orden (orden_*.sql). Solo lectura.

La consulta se arma igual que en la línea de comandos: bloque de banderas
(entre los marcadores de atricion.sql) + archivo de orden + consulta_atricion.sql.
"""
import re
from pathlib import Path

import pandas as pd
from dotenv import dotenv_values
from sqlalchemy import create_engine

AQUI = Path(__file__).resolve().parent
ENV = dotenv_values(AQUI.parents[1] / "s12-omop-cdm-introduccion" / "tu-entrega" / ".env")
NOMBRE = {1701: "Lisinopril (1701)", 1702: "Amlodipino (1702)"}


def motor():
    # default_transaction_read_only=on: garantía de que este script no escribe.
    return create_engine(
        f"postgresql+psycopg2://{ENV['POSTGRES_USER']}:{ENV['POSTGRES_PASSWORD']}"
        f"@localhost:{ENV.get('POSTGRES_PORT', '5433')}/{ENV['POSTGRES_DB']}",
        connect_args={"options": "-c default_transaction_read_only=on"},
    )


def _sin_comentarios(texto):
    # psycopg2 lee «%» como parámetro y los comentarios no hacen falta para ejecutar.
    return re.sub(r"--[^\n]*", "", texto)


def bloque_banderas():
    """El WITH de banderas, entre los marcadores de línea completa de atricion.sql."""
    sql = (AQUI / "atricion.sql").read_text(encoding="utf-8")
    m = re.search(r"^-- \[INICIO banderas\].*?^-- \[FIN banderas\]", sql, re.S | re.M)
    return m.group(0)


def leer_atricion(archivo_orden, con=None):
    """DataFrame: cohorte, paso, criterio, n, perdidos, pct_inicial, pct_perdida."""
    partes = [bloque_banderas(),
              (AQUI / archivo_orden).read_text(encoding="utf-8"),
              (AQUI / "consulta_atricion.sql").read_text(encoding="utf-8")]
    return pd.read_sql(_sin_comentarios("\n".join(partes)), con or motor())


def a_markdown(df):
    """Tabla en Markdown (una por cohorte) con la pérdida respecto al paso anterior."""
    salida = []
    for coh, g in df.groupby("cohorte"):
        salida += [f"**{NOMBRE[coh]}**", "",
                   "| paso | criterio | N | % del inicial | pérdida respecto al paso anterior |",
                   "|---:|---|---:|---:|---:|"]
        for r in g.itertuples():
            perd = "—" if pd.isna(r.perdidos) else f"−{int(r.perdidos):,} ({r.pct_perdida:.1f} %)"
            salida.append(f"| {r.paso} | {r.criterio} | {r.n:,} | {r.pct_inicial:.1f} % | {perd} |")
        salida.append("")
    return "\n".join(salida)
