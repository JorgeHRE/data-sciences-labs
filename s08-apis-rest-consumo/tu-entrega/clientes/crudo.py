"""Actividad 5: guardar las respuestas CRUDAS antes de transformar nada.

Cada respuesta se guarda en su propio archivo JSON dentro de un "sobre" con los
metadatos que hacen reproducible la descarga:

    {
      "fuente":         de qué API viene,
      "descargado_en":  fecha y hora (UTC) en que el servidor respondió,
      "desde_cache":    True si la respuesta se sirvió de la caché local,
      "url":            URL completa realmente solicitada,
      "parametros":     parámetros de la consulta tal como se enviaron,
      "http_status":    código de estado,
      "respuesta":      el JSON que devolvió la API, SIN modificar
    }

Los metadatos van al lado de los datos, nunca mezclados con ellos.
"""

import json
import re
from datetime import datetime, timezone
from pathlib import Path

import requests

DIRECTORIO_RAW = Path("data/raw")


def _momento_de_descarga(respuesta: requests.Response) -> datetime:
    """Si vino de la caché, la fecha real de descarga es la de cuando se guardó, no 'ahora'."""
    creada = getattr(respuesta, "created_at", None)
    if getattr(respuesta, "from_cache", False) and creada is not None:
        return creada if creada.tzinfo else creada.replace(tzinfo=timezone.utc)
    return datetime.now(timezone.utc)


def _slug(texto: str) -> str:
    """'gastric cancer' -> 'gastric-cancer' para usarlo en nombres de archivo."""
    return re.sub(r"[^a-zA-Z0-9]+", "-", texto).strip("-").lower()[:40]


def guardar_crudo(
    fuente: str,
    etiqueta: str,
    respuesta: requests.Response,
    parametros: dict,
    directorio: Path = DIRECTORIO_RAW,
) -> Path:
    """Guarda una respuesta HTTP en data/raw/<fuente>/<fecha>_<etiqueta>.json y devuelve la ruta."""
    momento = _momento_de_descarga(respuesta)
    sobre = {
        "fuente": fuente,
        "descargado_en": momento.isoformat(timespec="seconds"),
        "desde_cache": bool(getattr(respuesta, "from_cache", False)),
        "url": respuesta.url,
        "parametros": parametros,
        "http_status": respuesta.status_code,
        "respuesta": respuesta.json(),  # tal cual, sin transformar
    }
    carpeta = directorio / fuente
    carpeta.mkdir(parents=True, exist_ok=True)
    ruta = carpeta / f"{momento:%Y%m%d}_{_slug(etiqueta)}.json"
    ruta.write_text(json.dumps(sobre, ensure_ascii=False), encoding="utf-8")
    return ruta
