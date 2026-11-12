"""Lab 15, actividad 7: histograma de value_as_number separado por código y unidad.

Ejecuta la consulta 7b de actividades.sql (la lee del archivo, una sola copia)
y guarda figura_unidades.png junto a este script. Solo lectura.

Uso (desde la raíz del repo):
    s15-vocabularios-rxnorm-loinc/tu-entrega/.venv/bin/python \
        s15-vocabularios-rxnorm-loinc/tu-entrega/figura_unidades.py
"""
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from dotenv import dotenv_values
from sqlalchemy import create_engine, text

AQUI = Path(__file__).resolve().parent
ENV = dotenv_values(AQUI.parents[1] / "s12-omop-cdm-introduccion" / "tu-entrega" / ".env")
sql_todo = (AQUI / "actividades.sql").read_text(encoding="utf-8")
inicio = sql_todo.index("-- Actividad 7b.")
SQL = sql_todo[inicio:sql_todo.index(";\n", inicio)]

motor = create_engine(
    f"postgresql+psycopg2://{ENV['POSTGRES_USER']}:{ENV['POSTGRES_PASSWORD']}"
    f"@localhost:{ENV.get('POSTGRES_PORT', '5433')}/{ENV['POSTGRES_DB']}",
    connect_args={"options": "-c default_transaction_read_only=on"},
)
with motor.connect() as con:
    datos = pd.read_sql(text(SQL), con)

# Control contra las cifras de 7a: si algo cambia, se detiene en vez de dibujar otra cosa.
assert len(datos) == 296_149, len(datos)
assert datos["valor"].notna().all()

AZUL, TINTA, TINTA_2, FONDO, ROJO = "#2a78d6", "#0b0b0b", "#52514e", "#fcfcfb", "#e34948"
# Una fila por analito; un panel por (código, unidad). Bins pensados para cada escala:
# HbA1c y glucosa en lineal; creatinina en log porque la cola llega a ~130.
filas = [("HbA1c", np.arange(2, 11.2, 0.1), False),
         ("Glucosa", np.arange(60, 202, 2), False),
         ("Creatinina", np.logspace(np.log10(0.1), np.log10(200), 70), True)]

fig, ejes = plt.subplots(3, 2, figsize=(10, 8), facecolor=FONDO)
for (analito, bins, log), fila in zip(filas, ejes):
    grupos = list(datos[datos.analito == analito].groupby(["loinc", "system", "unidad"]))
    for ax, ((loinc, system, unidad), g) in zip(fila, grupos):
        ax.set_facecolor(FONDO)
        ax.hist(g["valor"], bins=bins, color=AZUL, edgecolor=FONDO, linewidth=0.3)
        if log:
            ax.set_xscale("log")
            ax.axvspan(40, 200, color=ROJO, alpha=0.08)   # zona ≥ 40 mg/dL a revisar
        ax.set_title(f"{analito} · {loinc} · {system} · {unidad}  (n = {len(g):,})",
                     loc="left", fontsize=8.5, color=TINTA)
        ax.set_xlabel(unidad, fontsize=8, color=TINTA_2)
        ax.tick_params(labelsize=7.5, colors=TINTA_2)
        for lado in ("top", "right"):
            ax.spines[lado].set_visible(False)
    for ax in fila[len(grupos):]:   # HbA1c tiene un solo código en uso
        ax.set_visible(False)

fig.suptitle("value_as_number por código y unidad: una sola unidad declarada en cada panel",
             x=0.01, ha="left", fontsize=10.5, fontweight="bold", color=TINTA)
fig.tight_layout(rect=(0, 0, 1, 0.96))
fig.savefig(AQUI / "figura_unidades.png", dpi=150, facecolor=FONDO)
print(datos.groupby(["analito", "loinc", "unidad"])["valor"].describe().round(2))
