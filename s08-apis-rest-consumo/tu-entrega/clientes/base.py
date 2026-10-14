"""Actividad 4: cliente HTTP robusto, reutilizable por las tres APIs.

Reúne en un solo lugar la política de red del laboratorio:
  - timeout en TODAS las peticiones (no se puede olvidar: lo pone la clase)
  - una Session reutilizada (una conexión TCP/TLS abierta para muchas peticiones)
  - reintentos con backoff exponencial, solo para GET y solo para 429 y 5xx
  - respeto al encabezado Retry-After
  - caché en disco (SQLite) que NUNCA guarda respuestas de error

Cómo encajan las piezas (el orden importa):

    get() -> CachedSession.send() -> [¿está en caché? sí: devuelve, sin red]
                                  -> HTTPAdapter(max_retries=Retry) -> red

  La caché de requests-cache envuelve al adaptador: un acierto de caché no toca
  la red ni los reintentos, y solo las respuestas 200 finales se guardan, así
  que un 429 o un 500 intermedio jamás se cachea.
"""

from datetime import timedelta
from pathlib import Path

import requests
from requests.adapters import HTTPAdapter
from requests_cache import CachedSession
from urllib3.util.retry import Retry

# Códigos que SÍ merecen reintento: fallos transitorios del servidor o petición
# de calma. Los demás 4xx (400, 401, 404...) son errores nuestros: repetir la
# misma petición daría exactamente el mismo error.
CODIGOS_REINTENTABLES = (429, 500, 502, 503, 504)

# Solo métodos idempotentes: repetirlos no cambia el estado del servidor.
METODOS_IDEMPOTENTES = frozenset({"GET", "HEAD", "OPTIONS"})


class ClienteHTTP:
    def __init__(
        self,
        directorio_cache: str | Path | None = "data/cache",
        expira: timedelta = timedelta(days=1),
        reintentos: int = 4,
        backoff: float = 1.0,
        timeout: tuple[float, float] = (5, 30),
        user_agent: str = "lab08-cliente-biomedico (uso academico)",
    ):
        """
        directorio_cache: carpeta de la caché en disco (None = sin caché).
        reintentos:       máximo de reintentos tras el primer intento.
        backoff:          factor del backoff exponencial (esperas de b*2^(n-1) s).
        timeout:          (segundos para conectar, segundos para leer la respuesta).
        """
        self.timeout = timeout

        if directorio_cache is None:
            self.session = requests.Session()
        else:
            Path(directorio_cache).mkdir(parents=True, exist_ok=True)
            self.session = CachedSession(
                cache_name=str(Path(directorio_cache) / "http_cache"),
                backend="sqlite",
                expire_after=expira,
                allowable_codes=(200,),     # solo se cachean respuestas correctas
                allowable_methods=("GET",),
            )

        retry = Retry(
            total=reintentos,
            backoff_factor=backoff,
            status_forcelist=CODIGOS_REINTENTABLES,
            allowed_methods=METODOS_IDEMPOTENTES,
            respect_retry_after_header=True,  # si el servidor dice cuánto esperar, se le hace caso
            raise_on_status=False,  # al agotar intentos devuelve la última respuesta;
        )                           # get() la convierte en HTTPError con raise_for_status
        adaptador = HTTPAdapter(max_retries=retry)
        self.session.mount("https://", adaptador)
        self.session.mount("http://", adaptador)
        self.session.headers["User-Agent"] = user_agent

    def get(self, url: str, params: dict | None = None) -> requests.Response:
        """GET con timeout, reintentos y caché. Lanza HTTPError si el resultado final es 4xx/5xx."""
        respuesta = self.session.get(url, params=params, timeout=self.timeout)
        respuesta.raise_for_status()
        return respuesta

    def get_json(self, url: str, params: dict | None = None) -> dict:
        return self.get(url, params).json()

    def close(self) -> None:
        self.session.close()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()
