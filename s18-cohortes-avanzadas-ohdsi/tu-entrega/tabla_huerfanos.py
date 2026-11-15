"""Lab 18, actividad 7: tablas de los conceptos huérfanos.

Ejecuta las cinco consultas de huerfanos.sql y los dos controles de impacto en la
cohorte (huerfanos_pa.sql, huerfanos_preeclampsia.sql; solo lectura), comprueba las
cifras y escribe huerfanos.md.

Uso (desde la raíz del repo):
    s18-cohortes-avanzadas-ohdsi/tu-entrega/.venv/bin/python \
        s18-cohortes-avanzadas-ohdsi/tu-entrega/tabla_huerfanos.py
"""
import re

import pandas as pd

from atricion_lib import AQUI, _sin_comentarios, leer_sql, motor

sql = (AQUI / "huerfanos.sql").read_text(encoding="utf-8")
_cab, q1, q2, q3, q4, q5, q6 = re.split(r"^-- Consulta \d+\..*$", sql, flags=re.MULTILINE)
con = motor()
resumen, lista, fuentes, pa_base, pre_base, ieca = (pd.read_sql(_sin_comentarios(q), con) for q in (q1, q2, q3, q4, q5, q6))
pa = leer_sql("huerfanos_pa.sql", con=con)
pre = leer_sql("huerfanos_preeclampsia.sql", con=con).set_index("cohorte")

# --- controles: si cambia la base o las cohortes, se detiene.
r = resumen.set_index(["conjunto", "nivel"])
assert (r.huerfanos.drop(("hipertensión", "ampliado")) == 0).all()          # ningún otro nivel tiene huérfanos
assert r.loc[("hipertensión", "ampliado"), "huerfanos"] == 4 and len(lista) == 4   # lo que lista la consulta 2
assert r.en_el_set.sum() == r.coinciden_con_registros.sum() - 4              # cada coincidencia está en el set o es huérfana
assert lista.concept_id.tolist() == [45769905, 45757499, 137613, 4065875]
assert fuentes.iloc[0].tolist() == [0, 0, 0, 0]
assert pa_base.iloc[0].tolist() == [2078, 1163, 915, 2207]
assert pa_base.con_dx_hta[0] + pa_base.sin_dx_hta[0] == pa_base.pa_elevada_2_fechas[0]
assert pre_base.iloc[0].tolist() == [85, 2207, 62]
assert dict(zip(ieca.ingrediente, ieca.personas)) == {'lisinopril': 1522, 'ramipril': 14, 'enalapril': 13, 'benazepril': 9, 'quinapril': 2}
assert pre.loc[1701].tolist() == [1522, 1447, 0, 0, 0, 0] and pre.loc[1702].tolist() == [1104, 1102, 0, 0, 0, 0]
p = pa.set_index("umbral")
assert (p.fallan_solo_hta == 22).all() and (p.cohorte == 1701).all()          # = costo marginal de hipertensión (+22)
assert p.loc["140/90", ["con_1_o_mas_fechas", "con_2_o_mas_fechas", "con_3_o_mas_fechas"]].tolist() == [4, 3, 2]
assert p.loc["130/80", "con_2_o_mas_fechas"] == 7 and p.loc["160/100", "con_2_o_mas_fechas"] == 0
for u, g in p.iterrows():                                                    # más fechas exigidas → no más personas
    assert g.con_1_o_mas_fechas >= g.con_2_o_mas_fechas >= g.con_3_o_mas_fechas

# --- Markdown
md = ["# Conceptos huérfanos: cifras\n", "Generado por `tabla_huerfanos.py` (no editar a mano).\n",
      "## Búsqueda por texto en CONCEPT\n",
      "| concept set | nivel | coinciden con registros | están en el set | huérfanos |", "|---|---|---:|---:|---:|"]
md += [f"| {x.conjunto} | {x.nivel} | {x.coinciden_con_registros} | {x.en_el_set} | {x.huerfanos} |" for x in resumen.itertuples()]
md += ["", "## Huérfanos encontrados (nivel ampliado de hipertensión)\n", "| concept_id | concepto | personas |", "|---:|---|---:|"]
md += [f"| {x.concept_id} | {x.concept_name} | {x.personas:,} |" for x in lista.itertuples()]
f = fuentes.iloc[0]
md += ["", f"**Sin mapear y códigos fuente:** condiciones sin mapear {f.condiciones_sin_mapear}, recetas sin mapear "
       f"{f.recetas_sin_mapear}, valores fuente de condición fuera del set {f.fuente_condicion_fuera_del_set}, "
       f"valores fuente de receta fuera del set {f.fuente_receta_fuera_del_set}.\n",
       "## Presión arterial elevada sin diagnóstico de hipertensión\n",
       f"En toda la base, {pa_base.pa_elevada_2_fechas[0]:,} personas tienen presión elevada (sistólica ≥ 140 o diastólica ≥ 90) en ≥ 2 fechas: "
       f"{pa_base.con_dx_hta[0]:,} con diagnóstico de hipertensión y **{pa_base.sin_dx_hta[0]:,} sin él**.\n",
       "En la cohorte 1701, de las 22 personas que fallan **solo** el criterio de hipertensión:\n",
       "| umbral (sistólica/diastólica) | con ≥ 1 fecha elevada | con ≥ 2 fechas | con ≥ 3 fechas |", "|---|---:|---:|---:|"]
md += [f"| {u} | {g.con_1_o_mas_fechas} | {g.con_2_o_mas_fechas} | {g.con_3_o_mas_fechas} |" for u, g in p.iterrows()]
md += ["", "## Pre-eclampsia dentro del criterio de hipertensión\n",
       f"En la base: {pre_base.con_preeclampsia[0]} personas con el código, {pre_base.con_algun_codigo_set[0]:,} con algún código del set "
       f"y **{pre_base.solo_preeclampsia[0]}** que cumplirían el criterio solo por él.\n",
       "| cohorte | primeras recetas | cumplen hipertensión | solo por pre-eclampsia | …con índice desde 2017 | …en la cohorte final |",
       "|---|---:|---:|---:|---:|---:|"]
md += [f"| {c} | {g.primeras_recetas:,} | {g.cumplen_hta:,} | {g.solo_preeclampsia} | {g.solo_preeclampsia_desde_2017} | {g.en_cohorte_final} |"
       for c, g in pre.iterrows()]
md += ["", "**Eclampsia (137613, fuera del set):** de quienes fallan solo el criterio de hipertensión, "
       f"{int(pre.solo_hta_con_eclampsia.sum())} tienen ese código hasta el índice.\n"]
md += ["", "## Otros inhibidores de la ECA en la base\n", "| ingrediente | personas con receta |", "|---|---:|"]
md += [f"| {x.ingrediente} | {x.personas:,} |" for x in ieca.itertuples()]
(AQUI / "huerfanos.md").write_text("\n".join(md) + "\n", encoding="utf-8")
print("\n".join(md))
