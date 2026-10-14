"""Configuración común de las pruebas: BLOQUEA toda conexión de red real.

Cualquier prueba que intente salir a internet falla con `RedBloqueada`, así
queda demostrado en el propio código (y no solo apagando el wifi) que la suite
no depende de la red. Las respuestas del "servidor" las simula `responses`.
"""

import socket

import pytest

from clientes.base import ClienteHTTP


class RedBloqueada(RuntimeError):
    """Se intentó abrir una conexión de red real durante una prueba."""


@pytest.fixture(autouse=True)
def sin_red(monkeypatch):
    def bloqueado(*args, **kwargs):
        raise RedBloqueada("la prueba intentó usar la red real (debe simularse con `responses`)")

    # DNS y conexión TCP: sin estas dos no se puede llegar a ningún servidor
    monkeypatch.setattr(socket, "getaddrinfo", bloqueado)
    monkeypatch.setattr(socket.socket, "connect", bloqueado)


@pytest.fixture
def cliente():
    """Cliente sin caché, con 3 reintentos y SIN esperas (backoff=0) para que las pruebas sean instantáneas."""
    with ClienteHTTP(directorio_cache=None, reintentos=3, backoff=0) as c:
        yield c
