# Bono del laboratorio: pruebas basadas en PROPIEDADES con Hypothesis.
#
# Diferencia con test_clinico.py:
#   - parametrize: TÚ eliges 8 casos y su resultado exacto (kidney.org).
#   - Hypothesis: TÚ describes una regla que debe cumplirse SIEMPRE ("el eGFR
#     es positivo") y Hypothesis genera cientos de entradas buscando una que
#     la rompa. Si la encuentra, la "encoge" (shrinking) hasta el ejemplo más
#     simple posible y te lo muestra.
# No reemplaza a la tabla de referencia: la tabla verifica que el número sea
# CORRECTO; la propiedad verifica que el comportamiento sea SENSATO en
# entradas que a nadie se le ocurrió probar.

from hypothesis import given
from hypothesis import strategies as st

from clinlab.clinico import (
    CREATININA_MAXIMA_MG_DL,
    EDAD_MAXIMA_ANIOS,
    calcular_egfr_ckd_epi,
)

# --- Estrategias: de dónde saca Hypothesis los valores ------------------------
# st.floats genera números decimales. Por defecto incluiría NaN e infinito, que
# no son entradas clínicas; por eso se desactivan.

# Creatinina en mg/dL: la función exige > 0 (exclude_min=True deja fuera el 0).
creatininas = st.floats(
    min_value=0,
    exclude_min=True,
    max_value=CREATININA_MAXIMA_MG_DL,
    allow_nan=False,
    allow_infinity=False,
)

# Edad en años: la función exige >= 0.
edades = st.floats(
    min_value=0,
    max_value=EDAD_MAXIMA_ANIOS,  # límite superior para evitar underflow numérico
    allow_nan=False,
    allow_infinity=False,
)

# Sexo: solo dos valores posibles; sampled_from elige uno de la lista.
sexos = st.sampled_from(["F", "M"])


# --- Propiedad 1: el eGFR siempre es positivo ---------------------------------
# @given conecta cada parámetro con su estrategia: Hypothesis llama al test
# muchas veces (100 por defecto) con valores distintos cada vez.
@given(creatinina=creatininas, edad=edades, sexo=sexos)
def test_egfr_siempre_es_positivo(creatinina: float, edad: float, sexo: str) -> None:
    egfr = calcular_egfr_ckd_epi(creatinina, edad, sexo)
    assert egfr > 0


# --- Propiedad 2: a mayor creatinina, menor eGFR (todo lo demás fijo) ---------
@given(creatinina1=creatininas, creatinina2=creatininas, edad=edades, sexo=sexos)
def test_egfr_disminuye_con_creatinina(
    creatinina1: float, creatinina2: float, edad: float, sexo: str
) -> None:
    # Si creatinina1 < creatinina2, entonces eGFR1 > eGFR2.
    if creatinina1 < creatinina2:
        egfr1 = calcular_egfr_ckd_epi(creatinina1, edad, sexo)
        egfr2 = calcular_egfr_ckd_epi(creatinina2, edad, sexo)
        assert egfr1 > egfr2


# --- Qué documentar (lo pide el enunciado) -----------------------------------
# Documentar cada propiedad con un comentario que explique la regla que se está verificando.
# Por ejemplo, la primera propiedad dice que el eGFR siempre es positivo,
# y la segunda propiedad dice que a mayor creatinina, menor eGFR,
# manteniendo edad y sexo constantes.
# Esto ayuda a entender el propósito de cada prueba y
# facilita la lectura del código.
