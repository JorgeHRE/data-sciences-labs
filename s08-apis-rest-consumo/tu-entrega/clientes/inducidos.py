"""Actividad 6: registros corrompidos A PROPÓSITO para probar las reglas de validación.

Los datos reales oficiales casi nunca fallan, así que para comprobar que los
modelos de verdad rechazan lo que deben, se parte de un registro real y se le
rompe una cosa. Estos fallos son INDUCIDOS (no reales) y así se etiquetan.

Se ejecuta con:  uv run python -m clientes.inducidos
"""

import copy
import logging

from clientes.modelos import EstudioCT, ReporteFDA, ResumenPubMed
from clientes.validar import FUENTES, validar


def _primero(fuente: str) -> dict:
    return copy.deepcopy(next(FUENTES[fuente][0]())[1])


def casos() -> list[tuple[str, type, dict]]:
    ct, fda, pm = _primero("clinicaltrials"), _primero("openfda"), _primero("pubmed")
    out = []

    c = copy.deepcopy(ct); c["protocolSection"]["designModule"]["enrollmentInfo"]["count"] = -50
    out.append(("CT: inscritos negativos (-50)", EstudioCT, c))

    c = copy.deepcopy(ct)
    c["protocolSection"]["statusModule"]["startDateStruct"] = {"date": "2024-07-15"}
    c["protocolSection"]["statusModule"]["completionDateStruct"] = {"date": "2023-01-10"}
    out.append(("CT: fin (2023-01-10) anterior al inicio (2024-07-15)", EstudioCT, c))

    c = copy.deepcopy(ct); c["protocolSection"]["statusModule"]["overallStatus"] = "EN_PROGRESO"
    out.append(("CT: estado fuera del conjunto oficial", EstudioCT, c))

    c = copy.deepcopy(ct); del c["protocolSection"]["identificationModule"]["nctId"]
    out.append(("CT: falta el identificador NCT (campo obligatorio)", EstudioCT, c))

    c = copy.deepcopy(ct)
    c["protocolSection"]["statusModule"]["startDateStruct"] = {"date": "2024-13"}
    out.append(("CT: fecha inexistente (mes 13)", EstudioCT, c))

    f = copy.deepcopy(fda); f["patient"]["patientonsetage"] = "150"; f["patient"]["patientonsetageunit"] = "801"
    out.append(("FDA: edad de 150 años", ReporteFDA, f))

    f = copy.deepcopy(fda); f["receivedate"] = "2024-03-12"
    out.append(("FDA: fecha con formato ISO en vez de YYYYMMDD", ReporteFDA, f))

    f = copy.deepcopy(fda); f["patient"]["reaction"] = []
    out.append(("FDA: reporte sin reacciones", ReporteFDA, f))

    p = copy.deepcopy(pm); p["pubdate"] = "1750 Jan 1"
    out.append(("PubMed: año 1750", ResumenPubMed, p))

    p = copy.deepcopy(pm); p.pop("uid")
    out.append(("PubMed: falta el uid", ResumenPubMed, p))
    return out


if __name__ == "__main__":
    logging.getLogger("validacion").setLevel(logging.CRITICAL)  # el log es de validar.py; aquí imprimimos
    print("=== FALLOS INDUCIDOS (no son datos reales) ===")
    for descripcion, modelo, crudo in casos():
        validos, rechazados = validar(iter([("inducido", crudo)]), modelo)
        estado = "RECHAZADO" if rechazados else "¡PASÓ! (la regla no funciona)"
        print(f"\n[{estado}] {descripcion}")
        for r in rechazados:
            for m in r["motivos"]:
                print("    motivo:", m)
