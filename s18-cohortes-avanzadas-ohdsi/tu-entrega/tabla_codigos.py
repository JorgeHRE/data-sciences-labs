"""Lab 18, actividad 6: tablas de los códigos de entrada a la cohorte.

Ejecuta las cuatro consultas de codigos_indice.sql (solo lectura), comprueba las
cifras y escribe codigos_indice.md con las tablas del documento.

Uso (desde la raíz del repo):
    s18-cohortes-avanzadas-ohdsi/tu-entrega/.venv/bin/python \
        s18-cohortes-avanzadas-ohdsi/tu-entrega/tabla_codigos.py
"""
import re

import pandas as pd

from atricion_lib import AQUI, NOMBRE, _sin_comentarios, motor

# El archivo se parte por las líneas «-- Consulta N.» (línea completa); lo anterior es la cabecera.
sql = (AQUI / "codigos_indice.sql").read_text(encoding="utf-8")
_cabecera, q1, q2, q3, q4, q5 = re.split(r"^-- Consulta \d+\..*$", sql, flags=re.MULTILINE)
con = motor()
t, ctrl, uso, etapas, otros = (pd.read_sql(_sin_comentarios(q), con) for q in (q1, q2, q3, q4, q5))

# --- controles: si cambia la base o las cohortes, se detiene.
N = {1701: 122, 1702: 81}
assert (ctrl.personas.tolist(), ctrl.con_receta_indice.tolist(), ctrl.con_mas_de_un_producto.tolist()) \
    == ([122, 81], [122, 81], [0, 0])                            # un producto por persona
for coh, g in t.groupby("cohorte"):
    assert g.personas.sum() == N[coh], coh                       # la tabla suma el N de la cohorte
    assert g.pct.is_monotonic_decreasing and abs(g.pct.sum() - 100) < 0.2
    assert g.pct_acumulado.iloc[-1] == 100.0
assert t[t.cohorte == 1701].iloc[0][["concept_id", "personas"]].tolist() == [19080128, 120]
assert t[t.cohorte == 1702].iloc[0][["concept_id", "personas"]].tolist() == [19073094, 81]
assert etapas.groupby("cohorte").total.apply(list).to_dict() == {1701: [42085, 1522, 242, 122], 1702: [34475, 1104, 131, 81]}
for coh, g in uso.groupby("cohorte"):
    assert g.en_el_set.sum() == {1701: 98, 1702: 303}[coh]
    assert g.con_recetas.sum() == {1701: 9, 1702: 6}[coh]
    assert g.como_indice.sum() == {1701: 2, 1702: 1}[coh]
    assert (g.como_indice <= g.con_recetas).all() and (g.con_recetas <= g.en_el_set).all()

o = otros.set_index("producto")
assert o.loc["10 mg"].tolist() == [1415, 318, 1097, 120] and o.loc["otro producto"].tolist() == [107, 28, 79, 2]
assert (o.indice_desde_2017 + o.indice_antes_2017 == o.primeras).all()   # cada primera receta cae en un lado

# --- Markdown
md = ["# Códigos de entrada a la cohorte\n",
      "Generado por `tabla_codigos.py` desde `codigos_indice.sql` (no editar a mano).\n"]
for coh, g in t.groupby("cohorte"):
    md += [f"## {NOMBRE[coh]}: producto de la receta del día índice (N = {N[coh]})\n",
           "| concept_id | producto | clase | personas | % | % acumulado |", "|---:|---|---|---:|---:|---:|"]
    md += [f"| {r.concept_id} | {r.concept_name} | {r.concept_class_id} | {r.personas} | {r.pct:.1f} | {r.pct_acumulado:.1f} |"
           for r in g.itertuples()]
    md.append("")
md += ["## Cuánto del concept set se usa\n",
       "| cohorte | conceptos en el set | con recetas en la base | producto del índice |", "|---|---:|---:|---:|"]
for coh, g in uso.groupby("cohorte"):
    md.append(f"| {NOMBRE[coh]} | {g.en_el_set.sum()} | {g.con_recetas.sum()} | {g.como_indice.sum()} |")
md += ["", "## Peso del producto más frecuente en cada etapa\n",
       "| cohorte | etapa | unidad | total | productos distintos | % del más frecuente |", "|---|---|---|---:|---:|---:|"]
md += [f"| {NOMBRE[r.cohorte]} | {r.etapa}. {r.nombre} | {r.unidad} | {int(r.total):,} | {r.productos_distintos} | {r.pct_top:.1f} |"
       for r in etapas.itertuples()]
md += ["", "## Lisinopril: quién inicia con el producto más frecuente y quién llega a la cohorte final\n",
       "| primer producto | primeras recetas | índice desde 2017 | índice antes de 2017 | en la cohorte final |", "|---|---:|---:|---:|---:|"]
md += [f"| {p} | {r.primeras:,} | {r.indice_desde_2017:,} | {r.indice_antes_2017:,} | {r.en_cohorte_final} |" for p, r in o.iterrows()]
(AQUI / "codigos_indice.md").write_text("\n".join(md) + "\n", encoding="utf-8")
print("\n".join(md))
