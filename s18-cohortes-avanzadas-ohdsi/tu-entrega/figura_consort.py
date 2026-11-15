"""Lab 18, actividad 4: diagrama de flujo tipo CONSORT de la atrición.

Lee la tabla de atrición (orden del lab 17, atricion.sql + orden_lab17.sql; solo
lectura) y dibuja, para cada cohorte, un diagrama vertical: cajas con el N de
cada paso en el centro y las pérdidas, con su motivo, al costado. Los pasos que
no quitan a nadie no son cajas: van como una nota junto a la flecha.

Escribe figura_consort_1701.png (lisinopril) y figura_consort_1702.png
(amlodipino), a 300 dpi. Las cifras salen de la base: si cambian, el script se
detiene en vez de dibujar una figura distinta a atricion_lab17.md.

Uso (desde la raíz del repo):
    s18-cohortes-avanzadas-ohdsi/tu-entrega/.venv/bin/python \
        s18-cohortes-avanzadas-ohdsi/tu-entrega/figura_consort.py
"""
import matplotlib

matplotlib.use("Agg")  # sin ventana: solo guarda el PNG
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch

from atricion_lib import AQUI, leer_atricion

COLOR = {1701: "#2a78d6", 1702: "#eb6834"}  # mismos colores que las figuras del lab 17
FARMACO = {1701: "lisinopril", 1702: "amlodipino"}
OTRO = {1701: "amlodipino", 1702: "lisinopril"}
GRIS, TINTA, TENUE = "#555555", "#1a1a1a", "#8a8a8a"

# criterio de la tabla (orden_lab17.sql) → (texto del nodo si pasa, motivo de la exclusión).
# {otro} se sustituye por el otro fármaco de la cohorte. Un criterio que cambie de
# nombre en orden_lab17.sql hace fallar el assert de abajo en lugar de dibujarse mal.
TEXTO = {
    "índice desde 2017-01-01": ("Índice desde 2017-01-01", "Primera receta antes de 2017-01-01"),
    "+ 365 d de observación previa": ("≥ 365 d de observación previa", None),
    "+ lavado de 365 d": ("lavado de 365 d", None),
    "+ edad ≥ 18": ("edad ≥ 18 años", None),
    "+ hipertensión (−∞, 0]": ("Con hipertensión", "Sin diagnóstico de hipertensión\nhasta el día índice"),
    "+ ≥ 2 visitas en [−365, −1]": ("≥ 2 visitas en los 365 días previos", "Menos de 2 visitas\nen [−365, −1]"),
    "− demencia previa": ("Sin demencia previa", "Demencia previa al índice"),
    "− otro fármaco previo": ("Sin {otro} previo", "Ya usaba {otro}\n(hasta el día índice, inclusive)"),
    "− combinación en el índice": ("combinación en el índice", None),
}

ANCHO, X_PRINC, X_DER, W_PRINC, W_DER = 8.0, 1.85, 5.75, 3.4, 3.5  # la columna derecha empieza en 4.0, después de la central (3.55)


def caja(ax, cx, cy, w, h, texto, borde=TINTA, relleno="white", lw=1.1, negrita_primera=True, ls="-", color=TINTA):
    ax.add_patch(FancyBboxPatch((cx - w / 2, cy - h / 2), w, h, boxstyle="round,pad=0.0,rounding_size=0.06",
                                fc=relleno, ec=borde, lw=lw, ls=ls, zorder=2))
    lineas = texto.split("\n")
    # la primera línea (el criterio) en negrita; el resto, normal
    paso = 0.17
    y0 = cy + paso * (len(lineas) - 1) / 2
    for i, ln in enumerate(lineas):
        ax.text(cx, y0 - i * paso, ln, ha="center", va="center", fontsize=8.6, color=color,
                fontweight="bold" if (i == 0 and negrita_primera) else "normal", zorder=3)


