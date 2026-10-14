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

import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlsplit

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


class AdaptadorContador(HTTPAdapter):
    """Cuenta las peticiones que REALMENTE salen a la red (actividad 9).

    Esta clase está debajo de la caché, así que un acierto de caché nunca llega
    aquí. `urllib3` hace los reintentos dentro de `send()` y deja la cuenta en
    `respuesta.raw.retries.history` (una entrada por reintento), por eso:

        peticiones reales de este envío = 1 + len(history)

    Si la conexión falla del todo (excepción), la historia se pierde y solo se
    puede asegurar 1 petición: en ese caso el conteo es un MÍNIMO.
    """

    def __init__(self, *args, registrar=None, **kwargs):
        super().__init__(*args, **kwargs)
        self._registrar = registrar

    def send(self, request, **kwargs):
        host = urlsplit(request.url).netloc
        try:
            respuesta = super().send(request, **kwargs)
        except Exception:
            self._registrar({"evento": "red", "host": host, "peticiones": 1, "estado": "excepcion"})
            raise
        reintentos = getattr(respuesta.raw, "retries", None)
        extra = len(reintentos.history) if reintentos is not None else 0
        self._registrar({"evento": "red", "host": host, "peticiones": 1 + extra,
                         "estado": respuesta.status_code})
        return respuesta


class ClienteHTTP:
    def __init__(
        self,
        directorio_cache: str | Path | None = "data/cache",
        expira: timedelta = timedelta(days=1),
        reintentos: int = 4,
        backoff: float = 1.0,
        timeout: tuple[float, float] = (5, 30),
        user_agent: str = "lab08-cliente-biomedico (uso academico)",
        registro: str | Path | None = None,
    ):
        """
        directorio_cache: carpeta de la caché en disco (None = sin caché).
        reintentos:       máximo de reintentos tras el primer intento.
        backoff:          factor del backoff exponencial (esperas de b*2^(n-1) s).
        timeout:          (segundos para conectar, segundos para leer la respuesta).
        registro:         archivo .jsonl donde se anota cada evento (None = solo en memoria).
        """
        self.timeout = timeout
        # Contadores de la actividad 9: peticiones que salieron a la red (incluye
        # reintentos) frente a respuestas servidas por la caché sin tocar la red.
        self.reales = 0
        self.de_cache = 0
        self._registro = Path(registro) if registro else None
        if self._registro:
            self._registro.parent.mkdir(parents=True, exist_ok=True)

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
        adaptador = AdaptadorContador(max_retries=retry, registrar=self._anotar)
        self.session.mount("https://", adaptador)
        self.session.mount("http://", adaptador)
        self.session.headers["User-Agent"] = user_agent

    def _anotar(self, evento: dict) -> None:
        """Suma al contador y, si hay archivo de registro, añade una línea JSON."""
        if evento["evento"] == "red":
            self.reales += evento["peticiones"]
        else:
            self.de_cache += 1
        if self._registro:
            evento = {"momento": datetime.now(timezone.utc).isoformat(timespec="seconds"), **evento}
            with self._registro.open("a", encoding="utf-8") as f:
                f.write(json.dumps(evento, ensure_ascii=False) + "\n")

    def get(self, url: str, params: dict | None = None) -> requests.Response:
        """GET con timeout, reintentos y caché. Lanza HTTPError si el resultado final es 4xx/5xx."""
        respuesta = self.session.get(url, params=params, timeout=self.timeout)
        if getattr(respuesta, "from_cache", False):  # la caché respondió: cero red
            self._anotar({"evento": "cache", "host": urlsplit(url).netloc, "peticiones": 0})
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
