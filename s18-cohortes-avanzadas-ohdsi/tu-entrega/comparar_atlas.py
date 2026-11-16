"""Lab 18, actividad 8: compara la cohorte que genera el SQL exportado de ATLAS con results.cohort.

El SQL que exporta ATLAS (CIRCE) trae marcadores (@cdm_database_schema, ...). Aquí se
sustituyen por los esquemas de la base del lab 12 y se ejecuta con el destino en una
TABLA TEMPORAL de la sesión (pg_temp): no se escribe nada persistente. Se compara con
la cohorte 1701 persona por persona, con el desplazamiento de salida (surveillance
window) en 0 y en 30, y se miden las diferencias de código (atlas_impacto.sql).

El archivo atlas_export.sql NO se versiona (.gitignore): si no existe, el script avisa y sale.
Escribe comparacion_atlas.md.

Uso (desde la raíz del repo):
    s18-cohortes-avanzadas-ohdsi/tu-entrega/.venv/bin/python \
        s18-cohortes-avanzadas-ohdsi/tu-entrega/comparar_atlas.py
"""
import sys

import pandas as pd
import psycopg2

from atricion_lib import AQUI, ENV, leer_sql

EXPORT = AQUI / "atlas_export.sql"
if not EXPORT.exists():
    print(f"No existe {EXPORT.name}: es el SQL exportado de ATLAS (no se versiona). Nada que comparar.")
    sys.exit(0)

CERO = "(ENDS.era_end_date + 0*INTERVAL'1 day')"  # surveillance window (Offset) de la estrategia de salida


def conexion():
    # Conexión normal (no de solo lectura): el SQL de ATLAS crea tablas temporales. El destino
    # es pg_temp, así que la base queda igual; el script no escribe en results ni en cdm.
    c = psycopg2.connect(host="localhost", port=ENV.get("POSTGRES_PORT", "5433"), dbname=ENV["POSTGRES_DB"],
                         user=ENV["POSTGRES_USER"], password=ENV["POSTGRES_PASSWORD"])
    c.autocommit = True
    return c


def cohorte_atlas(offset):
    """Ejecuta el SQL de ATLAS (con el surveillance window = offset) y devuelve la cohorte generada."""
    sql = (EXPORT.read_text(encoding="utf-8")
           .replace("@cdm_database_schema", "cdm").replace("@vocabulary_database_schema", "cdm")
           .replace("@target_database_schema.@target_cohort_table", "pg_temp.atlas_cohort")
           .replace("@target_cohort_id", "9999"))
    assert "@" not in sql, "quedan marcadores sin sustituir"
    if offset:
        assert sql.count(CERO) == 1, "no se encontró el desplazamiento de la salida"
        sql = sql.replace(CERO, CERO.replace("0*", f"{offset}*"))
    with conexion() as c, c.cursor() as cur:
        cur.execute("CREATE TEMP TABLE atlas_cohort (cohort_definition_id int, subject_id bigint, "
                    "cohort_start_date date, cohort_end_date date)")
        cur.execute(sql)
        cur.execute("SELECT subject_id, cohort_start_date, cohort_end_date FROM pg_temp.atlas_cohort")
        a = pd.DataFrame(cur.fetchall(), columns=["persona", "indice_atlas", "salida_atlas"])
        cur.execute("SELECT subject_id, cohort_start_date, cohort_end_date FROM results.cohort WHERE cohort_definition_id = 1701")
        t = pd.DataFrame(cur.fetchall(), columns=["persona", "indice_tuyo", "salida_tuyo"])
        cur.execute("SELECT person_id, observation_period_end_date FROM cdm.observation_period")
        op = pd.DataFrame(cur.fetchall(), columns=["persona", "op_fin"])
    return a.merge(t, on="persona", how="outer", indicator=True).merge(op, on="persona", how="left")


def resumen(df):
    ambas = df[df._merge == "both"]
    return dict(atlas=int(df._merge.isin(["both", "left_only"]).sum()), tuyo=int(df._merge.isin(["both", "right_only"]).sum()),
                en_ambas=len(ambas), solo_atlas=int((df._merge == "left_only").sum()), solo_tuyo=int((df._merge == "right_only").sum()),
                misma_fecha_indice=int((ambas.indice_atlas == ambas.indice_tuyo).sum()),
                misma_fecha_salida=int((ambas.salida_atlas == ambas.salida_tuyo).sum()))


