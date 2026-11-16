"""Lab 18, actividad 10: traslape de las tres variantes de lavado (y de la cohorte sin inicio de estudio).

Ejecuta variantes.sql (tabla TEMPORAL de la sesión; no escribe nada persistente) y lee
results.cohort 1711/1712 (sin inicio de estudio). Verifica el anidamiento
730 ⊆ 365 ⊆ 180 ⊆ sin inicio, persona por persona y con la misma fecha índice, y cuenta cada
persona en su región exclusiva (según en cuáles de las cuatro cohortes aparece).
Escribe traslape_tablas.md y figura_traslape.png (300 dpi).

Uso (desde la raíz del repo):
    s18-cohortes-avanzadas-ohdsi/tu-entrega/.venv/bin/python \
        s18-cohortes-avanzadas-ohdsi/tu-entrega/tabla_traslape.py
"""
import matplotlib

matplotlib.use("Agg")  # sin ventana: solo guarda el PNG
import matplotlib.pyplot as plt
import pandas as pd
import psycopg2

from atricion_lib import AQUI, ENV, NOMBRE, _sin_comentarios

COLOR = {1701: "#2a78d6", 1702: "#eb6834"}   # mismos colores que el resto de las figuras
CLARO = {1701: "#a9c8f0", 1702: "#f7c4ae"}
GRIS, TINTA, TENUE = "#b8b8b8", "#1a1a1a", "#555555"
CAPAS = [("sin_inicio", "sin inicio de estudio"), (180, "lavado 180 d"), (365, "lavado 365 d (principal)"), (730, "lavado 730 d")]
ESPERADO = {1701: {"sin_inicio": 242, 180: 122, 365: 122, 730: 121}, 1702: {"sin_inicio": 131, 180: 81, 365: 81, 730: 81}}

conn = psycopg2.connect(host="localhost", port=ENV.get("POSTGRES_PORT", "5433"), dbname=ENV["POSTGRES_DB"],
                        user=ENV["POSTGRES_USER"], password=ENV["POSTGRES_PASSWORD"])
conn.autocommit = True
cur = conn.cursor()
cur.execute(_sin_comentarios((AQUI / "variantes.sql").read_text(encoding="utf-8")))
cur.execute("SELECT c, w, pid, idx FROM variantes")
v = pd.DataFrame(cur.fetchall(), columns=["c", "w", "pid", "idx"])
cur.execute("SELECT cohort_definition_id - 10, subject_id, cohort_start_date FROM results.cohort WHERE cohort_definition_id IN (1711, 1712)")
s = pd.DataFrame(cur.fetchall(), columns=["c", "pid", "idx"])
s["w"] = "sin_inicio"
t = pd.concat([v, s], ignore_index=True)          # c, w, pid, idx: una fila por persona y cohorte

# --- controles: la base y las cohortes no cambiaron; una fila por persona en cada capa
assert not t.duplicated(["c", "w", "pid"]).any()
for c, e in ESPERADO.items():
    assert {w: int((t.c == c).__and__(t.w == w).sum()) for w in e} == e, c

regiones, filas, md = {}, [], ["# Traslape de las variantes de lavado\n",
                               "Generado por `tabla_traslape.py` (no editar a mano). Cada persona cuenta una vez, en la región que dice en cuáles "
                               "de las cuatro cohortes aparece (sí = ✓).\n"]
for c in (1701, 1702):
    S = {w: set(t[(t.c == c) & (t.w == w)].pid) for w, _ in CAPAS}
    # anidamiento: 730 ⊆ 365 ⊆ 180 ⊆ sin inicio (la trampa del enunciado)
    assert S[730] <= S[365] <= S[180] <= S["sin_inicio"], f"los conjuntos no están anidados en {c}"
    # y la misma persona entra con la MISMA fecha índice en todas las capas en que aparece
    idx = {w: t[(t.c == c) & (t.w == w)].set_index("pid").idx for w, _ in CAPAS}
    for w in (180, 365, 730):
        assert (idx[w] == idx["sin_inicio"].loc[idx[w].index]).all(), (c, w)
    n = {w: len(S[w]) for w in S}
    reg = [("en las cuatro (también en 730 d)", S[730]),
           ("en 180, 365 y sin inicio, no en 730 d", S[365] - S[730]),
           ("en 180 y sin inicio, no en 365 d", S[180] - S[365]),
           ("solo sin inicio de estudio", S["sin_inicio"] - S[180])]
    assert sum(len(x) for _, x in reg) == n["sin_inicio"]            # las regiones suman el conjunto más grande
    assert all(len(a & b) == 0 for i, (_, a) in enumerate(reg) for _, b in reg[i + 1:])
    regiones[c] = [(nom, len(x)) for nom, x in reg]
    md += [f"## {NOMBRE[c]}\n", "| región | 730 d | 365 d | 180 d | sin inicio | personas | % de la más laxa de lavado (180 d) |", "|---|:-:|:-:|:-:|:-:|---:|---:|"]
    marcas = [("✓", "✓", "✓", "✓"), ("—", "✓", "✓", "✓"), ("—", "—", "✓", "✓"), ("—", "—", "—", "✓")]
    for (nom, x), m in zip(reg, marcas):
        pct = f"{100 * len(x) / n[180]:.1f} %" if m[3] == "✓" and m != ("—", "—", "—", "✓") else "—"
        md.append(f"| {nom} | {m[0]} | {m[1]} | {m[2]} | {m[3]} | {len(x)} | {pct} |")
    md += [f"| **total** | | | | | **{n['sin_inicio']}** | |", "",
           f"Tamaños: 180 d = {n[180]}, 365 d = {n[365]}, 730 d = {n[730]}, sin inicio = {n['sin_inicio']}. "
           f"Anidamiento comprobado (730 ⊆ 365 ⊆ 180 ⊆ sin inicio) y misma fecha índice para todas las personas que aparecen en más de una cohorte.\n"]
