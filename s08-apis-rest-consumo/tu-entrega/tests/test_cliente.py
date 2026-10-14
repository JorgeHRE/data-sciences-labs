"""Actividad 8: la política de red del cliente, probada contra respuestas SIMULADAS."""

import pytest
import requests
import responses

from clientes.base import ClienteHTTP

URL = "https://api.ejemplo.test/estudios"
OK = {"studies": [{"id": 1}]}


@responses.activate
def test_200_con_json_valido(cliente):
    responses.add(responses.GET, URL, json=OK, status=200)

    assert cliente.get_json(URL) == OK
    assert len(responses.calls) == 1


@responses.activate
def test_429_seguido_de_200_reintenta_y_termina_bien(cliente):
    responses.add(responses.GET, URL, status=429, headers={"Retry-After": "0"})
    responses.add(responses.GET, URL, json=OK, status=200)

    assert cliente.get_json(URL) == OK
    assert len(responses.calls) == 2  # el 429 y el reintento exitoso


@responses.activate
def test_503_seguido_de_200_tambien_reintenta(cliente):
    responses.add(responses.GET, URL, status=503)
    responses.add(responses.GET, URL, json=OK, status=200)

    assert cliente.get_json(URL) == OK
    assert len(responses.calls) == 2


@responses.activate
def test_500_persistente_se_rinde_tras_los_intentos(cliente):
    responses.add(responses.GET, URL, status=500)  # se repite siempre

    with pytest.raises(requests.HTTPError) as error:
        cliente.get(URL)

    assert error.value.response.status_code == 500
    assert len(responses.calls) == 4  # 1 intento original + 3 reintentos, y se rinde


@pytest.mark.parametrize("codigo", [400, 401, 404])
@responses.activate
def test_los_4xx_no_se_reintentan(cliente, codigo):
    responses.add(responses.GET, URL, status=codigo)

    with pytest.raises(requests.HTTPError) as error:
        cliente.get(URL)

    assert error.value.response.status_code == codigo
    assert len(responses.calls) == 1  # una sola petición: repetirla daría el mismo error


@responses.activate
def test_un_post_no_se_reintenta_aunque_sea_500(cliente):
    responses.add(responses.POST, URL, status=500)

    respuesta = cliente.session.post(URL, timeout=cliente.timeout)

    assert respuesta.status_code == 500
    assert len(responses.calls) == 1  # solo los métodos idempotentes se reintentan


@responses.activate
def test_toda_peticion_lleva_timeout(cliente):
    responses.add(responses.GET, URL, json=OK)

    cliente.get(URL)

    assert responses.calls[0].request.req_kwargs["timeout"] == (5, 30)


def test_respeta_retry_after(cliente):
    """`responses` simula los reintentos pero NUNCA duerme, así que la espera real no se puede
    observar aquí (se comprobó con un servidor local en la actividad 4: esperó 1.0 s).
    Lo que sí se prueba: el cliente está configurado para obedecer Retry-After y urllib3
    lo interpreta como segundos de espera."""
    from urllib3.response import HTTPResponse

    reintento = cliente.session.get_adapter("https://api.ejemplo.test/").max_retries

    assert reintento.respect_retry_after_header is True
    assert reintento.get_retry_after(HTTPResponse(status=429, headers={"Retry-After": "7"})) == 7


def test_la_politica_de_reintentos_esta_configurada_como_se_justifico(cliente):
    """Complementa las pruebas de comportamiento: la configuración coincide con la tabla de la bitácora."""
    from clientes.base import CODIGOS_REINTENTABLES, METODOS_IDEMPOTENTES

    reintento = cliente.session.get_adapter("https://api.ejemplo.test/").max_retries

    assert set(reintento.status_forcelist) == set(CODIGOS_REINTENTABLES)
    assert {429, 500, 503} <= set(CODIGOS_REINTENTABLES)
    assert not {400, 401, 404} & set(CODIGOS_REINTENTABLES)  # los 4xx del cliente no se reintentan
    assert reintento.allowed_methods == METODOS_IDEMPOTENTES and "POST" not in reintento.allowed_methods


@responses.activate
def test_un_200_se_guarda_en_cache_y_no_vuelve_a_la_red(tmp_path):
    responses.add(responses.GET, URL, json=OK)

    with ClienteHTTP(directorio_cache=tmp_path, backoff=0) as c:
        primera, segunda = c.get(URL), c.get(URL)

    assert len(responses.calls) == 1  # la segunda salió de la caché
    assert primera.from_cache is False and segunda.from_cache is True


@pytest.mark.parametrize("codigo", [404, 500])
@responses.activate
def test_los_errores_no_se_guardan_en_cache(tmp_path, codigo):
    responses.add(responses.GET, URL, status=codigo)

    with ClienteHTTP(directorio_cache=tmp_path, reintentos=0, backoff=0) as c:
        for _ in range(2):
            with pytest.raises(requests.HTTPError):
                c.get(URL)

    assert len(responses.calls) == 2  # si se hubiera cacheado, la 2.ª no llegaría a la red


def test_la_red_real_esta_bloqueada(cliente):
    """Comprobación del propio bloqueo: sin `responses`, cualquier salida a internet falla."""
    from tests.conftest import RedBloqueada

    with pytest.raises(RedBloqueada):
        cliente.get("https://clinicaltrials.gov/api/v2/studies")
