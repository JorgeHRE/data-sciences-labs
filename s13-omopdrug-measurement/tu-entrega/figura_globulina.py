"""Actividad 7b. Antes y después de normalizar la globulina a g/L.

Lee results.globulina_normalizada (trozo 7a de farmacoepi.sql) y guarda
figura_globulina.png con dos paneles:
  - Antes: valor original coloreado por la etiqueta de unidad. Si las
    etiquetas fueran correctas, g/L y g/dL estarían separados ×10; aquí se
    solapan en 2-4 → la etiqueta g/L está mal.
  - Después: valor en g/L tras la regla por rango, con el rango normal
    22-42 g/L (suma de fracciones, MedlinePlus «Protein electrophoresis - serum»).
Eje Y logarítmico: 20,412 frente a 16 filas no se verían en escala lineal.
Uso: .venv/bin/python figura_globulina.py
"""
import os
from pathlib import Path

import matplotlib
matplotlib.use("Agg")  # sin ventana: solo se guarda el PNG (sesión por SSH)
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine

AQUI = Path(__file__).resolve().parent
load_dotenv(AQUI.parents[1] / "s12-omop-cdm-introduccion/tu-entrega/.env")
url = (f"postgresql+psycopg2://{os.environ['POSTGRES_USER']}:{os.environ['POSTGRES_PASSWORD']}"
       f"@localhost:{os.environ['POSTGRES_PORT']}/{os.environ['POSTGRES_DB']}")
df = pd.read_sql("SELECT valor_original, unidad_original_texto, valor_g_l "
                 "FROM results.globulina_normalizada", create_engine(url))
print(f"filas leídas: {len(df):,}")  # esperado 20,428 (igual que 7a)

# Bins centrados en la resolución real de los datos (para no inventar forma):
# valor original con 1 decimal → ancho 0.1; en g/L son enteros → ancho 1.
BINS_ANTES = np.arange(-0.05, 45.05, 0.1)
BINS_DESPUES = np.arange(-0.5, 45.5, 1)
RANGO_NORMAL = (22, 42)  # g/L

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(11, 4.2), sharey=True)
ax1.axvspan(*RANGO_NORMAL, color="0.85", label="donde estarían si fueran g/L")
for unidad, color in [("g/L", "tab:red"), ("g/dL", "tab:blue")]:
    sub = df.loc[df.unidad_original_texto == unidad, "valor_original"]
    ax1.hist(sub, bins=BINS_ANTES, alpha=0.7, color=color,
             label=f"etiqueta {unidad} (n={len(sub):,})")
ax1.set(title="Antes: valor original según etiqueta", xlabel="valor original",
        ylabel="mediciones (escala log)", yscale="log")
ax1.legend()

ax2.axvspan(*RANGO_NORMAL, color="0.85", label="rango normal 22-42 g/L")
ax2.hist(df.valor_g_l, bins=BINS_DESPUES, color="tab:green",
         label=f"normalizado (n={len(df):,})")
ax2.set(title="Después: g/L (unidad decidida por rango)", xlabel="globulina (g/L)",
        yscale="log")
ax2.legend(loc="upper left")

fig.suptitle("Globulina sérica (3027970): normalización a g/L")
fig.tight_layout()
fig.savefig(AQUI / "figura_globulina.png", dpi=150)
print("guardado figura_globulina.png")
