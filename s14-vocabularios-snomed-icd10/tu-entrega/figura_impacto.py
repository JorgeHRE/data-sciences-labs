"""Lab 14, actividad 5c: pacientes distintos por versión del concept set de T2DM.

Lee la vista results.cs_t2dm (actividad 4) cruzada con cdm.condition_occurrence
y guarda figura_impacto.png junto a este script. Solo lectura: no modifica la base.

Uso (desde la raíz del repo):
    s14-vocabularios-snomed-icd10/tu-entrega/.venv/bin/python \
        s14-vocabularios-snomed-icd10/tu-entrega/figura_impacto.py
"""
from pathlib import Path

import matplotlib
matplotlib.use("Agg")  # sin ventana: solo guarda el PNG
import matplotlib.pyplot as plt
import pandas as pd
from dotenv import dotenv_values
from sqlalchemy import create_engine

AQUI = Path(__file__).resolve().parent
ENV = dotenv_values(AQUI.parents[1] / "s12-omop-cdm-introduccion" / "tu-entrega" / ".env")

# Misma consulta que la actividad 5a: pacientes DISTINTOS, no filas.
SQL = """
SELECT cs.version, count(DISTINCT co.person_id) AS pacientes
FROM results.cs_t2dm cs
JOIN cdm.condition_occurrence co ON co.condition_concept_id = cs.concept_id
GROUP BY cs.version
ORDER BY cs.version
"""

motor = create_engine(
    f"postgresql+psycopg2://{ENV['POSTGRES_USER']}:{ENV['POSTGRES_PASSWORD']}"
    f"@localhost:{ENV.get('POSTGRES_PORT', '5433')}/{ENV['POSTGRES_DB']}",
    connect_args={"options": "-c default_transaction_read_only=on"},  # garantía de solo lectura
)
datos = pd.read_sql(SQL, motor).set_index("version")["pacientes"]

# Control: deben coincidir con la actividad 5a. Si la base cambia, el script
# se detiene en vez de dibujar una figura con cifras distintas a las del reporte.
assert datos.to_dict() == {"A": 444, "B": 444, "C": 1085}, datos.to_dict()

etiquetas = {
    "A": "A — estricta\nsolo 201826",
    "B": "B — amplia\n201826 + descendientes",
    "C": "C — razonada (provisional)\n+ rama 443732, sin exclusiones",
}
ref = datos["A"]

# Paleta: una sola serie → un solo color, sin leyenda (el título dice qué es).
AZUL, TINTA, TINTA_2, FONDO = "#2a78d6", "#0b0b0b", "#52514e", "#fcfcfb"

fig, ax = plt.subplots(figsize=(8, 3.4), facecolor=FONDO)
ax.set_facecolor(FONDO)
orden = ["C", "B", "A"]  # A arriba al leer de arriba abajo
y = range(len(orden))
ax.barh(y, [datos[v] for v in orden], height=0.55, color=AZUL)
ax.set_yticks(list(y), [etiquetas[v] for v in orden], fontsize=9, color=TINTA)

# Etiqueta directa al final de cada barra: pacientes y % frente a A.
for i, v in enumerate(orden):
    n = datos[v]
    pct = (n - ref) / ref * 100
    texto = f"{n:,}".replace(",", ".") + ("" if v == "A" else f"  ({pct:+.1f} % vs A)".replace(".", ","))
    ax.text(n + 15, i, texto, va="center", fontsize=9, color=TINTA)

ax.set_xlim(0, datos.max() * 1.35)
ax.set_xlabel("Pacientes distintos en condition_occurrence", fontsize=9, color=TINTA_2)
ax.tick_params(axis="x", colors=TINTA_2, labelsize=8)
ax.tick_params(axis="y", length=0)
for lado in ("top", "right", "left"):
    ax.spines[lado].set_visible(False)
ax.spines["bottom"].set_color("#cfcfcb")
ax.grid(axis="x", color="#e6e6e3", linewidth=0.6)
ax.set_axisbelow(True)

fig.suptitle("Diabetes tipo 2: la rama de complicaciones, no los descendientes, cambia la cohorte",
             x=0.01, ha="left", fontsize=10.5, fontweight="bold", color=TINTA)
ax.set_title("Pacientes distintos por versión del concept set · base Synthea (lab 12) · vocabulario v5.0 29-AUG-26",
             loc="left", fontsize=8, color=TINTA_2)
fig.tight_layout()
salida = AQUI / "figura_impacto.png"
fig.savefig(salida, dpi=150, facecolor=FONDO)
print(f"guardada {salida.name}:", datos.to_dict())
