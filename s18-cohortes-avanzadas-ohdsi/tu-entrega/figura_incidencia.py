"""Lab 18, actividad 5: incidencia de entrada a la cohorte por año calendario y por edad.

Lee las dos consultas de incidencia.sql ([A] por año, [B] por grupo de edad; solo
lectura), calcula las tasas por 1,000 personas-año con DOS denominadores
(observation_period y personas con visita) y dibuja:
  figura_incidencia_anio.png  - dos paneles: primeras recetas y cohortes 1711/1701
  figura_incidencia_edad.png  - tasa por grupo de edad con IC 95 % exacto de Poisson
También escribe incidencia_tablas.md con las cifras de las dos figuras.

Uso (desde la raíz del repo):
    s18-cohortes-avanzadas-ohdsi/tu-entrega/.venv/bin/python \
        s18-cohortes-avanzadas-ohdsi/tu-entrega/figura_incidencia.py
"""
import math
import re

import matplotlib

matplotlib.use("Agg")  # sin ventana: solo guarda el PNG
import matplotlib.pyplot as plt
import pandas as pd

from atricion_lib import AQUI, _sin_comentarios, motor

AZUL, NARANJA, GRIS, TINTA = "#2a78d6", "#eb6834", "#8a8a8a", "#1a1a1a"  # azul = 1701 (lab 17)

# --- consultas: se parte incidencia.sql por los marcadores de línea completa [A] y [B]
sql = (AQUI / "incidencia.sql").read_text(encoding="utf-8")
_, parte_a, parte_b = re.split(r"^-- \[[AB]\].*$", sql, flags=re.MULTILINE)
con = motor()
a = pd.read_sql(_sin_comentarios(parte_a), con)   # una fila por año, 2005-2026
b = pd.read_sql(_sin_comentarios(parte_b), con)   # una fila por grupo de edad

# --- controles: si cambian las cifras de las actividades 2-3, se detiene.
assert list(a.anio) == list(range(2005, 2027)) and a.anio.is_unique
assert a.n_1701.sum() == 122, a.n_1701.sum()                     # = results.cohort
assert (a[a.anio >= 2017].n_1701 == a[a.anio >= 2017].n_1711).all()  # 1701 es 1711 desde 2017
assert (a[a.anio < 2017].n_1701 == 0).all()                      # la cohorte final no tiene índice antes de 2017
assert a.primeras.sum() == 1272 and a.n_1711.sum() == 212        # + 250 y 30 antes de 2005 (no se muestran)
assert b.entradas.sum() == 122, b.entradas.sum()
assert list(b.grupo) == ["18-29", "30-39", "40-49", "50-59", "60-69", "70+"]

# --- tasas por 1,000 personas-año (año parcial: personas con visita × fracción del año cubierta)
a["py_vis"] = a.pers_visita * a.fraccion
for col in ("primeras", "n_1711", "n_1701"):
    a[f"t_{col}_op"] = 1000 * a[col] / a.py_op
    a[f"t_{col}_vis"] = 1000 * a[col] / a.py_vis
b["t_op"] = 1000 * b.entradas / b.py_op
b["t_vis"] = 1000 * b.entradas / b.py_visita


def poisson_ic(n, alfa=0.05):
    """IC exacto (Garwood) de un conteo de Poisson, por bisección (sin scipy)."""
    def cdf(k, mu):  # P(X ≤ k) con X ~ Poisson(mu)
        return sum(math.exp(-mu + i * math.log(mu) - math.lgamma(i + 1)) for i in range(k + 1))

    def bisecta(f, lo, hi):
        for _ in range(80):
            m = (lo + hi) / 2
            lo, hi = (m, hi) if f(m) > 0 else (lo, m)
        return (lo + hi) / 2
    inf = 0.0 if n == 0 else bisecta(lambda mu: -(1 - cdf(n - 1, mu) - alfa / 2), 1e-9, n + 10 * math.sqrt(n + 1) + 10)
    sup = bisecta(lambda mu: cdf(n, mu) - alfa / 2, 1e-9, n + 10 * math.sqrt(n + 1) + 10)
    return inf, sup


assert all(abs(x - y) < 0.01 for x, y in zip(poisson_ic(2), (0.2422, 7.2247)))  # valores de tabla conocidos

