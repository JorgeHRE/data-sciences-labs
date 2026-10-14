"""Actividad 2: la consulta más simple posible a ClinicalTrials.gov v2.

Incluye las tres líneas que nunca se omiten en una petición HTTP:
  1. timeout            -> sin él, una red caída puede colgar el script para siempre
  2. params=            -> requests codifica espacios y acentos por nosotros
  3. raise_for_status() -> convierte un 4xx/5xx en excepción en vez de seguir
                           como si nada con una página de error
"""

import requests

URL = "https://clinicaltrials.gov/api/v2/studies"


def buscar_estudios(condicion: str, tamano: int = 5) -> dict:
    """Devuelve el JSON de la primera página de estudios para una condición."""
    respuesta = requests.get(
        URL,
        # (1) timeout: 5 s para conectar, 30 s para recibir la respuesta
        timeout=(5, 30),
        # (2) params=: requests arma ?query.cond=...&pageSize=... y lo codifica
        params={"query.cond": condicion, "pageSize": tamano, "countTotal": "true"},
    )
    # (3) falla de inmediato si el servidor respondió 4xx o 5xx
    respuesta.raise_for_status()
    return respuesta.json()


def obtener_estudio(nct_id: str) -> dict:
    """Devuelve un estudio concreto por su identificador NCT."""
    respuesta = requests.get(f"{URL}/{nct_id}", timeout=(5, 30))
    respuesta.raise_for_status()
    return respuesta.json()


if __name__ == "__main__":
    datos = buscar_estudios("cáncer gástrico")  # con acento y espacio: params= lo maneja
    print("Total:", datos["totalCount"])
    for estudio in datos["studies"]:
        ident = estudio["protocolSection"]["identificationModule"]
        print(ident["nctId"], "-", ident["briefTitle"][:70])
