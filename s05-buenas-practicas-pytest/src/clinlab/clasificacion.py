def clasificar_grupo_etario(edad_anios: float) -> str:
    """
    Clasifica una edad en una etapa clínica.

    Parameters
    ----------
    edad_anios : float
        Edad del paciente, en años.

    Returns
    -------
    str
        Una de: "pediátrico" (0-17 años), "adulto" (18-64 años),
        "adulto mayor" (65 años o más).

    Raises
    ------
    ValueError
        Si edad_anios es negativa.
    """
    if edad_anios < 0:
        raise ValueError("La edad no puede ser negativa")
    if edad_anios < 18:
        return "pediátrico"
    elif edad_anios < 65:
        return "adulto"
    else:
        return "adulto mayor"
