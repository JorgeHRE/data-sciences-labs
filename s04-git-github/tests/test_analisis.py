"""Pruebas unitarias para el módulo de análisis."""

import numpy as np
import pandas as pd
from analisis import calcular_iqr, resumir_datos


def test_resumir_datos_basico():
    """Valida el cálculo de conteo y media en una serie simple."""
    df = pd.DataFrame({"medicion": [10.0, 20.0, 30.0]})
    res = resumir_datos(df)
    assert res["conteo"] == 3
    assert res["media"] == 20.0


def test_resumir_datos_vacio():
    """Valida el comportamiento ante un DataFrame vacío."""
    df = pd.DataFrame()
    res = resumir_datos(df)
    assert res["conteo"] == 0
    assert res["media"] == 0.0


def test_calcular_iqr_valores_conocidos():
    """Valida cálculo de IQR con una distribución simétrica conocida."""
    datos = pd.Series([10.0, 20.0, 30.0, 40.0, 50.0])
    res = calcular_iqr(datos)
    assert res["mediana"] == 30.0
    assert res["q1"] == 20.0
    assert res["q3"] == 40.0
    assert res["iqr"] == 20.0


def test_calcular_iqr_con_nulos():
    """Valida que la función ignore valores nulos (NaN)."""
    datos = pd.Series([10.0, np.nan, 20.0, 30.0, np.nan, 40.0, 50.0])
    res = calcular_iqr(datos)
    assert res["mediana"] == 30.0
    assert res["iqr"] == 20.0


def test_calcular_iqr_vacio():
    """Valida el comportamiento ante series vacías."""
    datos = pd.Series(dtype=float)
    res = calcular_iqr(datos)
    assert res["iqr"] == 0.0
    assert res["mediana"] == 0.0
