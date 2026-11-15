"""Lab 17, actividad 3b/3c: primeras recetas por año, antes y después de los
filtros de entrada (trampa 2 del enunciado): inicio de estudio 2017-01-01
(decisión 9) + 365 días de observación previa. Solo cohortes principales
1701/1702; la sensibilidad 1711/1712 es igual al evento inicial.

No repite la definición de la cohorte: lee de cohorte_definicion.sql el bloque
de CTE (entre «-- [INICIO cohorte]» y «-- [CONTEO]») y le añade su propio SELECT.
Solo lectura: no modifica la base. Guarda figura_primeras_recetas.png aquí.

Uso (desde la raíz del repo):
    s17-cohortes-omop-sql/tu-entrega/.venv/bin/python \
        s17-cohortes-omop-sql/tu-entrega/figura_primeras_recetas.py
"""
import re
from pathlib import Path

import matplotlib
matplotlib.use("Agg")  # sin ventana: solo guarda el PNG
import matplotlib.pyplot as plt
import pandas as pd
from dotenv import dotenv_values
from sqlalchemy import create_engine

AQUI = Path(__file__).resolve().parent
ENV = dotenv_values(AQUI.parents[1] / "s12-omop-cdm-introduccion" / "tu-entrega" / ".env")

# Los CTE de la cohorte, tal cual están en el SQL (desde «WITH» hasta [CONTEO]).
sql = (AQUI / "cohorte_definicion.sql").read_text(encoding="utf-8")
bloque = sql.split("-- [INICIO cohorte]")[1].split("-- [CONTEO]")[0]
# Empieza en la línea que es SOLO «WITH»: buscar el texto a secas lo
# encontraría antes, dentro de un comentario («una sentencia WITH que…»).
ctes = bloque[re.search(r"^WITH$", bloque, flags=re.MULTILINE).start():]
# Se quitan los comentarios «-- …» antes de enviar el SQL: el driver
# (psycopg2) lee «%» como marca de parámetro, y un comentario como «77.3 %»
# rompería la consulta. El SQL de la cohorte no tiene «--» dentro de textos.
ctes = re.sub(r"--[^\n]*", "", ctes)

# Años antes de 2000 se agrupan: son pocos por año y alargarían el eje sin
# cambiar la lectura (el corte es de presentación, no de la cohorte).
SQL = ctes + """
, por_anio AS (
    SELECT 'evento inicial' AS serie, cohort_definition_id, fecha_indice FROM evento_inicial
    UNION ALL
    SELECT 'tras inicio de estudio + 365 días', cohort_definition_id, fecha_indice FROM obs_previa
)
SELECT serie, cohort_definition_id,
       greatest(extract(year FROM fecha_indice)::int, 1999) AS anio,
       count(*) AS personas
FROM por_anio
WHERE cohort_definition_id IN (1701, 1702)
GROUP BY 1, 2, 3 ORDER BY 1, 2, 3
"""

motor = create_engine(
    f"postgresql+psycopg2://{ENV['POSTGRES_USER']}:{ENV['POSTGRES_PASSWORD']}"
    f"@localhost:{ENV.get('POSTGRES_PORT', '5433')}/{ENV['POSTGRES_DB']}",
    connect_args={"options": "-c default_transaction_read_only=on"},  # garantía de solo lectura
)
datos = pd.read_sql(SQL, motor)

# Controles: las cifras del SQL (actividades 2b, 3a y 3c). Si cambian, se
# detiene en vez de dibujar una figura distinta a la del reporte.
ANTES, DESPUES = "evento inicial", "tras inicio de estudio + 365 días"
tot = datos.groupby(["serie", "cohort_definition_id"])["personas"].sum().to_dict()
assert tot == {(ANTES, 1701): 1522, (ANTES, 1702): 1104,
               (DESPUES, 1701): 346, (DESPUES, 1702): 238}, tot
pico = datos.query("serie == @ANTES and anio == 2016").set_index("cohort_definition_id")["personas"]
assert pico.to_dict() == {1701: 665, 1702: 545}, pico.to_dict()
assert datos.query("serie == @DESPUES and anio < 2017").empty  # el filtro no deja índices previos

# --- figura: dos paneles (uno por cohorte), barras agrupadas antes/después
COLOR = {ANTES: "#2a78d6", DESPUES: "#eb6834"}  # slots 1-2 de la paleta
TITULO = {1701: "Lisinopril (1701)", 1702: "Amlodipino (1702)"}
anios = list(range(1999, 2027))
# años pares rotulados; 2000 se omite para que no choque con «<2000»
etiquetas = ["<2000" if a == 1999 else (str(a) if a % 2 == 0 and a != 2000 else "") for a in anios]

fig, ejes = plt.subplots(2, 1, figsize=(10, 6.5), sharex=True, sharey=True)
for eje, cid in zip(ejes, [1701, 1702]):
    for k, serie in enumerate(COLOR):
        s = (datos.query("serie == @serie and cohort_definition_id == @cid")
             .set_index("anio")["personas"].reindex(anios, fill_value=0))
        x = [i + (k - 0.5) * 0.4 for i in range(len(anios))]
        eje.bar(x, s.values, width=0.38, color=COLOR[serie], label=serie)
    n2016 = int(pico[cid])
    eje.annotate(f"2016: {n2016}", xy=(anios.index(2016), n2016), xytext=(12, -2),
                 textcoords="offset points", fontsize=9, color="#3d3d3a", va="top")
    eje.set_title(TITULO[cid], loc="left", fontsize=11, color="#1f1f1e")
    eje.set_ylabel("personas (primera receta)")
    eje.grid(axis="y", color="#e6e5e0", linewidth=0.8)
    eje.set_axisbelow(True)
    for lado in ("top", "right"):
        eje.spines[lado].set_visible(False)
ejes[1].set_xticks(range(len(anios)), etiquetas)
ejes[0].legend(frameon=False, loc="upper left")
fig.suptitle("Primeras recetas por año, antes y después de los filtros de entrada\n"
             "Solo con 365 días de observación no se quitaba a nadie; el inicio de estudio (2017) elimina el pico de 2016",
             x=0.01, ha="left", fontsize=11)
fig.tight_layout()
fig.savefig(AQUI / "figura_primeras_recetas.png", dpi=150)
print("guardada:", AQUI / "figura_primeras_recetas.png")
