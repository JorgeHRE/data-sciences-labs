import numpy as np  # np.nan es la forma estándar de escribir "falta el dato"
import pandas as pd

from clinlab.preprocesamiento import optimizar_dtypes


def test_optimizar_dtypes_dataframe_vacio():
    # Hallazgo lab 2: El dataframe de entrada está vacío, pero aún así se deben convertir los dtypes de las columnas especificadas.
    df_vacio = pd.DataFrame(
        {
            "GENDER": [],
            "BIRTHDATE": [],
        }
    )

    resultado = optimizar_dtypes(
        df_vacio,
        columnas_categoricas=["GENDER"],
        columnas_fecha=["BIRTHDATE"],
    )

    assert list(resultado.columns) == ["GENDER", "BIRTHDATE"]
    assert isinstance(resultado["GENDER"].dtype, pd.CategoricalDtype)
    assert pd.api.types.is_datetime64_any_dtype(resultado["BIRTHDATE"])


def test_optimizar_dtypes_columna_entera_nan():
    # Hallazgo lab 2: una columna puede venir completamente vacía (todo NaN);
    # optimizar_dtypes no debe tronar y debe dejar los dtypes correctos.

    # ARRANGE: 3 filas (no 0) para cubrir un caso distinto al test anterior:
    # hay filas, pero ningún valor real en ellas.
    df_nan = pd.DataFrame(
        {
            "GENDER": [np.nan, np.nan, np.nan],  # categórica sin ningún valor
            "BIRTHDATE": [np.nan, np.nan, np.nan],  # fecha sin ningún valor
        }
    )

    # ACT: llamamos a la función igual que en producción.
    resultado = optimizar_dtypes(
        df_nan,
        columnas_categoricas=["GENDER"],
        columnas_fecha=["BIRTHDATE"],
    )

    # ASSERT 1: no se pierden filas. Convertir dtypes nunca debería borrar datos.
    assert len(resultado) == 3

    # ASSERT 2: el dtype es el correcto aunque no haya ningún valor.
    # isinstance / is_datetime64_any_dtype en vez de strings exactos, por la
    # lección del test anterior (la resolución [ns] vs [s] cambia entre versiones).
    assert isinstance(resultado["GENDER"].dtype, pd.CategoricalDtype)
    assert pd.api.types.is_datetime64_any_dtype(resultado["BIRTHDATE"])

    # ASSERT 3: los valores siguen siendo NaN, no se inventa nada.
    assert resultado["GENDER"].isna().all()
    assert resultado["BIRTHDATE"].isna().all()
