import pytest

from clinlab.clinico import calcular_egfr_ckd_epi


@pytest.mark.parametrize(
    "creatinina_mg_dl, edad_anios, sexo, egfr_esperado",
    [
        pytest.param(1.0, 30, "M", 104, id="Hombre, creatinina normal"),
        pytest.param(0.9, 30, "F", 88.0, id="Mujer, creatinina normal"),
        pytest.param(1.5, 75, "M", 48.0, id="Hombre, creatinina alta"),
        pytest.param(1.3, 70, "F", 44.0, id="Mujer, creatinina alta"),
        pytest.param(0.4, 20, "M", 160.0, id="Hombre, creatinina baja"),
        pytest.param(0.5, 25, "F", 133.0, id="Mujer, creatinina baja"),
        pytest.param(4.0, 55, "F", 13.0, id="Mujer, erc avanzada"),
        pytest.param(6.0, 60, "M", 10.0, id="Hombre, erc avanzada"),
    ],
)
def test_calcular_egfr_ckd_epi_contra_referencia_kidney_org(
    creatinina_mg_dl, edad_anios, sexo, egfr_esperado
):
    """
    Test for calculating eGFR using the CKD-EPI equation against reference values from kidney.org.
    (https://www.kidney.org/professionals/gfr_calculator + CKD-EPI Creatinine (2021), Standardized Assays: Yes, Adjust for BSA: No).
    """
    result = calcular_egfr_ckd_epi(creatinina_mg_dl, edad_anios, sexo)
    assert result == pytest.approx(
        egfr_esperado, rel=0.01, abs=0.5
    )  # tolerancia relativa del 1%


# Hueco detectado por cobertura (paso 8): clinico.py líneas 43, 45 y 56
# (las validaciones de entrada) nunca se ejecutaban; la tabla de kidney.org
# solo usa entradas válidas. Sin la validación de edad, una edad negativa
# daría un eGFR "normal" en silencio en vez de tronar.
# Cada caso tiene UNA sola entrada inválida y las demás válidas, para saber
# qué validación se está probando.
@pytest.mark.parametrize(
    "creatinina_mg_dl, edad_anios, sexo",
    [
        pytest.param(0.0, 50, "F", id="creatinina cero"),
        pytest.param(-1.0, 50, "F", id="creatinina negativa"),
        # Valor implausible: la creatinina más alta reportada en la literatura
        # es 73.8 mg/dL (Persaud C, et al. Highest Recorded Serum Creatinine.
        # Case Rep Nephrol. 2021;2021:6048919. doi: 10.1155/2021/6048919).
        # Se fija en 100 mg/dL para admitir posibles futuros récords,
        # previniendo el underflow numérico (max(Scr/κ, 1) ** -1.2)
        # descubierto por Hypothesis.
        pytest.param(350.0, 50, "F", id="creatinina demasiado alta"),
        pytest.param(1, -5, "M", id="edad negativa"),
        # Hallazgo de Hypothesis: edad=119810 daba eGFR 0.0 (underflow).
        pytest.param(1, 119810.0, "M", id="edad imposible"),
        pytest.param(1, 30, "f", id="sexo invalido"),
    ],
)
def test_calcular_egfr_ckd_epi_entrada_invalida_lanza_error(
    creatinina_mg_dl, edad_anios, sexo
):
    # Sin match: basta con que se lance ValueError. Como cada caso tiene
    # una sola entrada mala, el error solo puede venir de esa validación
    # (salvo que otra validación también estuviera mal escrita).
    with pytest.raises(ValueError):
        calcular_egfr_ckd_epi(creatinina_mg_dl, edad_anios, sexo)
