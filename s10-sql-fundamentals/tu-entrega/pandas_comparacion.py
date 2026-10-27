"""Actividad 10: tres consultas (6.2, 6.6 y 6.15) en pandas, contra su versión en SQL.

Las tablas se cargan UNA vez desde clinica.duckdb a DataFrames; el tiempo de carga se
reporta aparte. Cada consulta se mide con la mediana de varias corridas, igual que en la
actividad 9, para que la comparación sea justa.
"""
import statistics
import time

import duckdb
import pandas as pd

BASE = "clinica.duckdb"
CORRIDAS = 31


def cargar():
    con = duckdb.connect(BASE, read_only=True)
    t0 = time.perf_counter()
    tablas = {
        "patients": con.execute('SELECT Id AS "Id", gender FROM patients').df(),
        "encounters": con.execute('SELECT Id AS "Id", patient, encounterclass FROM encounters').df(),
        "conditions": con.execute("SELECT encounter FROM conditions").df(),
    }
    return con, tablas, time.perf_counter() - t0


def mediana_ms(f, n=CORRIDAS):
    tiempos = []
    for _ in range(n):
        t0 = time.perf_counter()
        f()
        tiempos.append((time.perf_counter() - t0) * 1000)
    return statistics.median(tiempos)


def q62_pandas(patients: pd.DataFrame) -> pd.DataFrame:
    """Distribución demográfica por sexo (recuentos y porcentajes sobre el total)."""
    res = (
        patients.groupby("gender")
        .size()
        .reset_index(name="n_pacientes")
        .sort_values(by="n_pacientes", ascending=False)
    )
    res["pct"] = (res["n_pacientes"] / len(patients) * 100).round(2)
    return res


def q66_pandas(
    patients: pd.DataFrame, encounters: pd.DataFrame
) -> pd.DataFrame:
    """Media, mediana, mínimo y máximo de encuentros por paciente.

    Garantiza que pacientes con 0 encuentros entren al cálculo (Left Join).
    """
    # Conteo por paciente reindexado contra la cohorte completa de patients
    conteo = (
        encounters["patient"]
        .value_counts()
        .reindex(patients["Id"], fill_value=0)
    )

    return pd.DataFrame(
        [
            {
                "media": round(float(conteo.mean()), 2),
                "mediana": float(conteo.median()),
                "min": int(conteo.min()),
                "max": int(conteo.max()),
            }
        ]
    )


def q615_pandas(
    encounters: pd.DataFrame, conditions: pd.DataFrame
) -> pd.DataFrame:
    """Encuentros de urgencias sin diagnóstico en conditions y pacientes afectados (Anti-join)."""
    # 1. Filtro estricto por encounterclass = 'emergency'
    emergencias = encounters[encounters["encounterclass"] == "emergency"]

    # 2. Conjunto de encuentros únicos que sí registraron diagnóstico
    encuentros_con_dx = set(conditions["encounter"].dropna().unique())

    # 3. Anti-join mediante negación de pertenencia (~isin)
    sin_dx = emergencias[~emergencias["Id"].isin(encuentros_con_dx)]

    return pd.DataFrame(
        [
            {
                "encuentros_sin_dx": int(len(sin_dx)),
                "pacientes_afectados": int(sin_dx["patient"].nunique()),
            }
        ]
    )


if __name__ == "__main__":
    con, t, carga = cargar()
    print(f"Carga a pandas: {carga * 1000:.0f} ms")
    p, e, c = t["patients"], t["encounters"], t["conditions"]
    print(q62_pandas(p), q66_pandas(p, e), q615_pandas(e, c), sep="\n\n")
