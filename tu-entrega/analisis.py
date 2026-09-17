"""Módulo de procesamiento para el Laboratorio 04."""

import numpy as np
import pandas as pd


def resumir_datos(df: pd.DataFrame) -> dict:
    """Calcula métricas resumen de una serie de datos."""
    return {
        "conteo": int(len(df)),
        "media": float(np.mean(df.iloc[:, 0])) if not df.empty else 0.0,
    }
