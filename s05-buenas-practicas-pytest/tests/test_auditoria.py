import numpy as np
import pandas as pd
import pytest

from clinlab.auditoria import (
    contar_duplicados,
    detectar_fechas_imposibles,
    marcar_valores_implausibles,
)
from clinlab.preprocesamiento import optimizar_dtypes


def test_marcar_valores_implausibles_caso_normal():
    serie = pd.Series([10, 20, 30, 40, 50])
    resultado = marcar_valores_implausibles(serie, minimo=15, maximo=45)
    esperado = pd.Series([True, False, False, False, True])
    pd.testing.assert_series_equal(resultado, esperado)


def test_marcar_valores_implausibles_rango_invertido_lanza_error():
    serie = pd.Series([10, 20, 30])
    with pytest.raises(ValueError):
        marcar_valores_implausibles(serie, minimo=30, maximo=20)


def test_detectar_fechas_imposibles_visita_antes_de_nacer(df_pacientes_malicioso):
    # Hallazgo lab 2: hay visitas registradas antes de la fecha de nacimiento
    # del paciente (p5: nace 2000-01-01, visita 1999-12-31).

    # ARRANGE: la fixture trae las fechas como strings sin parsear. Las
    # convertimos con optimizar_dtypes, igual que en el pipeline real, para
    # comparar fechas de verdad y no texto (que solo "acierta" por suerte
    # cuando el formato es YYYY-MM-DD).
    # Pedimos la fixture como argumento del test: pytest la busca en
    # conftest.py y nos pasa un DataFrame nuevo en cada test.
    df = optimizar_dtypes(
        df_pacientes_malicioso,
        columnas_categoricas=[],  # aquí no nos interesa ninguna categórica
        columnas_fecha=["fecha_nacimiento", "fecha_visita"],
    )

    # ACT: el orden de los argumentos importa: primero la visita, luego el
    # nacimiento (la función pregunta "¿visita < nacimiento?").
    resultado = detectar_fechas_imposibles(
        df["fecha_visita"],
        df["fecha_nacimiento"],
    )

    pd.testing.assert_series_equal(
        resultado,
        pd.Series([False, False, False, False, True, False, False, False], name=None),
    )


# Hallazgo lab 2: valores centinela (edad 180 en p6, HbA1c 0 en p7) que se
# hacen pasar por datos reales. Se detectan porque caen fuera del rango
# fisiológicamente posible, que elegimos nosotros al llamar a la función.
@pytest.mark.parametrize(
    # Los 4 parámetros que cambian entre casos; el resto del test es igual.
    "columna, minimo, maximo, esperado",
    [
        # Edad 0-120 años: 0 deja pasar recién nacidos; 120 queda cerca del
        # máximo humano verificado (122) y deja fuera el centinela 180 (p6).
        pytest.param(
            "edad_anios",
            0,
            120,
            [False, False, False, False, False, True, False, False],
            id="edad, centinela 180",
        ),
        # HbA1c 3-20 %: 0 % es fisiológicamente imposible (centinela en p7).
        pytest.param(
            "hba1c",
            3,
            20,
            [False, False, False, False, False, False, True, False],
            id="hba1c, centinela 0",
        ),
    ],
)
def test_marcar_valores_implausibles_centinelas(
    df_pacientes_malicioso, columna, minimo, maximo, esperado
):
    # La fixture y los parámetros llegan juntos: pytest resuelve la fixture
    # por su nombre y los otros 4 argumentos salen de cada pytest.param.

    # ACT: auditamos solo la columna de este caso.
    resultado = marcar_valores_implausibles(
        df_pacientes_malicioso[columna], minimo=minimo, maximo=maximo
    )

    # ASSERT: las 8 filas, para atrapar falsos negativos Y falsos positivos.
    # name=columna: aquí las dos comparaciones internas (< minimo, > maximo)
    # usan la MISMA Series, así que el resultado sí conserva su nombre
    # (al revés que en el test de fechas, donde eran dos Series distintas).
    pd.testing.assert_series_equal(
        resultado,
        pd.Series(esperado, name=columna),
    )


# Hueco detectado por cobertura (paso 8): auditoria.py línea 46
# (contar_duplicados) no tenía ningún test. El test fija el CONTRATO del
# docstring: se cuentan las copias sobrantes (criterio de .duplicated(),
# la primera aparición no cuenta), no todas las filas involucradas.
@pytest.mark.parametrize(
    "identificadores, duplicados_esperados",
    [
        # Tres apariciones del mismo id: 2 copias sobrantes. Es el caso que
        # distingue las dos definiciones (keep=False daría 3).
        pytest.param(pd.Series(["p1", "p1", "p1"]), 2, id="p1 tres veces"),
        pytest.param(pd.Series(["p1", "p2", "p3"]), 0, id="sin duplicados"),
        # dtype=str evita el aviso de pandas por Series vacía sin tipo.
        pytest.param(pd.Series([], dtype=str), 0, id="serie vacia"),
        # Decisión consciente: dos person_id faltantes repetidos SÍ cuentan
        # como duplicado (comportamiento actual de .duplicated()). Si algún
        # día se cambia, este caso obliga a hacerlo a propósito.
        pytest.param(pd.Series([np.nan, np.nan, "p1"]), 1, id="NaN repetido"),
    ],
)
def test_contar_duplicados(identificadores, duplicados_esperados):
    # ACT
    resultado = contar_duplicados(identificadores)

    # ASSERT: comparamos enteros exactos con ==. Aquí no hace falta
    # pytest.approx porque no son flotantes.
    assert resultado == duplicados_esperados
