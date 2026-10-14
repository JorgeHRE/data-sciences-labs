"""Actividad 9: ¿el contador de peticiones reales dice la verdad?

Se compara contra la VERDAD: un servidor local que cuenta cuántas peticiones
le llegan de verdad por el socket. Si el contador del cliente coincide con el
del servidor en cada caso (reintentos incluidos), la medición es confiable.

Se ejecuta con:  uv run python -m clientes.verificar_contador
"""

import tempfile
import threading

import requests

from clientes.base import ClienteHTTP
from clientes.verificar_politica import Handler, visitas
from http.server import HTTPServer


def intentar(cliente, url):
    try:
        cliente.get(url)
    except requests.HTTPError:
        pass


if __name__ == "__main__":
    servidor = HTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=servidor.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{servidor.server_port}"

    # (ruta, veces que se pide) -> sin caché, para ver solo los reintentos
    casos = [("/200", 1), ("/429-luego-200", 1), ("/500-siempre", 1), ("/404", 1)]
    print(f"{'caso':<22}{'servidor recibió':>18}{'contador reales':>17}{'¿coincide?':>12}")
    todo_ok = True
    for ruta, veces in casos:
        visitas.clear()
        with ClienteHTTP(directorio_cache=None, reintentos=3, backoff=0.1) as c:
            for _ in range(veces):
                intentar(c, base + ruta)
            ok = c.reales == visitas[ruta]
            todo_ok &= ok
            print(f"{ruta:<22}{visitas[ruta]:>18}{c.reales:>17}{'sí' if ok else 'NO':>12}")

    # Con caché: 5 pedidos iguales -> 1 viaje a la red + 4 aciertos de caché
    visitas.clear()
    with tempfile.TemporaryDirectory() as tmp:
        with ClienteHTTP(directorio_cache=tmp, reintentos=3, backoff=0.1) as c:
            for _ in range(5):
                intentar(c, base + "/200")
            ok = (c.reales, c.de_cache, visitas["/200"]) == (1, 4, 1)
            todo_ok &= ok
            print(f"\n5 × /200 con caché: servidor recibió {visitas['/200']}, "
                  f"reales={c.reales}, de caché={c.de_cache}  -> {'OK' if ok else 'FALLA'}")
    servidor.shutdown()
    print("\nRESULTADO:", "el contador coincide con el servidor" if todo_ok else "DISCREPANCIA")
