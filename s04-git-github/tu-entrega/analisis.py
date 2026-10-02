"""Módulo de procesamiento y estadística para el Laboratorio 04."""

import numpy as np
import pandas as pd


def resumir_datos(df: pd.DataFrame) -> dict:
    """Calcula métricas resumen de una serie de datos."""
    return {
        "conteo": len(df),
        "media": float(np.mean(df.iloc[:, 0])) if not df.empty else 0.0,
    }


def calcular_iqr(serie: pd.Series) -> dict:
    """Calcula la mediana y el rango intercuartílico (IQR: Q3 - Q1)."""
    # Implementación inicial
    datos_limpios = serie.dropna()
    if datos_limpios.empty:
        return {"mediana": 0.0, "q1": 0.0, "q3": 0.0, "iqr": 0.0}

    q1 = float(np.percentile(datos_limpios, 25))
    q3 = float(np.percentile(datos_limpios, 75))
    mediana = float(np.median(datos_limpios))
    iqr = float(q3 - q1)

    return {"mediana": mediana, "q1": q1, "q3": q3, "iqr": iqr}
