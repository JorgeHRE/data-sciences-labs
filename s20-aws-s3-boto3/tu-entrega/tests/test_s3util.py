"""Pruebas unitarias y de integración para el módulo s3util."""

from __future__ import annotations

from pathlib import Path

import pytest
from botocore.stub import Stubber

from s3util import (
    AccesoDenegado,
    BucketNoExiste,
    LlaveNoExiste,
    PerfilInvalido,
    descargar,
    existe,
    listar,
    subir,
)
from s3util.nucleo import _cliente


def test_subir_y_descargar_ida_y_vuelta(bucket_moto: str, tmp_path: Path) -> None:
    origen = tmp_path / "muestra.txt"
    origen.write_text("dato sintetico de prueba", encoding="utf-8")
    subir(origen, bucket_moto, "tmp/muestra.txt")

    destino = tmp_path / "bajado" / "muestra.txt"
    resultado = descargar(bucket_moto, "tmp/muestra.txt", destino)
    assert resultado == destino
    assert destino.read_text(encoding="utf-8") == "dato sintetico de prueba"


def test_subir_archivo_local_inexistente(bucket_moto: str, tmp_path: Path) -> None:
    with pytest.raises(FileNotFoundError):
        subir(tmp_path / "no_existe.csv", bucket_moto, "tmp/no_existe.csv")


def test_existe_true_y_false(bucket_moto: str, tmp_path: Path) -> None:
    archivo = tmp_path / "a.txt"
    archivo.write_text("ok", encoding="utf-8")
    subir(archivo, bucket_moto, "raw/a.txt")

    assert existe(bucket_moto, "raw/a.txt") is True
    assert existe(bucket_moto, "raw/faltante.txt") is False


def test_descargar_llave_no_existe_404_y_nosuchkey(bucket_moto: str, tmp_path: Path) -> None:
    # Camino 1: download_file usa head_object internamente -> código HTTP "404"
    with pytest.raises(LlaveNoExiste) as exc_404:
        descargar(bucket_moto, "raw/no_existe.csv", tmp_path / "out.csv")
    assert "404" in str(exc_404.value)

    # Camino 2: código XML "NoSuchKey" (como el que devuelve get_object)
    cliente = _cliente(None)
    with Stubber(cliente) as stubber:
        stubber.add_client_error("head_object", service_error_code="NoSuchKey", http_status_code=404)
        with pytest.raises(LlaveNoExiste) as exc_nsk:
            descargar(bucket_moto, "raw/no_existe.csv", tmp_path / "out2.csv")
        assert "NoSuchKey" in str(exc_nsk.value)


def test_listar_y_subir_bucket_no_existe(bucket_moto: str, tmp_path: Path) -> None:
    with pytest.raises(BucketNoExiste):
        listar("bucket-que-no-existe-jamas", "raw/")

    archivo = tmp_path / "muestra.txt"
    archivo.write_text("contenido", encoding="utf-8")
    with pytest.raises(BucketNoExiste) as exc_subir:
        subir(archivo, "bucket-que-no-existe-jamas", "tmp/muestra.txt")
    assert "s3:PutObject" in str(exc_subir.value)


def test_access_denied_en_existe_descargar_subir_y_listar_con_stubber(tmp_path: Path) -> None:
    archivo = tmp_path / "local.txt"
    archivo.write_text("dato", encoding="utf-8")
    cliente = _cliente(None)
    with Stubber(cliente) as stubber:
        # En existe(), un 403 JAMÁS debe devolver False
        stubber.add_client_error("head_object", service_error_code="403", http_status_code=403)
        with pytest.raises(AccesoDenegado) as exc_existe:
            existe("omop-tesis-test", "raw/privado.csv")
        assert "s3:GetObject" in str(exc_existe.value)
        assert "arn:aws:s3:::omop-tesis-test/raw/privado.csv" in str(exc_existe.value)
        assert "Simulator" in str(exc_existe.value)

        stubber.add_client_error("head_object", service_error_code="AccessDenied", http_status_code=403)
        with pytest.raises(AccesoDenegado):
            descargar("omop-tesis-test", "raw/privado.csv", tmp_path / "no_importa.csv")

        # En subir(), upload_file envuelve ClientError en S3UploadFailedError -> debe traducirse a AccesoDenegado
        stubber.add_client_error("put_object", service_error_code="AccessDenied", http_status_code=403)
        with pytest.raises(AccesoDenegado) as exc_subir:
            subir(archivo, "omop-tesis-test", "tmp/bloqueado.txt")
        assert "s3:PutObject" in str(exc_subir.value)
        assert "arn:aws:s3:::omop-tesis-test/tmp/bloqueado.txt" in str(exc_subir.value)

        # En listar(), s3:ListBucket es a nivel de bucket (sin /raw/ pegado al ARN)
        stubber.add_client_error("list_objects_v2", service_error_code="AccessDenied", http_status_code=403)
        with pytest.raises(AccesoDenegado) as exc_listar:
            listar("omop-tesis-test", "raw/")
        msg_listar = str(exc_listar.value)
        assert "s3:ListBucket" in msg_listar
        assert "arn:aws:s3:::omop-tesis-test " in msg_listar
        assert "arn:aws:s3:::omop-tesis-test/raw/" not in msg_listar


