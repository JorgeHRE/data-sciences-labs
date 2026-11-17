"""Demo controlada de presigned URL vigente (200) y caducada (403) censurando credenciales."""

from __future__ import annotations

import re
import subprocess
import sys
import time
from pathlib import Path

RAIZ_ENTREGA = Path(__file__).resolve().parents[1]
if str(RAIZ_ENTREGA) not in sys.path:
    sys.path.insert(0, str(RAIZ_ENTREGA))

from s3util.nucleo import _cliente  # noqa: E402

BUCKET = "omop-tesis-jhr-2026"
PERFIL = "tesis"
LLAVE = "tmp/presigned/hola.txt"


def censurar_url(url: str) -> str:
    """Reemplaza X-Amz-Credential en la URL para no exponer el Access Key ID."""
    return re.sub(
        r"X-Amz-Credential=[^&]+",
        "X-Amz-Credential=<ACCESS_KEY_ID>%2F<FECHA>%2Fus-east-2%2Fs3%2Faws4_request",
        url,
    )


def main() -> None:
    cliente = _cliente(PERFIL)
    cliente.put_object(
        Bucket=BUCKET,
        Key=LLAVE,
        Body=b"Objeto sintetico de prueba para presigned URL (Lab 20)\n",
        ContentType="text/plain",
    )

    url_1h = cliente.generate_presigned_url(
        "get_object",
        Params={"Bucket": BUCKET, "Key": LLAVE},
        ExpiresIn=3600,
    )
    url_10s = cliente.generate_presigned_url(
        "get_object",
        Params={"Bucket": BUCKET, "Key": LLAVE},
        ExpiresIn=10,
    )

    print("=== 1. Prueba curl con presigned URL vigente (ExpiresIn=3600) ===")
    r_ok = subprocess.run(["curl", "-sS", "-i", url_1h], capture_output=True, text=True, check=False)
    print(r_ok.stdout.strip())

    print("\nEsperando 12 segundos para que caduque la URL de prueba (ExpiresIn=10)...")
    time.sleep(12)

    print("\n=== 2. Prueba curl con presigned URL caducada (ExpiresIn=10) ===")
    r_exp = subprocess.run(["curl", "-sS", "-i", url_10s], capture_output=True, text=True, check=False)
    print(r_exp.stdout.strip())
    print("\nURL caducada (censurada):")
    print(censurar_url(url_10s))


if __name__ == "__main__":
    main()
