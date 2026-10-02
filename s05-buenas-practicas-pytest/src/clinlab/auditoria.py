import pandas as pd


def detectar_fechas_imposibles(
    fecha_visita: pd.Series,
    fecha_nacimiento: pd.Series,
) -> pd.Series:
    """
    Detecta visitas registradas antes de la fecha de nacimiento del paciente.

    Parameters
    ----------
    fecha_visita : pd.Series
        Fechas de inicio de encuentro clínico (dtype datetime64).
    fecha_nacimiento : pd.Series
        Fechas de nacimiento del paciente, alineadas por índice con
        fecha_visita (dtype datetime64).

    Returns
    -------
    pd.Series
        Serie booleana: True donde la fecha de visita es anterior
        al nacimiento (dato imposible).
    """
    return fecha_visita < fecha_nacimiento


def contar_duplicados(identificadores: pd.Series) -> int:
    """
    Cuenta cuántas entradas duplicadas hay en una serie de identificadores.

    Usa el mismo criterio que .duplicated(): cada aparición de un valor
    repetido cuenta como duplicado, EXCEPTO la primera (la original no
    se cuenta a sí misma).

    Parameters
    ----------
    identificadores : pd.Series
        Serie de identificadores a auditar (ej. person_id).

    Returns
    -------
    int
        Número de entradas duplicadas encontradas.
    """
    return int(identificadores.duplicated().sum())


def marcar_valores_implausibles(
    valores: pd.Series,
    minimo: float,
    maximo: float,
) -> pd.Series:
    """
    Marca valores fuera de un rango fisiológico plausible.

    Un valor es implausible si es estrictamente menor que `minimo` o
    estrictamente mayor que `maximo` (los límites mismos SÍ se consideran
    plausibles).

    Parameters
    ----------
    valores : pd.Series
        Mediciones a auditar (ej. presión sistólica en mmHg,
        frecuencia cardíaca en lpm). Las unidades dependen del
        analito — documentalas en el caller, no acá.
    minimo : float
        Límite inferior plausible (inclusive).
    maximo : float
        Límite superior plausible (inclusive).

    Returns
    -------
    pd.Series
        Serie booleana: True donde el valor es implausible.
    """
    if minimo > maximo:
        raise ValueError(
            f"El límite inferior ({minimo}) no puede ser mayor que el superior ({maximo})."
        )
    mascara_implausibles = (valores < minimo) | (valores > maximo)
    return mascara_implausibles
