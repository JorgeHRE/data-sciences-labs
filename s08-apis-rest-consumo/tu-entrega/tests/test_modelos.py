"""Actividad 8: validación con Pydantic, con datos mínimos incrustados (no dependen de data/)."""

import copy

import pytest
import responses
from pydantic import ValidationError

from clientes.modelos import EstudioCT, ReporteFDA, ResumenPubMed

ESTUDIO = {
    "protocolSection": {
        "identificationModule": {"nctId": "NCT01234567", "briefTitle": "Estudio de prueba"},
        "statusModule": {
            "overallStatus": "RECRUITING",
            "startDateStruct": {"date": "2024-07-15"},
            "completionDateStruct": {"date": "2026-12"},
        },
        "designModule": {"enrollmentInfo": {"count": 120}},
        "contactsLocationsModule": {"locations": [{"country": "Mexico"}, {"country": "Spain"}, {"country": "Mexico"}]},
    }
}
REPORTE = {
    "safetyreportid": "100001",
    "receivedate": "20240312",
    "patient": {"patientonsetage": "8", "patientonsetageunit": "800",
                "reaction": [{"reactionmeddrapt": "Diarrhoea"}, {"reactionmeddrapt": "Nausea"}]},
}
RESUMEN = {"uid": "12345678", "title": "Un artículo", "pubdate": "2026 Mar 3"}


def con(base, **cambios):
    """Copia de `base` con una ruta anidada modificada: con(ESTUDIO, ("protocolSection", "designModule"), {...})"""
    copia = copy.deepcopy(base)
    for ruta, valor in cambios.items():
        *padres, ultimo = ruta.split(".")
        destino = copia
        for p in padres:
            destino = destino[p]
        if valor is ...:
            del destino[ultimo]
        else:
            destino[ultimo] = valor
    return copia


# --- ClinicalTrials.gov ----------------------------------------------------
def test_estudio_valido_se_normaliza():
    e = EstudioCT.desde_crudo(ESTUDIO)
    assert e.nct_id == "NCT01234567" and e.inscritos == 120
    assert e.paises == ["Mexico", "Spain"]  # sin duplicados y ordenados


def test_falta_el_identificador_se_rechaza():
    with pytest.raises(ValidationError, match="nct_id"):
        EstudioCT.desde_crudo(con(ESTUDIO, **{"protocolSection.identificationModule.nctId": ...}))


def test_inscritos_negativos_se_rechazan():
    with pytest.raises(ValidationError, match="inscritos"):
        EstudioCT.desde_crudo(con(ESTUDIO, **{"protocolSection.designModule.enrollmentInfo.count": -5}))


def test_sin_inscritos_es_valido_y_queda_en_none():
    e = EstudioCT.desde_crudo(con(ESTUDIO, **{"protocolSection.designModule": {}}))
    assert e.inscritos is None  # dato ausente != dato inválido


def test_estado_fuera_del_conjunto_oficial_se_rechaza():
    with pytest.raises(ValidationError, match="estado"):
        EstudioCT.desde_crudo(con(ESTUDIO, **{"protocolSection.statusModule.overallStatus": "EN_PROGRESO"}))


def test_fin_anterior_al_inicio_se_rechaza():
    malo = con(ESTUDIO, **{"protocolSection.statusModule.completionDateStruct": {"date": "2023-01-10"}})
    with pytest.raises(ValidationError, match="anterior"):
        EstudioCT.desde_crudo(malo)


def test_fin_con_solo_mes_del_mismo_mes_de_inicio_es_valido():
    """Inicio 2024-07-15 y fin '2024-07': el fin cuenta como fin de mes, no como día 1."""
    ok = con(ESTUDIO, **{"protocolSection.statusModule.completionDateStruct": {"date": "2024-07"}})
    assert EstudioCT.desde_crudo(ok).fin_txt == "2024-07"


# --- openFDA -----------------------------------------------------------------
def test_reporte_valido_convierte_decadas_a_anios():
    assert ReporteFDA.desde_crudo(REPORTE).edad_anios == 80.0  # "8" décadas


@pytest.mark.parametrize("cambio, motivo", [
    ({"patient.patientonsetage": "150", "patient.patientonsetageunit": "801"}, "edad_anios"),
    ({"receivedate": "2024-03-12"}, "fecha_recepcion"),
    ({"receivedate": "20990101"}, "futuro"),
    ({"patient.reaction": []}, "reacciones"),
    ({"safetyreportid": ...}, "id_reporte"),
])
def test_reportes_malformados_se_rechazan(cambio, motivo):
    with pytest.raises(ValidationError, match=motivo):
        ReporteFDA.desde_crudo(con(REPORTE, **cambio))


# --- PubMed ----------------------------------------------------------------
def test_resumen_valido():
    assert ResumenPubMed.desde_crudo(RESUMEN).anio == 2026


def test_articulo_con_numero_impreso_del_anio_siguiente_es_valido():
    from datetime import date
    siguiente = f"{date.today().year + 1} Feb 1"
    assert ResumenPubMed.desde_crudo(con(RESUMEN, pubdate=siguiente)).anio == date.today().year + 1


@pytest.mark.parametrize("cambio, motivo", [
    ({"pubdate": "1750 Jan 1"}, "anio"),
    ({"pubdate": "sin fecha"}, "anio"),
    ({"uid": ...}, "uid"),
    ({"uid": "abc"}, "uid"),
])
def test_resumenes_malformados_se_rechazan(cambio, motivo):
    with pytest.raises(ValidationError, match=motivo):
        ResumenPubMed.desde_crudo(con(RESUMEN, **cambio))


# --- De punta a punta: respuesta simulada del servidor -> validación ----------
@responses.activate
def test_json_con_campo_faltante_llega_por_la_red_y_pydantic_lo_rechaza(cliente):
    """El servidor responde 200 (la red está bien) pero el registro viene incompleto."""
    url = "https://api.ejemplo.test/studies"
    incompleto = con(ESTUDIO, **{"protocolSection.identificationModule.nctId": ...})
    responses.add(responses.GET, url, json={"studies": [incompleto]})

    estudio = cliente.get_json(url)["studies"][0]

    assert len(responses.calls) == 1
    with pytest.raises(ValidationError, match="nct_id"):
        EstudioCT.desde_crudo(estudio)
