"""Lab 18, actividad 9: las tres variantes de lavado (180, 365 y 730 días) y su caracterización.

Ejecuta variantes.sql (crea la tabla TEMPORAL `variantes` de la sesión; no escribe nada
persistente), comprueba que la variante de 365 días reproduce results.cohort persona por
persona, y calcula N, edad, sexo, seguimiento y las tres comorbilidades más frecuentes de
cada variante, más la cohorte sin inicio de estudio (1711/1712) como comparación.
Escribe variantes_tablas.md.

Uso (desde la raíz del repo):
    s18-cohortes-avanzadas-ohdsi/tu-entrega/.venv/bin/python \
        s18-cohortes-avanzadas-ohdsi/tu-entrega/tabla_variantes.py
"""
import re

import numpy as np
import pandas as pd
import psycopg2

from atricion_lib import AQUI, ENV, NOMBRE, _sin_comentarios

ORDEN = ["W180", "W365", "W730", "sin_inicio"]
ETIQ = {"W180": "lavado 180 d", "W365": "lavado 365 d (principal)", "W730": "lavado 730 d", "sin_inicio": "sin inicio de estudio (1711/1712)"}


def consulta(cur, sql, cols):
    cur.execute(sql)
    return pd.DataFrame(cur.fetchall(), columns=cols)


# Conexión normal (el SQL crea una tabla TEMPORAL); no se escribe en results ni en cdm.
conn = psycopg2.connect(host="localhost", port=ENV.get("POSTGRES_PORT", "5433"), dbname=ENV["POSTGRES_DB"],
                        user=ENV["POSTGRES_USER"], password=ENV["POSTGRES_PASSWORD"])
conn.autocommit = True
cur = conn.cursor()
cur.execute(_sin_comentarios((AQUI / "variantes.sql").read_text(encoding="utf-8")))   # CREATE TEMP TABLE variantes + resumen

_cab, qa, qb = re.split(r"^-- \[[AB]\].*$", (AQUI / "variantes_caracterizacion.sql").read_text(encoding="utf-8"), flags=re.MULTILINE)
pers = consulta(cur, _sin_comentarios(qa), ["variante", "cohorte", "persona", "edad", "sexo", "seguimiento_dias"])
com = consulta(cur, _sin_comentarios(qb), ["variante", "cohorte", "persona", "concepto", "nombre"])
vcoh = consulta(cur, "SELECT c, w, pid, idx, salida FROM variantes", ["c", "w", "pid", "idx", "salida"])
res = consulta(cur, "SELECT cohort_definition_id, subject_id, cohort_start_date, cohort_end_date FROM results.cohort "
                    "WHERE cohort_definition_id IN (1701, 1702)", ["c", "pid", "idx", "salida"])

# --- controles: si cambia la base o las cohortes, se detiene.
n = pers.groupby(["variante", "cohorte"]).persona.nunique()
assert len(pers) == pers.groupby(["variante", "cohorte"]).persona.nunique().sum()            # una fila por persona y variante
assert {k: int(v) for k, v in n.items()} == {("W180", 1701): 122, ("W180", 1702): 81, ("W365", 1701): 122, ("W365", 1702): 81,
                                             ("W730", 1701): 121, ("W730", 1702): 81, ("sin_inicio", 1701): 242, ("sin_inicio", 1702): 131}
# la variante de 365 días ES la cohorte del lab 17 (persona, fecha índice y fecha de salida)
v365 = vcoh[vcoh.w == 365].drop(columns="w").sort_values(["c", "pid"]).reset_index(drop=True)
assert v365.equals(res.sort_values(["c", "pid"]).reset_index(drop=True)), "W365 no reproduce results.cohort"
# anidamiento (actividad 10 lo reporta; aquí se comprueba para no caracterizar un error)
for c in (1701, 1702):
    s = {w: set(vcoh[(vcoh.c == c) & (vcoh.w == w)].pid) for w in (180, 365, 730)}
    assert s[730] <= s[365] <= s[180], c
# edad y seguimiento de 1701 W365 = tabla 1 del lab 17 (mediana 40; seguimiento mediano 927.5 d)
g = pers[(pers.variante == "W365") & (pers.cohorte == 1701)]
assert g.edad.median() == 40 and g.seguimiento_dias.median() == 927.5
assert (pers.edad >= 18).all()

q = lambda s, p: float(np.quantile(s, p))
filas = []
for coh in (1701, 1702):
    for v in ORDEN:
        g = pers[(pers.variante == v) & (pers.cohorte == coh)]
        c3 = (com[(com.variante == v) & (com.cohorte == coh)].groupby("nombre").persona.nunique()
              .sort_values(ascending=False, kind="stable").reset_index().sort_values(["persona", "nombre"], ascending=[False, True]).head(3))
        filas.append(dict(cohorte=coh, variante=v, n=len(g), edad=f"{q(g.edad, .5):.0f} [{q(g.edad, .25):.0f}–{q(g.edad, .75):.0f}]",
                          mujeres=f"{(g.sexo == 'FEMALE').sum()} ({100 * (g.sexo == 'FEMALE').mean():.1f} %)",
                          seg=f"{q(g.seguimiento_dias, .5):,.1f} [{q(g.seguimiento_dias, .25):,.0f}–{q(g.seguimiento_dias, .75):,.0f}]",
                          anios=f"{q(g.seguimiento_dias, .5) / 365.25:.1f}",
                          c3="; ".join(f"{r.nombre} {r.persona} ({100 * r.persona / len(g):.0f} %)" for r in c3.itertuples())))
t = pd.DataFrame(filas)
# 180 y 365 son la misma cohorte: su caracterización es idéntica
for coh in (1701, 1702):
    a, b = t[(t.cohorte == coh) & (t.variante == "W180")].iloc[0], t[(t.cohorte == coh) & (t.variante == "W365")].iloc[0]
    assert a.drop(["variante"]).equals(b.drop(["variante"]))

md = ["# Variantes de lavado: caracterización\n", "Generado por `tabla_variantes.py` (no editar a mano). Mediana [Q1–Q3]. "
      "Seguimiento en días (y mediana en años). Comorbilidades: las tres más frecuentes (clase Disorder, [−365, 0]), personas y % de la cohorte.\n"]
for coh in (1701, 1702):
    md += [f"## {NOMBRE[coh]}\n", "| variante | N | edad (años) | mujeres | seguimiento (días) | años | tres comorbilidades más frecuentes |",
           "|---|---:|---|---:|---|---:|---|"]
    md += [f"| {ETIQ[r.variante]} | {r.n} | {r.edad} | {r.mujeres} | {r.seg} | {r.anios} | {r.c3} |" for r in t[t.cohorte == coh].itertuples()]
    md.append("")
(AQUI / "variantes_tablas.md").write_text("\n".join(md), encoding="utf-8")
print("\n".join(md))