# ----------------------------------------------------------------- figura por año
fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(9, 8), sharex=True, gridspec_kw={"height_ratios": [3, 2.4]})
x = a.anio
parcial = a.anio == a.anio.max()


def linea(ax, y, color, ls, label, marker="o"):
    ax.plot(x[~parcial], y[~parcial], ls=ls, color=color, marker=marker, ms=4, lw=1.6, label=label)
    ax.plot(x, y, ls=ls, color=color, lw=1.6)  # une también el último punto (año parcial)
    ax.plot(x[parcial], y[parcial], marker=marker, ms=6, mfc="white", mec=color, color=color, ls="")  # parcial: hueco


linea(ax1, a.t_primeras_op, GRIS, "-", "denominador: observation_period")
linea(ax1, a.t_primeras_vis, TINTA, "--", "denominador: personas con ≥ 1 visita", marker="s")
ax1.set_yscale("log")
ax1.set_ylabel("Primeras recetas de lisinopril\npor 1,000 personas-año (escala log)")
ax1.set_title("A. Evento inicial: primera receta de lisinopril (antes de los criterios)", loc="left", fontsize=10.5, fontweight="bold")
r16 = a[a.anio == 2016].iloc[0]
ax1.annotate(f"2016: {int(r16.primeras)} primeras recetas\n(44 % de las 1,522; otros años: 7 a 116)",
             xy=(2016, r16.t_primeras_op), xytext=(2005.3, 75), fontsize=8.8,
             arrowprops=dict(arrowstyle="-", color=GRIS))
r05 = a[a.anio == 2005].iloc[0]
ax1.annotate(f"2005: observation_period cuenta {r05.py_op:,.0f} personas-año;\nsolo {int(r05.pers_visita):,} personas tienen una visita",
             xy=(2005, r05.t_primeras_op), xytext=(2005.3, 24), fontsize=8.2, color=GRIS)
r26 = a[a.anio == 2026].iloc[0]
ax1.annotate("2026: año parcial (datos hasta el 26-oct).\nobservation_period lo infla: su periodo\ntermina en la última visita de cada persona",
             xy=(2026, r26.t_primeras_op), xytext=(2019.7, 40), fontsize=8.2, color=GRIS,
             arrowprops=dict(arrowstyle="-", color=GRIS))
ax1.legend(loc="lower right", fontsize=8.5, frameon=False)

linea(ax2, a.t_n_1711_op, NARANJA, "-", "1711 (sin inicio de estudio): obs. period")
linea(ax2, a.t_n_1711_vis, NARANJA, "--", "1711: personas con visita", marker="s")
mask = a.anio >= 2017
ax2.plot(x[mask], a.t_n_1701_op[mask], color=AZUL, lw=1.6, marker="o", ms=4, label="1701 (cohorte final, desde 2017): obs. period")
ax2.plot(x[mask], a.t_n_1701_vis[mask], color=AZUL, lw=1.6, ls="--", marker="s", ms=4, label="1701: personas con visita")
for serie, color, m in ((a.t_n_1711_op, NARANJA, "o"), (a.t_n_1711_vis, NARANJA, "s"),
                        (a.t_n_1701_op, AZUL, "o"), (a.t_n_1701_vis, AZUL, "s")):  # año parcial: marcador hueco
    ax2.plot(x[parcial], serie[parcial], marker=m, ms=6, mfc="white", mec=color, ls="", zorder=5)
ax2.axvline(2016.5, color=GRIS, lw=1, ls=":")
ax2.text(2016.6, ax2.get_ylim()[1] * 0.9, "inicio de estudio\n2017-01-01", fontsize=8.2, color=GRIS, va="top")
ax2.set_ylabel("Entradas a la cohorte\npor 1,000 personas-año")
ax2.set_title("B. Cohorte con todos los criterios clínicos, con y sin inicio de estudio", loc="left", fontsize=10.5, fontweight="bold")
ax2.legend(loc="upper left", fontsize=8, frameon=False, ncol=1)
ax2.set_xticks(range(2005, 2027, 2))
ax2.set_xlabel("Año calendario del índice (círculo vacío = año parcial)")
for ax in (ax1, ax2):
    ax.grid(axis="y", color="#e5e5e5", lw=0.8)
    for lado in ("top", "right"):
        ax.spines[lado].set_visible(False)
