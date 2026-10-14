"""Actividad 7: consolida las tres fuentes en DataFrames y las guarda en Parquet.

Los DataFrames se construyen desde los modelos YA VALIDADOS (actividad 6), así que
los tipos son limpios: fechas reales, edad en años, estado como categoría.
Donde el JSON anidado conviene aplanarlo tal cual, se usa pd.json_normalize
(record_path + meta), que es la herramienta que sugiere el enunciado.

Tablas "largas": un estudio tiene varios países y un reporte varias reacciones,
así que van en tablas aparte en vez de listas dentro de una celda.

Se ejecuta con:  uv run python -m clientes.consolidar
"""

import glob
import json
from pathlib import Path

import pandas as pd

from clientes.validar import FUENTES, validar

RAW = Path("data/raw")
SALIDA = Path("data/procesado")
ESTADOS_ACTIVOS = ["RECRUITING", "NOT_YET_RECRUITING", "ACTIVE_NOT_RECRUITING", "ENROLLING_BY_INVITATION"]


def _leer_json(patron: str) -> list[dict]:
    return [json.loads(Path(a).read_text()) for a in sorted(glob.glob(str(RAW / patron)))]


def tablas() -> dict[str, pd.DataFrame]:
    # --- ClinicalTrials.gov -------------------------------------------------
    leer, modelo = FUENTES["clinicaltrials"]
    estudios_ok, _ = validar(leer(), modelo)
    estudios = pd.DataFrame(
        {
            "nct_id": e.nct_id, "titulo": e.titulo, "estado": e.estado.value,
            "inscritos": e.inscritos, "inicio": e.inicio, "fin": e.fin,
            "inicio_solo_mes": bool(e.inicio_txt and len(e.inicio_txt) == 7),
            "activo": e.estado.value in ESTADOS_ACTIVOS, "n_paises": len(e.paises),
        }
        for e in estudios_ok
    ).astype({"estado": "category", "inscritos": "Int64"})
    estudios["inicio"] = pd.to_datetime(estudios["inicio"])
    estudios["fin"] = pd.to_datetime(estudios["fin"])

    # Países: tabla larga (un estudio puede tener varios)
    estudios_paises = pd.DataFrame(
        {"nct_id": e.nct_id, "pais": p} for e in estudios_ok for p in e.paises
    )

    crudos = [s for pag in _leer_json("clinicaltrials/*.json") for s in pag["respuesta"]["studies"]]
    validos = set(estudios["nct_id"])
    # Ubicaciones con json_normalize: record_path baja a la lista de sedes y meta arrastra el
    # identificador del estudio a cada fila. TRAMPA: con rutas anidadas en meta, pandas busca la
    # clave relativa a cada sede y, con errors="ignore", rellena NaN EN SILENCIO. Por eso se
    # sube primero el nctId al nivel superior y se usa errors="raise" (que avisa si falla).
    # Además record_path exige que TODOS los elementos tengan 'locations': los 376 estudios sin
    # sedes no aportarían filas de todos modos, así que se filtran antes.
    proyeccion = [
        {"nctId": s["protocolSection"]["identificationModule"]["nctId"],
         "locations": s["protocolSection"]["contactsLocationsModule"]["locations"]}
        for s in crudos
        if s["protocolSection"]["identificationModule"]["nctId"] in validos
        and s["protocolSection"].get("contactsLocationsModule", {}).get("locations")
    ]
    ubic = pd.json_normalize(proyeccion, record_path="locations", meta="nctId", errors="raise").rename(
        columns={"nctId": "nct_id"}
    )
    ubicaciones = ubic[["nct_id", "country", "city", "facility"]].rename(
        columns={"country": "pais", "city": "ciudad", "facility": "sede"}
    )

    # --- openFDA ------------------------------------------------------------
    leer, modelo = FUENTES["openfda"]
    reportes_ok, _ = validar(leer(), modelo)
    reportes = pd.DataFrame(
        {"id_reporte": r.id_reporte, "fecha_recepcion": pd.Timestamp(r.fecha_recepcion),
         "edad_anios": r.edad_anios, "n_reacciones": len(r.reacciones)}
        for r in reportes_ok
    )
    reportes_reacciones = pd.DataFrame(
        {"id_reporte": r.id_reporte, "reaccion": x} for r in reportes_ok for x in r.reacciones
    )
    # Conteo hecho por el servidor sobre TODOS los reportes (json_normalize sobre results)
    conteo = _leer_json("openfda/*conteo*.json")[0]
    reacciones_servidor = pd.json_normalize(conteo["respuesta"]["results"]).rename(
        columns={"term": "reaccion", "count": "reportes"}
    )

    # --- PubMed -------------------------------------------------------------
    filas = []
    for archivo in _leer_json("pubmed/*conteo-*.json"):
        anio = int(archivo["parametros"]["term"].split(" AND ")[1][:4])
        filas.append({"anio": anio, "publicaciones": int(archivo["respuesta"]["esearchresult"]["count"]),
                      "descargado_en": archivo["descargado_en"]})
    pubmed_por_anio = pd.DataFrame(filas).sort_values("anio").reset_index(drop=True)
    # El último año está incompleto: se marca para no confundirlo con un descenso real
    fecha_descarga = pd.Timestamp(pubmed_por_anio["descargado_en"].max())
    pubmed_por_anio["parcial"] = pubmed_por_anio["anio"] == fecha_descarga.year
    pubmed_por_anio = pubmed_por_anio.drop(columns="descargado_en")

    return {
        "estudios": estudios, "estudios_paises": estudios_paises, "ubicaciones": ubicaciones,
        "reportes": reportes, "reportes_reacciones": reportes_reacciones,
        "reacciones_servidor": reacciones_servidor, "pubmed_por_anio": pubmed_por_anio,
    }


if __name__ == "__main__":
    SALIDA.mkdir(parents=True, exist_ok=True)
    for nombre, df in tablas().items():
        df.to_parquet(SALIDA / f"{nombre}.parquet", index=False)
        print(f"{nombre:<22} {len(df):>6} filas x {df.shape[1]} columnas -> data/procesado/{nombre}.parquet")
