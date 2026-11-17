"""Fixtures compartidos para pruebas unitarias (moto/Stubber) e integración."""

from __future__ import annotations

import boto3
import pytest
from moto import mock_aws

from s3util.nucleo import _cliente


@pytest.fixture(autouse=True)
def aislar_cliente_y_credenciales(request: pytest.FixtureRequest, monkeypatch: pytest.MonkeyPatch):
    """Limpia la caché de clientes y fija credenciales falsas en pruebas unitarias."""
    _cliente.cache_clear()
    if "integracion" not in request.keywords:
        monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
        monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
        monkeypatch.setenv("AWS_SECURITY_TOKEN", "testing")
        monkeypatch.setenv("AWS_SESSION_TOKEN", "testing")
        monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-2")
        monkeypatch.setenv("AWS_CONFIG_FILE", "/dev/null")
        monkeypatch.setenv("AWS_SHARED_CREDENTIALS_FILE", "/dev/null")
    yield
    _cliente.cache_clear()


@pytest.fixture()
def bucket_moto():
    """Crea un bucket S3 simulado en memoria con moto."""
    nombre = "omop-tesis-test"
    with mock_aws():
        _cliente.cache_clear()
        s3 = boto3.client("s3", region_name="us-east-2")
        s3.create_bucket(
            Bucket=nombre,
            CreateBucketConfiguration={"LocationConstraint": "us-east-2"},
        )
        yield nombre