fig.text(0.01, 0.005, "Antes de 2005: 250 primeras recetas y 30 entradas de 1711 (no se muestran). 1701 = 1711 desde 2017.", fontsize=7.4, color=GRIS)
fig.tight_layout(rect=(0, 0.015, 1, 1))
fig.savefig(AQUI / "figura_incidencia_anio.png", dpi=300, facecolor="white")
plt.close(fig)

# ----------------------------------------------------------------- figura por edad
fig, ax = plt.subplots(figsize=(8, 5))
ic = [poisson_ic(int(n)) for n in b.entradas]
tasa = b.t_op.values
lo = [1000 * i[0] / py for i, py in zip(ic, b.py_op)]
hi = [1000 * i[1] / py for i, py in zip(ic, b.py_op)]
pos = range(len(b))
ax.bar(pos, tasa, color=AZUL, width=0.6, alpha=0.9, label="tasa (observation_period) con IC 95 % exacto")
ax.errorbar(pos, tasa, yerr=[tasa - lo, [h - t for h, t in zip(hi, tasa)]], fmt="none", ecolor=TINTA, capsize=4, lw=1.2)
ax.plot(pos, b.t_vis, ls="", marker="D", color=NARANJA, ms=7, label="tasa con denominador de personas con visita")
for i, r in b.iterrows():
    ax.text(i, hi[i] + 0.25, f"n = {int(r.entradas)}", ha="center", fontsize=9)
ax.set_xticks(list(pos)); ax.set_xticklabels(b.grupo)
ax.set_xlabel("Grupo de edad (años) al índice")
ax.set_ylabel("Entradas a la cohorte 1701\npor 1,000 personas-año, 2017-2026")
ax.set_title("Incidencia de entrada por grupo de edad", loc="left", fontsize=11, fontweight="bold")
ax.set_ylim(0, max(hi) + 1.2)
ax.set_axisbelow(True)  # la cuadrícula va detrás de las barras
ax.grid(axis="y", color="#e5e5e5", lw=0.8)
for lado in ("top", "right"):
    ax.spines[lado].set_visible(False)
ax.legend(loc="upper right", fontsize=8.5, frameon=False)
fig.text(0.01, 0.005, "Edad = año − año de nacimiento, en el numerador y el denominador. Solo adultos. Intervalos exactos de Poisson (Garwood).",
         fontsize=7.4, color=GRIS)
fig.tight_layout(rect=(0, 0.02, 1, 1))
fig.savefig(AQUI / "figura_incidencia_edad.png", dpi=300, facecolor="white")
plt.close(fig)

# ----------------------------------------------------------------- tablas en Markdown
t = ["# Incidencia de entrada: cifras de las figuras\n",
     "Generado por `figura_incidencia.py` (no editar a mano). Tasas por 1,000 personas-año. "
     "OP = denominador `observation_period`; Vis = personas con ≥ 1 visita (× fracción del año en 2026).\n",
     "## Por año (primeras recetas de lisinopril, cohorte 1711 y cohorte final 1701)\n",
     "| año | personas-año OP | personas con visita | primeras recetas | tasa OP | tasa Vis | 1711 | tasa OP | 1701 | tasa OP |",
     "|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|"]
for r in a.itertuples():
    t.append(f"| {r.anio}{'*' if r.fraccion < 1 else ''} | {r.py_op:,.0f} | {r.pers_visita:,} | {r.primeras} | {r.t_primeras_op:.1f} | "
             f"{r.t_primeras_vis:.1f} | {r.n_1711} | {r.t_n_1711_op:.2f} | {r.n_1701} | {r.t_n_1701_op:.2f} |")
t += ["", "\\* año parcial (datos hasta 2026-10-26).\n", "## Por grupo de edad (cohorte 1701, 2017-2026)\n",
      "| grupo | personas-año OP | entradas | tasa OP [IC 95 %] | tasa Vis |", "|---|---:|---:|---:|---:|"]
for i, r in b.iterrows():
    t.append(f"| {r.grupo} | {r.py_op:,.0f} | {int(r.entradas)} | {r.t_op:.2f} [{lo[i]:.2f}–{hi[i]:.2f}] | {r.t_vis:.2f} |")
(AQUI / "incidencia_tablas.md").write_text("\n".join(t) + "\n", encoding="utf-8")
print("\n".join(t[-9:]))
