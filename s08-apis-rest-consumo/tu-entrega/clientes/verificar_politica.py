"""Actividad 4: comprueba la política de reintentos contra un servidor LOCAL.

Las APIs públicas no se pueden forzar a devolver 429 o 500 sin abusar de ellas,
así que levantamos un servidor falso en 127.0.0.1 que responde lo que le
programamos, y contamos cuántas peticiones recibe realmente por ruta.

Se ejecuta con:  uv run python -m clientes.verificar_politica
"""

import json
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

import requests

from clientes.base import ClienteHTTP

# ruta -> lista de respuestas (estado, cabeceras) en orden; la última se repite
GUION = {
    "/200": [(200, {})],
    "/429-luego-200": [(429, {"Retry-After": "1"}), (200, {})],
    "/503-luego-200": [(503, {}), (200, {})],
    "/500-siempre": [(500, {})],
    "/404": [(404, {})],
    "/400": [(400, {})],
    "/401": [(401, {})],
}
visitas: dict[str, int] = {}


class Handler(BaseHTTPRequestHandler):
    def _responder(self):
        ruta = self.path.split("?")[0]
        n = visitas.get(ruta, 0)
        visitas[ruta] = n + 1
        pasos = GUION[ruta]
        estado, cabeceras = pasos[min(n, len(pasos) - 1)]
        cuerpo = json.dumps({"estado": estado}).encode()
        self.send_response(estado)
        for k, v in cabeceras.items():
            self.send_header(k, v)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(cuerpo)))
        self.end_headers()
        self.wfile.write(cuerpo)

    do_GET = do_POST = _responder

    def log_message(self, *args):  # silenciar el log del servidor
        pass


def caso(cliente, base, ruta, metodo="GET"):
    visitas.pop(ruta, None)
    t0 = time.perf_counter()
    try:
        if metodo == "GET":
            r = cliente.get(base + ruta)
        else:  # POST directo a la sesión, para ver que NO se reintenta
            r = cliente.session.post(base + ruta, timeout=cliente.timeout)
            r.raise_for_status()
        resultado = f"OK {r.status_code}"
    except requests.HTTPError as e:
        resultado = f"HTTPError {e.response.status_code}"
    dt = time.perf_counter() - t0
    print(f"{metodo:<4} {ruta:<16} -> {resultado:<14} peticiones al servidor={visitas[ruta]}  ({dt:.1f} s)")


if __name__ == "__main__":
    servidor = HTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=servidor.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{servidor.server_port}"

    # backoff chico para que la demo no tarde; reintentos=3 => máx. 4 intentos
    with ClienteHTTP(directorio_cache=None, reintentos=3, backoff=0.1) as c:
        print("=== Política de reintentos (sin caché) ===")
        for ruta in ("/200", "/429-luego-200", "/503-luego-200", "/500-siempre",
                     "/400", "/401", "/404"):
            caso(c, base, ruta)
        caso(c, base, "/500-siempre", metodo="POST")  # no idempotente: no se reintenta

    print("\n=== Caché: solo se guardan las respuestas 200 ===")
    with tempfile.TemporaryDirectory() as tmp:
        with ClienteHTTP(directorio_cache=tmp, reintentos=1, backoff=0.1) as c:
            visitas.clear()
            r1, r2 = c.get(base + "/200"), c.get(base + "/200")
            print(f"/200 pedida 2 veces: peticiones al servidor={visitas['/200']}, "
                  f"2.ª desde caché={r2.from_cache}")
            for ruta in ("/404", "/500-siempre"):
                visitas.pop(ruta, None)
                for _ in range(2):
                    try:
                        c.get(base + ruta)
                    except requests.HTTPError:
                        pass
                print(f"{ruta} pedida 2 veces: peticiones al servidor={visitas[ruta]} "
                      f"(si se hubiera cacheado, serían menos)")
    servidor.shutdown()
