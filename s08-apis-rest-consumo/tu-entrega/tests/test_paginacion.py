"""Actividad 8: el generador de paginación, con dos páginas simuladas."""

import responses
from responses import matchers

from clientes.paginacion import URL, generar_estudios

PAGINA_1 = {"studies": [{"n": 1}, {"n": 2}], "nextPageToken": "TOKEN2"}
PAGINA_2 = {"studies": [{"n": 3}]}  # la última página no trae nextPageToken


def _registrar_paginas():
    responses.add(responses.GET, URL, json=PAGINA_1)
    responses.add(responses.GET, URL, json=PAGINA_2)


@responses.activate
def test_recorre_todas_las_paginas_siguiendo_el_token(cliente):
    _registrar_paginas()

    estudios = list(generar_estudios("gastric cancer", pausa=0, cliente=cliente))

    assert [e["n"] for e in estudios] == [1, 2, 3]
    assert len(responses.calls) == 2
    assert "pageToken=TOKEN2" in responses.calls[1].request.url  # la 2.ª petición usa el cursor


@responses.activate
def test_es_perezoso_no_pide_nada_hasta_que_se_le_pide(cliente):
    _registrar_paginas()

    gen = generar_estudios("gastric cancer", pausa=0, cliente=cliente)
    assert len(responses.calls) == 0  # crearlo no hace peticiones

    next(gen)
    assert len(responses.calls) == 1  # pedir el primero trae solo la página 1
    next(gen)
    assert len(responses.calls) == 1  # el segundo sigue en la misma página
    next(gen)
    assert len(responses.calls) == 2  # el tercero obliga a pedir la página 2


@responses.activate
def test_maximo_corta_a_mitad_de_pagina_y_no_pide_la_siguiente(cliente):
    _registrar_paginas()

    estudios = list(generar_estudios("gastric cancer", maximo=1, pausa=0, cliente=cliente))

    assert [e["n"] for e in estudios] == [1]
    assert len(responses.calls) == 1