(AQUI / "traslape_tablas.md").write_text("\n".join(md), encoding="utf-8")
print("\n".join(md))

# --- figura: una barra por capa y cohorte; los segmentos son las regiones. Sin leyenda: etiquetas directas.
fig, axs = plt.subplots(1, 2, figsize=(11, 3.9))
for ax, c in zip(axs, (1701, 1702)):
    n = ESPERADO[c]
    tres, solo_730, solo_ini = regiones[c][0][1], regiones[c][1][1] + regiones[c][2][1], regiones[c][3][1]
    xmax = max(n.values())
    for i, (w, nom) in enumerate(reversed(CAPAS)):          # la más estricta abajo, sin inicio arriba
        segs = [(tres, COLOR[c]), (solo_730 if w != 730 else 0, CLARO[c]), (solo_ini if w == "sin_inicio" else 0, GRIS)]
        if w == 730:
            segs = [(tres, COLOR[c])]
        x0 = 0
        for ancho, col in segs:
            if ancho > 0:
                ax.barh(i, ancho, left=x0, height=0.62, color=col, edgecolor="white", linewidth=1.2, zorder=2)
            x0 += ancho
        # el segmento claro es de 1 persona: invisible a esta escala, así que se declara en el texto
        extra = f"  = {tres} + {solo_730}" if (solo_730 and w in (180, 365)) else ""
        ax.text(n[w] + xmax * 0.015, i, f"{n[w]}{extra}", va="center", ha="left", fontsize=9, color=TINTA, fontweight="bold")
        ax.text(-xmax * 0.02, i, nom, va="center", ha="right", fontsize=8.6, color=TINTA)
    ax.text(tres / 2, 3, f"en las tres: {tres}", va="center", ha="center", fontsize=8.4, color="white", fontweight="bold")
    ax.text(tres + solo_ini / 2 + solo_730, 3, f"solo sin inicio: {solo_ini}", va="center", ha="center", fontsize=8.4, color=TINTA)
    ax.set_title(NOMBRE[c], fontsize=10.5, color=TINTA, loc="left", pad=8)
    ax.set_xlim(0, xmax * 1.28); ax.set_ylim(-0.6, len(CAPAS) - 0.4)
    ax.set_yticks([]); ax.tick_params(axis="x", labelsize=8, colors=TENUE)
    for lado in ("top", "right", "left"):
        ax.spines[lado].set_visible(False)
    ax.spines["bottom"].set_color(GRIS)
    ax.set_xlabel("personas", fontsize=8.5, color=TENUE)
fig.text(0.01, 0.01, "Azul/naranja: personas que están en las tres variantes de lavado. Gris: solo sin inicio de estudio. En lisinopril, la persona 4993 "
         "(tono claro, 1 persona: no se ve a esta escala)\nestá en 180 y 365 d pero no en 730 d. Todas las personas que aparecen en más de una cohorte lo hacen con la misma fecha índice.",
         fontsize=7.4, color=TENUE, va="bottom", ha="left")
fig.suptitle("Las cohortes están anidadas: 730 d ⊆ 365 d ⊆ 180 d ⊆ sin inicio de estudio", fontsize=11, x=0.01, ha="left", color=TINTA)
fig.tight_layout(rect=(0.0, 0.07, 1, 0.95))
fig.savefig(AQUI / "figura_traslape.png", dpi=300, bbox_inches="tight", facecolor="white")
print(AQUI / "figura_traslape.png")