def test_perfil_invalido() -> None:
    with pytest.raises(PerfilInvalido):
        listar("cualquier-bucket", "", perfil="perfil_inexistente_123")


def test_listar_con_prefijo_y_prefijo_vacio(bucket_moto: str, tmp_path: Path) -> None:
    f = tmp_path / "f.txt"
    f.write_text("x", encoding="utf-8")
    subir(f, bucket_moto, "raw/a.csv")
    subir(f, bucket_moto, "raw/b.csv")
    subir(f, bucket_moto, "staging/c.parquet")

    assert sorted(listar(bucket_moto, "raw/")) == ["raw/a.csv", "raw/b.csv"]
    assert listar(bucket_moto, "inexistente/") == []


def test_listar_pagina_1500_objetos_y_control_truncado(bucket_moto: str) -> None:
    cliente = _cliente(None)
    for i in range(1500):
        cliente.put_object(Bucket=bucket_moto, Key=f"tmp/pag/{i:04d}.txt", Body=b"x")

    # Prueba de control: una sola llamada a list_objects_v2 corta en 1 000 y marca IsTruncated=True
    una_pagina = cliente.list_objects_v2(Bucket=bucket_moto, Prefix="tmp/pag/")
    assert len(una_pagina["Contents"]) == 1000
    assert una_pagina["IsTruncated"] is True

    # listar() debe devolver los 1 500 completos usando el paginador
    llaves = listar(bucket_moto, "tmp/pag/")
    assert len(llaves) == 1500
    assert llaves[0] == "tmp/pag/0000.txt"
    assert llaves[-1] == "tmp/pag/1499.txt"


BUCKET_REAL = "omop-tesis-jhr-2026"
PERFIL_REAL = "tesis"


@pytest.mark.integracion
def test_integracion_subir_existe_listar_descargar(tmp_path: Path) -> None:
    llave = "tmp/pruebas/integracion_ida_vuelta.txt"
    origen = tmp_path / "origen.txt"
    origen.write_text("prueba integracion s20", encoding="utf-8")
    try:
        subir(origen, BUCKET_REAL, llave, perfil=PERFIL_REAL)
        assert existe(BUCKET_REAL, llave, perfil=PERFIL_REAL) is True
        assert llave in listar(BUCKET_REAL, "tmp/pruebas/", perfil=PERFIL_REAL)

        destino = tmp_path / "destino.txt"
        descargar(BUCKET_REAL, llave, destino, perfil=PERFIL_REAL)
        assert destino.read_text(encoding="utf-8") == "prueba integracion s20"
    finally:
        _cliente(PERFIL_REAL).delete_object(Bucket=BUCKET_REAL, Key=llave)


@pytest.mark.integracion
def test_integracion_existe_false_en_llave_inexistente() -> None:
    assert existe(BUCKET_REAL, "tmp/pruebas/seguro_no_existe_xyz.txt", perfil=PERFIL_REAL) is False


@pytest.mark.integracion
def test_integracion_descargar_llave_no_existe(tmp_path: Path) -> None:
    with pytest.raises(LlaveNoExiste):
        descargar(BUCKET_REAL, "tmp/pruebas/seguro_no_existe_xyz.txt", tmp_path / "x.txt", perfil=PERFIL_REAL)


@pytest.mark.integracion
def test_integracion_listar_raw_real() -> None:
    llaves = listar(BUCKET_REAL, "raw/synthea/fecha_carga=2026-11-17/", perfil=PERFIL_REAL)
    assert len(llaves) == 15
