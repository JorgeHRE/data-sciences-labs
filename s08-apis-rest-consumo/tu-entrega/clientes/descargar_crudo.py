"""Actividad 5: descarga las tres fuentes y deja el JSON crudo en data/raw/.

Se ejecuta con:  uv run python -m clientes.descargar_crudo
Cada fuente es independiente: se puede pedir solo una, p. ej.  ... clinicaltrials

Alcance (elegido con los tamaños reales medidos):
  - ClinicalTrials.gov: TODOS los estudios de la condición (~4 300, ~85 MB).
  - PubMed: conteo por año de publicación + resumen de los 500 más recientes.
  - openFDA: conteo de reacciones adversas hecho por el servidor sobre TODOS los
    reportes + una muestra de 500 reportes completos para validar en la actividad 6.
"""

import sys
import time

from clientes.base import ClienteHTTP
from clientes.crudo import guardar_crudo

CONDICION_CT = "gastric cancer"
TERMINO_PUBMED = "stomach neoplasms[MeSH]"
BUSQUEDA_FDA = 'patient.drug.openfda.generic_name:"capecitabine" AND patient.drug.drugindication:"gastric"'

URL_CT = "https://clinicaltrials.gov/api/v2/studies"
URL_ESEARCH = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi"
URL_ESUMMARY = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi"
URL_FDA = "https://api.fda.gov/drug/event.json"


def clinicaltrials(cliente: ClienteHTTP, pausa: float = 0.3) -> int:
    """Una página de 100 estudios por archivo, siguiendo nextPageToken hasta el final."""
    params = {"query.cond": CONDICION_CT, "pageSize": 100, "countTotal": "true"}
    n = 0
    while True:
        n += 1
        r = cliente.get(URL_CT, params)
        guardar_crudo("clinicaltrials", f"{CONDICION_CT}_p{n:03d}", r, dict(params))
        token = r.json().get("nextPageToken")
        if not token:
            return n
        params = {**params, "pageToken": token}
        time.sleep(pausa)


def pubmed(cliente: ClienteHTTP, anio_ini: int = 2000, anio_fin: int = 2026, pausa: float = 0.4) -> int:
    """Conteo por año (retmax=0 devuelve solo el total) y resumen de los 500 más recientes."""
    n = 0
    for anio in range(anio_ini, anio_fin + 1):
        params = {"db": "pubmed", "term": f"{TERMINO_PUBMED} AND {anio}[dp]", "retmode": "json", "retmax": 0}
        guardar_crudo("pubmed", f"conteo_{anio}", cliente.get(URL_ESEARCH, params), params)
        n += 1
        time.sleep(pausa)

    # Los 500 IDs más recientes y su resumen (esummary admite lotes; usamos 3 de ~170)
    params = {"db": "pubmed", "term": TERMINO_PUBMED, "retmode": "json", "retmax": 500, "sort": "pub_date"}
    r = cliente.get(URL_ESEARCH, params)
    guardar_crudo("pubmed", "recientes_ids", r, params)
    ids = r.json()["esearchresult"]["idlist"]
    n += 1
    for i in range(0, len(ids), 170):
        time.sleep(pausa)
        p = {"db": "pubmed", "retmode": "json", "id": ",".join(ids[i:i + 170])}
        guardar_crudo("pubmed", f"recientes_resumen_{i // 170 + 1}", cliente.get(URL_ESUMMARY, p), p)
        n += 1
    return n


def openfda(cliente: ClienteHTTP, pausa: float = 0.3) -> int:
    """Conteo de reacciones (sobre todos los reportes) + 5 páginas de 100 reportes completos."""
    n = 0
    params = {"search": BUSQUEDA_FDA, "count": "patient.reaction.reactionmeddrapt.exact", "limit": 500}
    guardar_crudo("openfda", "conteo_reacciones", cliente.get(URL_FDA, params), params)
    n += 1
    for pagina in range(5):
        time.sleep(pausa)
        params = {"search": BUSQUEDA_FDA, "limit": 100, "skip": pagina * 100}
        guardar_crudo("openfda", f"reportes_p{pagina + 1:03d}", cliente.get(URL_FDA, params), params)
        n += 1
    return n


FUENTES = {"clinicaltrials": clinicaltrials, "pubmed": pubmed, "openfda": openfda}

if __name__ == "__main__":
    elegidas = sys.argv[1:] or list(FUENTES)
    with ClienteHTTP(directorio_cache="data/cache", registro="data/logs/peticiones.jsonl") as cliente:
        for nombre in elegidas:
            t0 = time.perf_counter()
            archivos = FUENTES[nombre](cliente)
            print(f"{nombre:<15} {archivos:>3} archivos en data/raw/{nombre}/  ({time.perf_counter() - t0:.0f} s)")
        print(f"Peticiones reales: {cliente.reales} | servidas por caché: {cliente.de_cache}")
