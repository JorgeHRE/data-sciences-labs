"""Actividad 2: romper a propósito cada práctica y observar qué pasa.

Se ejecuta con:  uv run python -m clientes.fallos_provocados
"""

import requests

URL = "https://clinicaltrials.gov/api/v2/studies"


def fallo_1_sin_raise_for_status():
    """Pedimos un NCT inexistente y NO llamamos a raise_for_status()."""
    print("=== Fallo 1: sin raise_for_status(), NCT inexistente ===")
    r = requests.get(f"{URL}/NCT99999999", timeout=(5, 30))
    print("status_code:", r.status_code)
    print("Content-Type:", r.headers.get("Content-Type"))
    print("cuerpo (primeros 200 car.):", r.text[:200])
    try:
        datos = r.json()
        print("r.json() NO falló, devolvió:", datos)
        # Aquí el código "sigue como si nada": buscar una clave que no existe
        print(datos["protocolSection"])
    except Exception as e:
        print(f"-> {type(e).__name__}: {e}")


def fallo_2_params_a_mano():
    """Concatenamos la cadena de consulta nosotros mismos, con espacios y acento."""
    print("\n=== Fallo 2: concatenar la URL a mano ===")
    url_mala = URL + "?query.cond=cáncer gástrico&pageSize=1"
    try:
        r = requests.get(url_mala, timeout=(5, 30))
        print("URL que se envió:", r.request.url)
        print("status_code:", r.status_code)
        print("cuerpo (primeros 200 car.):", r.text[:200])
    except Exception as e:
        print(f"-> {type(e).__name__}: {e}")

    print("\n--- Misma búsqueda con params= ---")
    r = requests.get(
        URL, params={"query.cond": "cáncer gástrico", "pageSize": 1, "countTotal": "true"},
        timeout=(5, 30),
    )
    print("URL que se envió:", r.request.url)
    print("status_code:", r.status_code, "| totalCount:", r.json().get("totalCount"))

    print("\n--- Para comparar: lo mismo en inglés ---")
    r = requests.get(
        URL, params={"query.cond": "gastric cancer", "pageSize": 1, "countTotal": "true"},
        timeout=(5, 30),
    )
    print("totalCount:", r.json().get("totalCount"))


def fallo_2b_ampersand():
    """Un valor con '&' rompe la concatenación manual: el servidor lo lee como otro parámetro."""
    print("\n=== Fallo 2b: valor con '&' al concatenar a mano ===")
    farmacos = "capecitabine & oxaliplatin"
    r = requests.get(
        URL + f"?query.cond=gastric cancer&query.intr={farmacos}&pageSize=1&countTotal=true",
        timeout=(5, 30),
    )
    print("URL enviada:", r.request.url)
    print("status_code:", r.status_code, "| cuerpo:", r.text[:200])

    print("\n--- Con params= ---")
    r = requests.get(
        URL,
        params={"query.cond": "gastric cancer", "query.intr": farmacos,
                "pageSize": 1, "countTotal": "true"},
        timeout=(5, 30),
    )
    print("URL enviada:", r.request.url)
    print("status_code:", r.status_code, "| totalCount:", r.json().get("totalCount"))


if __name__ == "__main__":
    fallo_1_sin_raise_for_status()
    fallo_2_params_a_mano()
    fallo_2b_ampersand()
