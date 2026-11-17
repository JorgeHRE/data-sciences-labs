"""Demostración real de paginación (> 1 000 objetos) en S3 con s3util.listar (Act. 5)."""

from __future__ import annotations

import argparse
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

RAIZ_ENTREGA = Path(__file__).resolve().parents[1]
if str(RAIZ_ENTREGA) not in sys.path:
    sys.path.insert(0, str(RAIZ_ENTREGA))

from s3util import listar  # noqa: E402
from s3util.nucleo import _cliente  # noqa: E402

BUCKET = "omop-tesis-jhr-2026"
PERFIL = "tesis"
PREFIJO = "tmp/paginacion/"
TOTAL_OBJETOS = 1200


def subir_y_listar(n: int = TOTAL_OBJETOS) -> None:
    """Sube N objetos diminutos en paralelo y verifica el conteo con s3util.listar."""
    cliente = _cliente(PERFIL)

    def _subir_uno(idx: int) -> None:
        cliente.put_object(Bucket=BUCKET, Key=f"{PREFIJO}obj_{idx:04d}.txt", Body=b"ok")

    with ThreadPoolExecutor(max_workers=16) as pool:
        list(pool.map(_subir_uno, range(n)))

    llaves = listar(BUCKET, PREFIJO, perfil=PERFIL)
    print(f"Subidos: {n} | Listados por s3util.listar: {len(llaves)}")
    assert len(llaves) == n, f"Se esperaban {n} objetos y se listaron {len(llaves)}"


def limpiar_sin_version_id() -> None:
    """Borra objetos actuales bajo tmp/paginacion/ en lotes de 1 000 (sin VersionId, D7)."""
    cliente = _cliente(PERFIL)
    llaves = listar(BUCKET, PREFIJO, perfil=PERFIL)
    borrados = 0
    for i in range(0, len(llaves), 1000):
        lote = [{"Key": k} for k in llaves[i : i + 1000]]
        resp = cliente.delete_objects(Bucket=BUCKET, Delete={"Objects": lote, "Quiet": True})
        borrados += len(lote) - len(resp.get("Errors", []))
    print(f"Delete markers creados en {PREFIJO}: {borrados} (la regla R2 expira versiones)")


def purgar_versiones_tmp(prefijo_tmp: str = "tmp/") -> None:
    """Elimina todas las versiones y delete markers bajo tmp/ con VersionId en lotes de 1 000."""
    cliente = _cliente(PERFIL)
    paginador = cliente.get_paginator("list_object_versions")
    por_borrar: list[dict[str, str]] = []
    for pagina in paginador.paginate(Bucket=BUCKET, Prefix=prefijo_tmp):
        for ver in pagina.get("Versions", []):
            por_borrar.append({"Key": ver["Key"], "VersionId": ver["VersionId"]})
        for dm in pagina.get("DeleteMarkers", []):
            por_borrar.append({"Key": dm["Key"], "VersionId": dm["VersionId"]})
    borrados = 0
    for i in range(0, len(por_borrar), 1000):
        lote = por_borrar[i : i + 1000]
        resp = cliente.delete_objects(Bucket=BUCKET, Delete={"Objects": lote, "Quiet": True})
        borrados += len(lote) - len(resp.get("Errors", []))
    print(f"Versiones + delete markers purgados en {prefijo_tmp}: {borrados}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Demo de paginación S3 (> 1 000 objetos)")
    parser.add_argument("--limpiar", action="store_true", help="Borrar objetos de tmp/paginacion/")
    parser.add_argument(
        "--purgar-tmp",
        action="store_true",
        help="Purgar todas las versiones y delete markers bajo tmp/ (con VersionId)",
    )
    args = parser.parse_args()
    if args.purgar_tmp:
        purgar_versiones_tmp()
    elif args.limpiar:
        limpiar_sin_version_id()
    else:
        subir_y_listar()
