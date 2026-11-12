"""Lab 15, actividad 4: conceptos y pacientes por versión de «exposición a metformina».

Ejecuta la consulta 4a de actividades.sql (la lee del archivo para no tener dos
copias que se desincronicen) y guarda figura_metformina.png junto a este script.
Solo lectura: no modifica la base.

Uso (desde la raíz del repo):
    s15-vocabularios-rxnorm-loinc/tu-entrega/.venv/bin/python \
        s15-vocabularios-rxnorm-loinc/tu-entrega/figura_metformina.py
"""
from pathlib import Path

import matplotlib
matplotlib.use("Agg")  # sin ventana: solo guarda el PNG
import matplotlib.pyplot as plt
import pandas as pd
from dotenv import dotenv_values
from sqlalchemy import create_engine, text

AQUI = Path(__file__).resolve().parent
ENV = dotenv_values(AQUI.parents[1] / "s12-omop-cdm-introduccion" / "tu-entrega" / ".env")

# La consulta 4a va desde su encabezado hasta el primer ';' que cierra una línea.
sql_todo = (AQUI / "actividades.sql").read_text(encoding="utf-8")
inicio = sql_todo.index("-- Actividad 4a.")
SQL = sql_todo[inicio:sql_todo.index(";\n", inicio)]

motor = create_engine(
    f"postgresql+psycopg2://{ENV['POSTGRES_USER']}:{ENV['POSTGRES_PASSWORD']}"
    f"@localhost:{ENV.get('POSTGRES_PORT', '5433')}/{ENV['POSTGRES_DB']}",
    connect_args={"options": "-c default_transaction_read_only=on"},  # garantía de solo lectura
)
with motor.connect() as con:
    datos = pd.read_sql(text(SQL), con).set_index("version")

# Control: si la base o la consulta cambian, el script se detiene en vez de
# dibujar cifras distintas a las del reporte.
esperado = {"conceptos": {"A": 83, "B": 400, "C": 249}, "pacientes": {"A": 231, "B": 231, "C": 231}}
assert datos.to_dict() == esperado, datos.to_dict()

etiquetas = {"A": "A — un solo ingrediente", "B": "B — con combinaciones", "C": "C — B sin iSGLT2"}
orden = ["C", "B", "A"]  # A arriba al leer de arriba abajo
AZUL, GRIS, TINTA, TINTA_2, FONDO = "#2a78d6", "#8a8a85", "#0b0b0b", "#52514e", "#fcfcfb"

fig, ejes = plt.subplots(1, 2, figsize=(9, 3.2), facecolor=FONDO, sharey=True)
paneles = [("conceptos", "Conceptos estándar en el concept set", AZUL),
           ("pacientes", "Pacientes distintos en drug_exposure", GRIS)]
for ax, (col, titulo, color) in zip(ejes, paneles):
    valores = [datos.loc[v, col] for v in orden]
    ax.set_facecolor(FONDO)
    ax.barh(range(3), valores, height=0.55, color=color)
    for i, n in enumerate(valores):  # etiqueta directa, sin eje que leer
        ax.text(n + max(valores) * 0.02, i, f"{n:,}", va="center", fontsize=9, color=TINTA)
    ax.set_xlim(0, max(valores) * 1.25)
    ax.set_title(titulo, loc="left", fontsize=9, color=TINTA_2)
    ax.set_xticks([])
    ax.tick_params(axis="y", length=0)
    for lado in ("top", "right", "bottom", "left"):
        ax.spines[lado].set_visible(False)
ejes[0].set_yticks(range(3), [etiquetas[v] for v in orden], fontsize=9, color=TINTA)

fig.suptitle("Metformina: la definición cambia casi 5 veces; los pacientes, nada",
             x=0.01, ha="left", fontsize=10.5, fontweight="bold", color=TINTA)
fig.text(0.01, 0.02, "Base Synthea (lab 12) · RxNorm 20260601. El único producto con metformina en la base es "
         "monocomponente,\nasí que A, B y C dan los mismos 231 pacientes: es una limitación de los datos, "
         "no del método.", fontsize=7.5, color=TINTA_2)
fig.tight_layout(rect=(0, 0.09, 1, 0.95))
salida = AQUI / "figura_metformina.png"
fig.savefig(salida, dpi=150, facecolor=FONDO)
print(f"guardada {salida.name}:", datos.to_dict())
