import pandas as pd


def optimizar_dtypes(
    df: pd.DataFrame,
    columnas_categoricas: list[str],
    columnas_fecha: list[str],
) -> pd.DataFrame:
    """
    Convierte columnas de un DataFrame a dtypes más eficientes en memoria.

    Parameters
    ----------
    df : pd.DataFrame
        DataFrame de entrada. No se modifica in-place.
    columnas_categoricas : list[str]
        Nombres de columnas a convertir a dtype 'category'
        (valores repetitivos de un conjunto cerrado, ej. GENDER, RACE).
    columnas_fecha : list[str]
        Nombres de columnas a convertir a datetime64 con pd.to_datetime
        (ej. BIRTHDATE, START). La resolución (ns, us, ...) la decide la
        versión de pandas: pandas 3 usa microsegundos al leer texto.

    Returns
    -------
    pd.DataFrame
        Copia de df con los dtypes convertidos.
    """
    df = df.copy()
    for col in columnas_categoricas:
        df[col] = df[col].astype("category")
    for col in columnas_fecha:
        df[col] = pd.to_datetime(df[col])
    return df
