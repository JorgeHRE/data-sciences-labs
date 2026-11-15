"""Lab 17, actividad 9: tabla 1 (caracterización) y histograma del seguimiento
de las cohortes finales 1701 (lisinopril) y 1702 (amlodipino).

Lee results.cohort (actividad 7) con las dos consultas de caracterizacion.sql
y calcula con ellas la tabla 1 (con diferencia estándar, SMD) y la figura.
Solo lectura: no modifica la base. Escribe tabla1.md y figura_seguimiento.png.

Uso (desde la raíz del repo):
    s17-cohortes-omop-sql/tu-entrega/.venv/bin/python \
        s17-cohortes-omop-sql/tu-entrega/tabla1.py
"""
import re
from pathlib import Path

import matplotlib
matplotlib.use("Agg")  # sin ventana: solo guarda el PNG
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from dotenv import dotenv_values
from sqlalchemy import create_engine

AQUI = Path(__file__).resolve().parent
ENV = dotenv_values(AQUI.parents[1] / "s12-omop-cdm-introduccion" / "tu-entrega" / ".env")
NOMBRE = {1701: "Lisinopril", 1702: "Amlodipino"}
COLOR = {1701: "#2a78d6", 1702: "#eb6834"}  # slots 1-2 de la paleta

# --- consultas: se parte el archivo SQL por el marcador [B]; se quitan los
# comentarios «--» antes de enviar (psycopg2 lee «%» como parámetro).
sql = (AQUI / "caracterizacion.sql").read_text(encoding="utf-8")
# Los marcadores se buscan como LÍNEA COMPLETA («^-- [A]…$»): cortar solo en el
# texto «-- [A]» dejaría el resto de esa línea de comentario como SQL.
_, parte_a, parte_b = re.split(r"^-- \[[AB]\].*$", sql, flags=re.MULTILINE)
limpia = lambda t: re.sub(r"--[^\n]*", "", t)

motor = create_engine(
    f"postgresql+psycopg2://{ENV['POSTGRES_USER']}:{ENV['POSTGRES_PASSWORD']}"
    f"@localhost:{ENV.get('POSTGRES_PORT', '5433')}/{ENV['POSTGRES_DB']}",
    connect_args={"options": "-c default_transaction_read_only=on"},  # garantía de solo lectura
)
a = pd.read_sql(limpia(parte_a), motor)   # una fila por persona
b = pd.read_sql(limpia(parte_b), motor)   # una fila por persona y diagnóstico

# --- controles: si cambian las cifras de las actividades 6-7, se detiene.
n = a.groupby("cohorte")["persona"].nunique().to_dict()
assert n == {1701: 122, 1702: 81}, n
assert len(a) == 203 and a["persona"].is_unique          # una fila por persona
assert (a["edad"] >= 18).all()                           # criterio 5a
med_seg = a.groupby("cohorte")["seguimiento_dias"].median().to_dict()
assert med_seg == {1701: 927.5, 1702: 401.0}, med_seg    # = distribucion_salida.sql
assert not b.duplicated().any()                          # DISTINCT funcionó: sin registros repetidos
assert set(b["persona"]) <= set(a["persona"])
dif_edad = int((a["edad"] != a["edad_por_anio"]).sum())
print(f"edad exacta distinta de la aproximada por año en {dif_edad} de {len(a)} personas")

# --- funciones de la tabla: n (%), mediana [Q1–Q3], media (DE) y SMD ---------
def smd_bin(p1, p2):
    d = np.sqrt((p1 * (1 - p1) + p2 * (1 - p2)) / 2)
    return (p1 - p2) / d if d > 0 else 0.0

def smd_cont(x1, x2):
    d = np.sqrt((x1.var(ddof=1) + x2.var(ddof=1)) / 2)
    return (x1.mean() - x2.mean()) / d

def fila_bin(etiqueta, m1, m2):
    """m1, m2: serie booleana por persona en cada cohorte."""
    p1, p2 = m1.mean(), m2.mean()
    return [etiqueta, f"{int(m1.sum())} ({100*p1:.1f} %)", f"{int(m2.sum())} ({100*p2:.1f} %)", smd_bin(p1, p2)]

def q(x, f=1):
    return f"{x.median():.{f}f} [{x.quantile(.25):.{f}f}–{x.quantile(.75):.{f}f}]"

L, A = a[a.cohorte == 1701], a[a.cohorte == 1702]
filas = [["N", str(len(L)), str(len(A)), None]]
# El SMD de una variable continua compara MEDIAS (usa la media y la DE), por eso
# va en la fila de la media y no en la de la mediana.
filas.append(["Edad en la fecha índice, años: mediana [Q1–Q3]", q(L.edad, 0), q(A.edad, 0), None])
filas.append(["Edad en la fecha índice, años: media (DE)", f"{L.edad.mean():.1f} ({L.edad.std():.1f})",
              f"{A.edad.mean():.1f} ({A.edad.std():.1f})", smd_cont(L.edad, A.edad)])
