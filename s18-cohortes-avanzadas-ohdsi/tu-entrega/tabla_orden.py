"""Lab 18, actividad 3: la tabla de atrición en dos órdenes, lado a lado.

Compara el orden del lab 17 (orden_lab17.sql) con el orden B (orden_b.sql, que
intercambia «≥ 2 visitas» y «sin otro fármaco»), comprueba que el N final es el
mismo y escribe atricion_ordenes.md. Solo lectura.

Uso (desde la raíz del repo):
    s18-cohortes-avanzadas-ohdsi/tu-entrega/.venv/bin/python \
        s18-cohortes-avanzadas-ohdsi/tu-entrega/tabla_orden.py
"""
import pandas as pd

from atricion_lib import AQUI, NOMBRE, leer_atricion, leer_sql

a = leer_atricion("orden_lab17.sql")
b = leer_atricion("orden_b.sql")
aislado = leer_sql("consulta_aislado.sql").set_index("cohorte")
indice = leer_sql("contraejemplo_indice.sql").set_index("cohorte")["con_receta_desde_inicio"]

# criterio → columna de consulta_aislado.sql
COL = {"índice desde 2017-01-01": "estudio", "+ 365 d de observación previa": "obs",
       "+ lavado de 365 d": "lavado", "+ edad ≥ 18": "adulto", "+ hipertensión (−∞, 0]": "hta",
       "+ ≥ 2 visitas en [−365, −1]": "visitas", "− demencia previa": "demencia",
       "− otro fármaco previo": "otro", "− combinación en el índice": "combo"}
MOVIDOS = ["+ ≥ 2 visitas en [−365, −1]", "− otro fármaco previo"]

# --- controles ------------------------------------------------------------
for coh in (1701, 1702):
    ga, gb = a[a.cohorte == coh].reset_index(drop=True), b[b.cohorte == coh].reset_index(drop=True)
    assert len(ga) == len(gb) == 10
    # 1. El N final es el mismo (lo que pide el enunciado): criterios independientes.
    assert ga["n"].iloc[-1] == gb["n"].iloc[-1] == {1701: 122, 1702: 81}[coh], coh
    # 2. La pérdida total es la misma (mismo inicio, mismo final).
    assert ga["perdidos"].sum() == gb["perdidos"].sum()
    # 3. Los pasos 0-5 no se movieron: tabla idéntica.
    assert ga.loc[:5, ["criterio", "n"]].equals(gb.loc[:5, ["criterio", "n"]])
    # 4. Los dos criterios intercambiados SÍ cambian de pérdida (si no, no se vería el efecto).
    pa = ga.set_index("criterio")["perdidos"]; pb = gb.set_index("criterio")["perdidos"]
    assert all(pa[c] != pb[c] for c in MOVIDOS), (coh, pa[MOVIDOS].to_dict(), pb[MOVIDOS].to_dict())
    # 5. Fallar «solo» siempre es ≥ que lo que quita en secuencia (en cualquier orden).
    for c, col in COL.items():
        assert aislado.loc[coh, col] >= max(pa[c], pb[c]), (coh, c)
    assert aislado.loc[coh, "inicial"] == ga["n"].iloc[0]
assert indice.to_dict() == {1701: 1233, 1702: 934}, indice.to_dict()  # lab 17, decisión 9

# --- Markdown ---------------------------------------------------------------
sal = ["# La tabla de atrición en dos órdenes\n",
       "Generada por `tabla_orden.py` (no editar a mano). Orden A = el del lab 17 "
       "(`orden_lab17.sql`); orden B = intercambia «≥ 2 visitas» y «sin otro fármaco» (`orden_b.sql`).\n"]
for coh in (1701, 1702):
    ga, gb = a[a.cohorte == coh].reset_index(drop=True), b[b.cohorte == coh].reset_index(drop=True)
    sal += [f"## {NOMBRE[coh]}\n",
            "| paso | orden A: criterio | N | pérdida | orden B: criterio | N | pérdida |",
            "|---:|---|---:|---:|---|---:|---:|"]
    f = lambda r: "—" if pd.isna(r) else f"−{int(r):,}"
    for i in range(10):
        marca = "**" if ga.criterio[i] != gb.criterio[i] else ""
        sal.append(f"| {i} | {marca}{ga.criterio[i]}{marca} | {ga.n[i]:,} | {marca}{f(ga.perdidos[i])}{marca} | "
                   f"{marca}{gb.criterio[i]}{marca} | {gb.n[i]:,} | {marca}{f(gb.perdidos[i])}{marca} |")
    pa = ga.set_index("criterio"); pb = gb.set_index("criterio")
    sal += ["", f"**Pérdida de cada criterio según el orden ({NOMBRE[coh]})**\n",
            "| criterio | falla solo (de las "f"{int(aislado.loc[coh, 'inicial']):,}) | pérdida en orden A | pérdida en orden B |",
            "|---|---:|---:|---:|"]
    for c, col in COL.items():
        sal.append(f"| {c.lstrip('+− ').strip()} | {int(aislado.loc[coh, col]):,} | "
                   f"{int(pa.perdidos[c]):,} | {int(pb.perdidos[c]):,} |")
    sal += [f"| **N final** | | **{int(ga.n.iloc[-1]):,}** | **{int(gb.n.iloc[-1]):,}** |", ""]
sal += ["## Lo que no es reordenar: el índice\n",
        "Filtrar por fecha **antes** de tomar la primera receta cambia cuál es el índice. Personas con alguna "
        f"receta desde 2017-01-01: **{indice[1701]:,}** (1701) y **{indice[1702]:,}** (1702), contra 346 y 238 "
        "con el índice de toda la historia (`contraejemplo_indice.sql`).\n"]
(AQUI / "atricion_ordenes.md").write_text("\n".join(sal), encoding="utf-8")
print("\n".join(sal))
