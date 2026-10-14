# Lab 08 — Cliente para APIs biomédicas públicas

Cliente HTTP robusto que consulta tres APIs públicas sobre **cáncer gástrico** (fármaco principal: **capecitabina**), valida lo que recibe con Pydantic, lo consolida en Parquet y se prueba **sin conexión a internet**.

Entorno: Python 3.12 con [`uv`](https://docs.astral.sh/uv/).

```bash
uv sync                          # instala dependencias (incluye las de desarrollo)
uv run pytest -v                 # 40 pruebas, sin red (ver "Pruebas")
```

## Cómo obtener los datos

> **Los datos (`data/`) no se suben al repositorio** (están en `.gitignore`) y tampoco hay llaves de API: las tres fuentes se usaron **sin llave**. Para regenerarlos:
>
> ```bash
> uv run python -m clientes.descargar_crudo   # crudo -> data/raw/  (~81 peticiones, ~1 min)
> uv run python -m clientes.validar           # valida con Pydantic (rechazados -> data/rechazados/)
> uv run python -m clientes.consolidar        # Parquet -> data/procesado/
> ```
> Después, `notebooks/consolidado.ipynb` hace el análisis. Una segunda ejecución de `descargar_crudo` se resuelve desde la caché (`data/cache/`, expira a 1 día) con 0 peticiones reales.

**Fecha de la descarga documentada aquí: 2026-10-14** (UTC). Los conteos cambian con el tiempo; cada archivo de `data/raw/` guarda su sobre con `descargado_en`, URL y parámetros exactos.

| Fuente | Endpoint | Parámetros principales | Qué se descarga |
|---|---|---|---|
| ClinicalTrials.gov v2 | `https://clinicaltrials.gov/api/v2/studies` | `query.cond=gastric cancer`, `pageSize=100`, `countTotal=true`, `pageToken` (de `nextPageToken`) | Todos los estudios de la condición: 44 páginas, 4 347 estudios |
| PubMed (NCBI E-utilities) | `https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi` | `db=pubmed`, `term=stomach neoplasms[MeSH] AND <año>[dp]`, `retmode=json`, `retmax=0` | Conteo de publicaciones por año, 2000–2026 (27 archivos) |
| PubMed | `esearch.fcgi` y `.../esummary.fcgi` | `term=stomach neoplasms[MeSH]`, `retmax=500`, `sort=pub_date`; luego `id=<lista>` | Los 500 artículos más recientes (1 archivo de IDs + 3 de resumen) |
| openFDA (eventos adversos) | `https://api.fda.gov/drug/event.json` | `search=patient.drug.openfda.generic_name:"capecitabine" AND patient.drug.drugindication:"gastric"`; `count=patient.reaction.reactionmeddrapt.exact`, `limit=500` | Conteo de reacciones adversas sobre **todos** los reportes |
| openFDA | `drug/event.json` | mismo `search`, `limit=100`, `skip=0…400` | Muestra de 500 reportes completos (5 archivos) |

Notas de límites (verificadas durante el lab): openFDA sin llave 240 req/min y 1 000/día por IP (`limit=1000` da 403 sin llave; se usó ≤ 500); NCBI 3 req/s sin llave; ClinicalTrials.gov no publica un límite oficial. El script pausa 0.3–0.4 s entre peticiones.

## Estructura

```
clientes/
  base.py              ClienteHTTP: timeout en todo, Session, reintentos con backoff, Retry-After, caché, contador
  paginacion.py        generador de páginas (perezoso, sigue el token, respeta un máximo)
  crudo.py             guarda cada respuesta cruda en un "sobre" con metadatos
  descargar_crudo.py   descarga de las tres fuentes
  modelos.py, validar.py, inducidos.py   Pydantic: validación y registros malformados inducidos
  consolidar.py        DataFrames -> Parquet
  peticion_basica.py, fallos_provocados.py, comparar_memoria.py,
  verificar_politica.py, verificar_contador.py     scripts de las actividades 2-4 y 9
tests/                 40 pruebas sin red (responses + bloqueo de sockets)
notebooks/consolidado.ipynb   análisis de las tres fuentes
evidencia/             salidas guardadas de cada actividad
bitacora.md            decisiones, hallazgos y observaciones por actividad
```

## Política del cliente (resumen)

- **Timeout** `(5, 30)` s en toda petición (lo pone la clase, no se puede olvidar).
- **Reintentos** solo para `GET` y solo ante 429 y 500/502/503/504: 4 reintentos, `backoff_factor=1`, obedece `Retry-After`. Los 400/401/404 **no** se reintentan: repetir la misma petición da el mismo error.
- **Caché** SQLite que solo guarda respuestas 200.
- Justificación y verificación con un servidor local: `bitacora.md` (act. 4) y `evidencia/act4_politica.txt`.

## Pruebas

`uv run pytest -v` → **40 pasan en ~0.1 s**. Un `conftest.py` bloquea DNS y `connect`, de modo que cualquier acceso real a la red hace fallar la prueba. Cubren 200, 429→200, 500 persistente, 404/400/401 sin reintento y JSON con campo faltante, además de 503, POST, timeout, caché, modelos, paginación y contadores. Evidencia con la red desconectada: `evidencia/act8_pytest_wifi_apagado.txt` (wifi apagado) y `evidencia/act8_pytest_sin_red.txt` (entorno sin interfaces de red, `unshare -rn`).

## Cortesía con los servidores (actividad 9)

Una descarga completa con caché vacía = **81 peticiones reales** (44 + 31 + 6, sin reintentos); repetida con la caché poblada = **0 reales, 81 desde caché**. El total exacto del laboratorio completo no se mide: las actividades 1–4 son anteriores al contador. Detalle en `bitacora.md` y `evidencia/act9_*`.

## Criterios de evaluación → dónde está la evidencia

| Criterio | Evidencia |
|---|---|
| Ninguna petición sin `timeout` | `clientes/base.py`; prueba `test_toda_peticion_lleva_timeout` |
| Política 4xx vs 429/5xx justificada | `bitacora.md` act. 4; `evidencia/act4_politica.txt` |
| Generador + memoria medida | `clientes/paginacion.py`; `evidencia/act3_memoria.txt` |
| Crudo guardado antes de transformar | `clientes/crudo.py`; `evidencia/act5_*` |
| Pydantic rechaza y se reporta cuántos y por qué | `evidencia/act6_*` |
| `pytest` pasa con la red desconectada | `evidencia/act8_pytest_*` |
| Pruebas: 200, 429→200, 500, 404, JSON inválido | `tests/test_cliente.py` |
| Ninguna llave de API en el repositorio | no se usó ninguna; revisión del índice antes de cada commit |
| Conteo de peticiones reales vs caché | `evidencia/act9_*` |