for et, f in [("Edad 18–44", lambda s: s < 45), ("Edad 45–64", lambda s: (s >= 45) & (s < 65)), ("Edad ≥ 65", lambda s: s >= 65)]:
    filas.append(fila_bin(et, f(L.edad), f(A.edad)))
filas.append(fila_bin("Mujer", L.sexo.eq("FEMALE"), A.sexo.eq("FEMALE")))
filas.append(fila_bin("Hombre", L.sexo.eq("MALE"), A.sexo.eq("MALE")))
assert set(a.sexo) == {"FEMALE", "MALE"}, set(a.sexo)
sl, sa = L.seguimiento_dias / 365.25, A.seguimiento_dias / 365.25
filas.append(["Seguimiento, años: mediana [Q1–Q3]", q(sl, 1), q(sa, 1), None])
filas.append(["Seguimiento, años: media (DE)", f"{sl.mean():.1f} ({sl.std():.1f})", f"{sa.mean():.1f} ({sa.std():.1f})", smd_cont(sl, sa)])
filas.append(["Seguimiento total, años-persona", f"{sl.sum():.0f}", f"{sa.sum():.0f}", None])

# Diez diagnósticos más frecuentes (personas, las dos cohortes juntas) y su
# frecuencia en cada cohorte. Se cuentan PERSONAS distintas por diagnóstico.
top = (b.groupby(["concepto", "nombre"])["persona"].nunique().sort_values(ascending=False).head(10))
filas.append(["**Comorbilidades en [−365, 0]** (diez diagnósticos más frecuentes, clase Disorder)", "", "", None])
for (concepto, nombre), _ in top.items():
    tiene = set(b.loc[b.concepto == concepto, "persona"])
    filas.append(fila_bin(nombre, L.persona.isin(tiene), A.persona.isin(tiene)))

# --- tabla 1 en markdown -----------------------------------------------------
def fmt_smd(v):
    if v is None:
        return ""
    r = round(v, 2) + 0.0          # +0.0 evita el «-0.00»
    return f"{r:+.2f}{' *' if abs(v) > 0.1 else ''}"
md = ["| | Lisinopril (1701) | Amlodipino (1702) | SMD |", "|---|---:|---:|---:|"]
md += [f"| {f[0]} | {f[1]} | {f[2]} | {fmt_smd(f[3])} |" for f in filas]
(AQUI / "tabla1.md").write_text("\n".join(md) + "\n", encoding="utf-8")
print("\n".join(md))
smds = [f[3] for f in filas if f[3] is not None]
print(f"\nfilas con |SMD| > 0.1: {sum(abs(s) > 0.1 for s in smds)} de {len(smds)}")

# --- figura: histograma del seguimiento, un panel por cohorte -----------------
anios_bins = np.arange(0, 10.5, 0.5)
fig, ejes = plt.subplots(2, 1, figsize=(10, 6.5), sharex=True, sharey=True)
for eje, cid, s in zip(ejes, [1701, 1702], [sl, sa]):
    eje.hist(s, bins=anios_bins, color=COLOR[cid])
    med = s.median()
    eje.axvline(med, color="#1f1f1e", linestyle="--", linewidth=1)
    eje.annotate(f"mediana {med:.1f} años", xy=(med, eje.get_ylim()[1]), xytext=(6, -14),
                 textcoords="offset points", fontsize=9, color="#1f1f1e")
    primera = int((s <= 0.5).sum())
    # texto en la esquina del panel (coordenadas del eje), lejos de las barras
    eje.text(0.98, 0.80, f"{primera} de {len(s)} ({100*primera/len(s):.0f} %) con ≤ 6 meses",
             transform=eje.transAxes, ha="right", fontsize=9, color="#3d3d3a")
    eje.set_title(f"{NOMBRE[cid]} ({cid}), n = {len(s)}", loc="left", fontsize=11, color="#1f1f1e")
    eje.set_ylabel("personas")
    eje.grid(axis="y", color="#e6e5e0", linewidth=0.8)
    eje.set_axisbelow(True)
    for lado in ("top", "right"):
        eje.spines[lado].set_visible(False)
ejes[1].set_xlabel("años de seguimiento (de la fecha índice a la fecha de salida)")
assert (sl.max() < 10 and sa.max() < 10)   # nadie queda fuera del eje
# el título usa cifras calculadas aquí; la causa (otro fármaco) no se puede ver en
# esta figura porque results.cohort no guarda el motivo de salida (actividad 6).
pct6m = {c: 100 * (s <= 0.5).mean() for c, s in [(1701, sl), (1702, sa)]}
fig.suptitle(f"Seguimiento de las cohortes finales: {pct6m[1701]:.0f} % (lisinopril) y {pct6m[1702]:.0f} % (amlodipino) "
             "salen en los primeros 6 meses\n"
             "y el resto se reparte hasta 10 años",
             x=0.01, ha="left", fontsize=11)
fig.tight_layout()
fig.savefig(AQUI / "figura_seguimiento.png", dpi=150)
print("guardada:", AQUI / "figura_seguimiento.png")
