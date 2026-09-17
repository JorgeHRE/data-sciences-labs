"""Pruebas unitarias para el módulo de análisis."""

import pandas as pd
from analisis import resumir_datos


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
