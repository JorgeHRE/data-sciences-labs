import pytest

from clinlab.clasificacion import clasificar_grupo_etario


def test_clasificar_grupo_etario_caso_normal():
    definir_edad = 18
    resultado = clasificar_grupo_etario(definir_edad)
    assert resultado == "adulto"


def test_clasificar_grupo_etario_edad_negativa_lanza_error():
    definir_edad = -5
    with pytest.raises(ValueError):
        clasificar_grupo_etario(definir_edad)


# Hueco detectado por cobertura (paso 8): clasificacion.py líneas 24 y 28
# (ramas "pediátrico" y "adulto mayor") nunca se ejecutaban; el único caso
# normal usaba edad 18. Probamos cada límite por ambos lados, porque ahí
# viven los bugs tipo "< 66 en vez de < 65".
@pytest.mark.parametrize(
    "edad_anios, grupo_esperado",
    [
        pytest.param(0, "pediátrico", id="0 anios, recien nacido"),
        pytest.param(1, "pediátrico", id="1 anio, lactante"),
        pytest.param(17, "pediátrico", id="17 anios, adolescente"),
        pytest.param(18, "adulto", id="18 anios, adulto"),
        pytest.param(19, "adulto", id="19 anios, adulto"),
        pytest.param(64, "adulto", id="64 anios, adulto"),
        pytest.param(65, "adulto mayor", id="65 anios, adulto mayor"),
        pytest.param(66, "adulto mayor", id="66 anios, adulto mayor"),
    ],
)
def test_clasificar_grupo_etario_limites(edad_anios, grupo_esperado):
    # ACT: cada caso de la tabla llega aquí por separado.
    resultado = clasificar_grupo_etario(edad_anios)

    # ASSERT: comparamos strings exactos; si el límite se corre un año,
    # algún caso de la tabla recibe el grupo vecino y falla.
    assert resultado == grupo_esperado
