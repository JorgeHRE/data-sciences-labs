"""Lab 18, actividad 2: tabla de atrición en el orden del lab 17.

Lee las banderas de atricion.sql (solo lectura), comprueba que la tabla cuadra
y reproduce el lab 17, y escribe atricion_lab17.md.

Uso (desde la raíz del repo):
    s18-cohortes-avanzadas-ohdsi/tu-entrega/.venv/bin/python \
        s18-cohortes-avanzadas-ohdsi/tu-entrega/tabla_atricion.py
"""
from atricion_lib import AQUI, a_markdown, leer_atricion

df = leer_atricion("orden_lab17.sql")

# --- controles: si algo cambia en la base o en las banderas, se detiene.
for coh, g in df.groupby("cohorte"):
    assert list(g["paso"]) == list(range(10)), (coh, "faltan pasos")  # 0-9, sin huecos
    n0, nf = g["n"].iloc[0], g["n"].iloc[-1]
    # la suma de pérdidas es exactamente lo que se fue entre el inicio y el final
    assert int(g["perdidos"].sum()) == n0 - nf, (coh, "las pérdidas no suman")
    assert (g["n"].diff().dropna() <= 0).all(), (coh, "un paso aumentó el N")
# cifras de cohorte_definicion.sql (lab 17) y results.cohort
esperado = {1701: [1522, 346, 346, 346, 346, 320, 173, 172, 122, 122],
            1702: [1104, 238, 238, 238, 238, 237, 165, 164, 81, 81]}
for coh, g in df.groupby("cohorte"):
    assert list(g["n"]) == esperado[coh], (coh, list(g["n"]))

md = ("# Tabla de atrición, en el orden del lab 17\n\n"
      "Generada por `tabla_atricion.py` desde `atricion.sql` y `orden_lab17.sql` "
      "(no editar a mano).\n\n" + a_markdown(df))
(AQUI / "atricion_lab17.md").write_text(md, encoding="utf-8")
print(md)
