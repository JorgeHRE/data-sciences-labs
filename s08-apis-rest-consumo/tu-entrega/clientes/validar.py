"""Actividad 6: valida los datos crudos de data/raw/ y reporta el resultado.

Los registros válidos pasan; los malformados se REGISTRAN (log + data/rechazados/)
y se SALTAN, sin detener el proceso.

Se ejecuta con:  uv run python -m clientes.validar
"""

import glob
import json
import logging
from collections import Counter
from collections.abc import Iterator
from pathlib import Path

from pydantic import ValidationError

from clientes.modelos import EstudioCT, ReporteFDA, ResumenPubMed

RAW = Path("data/raw")
RECHAZADOS = Path("data/rechazados")
log = logging.getLogger("validacion")


def _registros_ct() -> Iterator[tuple[str, dict]]:
    for a in sorted(glob.glob(str(RAW / "clinicaltrials" / "*.json"))):
        for e in json.loads(Path(a).read_text())["respuesta"]["studies"]:
            yield e["protocolSection"]["identificationModule"].get("nctId", "?"), e


def _registros_fda() -> Iterator[tuple[str, dict]]:
    for a in sorted(glob.glob(str(RAW / "openfda" / "*reportes*.json"))):
        for r in json.loads(Path(a).read_text())["respuesta"]["results"]:
            yield r.get("safetyreportid", "?"), r


def _registros_pubmed() -> Iterator[tuple[str, dict]]:
    for a in sorted(glob.glob(str(RAW / "pubmed" / "*resumen*.json"))):
        res = json.loads(Path(a).read_text())["respuesta"]["result"]
        for uid in res["uids"]:
            yield uid, res[uid]


FUENTES = {
    "clinicaltrials": (_registros_ct, EstudioCT),
    "openfda": (_registros_fda, ReporteFDA),
    "pubmed": (_registros_pubmed, ResumenPubMed),
}


def validar(registros: Iterator[tuple[str, dict]], modelo) -> tuple[list, list[dict]]:
    """Devuelve (validos, rechazados). Cada rechazado lleva su id y los motivos."""
    validos, rechazados = [], []
    for ident, crudo in registros:
        try:
            validos.append(modelo.desde_crudo(crudo))
        except (ValidationError, ValueError) as e:
            if isinstance(e, ValidationError):
                motivos = [f"{'.'.join(map(str, err['loc']))}: {err['msg']}" for err in e.errors()]
            else:
                motivos = [str(e)]
            rechazados.append({"id": ident, "motivos": motivos})
            log.warning("RECHAZADO %s | %s", ident, " ; ".join(motivos))
    return validos, rechazados


def validar_fuente(nombre: str) -> tuple[list, list[dict], int]:
    leer, modelo = FUENTES[nombre]
    registros = list(leer())
    validos, rechazados = validar(iter(registros), modelo)
    RECHAZADOS.mkdir(parents=True, exist_ok=True)
    with open(RECHAZADOS / f"{nombre}.jsonl", "w", encoding="utf-8") as f:
        for r in rechazados:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    return validos, rechazados, len(registros)


if __name__ == "__main__":
    Path("data/logs").mkdir(parents=True, exist_ok=True)
    logging.basicConfig(filename="data/logs/validacion.log", filemode="w", level=logging.INFO,
                        format="%(asctime)s %(levelname)s %(message)s")
    print(f"{'fuente':<16}{'llegaron':>9}{'válidos':>9}{'rechazados':>11}")
    for nombre in FUENTES:
        validos, rechazados, total = validar_fuente(nombre)
        print(f"{nombre:<16}{total:>9}{len(validos):>9}{len(rechazados):>11}")
        motivos = Counter(m.split(":")[0] for r in rechazados for m in r["motivos"])
        if motivos:
            print("   motivos por campo:", dict(motivos))
