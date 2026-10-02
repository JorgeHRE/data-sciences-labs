from typing import Literal

import pandas as pd


def unir_con_validacion(
    izquierda: pd.DataFrame,
    derecha: pd.DataFrame,
    llave_izquierda: str,
    llave_derecha: str,
    how: Literal["left", "right", "outer", "inner"] = "left",
    validate: Literal["1:1", "m:1", "1:m", "m:m"] = "m:1",
) -> pd.DataFrame:
    """
    Une dos tablas clínicas validando la cardinalidad esperada del cruce.

    Delega en pd.DataFrame.merge, cuyo propio parámetro `validate` lanza
    un MergeError si la cardinalidad declarada no se cumple (ej. si hay
    llaves duplicadas del lado que debería ser único en un merge 'm:1').
    Esta función no necesita capturar ni relanzar ese error: confiamos
    en la garantía que ya ofrece pandas.

    Parameters
    ----------
    izquierda : pd.DataFrame
        Tabla del lado izquierdo del merge (ej. observations).
    derecha : pd.DataFrame
        Tabla del lado derecho del merge (ej. encounters o patients).
    llave_izquierda : str
        Nombre de la columna llave en `izquierda` (ej. 'ENCOUNTER').
    llave_derecha : str
        Nombre de la columna llave en `derecha` (ej. 'Id').
    how : str, default "left"
        Tipo de join, igual que en pd.DataFrame.merge.
    validate : str, default "m:1"
        Cardinalidad esperada del cruce ('1:1', 'm:1', '1:m', 'm:m'),
        igual que en pd.DataFrame.merge.

    Returns
    -------
    pd.DataFrame
        Resultado del merge.

    Raises
    ------
    pandas.errors.MergeError
        Si la cardinalidad real del cruce no coincide con `validate`.
    """
    merge_result = izquierda.merge(
        derecha,
        left_on=llave_izquierda,
        right_on=llave_derecha,
        how=how,
        validate=validate,
    )
    return merge_result