cero, treinta = cohorte_atlas(0), cohorte_atlas(30)
r0, r30 = resumen(cero), resumen(treinta)

# --- controles: si cambia la base, el export o la cohorte, se detiene.
assert r0 == dict(atlas=122, tuyo=122, en_ambas=122, solo_atlas=0, solo_tuyo=0, misma_fecha_indice=122, misma_fecha_salida=67), r0
assert r30 == dict(atlas=122, tuyo=122, en_ambas=122, solo_atlas=0, solo_tuyo=0, misma_fecha_indice=122, misma_fecha_salida=122), r30
amb = cero[cero._merge == "both"].copy()
amb["dif"] = (pd.to_datetime(amb.salida_tuyo) - pd.to_datetime(amb.salida_atlas)).dt.days
assert (amb.dif >= 0).all()                                        # tu salida nunca es anterior a la de ATLAS
mas30, otras = amb[amb.dif == 30], amb[(amb.dif != 0) & (amb.dif != 30)]
assert (len(mas30), len(otras)) == (23, 32)
assert (otras.salida_tuyo == otras.op_fin).all() and otras.dif.between(1, 28).all()  # tu +30 lo corta el fin de observación

imp = leer_sql("atlas_impacto.sql").iloc[0]
assert imp.tolist() == [122, 0, 0, 0, 44, 0, 83, 0], imp.tolist()

md = ["# Comparación con el SQL exportado de ATLAS\n",
      "Generado por `comparar_atlas.py` (no editar a mano). El SQL exportado (`atlas_export.sql`) no se versiona.\n",
      "## Cohorte de ATLAS contra la 1701 (lisinopril), persona por persona\n",
      "| surveillance window (días añadidos al fin de la exposición) | personas ATLAS | personas 1701 | en ambas | solo ATLAS | solo 1701 | misma fecha índice | misma fecha de salida |",
      "|---:|---:|---:|---:|---:|---:|---:|---:|"]
for nombre, r in (("0", r0), ("30", r30)):
    md.append(f"| {nombre} | {r['atlas']} | {r['tuyo']} | {r['en_ambas']} | {r['solo_atlas']} | {r['solo_tuyo']} | "
              f"{r['misma_fecha_indice']} | {r['misma_fecha_salida']} |")
md += ["", f"Con 0, la salida coincide en {r0['misma_fecha_salida']} de 122: en {len(mas30)} difiere exactamente 30 días y en {len(otras)} "
       f"la salida de 1701 es el fin del periodo de observación y la de ATLAS queda entre {int(otras.dif.min())} y {int(otras.dif.max())} días antes. "
       "Con 30 coinciden las 122 (fecha índice y fecha de salida).\n",
       "## Impacto de las diferencias de código en la cohorte final (122)\n", "| diferencia | medida | valor |", "|---|---|---:|",
       f"| A. ventanas recortadas al periodo de observación | con diagnóstico de hipertensión anterior al periodo | {imp.a_dx_hta_antes_del_periodo} |",
       f"| | cumplirían hipertensión solo por esos | {imp.a_hta_solo_antes_del_periodo} |",
       f"| B. «la primera» entre eventos con 365 días previos | primera receta sin 365 días de observación previa | {imp.b_primera_sin_365_previos} |",
       f"| | con ≥ 2 recetas el día índice (empate) | {imp.b_dos_recetas_dia_indice} |",
       f"| C. fin de receta | recetas de lisinopril sin fin | {imp.c_recetas_sin_fin} |",
       f"| | recetas con fin anterior al inicio (CIRCE no las corrige) | {imp.c_recetas_fin_antes_inicio} |",
       f"| E. conceptos válidos | conceptos inválidos en los concept sets | {imp.e_conceptos_invalidos} |", ""]
(AQUI / "comparacion_atlas.md").write_text("\n".join(md), encoding="utf-8")
print("\n".join(md))
