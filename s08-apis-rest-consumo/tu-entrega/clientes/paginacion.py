"""Actividad 3: paginación de ClinicalTrials.gov con un generador.

Dos versiones de lo mismo para poder comparar su uso de memoria:
  - generar_estudios(): GENERADOR. Pide una página, entrega los estudios uno a
    uno con `yield` y, cuando se agotan, pide la siguiente. Nunca tiene en
    memoria más que la página actual.
  - acumular_estudios(): LISTA. Consume el generador completo y devuelve todo
    junto, así que la memoria crece con el número de registros.
"""

import time
from collections.abc import Iterator

import requests

URL = "https://clinicaltrials.gov/api/v2/studies"


def generar_estudios(
    condicion: str,
    maximo: int | None = None,
    tamano_pagina: int = 100,
    pausa: float = 0.3,
) -> Iterator[dict]:
    """Entrega estudios de uno en uno, siguiendo `nextPageToken` página a página.

    maximo: se detiene tras entregar este número de estudios (None = todos).
    pausa:  segundos de espera entre páginas, por cortesía con el servidor.
    """
    params = {"query.cond": condicion, "pageSize": tamano_pagina}
    entregados = 0

    while True:
        respuesta = requests.get(URL, params=params, timeout=(5, 30))
        respuesta.raise_for_status()
        pagina = respuesta.json()

        for estudio in pagina["studies"]:
            if maximo is not None and entregados >= maximo:
                return  # cortamos a mitad de página si ya llegamos al tope
            yield estudio  # <- aquí el generador "se pausa" hasta que lo vuelvan a pedir
            entregados += 1

        # La última página no trae nextPageToken: se acabó la paginación
        token = pagina.get("nextPageToken")
        if not token:
            return
        params["pageToken"] = token  # el cursor para pedir la página siguiente
        time.sleep(pausa)


def acumular_estudios(condicion: str, maximo: int | None = None, **kwargs) -> list[dict]:
    """Versión 'ingenua': guarda todos los estudios en una lista."""
    return list(generar_estudios(condicion, maximo, **kwargs))
