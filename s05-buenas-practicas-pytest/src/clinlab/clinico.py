from typing import Literal

# Límite superior fisiológico para validación de edad.
# Récord humano verificado: Jeanne Calment (122 años y 164 días, Guinness World Records).
# Se fija en 130 años para admitir fracciones de año y posibles futuros récords,
# previniendo el underflow numérico (0.9938 ** edad -> 0.0) descubierto por Hypothesis.
EDAD_MAXIMA_ANIOS: float = 130.0


# Limite superior fisiológico para validación de creatinina sérica.
# Récord humano verificado: 73.8 mg/dL (Persaud C, et al. Highest Recorded Serum Creatinine. Case Rep Nephrol. 2021;2021:6048919. doi: 10.1155/2021/6048919)
# Se fija en 100 mg/dL para admitir posibles futuros récords, previniendo el underflow numérico (max(Scr/κ, 1) ** -1.2) descubierto por Hypothesis.
# El notebook (sección 6) usa 73.8 para marcar valores clínicamente inverosímiles; aquí el límite es más amplio porque solo rechaza entradas imposibles de procesar.
CREATININA_MAXIMA_MG_DL: float = 100


def calcular_egfr_ckd_epi(
    creatinina_mg_dl: float,
    edad_anios: float,
    sexo: Literal["F", "M"],
) -> float:
    """
    Calcula la tasa de filtrado glomerular estimada (eGFR) con la ecuación
    CKD-EPI 2021 de creatinina (sin ajuste por raza).

    Fórmula y coeficientes verificados en:
    https://www.kidney.org/professionals/ckd-epi-creatinine-equation-2021

        eGFR = 142 x min(Scr/κ, 1)^α x max(Scr/κ, 1)^(-1.200)
               x 0.9938^edad x (1.012 si sexo == "F")

        κ = 0.7 (F) / 0.9 (M)
        α = -0.241 (F) / -0.302 (M)

    Parameters
    ----------
    creatinina_mg_dl : float
        Creatinina sérica, en mg/dL.
    edad_anios : float
        Edad del paciente, en años.
    sexo : {"F", "M"}
        Sexo biológico del paciente, tal como se codifica en GENDER
        de Synthea.

    Returns
    -------
    float
        eGFR estimado, en mL/min/1.73 m^2.

    Raises
    ------
    ValueError
        Si creatinina_mg_dl <= 0 o edad_anios < 0.
    ValueError
        Si edad_anios > EDAD_MAXIMA_ANIOS.
    ValueError
        Si creatinina_mg_dl > CREATININA_MAXIMA_MG_DL.
    """
    if creatinina_mg_dl <= 0:
        raise ValueError("creatinina_mg_dl debe ser > 0")
    if creatinina_mg_dl > CREATININA_MAXIMA_MG_DL:
        raise ValueError(
            f"creatinina_mg_dl supera el límite máximo permitido: {CREATININA_MAXIMA_MG_DL} mg/dL"
        )

    if edad_anios < 0:
        raise ValueError("edad_anios debe ser >= 0")
    if edad_anios > EDAD_MAXIMA_ANIOS:
        raise ValueError(
            f"edad_anios supera el límite máximo permitido: {EDAD_MAXIMA_ANIOS} años"
        )

    if sexo == "F":
        kappa = 0.7
        alpha = -0.241
        factor_sexo = 1.012
    elif sexo == "M":
        kappa = 0.9
        alpha = -0.302
        factor_sexo = 1.0
    else:
        raise ValueError('sexo debe ser "F" o "M"')

    min_ratio = min(creatinina_mg_dl / kappa, 1)
    max_ratio = max(creatinina_mg_dl / kappa, 1)

    egfr = (
        142
        * (min_ratio**alpha)
        * (max_ratio ** (-1.200))
        * (0.9938**edad_anios)
        * factor_sexo
    )
    return egfr