def dibujar(df, coh):
    g = df[df.cohorte == coh].reset_index(drop=True)
    n0, nf = int(g.n.iloc[0]), int(g.n.iloc[-1])
    assert set(g.criterio.iloc[1:]) <= set(TEXTO), set(g.criterio.iloc[1:]) - set(TEXTO)
    sub = lambda t: t.format(otro=OTRO[coh])

    # --- nodos: la primera receta y cada paso con pérdida; los pasos sin pérdida se acumulan en notas
    nodos = [dict(txt=f"Primeras recetas de {FARMACO[coh]}\n(toda la historia)\nN = {n0:,}", n=n0, perdida=None, nota=None)]
    notas = []
    for r in g.iloc[1:].itertuples():
        nodo_txt, motivo = TEXTO[r.criterio]
        if r.perdidos == 0:
            notas.append(sub(nodo_txt))
            continue
        nodos.append(dict(txt=f"{sub(nodo_txt)}\nN = {int(r.n):,} · {r.pct_inicial:.1f} %", n=int(r.n),
                          perdida=f"Excluidos: n = {int(r.perdidos):,} ({r.pct_perdida:.1f} %)\n{sub(motivo)}",
                          nota=notas or None))
        notas = []
    # pasos sin pérdida al final (p. ej. combinación en el índice): van en la caja final
    final_extra = notas
    nodos[-1]["final"] = True
    assert nodos[-1]["n"] == nf
    # las pérdidas dibujadas suman lo que se fue entre el inicio y el final
    perdidas = int(g.perdidos.sum())
    assert perdidas == n0 - nf and sum(int(r.perdidos) for r in g.iloc[1:].itertuples()) == n0 - nf

    # --- alturas (pulgadas). Un hueco entre cajas mide 1.0; si lleva una nota de pasos sin
    # pérdida, crece lo que ocupa la nota (alto = 0.17 por línea + 0.2) encima de la exclusión.
    def lineas_nota(nd):
        return ["Pasos sin pérdidas (n = 0):"] + ["· " + t for t in nd["nota"]]
    huecos = [(0.11 + 0.62 + 0.1 + 0.17 * len(lineas_nota(n)) + 0.2 + 0.35) if n["nota"] else 1.0 for n in nodos[1:]]
    alturas = [0.95] + [0.8] * (len(nodos) - 2) + [0.95 + (0.25 if final_extra else 0)]
    total = sum(alturas) + sum(huecos) + 1.0
    fig, ax = plt.subplots(figsize=(ANCHO, total))
    ax.set_xlim(0, ANCHO); ax.set_ylim(0, total); ax.axis("off")

    y = total - 0.35
    for i, nd in enumerate(nodos):
        h = alturas[i]
        cy = y - h / 2
        final = nd.get("final")
        txt = nd["txt"]
        if final:
            txt = (f"Cohorte final de {FARMACO[coh]}\nN = {nf:,} · {100 * nf / n0:.1f} % de las primeras recetas")
            if final_extra:
                txt += "\n(sin pérdidas: " + ", ".join(final_extra) + ")"
        caja(ax, X_PRINC, cy, W_PRINC, h, txt,
             borde=COLOR[coh] if final else TINTA, lw=2.0 if final else 1.1,
             relleno=("#eef4fc" if coh == 1701 else "#fdf1ec") if final else "white")
        y = cy - h / 2
        if i < len(nodos) - 1:
            hueco = huecos[i]
            nxt = nodos[i + 1]
            ax.annotate("", xy=(X_PRINC, y - hueco), xytext=(X_PRINC, y),
                        arrowprops=dict(arrowstyle="-|>", color=GRIS, lw=1.2, shrinkA=0, shrinkB=0), zorder=1)
            # exclusión a la derecha, cerca del final de la flecha; la nota (si hay) arriba de ella
            cy_p = y - hueco + 0.42
            ax.plot([X_PRINC, X_DER - W_DER / 2], [cy_p, cy_p], color=GRIS, lw=1.0, zorder=1)
            caja(ax, X_DER, cy_p, W_DER, 0.62, nxt["perdida"], borde=TENUE, relleno="#f4f4f4", lw=1.0)
            if nxt["nota"]:
                lineas = lineas_nota(nxt)
                alto_nota = 0.17 * len(lineas) + 0.2
                caja(ax, X_DER, cy_p + 0.31 + 0.1 + alto_nota / 2, W_DER, alto_nota, "\n".join(lineas),
                     borde=TENUE, relleno="white", lw=0.9, ls=(0, (4, 3)), negrita_primera=False, color=GRIS)
            y -= hueco
    ax.text(0.15, 0.18, "% bajo el N: respecto a las primeras recetas. % en las exclusiones: respecto al paso anterior.\n"
            "Orden de los criterios: el del lab 17 (declarado; el costo de cada criterio depende del orden).",
            fontsize=7.2, color=GRIS, va="bottom", ha="left")
    salida = AQUI / f"figura_consort_{coh}.png"
    fig.savefig(salida, dpi=300, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    return salida


df = leer_atricion("orden_lab17.sql")
esperado = {1701: (1522, 122), 1702: (1104, 81)}  # = atricion_lab17.md y results.cohort
for coh, (n0, nf) in esperado.items():
    g = df[df.cohorte == coh]
    assert (int(g.n.iloc[0]), int(g.n.iloc[-1])) == (n0, nf), coh
    print(dibujar(df, coh))
