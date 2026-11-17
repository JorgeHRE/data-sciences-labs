"""Núcleo de operaciones S3 con manejo explícito de errores y paginación."""

from __future__ import annotations

import logging
from functools import lru_cache
from pathlib import Path

import boto3
from boto3.exceptions import S3UploadFailedError
from botocore.exceptions import ClientError, NoCredentialsError, PartialCredentialsError, ProfileNotFound

logger = logging.getLogger(__name__)


class S3UtilError(Exception):
    """Error base para operaciones de s3util."""


class LlaveNoExiste(S3UtilError):
    """El objeto (llave) solicitado no existe en el bucket (NoSuchKey / 404)."""


class BucketNoExiste(S3UtilError):
    """El bucket indicado no existe (NoSuchBucket)."""


class AccesoDenegado(S3UtilError):
    """Permiso insuficiente para la acción y ARN solicitados (AccessDenied / 403)."""


class PerfilInvalido(S3UtilError):
    """Perfil de AWS inexistente o sin credenciales válidas en la cadena."""


@lru_cache(maxsize=8)
def _cliente(perfil: str | None = None):
    """Devuelve un cliente S3 cacheado por nombre de perfil (o credential chain si es None)."""
    try:
        sesion = boto3.Session(profile_name=perfil)
        return sesion.client("s3")
    except (ProfileNotFound, NoCredentialsError, PartialCredentialsError) as exc:
        raise PerfilInvalido(
            f"No se pudo inicializar el perfil AWS {perfil!r}: verifica ~/.aws/config y credentials."
        ) from exc


def _traducir_client_error(exc: ClientError, accion: str, bucket: str, llave: str = "") -> S3UtilError:
    """Mapea ClientError de botocore a excepciones específicas con contexto de acción y ARN."""
    codigo = exc.response.get("Error", {}).get("Code", "Desconocido")
    es_nivel_bucket = accion == "s3:ListBucket"
    arn = f"arn:aws:s3:::{bucket}" if (es_nivel_bucket or not llave) else f"arn:aws:s3:::{bucket}/{llave}"
    ctx_prefijo = f" (prefijo={llave!r})" if (es_nivel_bucket and llave) else ""
    if codigo in ("NoSuchKey", "404"):
        return LlaveNoExiste(f"Llave no encontrada ({codigo}) en {accion} sobre {arn}{ctx_prefijo}.")
    if codigo == "NoSuchBucket":
        return BucketNoExiste(f"El bucket '{bucket}' no existe ({codigo}) al ejecutar {accion}.")
    if codigo in ("AccessDenied", "403"):
        return AccesoDenegado(
            f"Acceso denegado ({codigo}) al ejecutar '{accion}' sobre {arn}{ctx_prefijo}. "
            "Verifica los permisos en el IAM Policy Simulator (sesión 19) antes de ampliar la política."
        )
    return S3UtilError(f"Error S3 ({codigo}) al ejecutar '{accion}' sobre {arn}{ctx_prefijo}: {exc}")


def subir(ruta_local: str | Path, bucket: str, llave: str, perfil: str | None = None) -> None:
    """Sube un archivo local al bucket y llave indicados."""
    ruta = Path(ruta_local)
    if not ruta.is_file():
        raise FileNotFoundError(f"No existe el archivo local: {ruta}")
    try:
        _cliente(perfil).upload_file(str(ruta), bucket, llave)
        logger.info("Subido %s -> s3://%s/%s", ruta, bucket, llave)
    except S3UploadFailedError as exc:
        causa = exc.__cause__ or exc.__context__
        if isinstance(causa, ClientError):
            raise _traducir_client_error(causa, "s3:PutObject", bucket, llave) from exc
        if isinstance(causa, (NoCredentialsError, PartialCredentialsError)):
            raise PerfilInvalido("Sin credenciales válidas al subir a S3.") from exc
        raise S3UtilError(f"Fallo al subir {ruta} a s3://{bucket}/{llave}: {exc}") from exc
    except (NoCredentialsError, PartialCredentialsError) as exc:
        raise PerfilInvalido("Sin credenciales válidas al subir a S3.") from exc
    except ClientError as exc:
        raise _traducir_client_error(exc, "s3:PutObject", bucket, llave) from exc


def descargar(bucket: str, llave: str, ruta_local: str | Path, perfil: str | None = None) -> Path:
    """Descarga un objeto de S3 hacia ruta_local (crea directorios padre si faltan)."""
    ruta = Path(ruta_local)
    ruta.parent.mkdir(parents=True, exist_ok=True)
    try:
        _cliente(perfil).download_file(bucket, llave, str(ruta))
        logger.info("Descargado s3://%s/%s -> %s", bucket, llave, ruta)
        return ruta
    except (NoCredentialsError, PartialCredentialsError) as exc:
        raise PerfilInvalido("Sin credenciales válidas al descargar de S3.") from exc
    except ClientError as exc:
        raise _traducir_client_error(exc, "s3:GetObject", bucket, llave) from exc


def existe(bucket: str, llave: str, perfil: str | None = None) -> bool:
    """Devuelve True si el objeto existe, False ante 404 y lanza AccesoDenegado ante 403."""
    try:
        _cliente(perfil).head_object(Bucket=bucket, Key=llave)
        return True
    except (NoCredentialsError, PartialCredentialsError) as exc:
        raise PerfilInvalido("Sin credenciales válidas al consultar S3.") from exc
    except ClientError as exc:
        traducido = _traducir_client_error(exc, "s3:GetObject", bucket, llave)
        if isinstance(traducido, LlaveNoExiste):
            return False
        raise traducido from exc


def listar(bucket: str, prefijo: str = "", perfil: str | None = None) -> list[str]:
    """Lista todas las llaves bajo un prefijo usando el paginador de list_objects_v2."""
    try:
        paginador = _cliente(perfil).get_paginator("list_objects_v2")
        llaves: list[str] = []
        for pagina in paginador.paginate(Bucket=bucket, Prefix=prefijo):
            for obj in pagina.get("Contents", []):
                llaves.append(obj["Key"])
        return llaves
    except (NoCredentialsError, PartialCredentialsError) as exc:
        raise PerfilInvalido("Sin credenciales válidas al listar S3.") from exc
    except ClientError as exc:
        raise _traducir_client_error(exc, "s3:ListBucket", bucket, prefijo) from exc
