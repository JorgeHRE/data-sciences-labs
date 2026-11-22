"""Auditoría de plausibilidad: función pura (sin S3) para poder probarla con pytest."""

import pandas as pd
from clinlab.auditoria import contar_duplicados, marcar_valores_implausibles

# Código LOINC -> (analito, unidad esperada, mínimo, máximo). Límites inclusivos.
# Rangos amplios a propósito: buscan errores de dato, no pacientes enfermos (D1, DECISIONES.md).
# Se agrupa por CODE y no por DESCRIPTION: el mismo código aparece con dos descripciones.
RANGOS = {
    "8480-6": ("presion_sistolica", "mm[Hg]", 50, 250),
    "8867-4": ("frecuencia_cardiaca", "/min", 30, 220),
    "29463-7": ("peso", "kg", 0.5, 300),  # 0.5 kg: incluye prematuros
    "39156-5": ("imc", "kg/m2", 10, 80),
    "2339-0": ("glucosa_sangre", "mg/dL", 20, 600),
    "38483-4": ("creatinina_sangre", "mg/dL", 0.1, 20),
}


def auditar(obs: pd.DataFrame) -> pd.DataFrame:
    """Devuelve una fila por (anio, código) con conteos de calidad. No modifica `obs`."""
    sub = obs[obs["CODE"].isin(RANGOS)]
    filas = []
    for (anio, codigo), g in sub.groupby(["anio", "CODE"], observed=True):
        analito, unidad, minimo, maximo = RANGOS[codigo]
        # errors="coerce": un VALUE no numérico se vuelve NaN en lugar de romper el pipeline...
        valor = pd.to_numeric(g["VALUE"], errors="coerce")
        # ...pero NaN < minimo es False, así que clinlab NO lo marcaría: se cuenta aparte.
        no_numericos = int(valor.isna().sum())
        implausibles = int(marcar_valores_implausibles(valor, minimo, maximo).sum())
        # Duplicado = mismo paciente, mismo instante, mismo valor (opción A: se cuenta, no se borra).
        llave = pd.util.hash_pandas_object(g[["PATIENT", "DATE", "VALUE"]], index=False)
        filas.append({
            "anio": int(anio), "codigo": codigo, "analito": analito, "unidad_esperada": unidad,
            "filas": len(g),
            "unidad_inesperada": int((g["UNITS"] != unidad).sum()),
            "no_numericos": no_numericos,
            "implausibles": implausibles,
            "pct_implausibles": round(100 * implausibles / len(g), 3),
            "duplicados": contar_duplicados(llave),
        })
    return pd.DataFrame(filas)
