"""Casos fabricados: los datos reales salieron casi limpios y no ejercitan estas ramas."""

import pandas as pd
import pytest

from auditoria_obs.nucleo import auditar

T = pd.Timestamp("2025-01-01T08:00:00Z")


@pytest.fixture
def obs() -> pd.DataFrame:
    filas = [
        # (PATIENT, DATE, CODE, VALUE, UNITS, anio)
        ("p1", T, "8480-6", "50", "mm[Hg]", 2025),           # límite inferior: plausible
        ("p2", T, "8480-6", "250", "mm[Hg]", 2025),          # límite superior: plausible
        ("p3", T, "8480-6", "49.9", "mm[Hg]", 2025),         # implausible bajo
        ("p4", T, "8480-6", "texto", "mm[Hg]", 2025),        # no numérico (NaN)
        ("p5", T, "8480-6", "120", "mmHg", 2025),            # unidad inesperada
        ("p5", T, "8480-6", "120", "mmHg", 2025),            # duplicado exacto de la anterior
        ("p6", T, "38483-4", "21", "mg/dL", 2024),           # creatinina implausible alta
        ("p7", T, "25428-4", "Negative", "{nominal}", 2025),  # código fuera de RANGOS
    ]
    return pd.DataFrame(filas, columns=["PATIENT", "DATE", "CODE", "VALUE", "UNITS", "anio"])


def test_una_fila_por_anio_y_codigo_e_ignora_codigos_ajenos(obs):
    r = auditar(obs)
    assert sorted(zip(r.anio, r.codigo)) == [(2024, "38483-4"), (2025, "8480-6")]


def test_conteos_de_sistolica(obs):
    s = auditar(obs).set_index("codigo").loc["8480-6"]
    assert s.filas == 6
    assert s.implausibles == 1          # solo 49.9: los límites son inclusivos
    assert s.no_numericos == 1          # "texto" se cuenta aparte, no como implausible
    assert s.unidad_inesperada == 2
    assert s.duplicados == 1            # la copia cuenta, la original no
    assert s.pct_implausibles == pytest.approx(16.667)


def test_creatinina_alta(obs):
    c = auditar(obs).set_index("codigo").loc["38483-4"]
    assert (c.implausibles, c.pct_implausibles) == (1, 100.0)


def test_no_modifica_la_entrada(obs):
    copia = obs.copy()
    auditar(obs)
    pd.testing.assert_frame_equal(obs, copia)
