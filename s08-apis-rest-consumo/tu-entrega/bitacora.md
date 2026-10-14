# Bitácora — Lab 08: cliente para APIs biomédicas

**Condición:** cáncer gástrico
**Fármaco principal (openFDA):** capecitabina

## Actividad 1 — Explorar antes de programar

Primeras peticiones hechas con `curl` el 2026-10-14, viendo el JSON crudo.

| | Endpoint que usarás | Parámetros clave | ¿Cómo pagina? | ¿Límite de tasa? |
|---|---|---|---|---|
| NCBI E-utilities (PubMed) | `https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi` (IDs) y `efetch.fcgi` (detalle) | `db=pubmed`, `term=stomach neoplasms[MeSH]`, `retmode=json`, `retmax` | `retstart` + `retmax` (esearch devuelve `count` total) | 3 peticiones/s sin llave, 10/s con llave *(verificar en docs)* |
| ClinicalTrials.gov v2 | `https://clinicaltrials.gov/api/v2/studies` | `query.cond=gastric cancer`, `pageSize`, `countTotal=true` | Cursor: la respuesta trae `nextPageToken`, se envía como `pageToken` | No hay cifra fija visible en las cabeceras *(verificar en docs)* |
| openFDA | `https://api.fda.gov/drug/event.json` | `search=patient.drug.openfda.generic_name:"capecitabine"`, `limit`, `count=` | `skip` + `limit`; también cabecera `Link: rel="next"` con `search_after` | Con `limit` y `skip` hay topes; los límites por minuto y por día están en la doc *(verificar)* |

### Lo que vi en el JSON crudo

- **PubMed:** `esearchresult.count` = 123 770 artículos con el MeSH *stomach neoplasms*. Devuelve solo los IDs (`idlist`); los datos del artículo requieren una segunda llamada (`efetch`/`esummary`). Sin `retmode=json` responde XML.
- **ClinicalTrials.gov:** `totalCount` = 4 347 estudios para "gastric cancer". Cada estudio vive en `protocolSection` con módulos anidados (`identificationModule`, `statusModule`, `conditionsModule`, ...). Esto es lo que `json_normalize` va a tener que aplanar.
- **openFDA:** `meta.results.total` = 90 991 reportes con capecitabina (todas las indicaciones). La respuesta trae `meta` y `results`.

### Observaciones propias

**Límites de tasa oficiales y reglas operativas**

| API | Sin API Key | Con API Key | Mecanismo de Paginación | Límites de Extracción y Reglas Operativas | Fuente Oficial |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **OpenFDA** | **240 req/min**<br>1,000 req/día *(por IP)* | **240 req/min**<br>120,000 req/día *(por clave)* | **1) Offset:** `limit` y `skip`<br>**2) Cursor:** `search_after` (vía header `Link`) | • `limit` por defecto: **1**; máximo por llamada: **1,000**.<br>• `skip` máximo: **25,000**.<br>• Para extraer más de 25,000 registros sin usar descargas masivas (*bulk downloads*), se debe paginar con `search_after`. | • [Authentication & Rate Limits](https://open.fda.gov/apis/authentication/)<br>• [Paging](https://open.fda.gov/apis/paging/)<br>• [How to use the API](https://open.fda.gov/apis/drug/event/how-to-use-the-endpoint/) |
| **ClinicalTrials.gov (API v2)** | **No publicado oficialmente**<br>*(Límite práctico: **~50 req/min** o ~0.8 req/seg por IP)* Fuente secundaria | **No aplica**<br>*(API pública sin sistema de API keys)* | **Cursor:** parámetros `pageSize` y `pageToken` (usando el valor `nextPageToken` devuelto en el JSON) | • `pageSize` por defecto: **10**; máximo por llamada: **1,000** estudios.<br>• Permite paginar más allá de 10,000 registros mediante `pageToken`.<br>• Exceder la frecuencia devuelve `HTTP 429 Too Many Requests`. | • [ClinicalTrials.gov API v2 Spec](https://clinicaltrials.gov/data-api/api)<br>• [About the API](https://clinicaltrials.gov/data-api/about-api)<br>• [API Migration Guide](https://clinicaltrials.gov/data-api/about-api/api-migration) |
| **NCBI E-utilities** | **3 req/seg** *(por IP)* | **10 req/seg** *(parámetro `&api_key=`)* | **1) Offset:** `retstart` y `retmax`<br>**2) Historial:** `usehistory=y` con `WebEnv` y `query_key` | • `retmax` por defecto: **20**; máximo: **10,000**.<br>• **Tope en PubMed/PMC:** `esearch` solo recupera hasta **9,999 registros** por búsqueda; para más de 9,999 se requiere **EDirect** o particionar por fechas.<br>• En `efetch` se recomiendan lotes de <= 200 IDs.<br>• Enviar `tool` y `email` (recomendado/registrado; ver NBK25497); cargas masivas de 9:00 PM a 5:00 AM ET o fines de semana. | • [Introduction to E-utilities (NBK25497)](https://www.ncbi.nlm.nih.gov/books/NBK25497/)<br>• [E-utilities In-Depth: Parameters (NBK25499)](https://www.ncbi.nlm.nih.gov/books/NBK25499/) |

Durante la revisión del JSON crudo observé que, para openFDA, las fechas no están en formato ISO 8601 extendido, sino en formato numérico compacto ("20231104"), lo que requiere de un paso extra para convertirlos a objeto temporal. Por otro lado en el caso de ClinicalTrials.gov (API v2) utiliza fechas parciales (2024-07-15, y a veces solo el año). Además divide cada estudio en un árbol de submódulos (protocolSection -> designModule, eligibilityModule, outcomesModule). Llegar al criterio de inclusión o al tamaño de muestra exige descender 4 y 3 niveles de llaves de diccionario. NCBI E-utilities tiene diccionarios con claves dinámicas en `esummary`. El JSON resultante no entrega una lista indexada, sino un objeto donde las claves son los propios identificadores numéricos (PMIDs o UIDs de NCBI):

```json
"result": {
  "uids": ["34567890", "34567891"],
  "34567890": { "title": "..." },
  "34567891": { "title": "..." }
}
```

Esto obliga a iterar primero sobre la lista `uids` para acceder dinámicamente a las propiedades de cada artículo.

## Actividad 2 — Una petición decente

Código correcto: `clientes/peticion_basica.py`. Fallos provocados: `clientes/fallos_provocados.py`.
Salidas guardadas en `evidencia/act2_peticion_correcta.txt` y `evidencia/act2_fallos.txt`.

### Fallo 1 — sin `raise_for_status()`, NCT inexistente (`NCT99999999`)

- El servidor respondió **404** con `Content-Type: text/plain` y el cuerpo `NCT number NCT99999999 not found`.
- Sin `raise_for_status()` el código siguió, llamó a `r.json()` y falló con `JSONDecodeError: Expecting value: line 1 column 1 (char 0)`.
- El error que se ve es sobre el JSON, no sobre el 404: esconde la causa real.

### Fallo 2 — `params=` mal usado (URL concatenada a mano)

- Con espacio y acento (`cáncer gástrico`) **no falló**: `requests` moderno codifica la URL por su cuenta (`c%C3%A1ncer%20g%C3%A1strico`). Esperaba un error y no apareció.
- Con un `&` dentro del valor (`capecitabine & oxaliplatin`) **sí falló**: el servidor devolvió **400** con `` ` oxaliplatin` is unknown parameter ``, porque leyó el `&` como separador de parámetros.
- Con `params=` la misma búsqueda dio 200 y 320 estudios, porque el `&` se codificó como `%26`.

### Hallazgo extra

- `query.cond=cáncer gástrico` devuelve **2** estudios; `gastric cancer` devuelve **4 347**. Los registros están en inglés, así que las búsquedas deben ir en inglés.

### Observaciones propias

### 1. Hipótesis inicial vs. comportamiento real: la trampa del *percent-encoding* en el Fallo 2
Al omitir el diccionario `params={...}` y concatenar manualmente la cadena de consulta en la URL con caracteres no ASCII y espacios (`?query.cond=cáncer gástrico`), la hipótesis inicial era que la petición fallaría de inmediato por contener caracteres inválidos en una URI. Sin embargo, la petición tuvo éxito (`HTTP 200`). 

Esto ocurrió porque las versiones actuales de `requests` (apoyadas en `urllib3`) procesan la URL antes de enviarla a través de `PreparedRequest.prepare_url()`, la cual aplica codificación porcentual automática (*percent-encoding*, `c%C3%A1ncer%20g%C3%A1strico`) a los espacios y caracteres fuera del rango ASCII básico, pero **preserva intactos los caracteres reservados del estándar URI** (RFC 3986, Sección 2.2) porque asume que quien escribió la URL los colocó deliberadamente como delimitadores sintácticos.

El verdadero fallo estructural apareció al combinar la condición (`query.cond=gastric cancer`) con una intervención farmacológica que incluía el carácter reservado `&` (`?query.cond=gastric cancer&query.intr=capecitabine & oxaliplatin`):
* **Concatenando a mano:** `requests` asumió que el `&` dentro de la intervención era un separador legítimo de la *query string*. El servidor de ClinicalTrials.gov procesó `query.cond=gastric cancer`, pero partió el filtro de intervención en dos: `query.intr=capecitabine ` y un supuesto parámetro independiente llamado ` oxaliplatin`, devolviendo `HTTP 400 Bad Request` con el mensaje `` ` oxaliplatin` is unknown parameter `` (como quedó registrado en `evidencia/act2_fallos.txt`).
* **Usando `params=`:** La librería invoca internamente `urllib.parse.urlencode()`, la cual escapa todos los caracteres reservados dentro de los valores convirtiendo el `&` de `query.intr` en `%26`. Así, el servidor recibió tanto la condición como la intervención íntegra y devolvió `HTTP 200` con 320 estudios.

#### 2. Por qué ocultar un `404` tras un `JSONDecodeError` es crítico en depuración (*Fail-Fast*)
En el **Fallo 1** (`NCT99999999`), omitir `r.raise_for_status()` permitió que el programa continuara su flujo normal a pesar de haber recibido un código de estado `HTTP 404 Not Found` (RFC 9110, Sección 15.5.5). 

El problema de diseño radica en que la API v2 de ClinicalTrials.gov cambia la cabecera de respuesta a `Content-Type: text/plain` cuando un identificador no existe y devuelve el texto plano `"NCT number NCT99999999 not found"`. Al ejecutar `r.json()` sobre ese cuerpo, el intérprete lanza `requests.exceptions.JSONDecodeError: Expecting value: line 1 column 1 (char 0)`. 

Desde el punto de vista de diagnóstico, este comportamiento es mucho más costoso que un `HTTPError` por tres razones:
1. **Enmascara la capa del fallo:** Desplaza un problema de la **capa de transporte/protocolo HTTP** (recurso inexistente en el servidor) hacia la **capa de serialización de datos**, haciendo parecer que la API envió un JSON corrupto o vacío.
2. **Pérdida de contexto en la traza (*stack trace*):** La excepción `JSONDecodeError` no informa qué código HTTP devolvió el servidor ni qué URL falló; en cambio, `raise_for_status()` levanta un `HTTPError` que adjunta el objeto `response` completo y expone explícitamente `404 Client Error: Not Found for url: ...`.
3. **Riesgo de fallos silenciosos:** Si en otro endpoint el servidor devolviera su error `404` o `500` formateado como un objeto JSON (por ejemplo, `{"error": "Not found"}`), `r.json()` ni siquiera fallaría: el script inyectaría un diccionario inválido en las fases posteriores del pipeline sin alertar del error HTTP.

#### 3. Sesgo de idioma en el motor de indexación de ClinicalTrials.gov
La abismal diferencia entre consultar `"cáncer gástrico"` (2 estudios) y `"gastric cancer"` (4,347 estudios) demuestra que el motor de búsqueda de ClinicalTrials.gov no realiza traducción cruzada de términos libres al español.

#### 4. Qué haría distinto en un pipeline de investigación con miles de peticiones
Pasar de un script exploratorio (`clientes/peticion_basica.py`) a una extracción masiva reproducible de miles de registros requiere modificar la arquitectura en cinco puntos:

1. **Reutilización de conexiones TCP con `requests.Session()`:** Llamar a `requests.get()` miles de veces abre y cierra un socket TCP y negocia un *handshake* TLS en cada petición. Instanciar un objeto `requests.Session()` reutiliza la misma conexión persistente (*HTTP Keep-Alive*), reduciendo drásticamente la latencia y la sobrecarga de red.
2. **Separación estricta de `timeout=(connect, read)` y manejo de excepciones de red:** Mantener la tupla `(5, 30)` evita bloqueos infinitos —pues el valor por defecto en `requests` es `timeout=None`—, pero en un lote de miles de llamadas es obligatorio envolver la petición en un bloque `try / except` que capture `requests.exceptions.Timeout` y `requests.exceptions.ConnectionError` para registrar qué `NCTId` falló y continuar sin abortar horas de ejecución.
3. **Política de reintentos con *exponential backoff* y control de tasa:** Para respetar los límites del servidor y recuperarse de errores transitorios (`HTTP 429 Too Many Requests`, `502`, `503`, `504`), acoplaría `urllib3.util.retry.Retry` con un factor de espera exponencial (`backoff_factor`) sobre el adaptador HTTP de la sesión, además de un espaciado base entre peticiones.
4. **Distinción entre errores fatales y registros ausentes:** Usar `raise_for_status()` dentro de un manejador que distinga un `404` (un identificador `NCT` obsoleto o mal escrito, que debe registrarse en un archivo de *log* de descartados y saltarse) de un `400` (error de sintaxis en nuestra consulta, que debe detener la ejecución de inmediato).
5. **Persistencia incremental del JSON crudo (*checkpointing*):** Guardar cada respuesta cruda o lote paginado (`pageToken`) en disco antes de transformarlo, garantizando que, si el proceso se interrumpe en la petición 3,500, pueda reanudarse desde el último estado válido sin repetir las consultas previas.

---


## Actividad 3 — Paginación sin agotar la memoria

Código: `clientes/paginacion.py` (generador y versión con lista) y `clientes/comparar_memoria.py` (medición). Salida en `evidencia/act3_memoria.txt`.

### Qué se hizo
- `generar_estudios()` es un generador: pide una página (100 estudios), entrega los estudios uno a uno con `yield` y, al agotarlos, sigue con el `nextPageToken`. La última página no trae token y termina.
- `acumular_estudios()` consume el mismo generador y devuelve una lista con todo.
- Se pidieron **500 registros** de ClinicalTrials.gov (condición `gastric cancer`), 5 páginas, con una pausa de 0.3 s entre páginas.
- La memoria se midió con `tracemalloc` (pico de memoria), igual que en el laboratorio 2.

### Resultados

| Versión | Registros | Pico de memoria |
|---|---|---|
| Generador (procesa y descarta) | 500 | 22.36 MB |
| Lista (acumula todo) | 500 | 45.06 MB |

Ambas dieron el mismo resultado de la tarea de ejemplo (2 699 482 inscritos sumados), así que solo cambia el uso de memoria.

### Demostración de que es un generador de verdad
- `inspect.isgeneratorfunction(generar_estudios)` devuelve `True`.
- Al crear el generador hizo **0 peticiones**; al pedir el primer estudio, **1**; tras consumir 100 estudios, seguía en **1**; al pedir el 101, subió a **2**. Solo trabaja cuando se le pide.

### Matiz sobre la medición
El pico del generador (22 MB) no es "un registro": es **una página** de 100 estudios más el JSON que se descarga y se parsea. La ventaja es que ese pico no crece con el total de registros, mientras que el de la lista sí. Con más registros, la diferencia entre ambos aumentaría. (No lo medí con otro tamaño: es lo esperado, no un resultado observado.)

### Observaciones propias


### 1. Demostración de evaluación perezosa (*lazy evaluation*)
La inspección del contador de peticiones confirmó el comportamiento estrictamente perezoso de `generar_estudios()`:
* Al instanciar el generador se registraron **0 peticiones**.
* La primera petición a la API ocurrió únicamente al solicitar el primer elemento con `next()` o al iniciar la iteración.
* Al terminar de consumir el estudio número 100, el contador se mantuvo en **1 petición**. La segunda petición se disparó recién al solicitar el **estudio 101**, demostrando que el generador solo consulta la red y resuelve el cursor (`nextPageToken`) cuando agota la página local y requiere el siguiente elemento.

### 2. Por qué el generador consume 22 MB y no "casi cero"
El generador redujo el pico de memoria a la mitad (22.36 MB frente a 45.06 MB de la lista), pero mantuvo un piso de 22 MB debido a la unidad de transferencia y al procesamiento de red:
* **Retención por página completa:** La API entrega lotes de 100 estudios. Aunque el generador cede (`yield`) un estudio individual, la estructura anidada de la página completa permanece en el heap de Python hasta que se agota el lote.
* **Coexistencia en memoria y buffers de red:** Dado que `tracemalloc.start()` se llamó después de importar las librerías (`requests`, `urllib3`), el pico no refleja la carga de módulos. Probablemente se debe a la coexistencia temporal en memoria del texto HTTP en bruto devuelto por el socket junto con el árbol de diccionarios ya deserializado por `.json()`, además de los buffers internos de la conexión TLS.

### 3. Escalabilidad teórica vs. límite de la medición
Con 500 registros, la lista acumuló las 5 páginas de forma simultánea, duplicando el consumo (45.06 MB):
* En la lista, la memoria escala en función del total acumulado: $\mathcal{O}(N)$.
* En el generador, el consumo se mantiene acotado al tamaño de la página activa: $\mathcal{O}(\text{tamaño\_página})$, permitiendo liberar la página previa para recolección de basura.
* **Límite honesto del experimento:** La prueba se acotó a 500 registros (5 páginas). Por ello, la estabilidad del pico de memoria en volúmenes masivos es un comportamiento previsto teóricamente, no observado de manera empírica en esta corrida. Asimismo, `tracemalloc` midió únicamente las reservas del heap de Python a partir de su inicio, sin registrar el consumo total del proceso a nivel de sistema operativo.

### 4. Relevancia para el procesamiento de datos de tesis
Este patrón de consumo resulta clave al escalar la extracción a los **4,347 estudios de cáncer gástrico** disponibles:
* **Prevención de desbordamiento:** Mediante una estimación lineal simple ($4\,347 / 500 \approx 8.7$), cargar todos los estudios en una única lista multiplicaría el pico de memoria por un factor cercano a 9 respecto a lo medido aquí, lo que incrementaría la competencia por RAM frente a procesos pesados en paralelo.
* **Procesamiento en flujo (*streaming*):** El generador permite construir un pipeline donde cada estudio se procesa, filtra (e.g. seleccionando únicamente campos relevantes o criterios específicos) o se persiste en disco conforme llega, permitiendo descartar el resto del JSON de la memoria sin esperar la descarga de todo el catálogo.

## Actividad 4 — El cliente robusto

Código: `clientes/base.py` (clase `ClienteHTTP`). Verificación: `clientes/verificar_politica.py`, con salida en `evidencia/act4_politica.txt` y `evidencia/act4_cache_real.txt`. El generador de la actividad 3 ahora usa este cliente.

### Qué se hizo
- **`timeout` en todas las peticiones:** lo pone la clase, `(5, 30)` por defecto; quien usa `get()` no puede olvidarlo.
- **Una `Session` reutilizada:** una `CachedSession` por cliente, así se reaprovecha la conexión.
- **Reintentos con backoff exponencial:** `urllib3.Retry` montado en un `HTTPAdapter`. Solo `GET`, `HEAD` y `OPTIONS` (idempotentes) y solo para 429, 500, 502, 503 y 504. Máximo 4 reintentos y `backoff_factor=1` (esperas de 0, 2, 4 y 8 s tras los fallos sucesivos).
- **`Retry-After`:** `respect_retry_after_header=True`.
- **Caché en disco:** SQLite en `data/cache/` (ignorada por git), expira a las 24 h, y **solo guarda respuestas 200** (`allowable_codes=(200,)`).
- **Orden de las piezas:** la caché envuelve al adaptador de reintentos. Un acierto de caché no toca la red, y un 429 o 500 intermedio nunca se guarda.

### Política de reintentos

| Código | ¿Reintentar? | Por qué | Observado (servidor local, 3 reintentos) |
|---|---|---|---|
| 400 | No | La petición está mal formada; repetirla da el mismo error. | 1 petición |
| 401 | No | Faltan credenciales o son inválidas; reintentar no las arregla. | 1 petición |
| 404 | No | El recurso no existe; seguirá sin existir. | 1 petición |
| 429 | Sí, esperando `Retry-After` | El servidor pide calma y dice cuánto; adelantarse empeora el bloqueo. | 2 peticiones; esperó 1.0 s (el valor de `Retry-After`) |
| 500 | Sí, con backoff | Fallo transitorio del servidor; puede recuperarse. | 4 peticiones y luego `HTTPError 500` |
| 503 | Sí, con backoff | Servicio saturado o en mantenimiento; suele ser temporal. | 2 peticiones (503, luego 200) |

Además, un `POST` a una ruta que da 500 hizo **1 sola petición**: los métodos no idempotentes no se reintentan.

### Cómo se verificó
Las APIs públicas no se pueden forzar a dar 429 o 500 sin abusar de ellas, así que se levantó un servidor falso en `127.0.0.1` que responde lo programado y cuenta las peticiones recibidas. También se comprobó la caché: una respuesta 200 pedida dos veces llegó una sola vez al servidor (la segunda con `from_cache=True`), mientras que las rutas 404 y 500 pedidas dos veces llegaron las dos veces (no se cachean los errores).
Contra la API real: pedir 200 estudios de ClinicalTrials.gov dos veces tardó 1.87 s y 0.65 s; la segunda salió de la caché.

### Observaciones propias

#### 1. Jerarquía de control: por qué `Retry-After` tiene precedencia sobre el *backoff*
En la prueba con el error `HTTP 429`, el cliente esperó exactamente el 1.0 s indicado en la cabecera devuelta por el servidor:
* Con la fórmula interna de `urllib3` y `backoff_factor=1`, el primer reintento habría tenido una espera de 0.0 s. 
* Respetar `Retry-After` prioriza la instrucción explícita del servidor sobre el cálculo local. Esto evita reintentar inmediatamente a los 0 s (lo que mantendría el bloqueo de tasa) y ajusta la pausa de forma proporcional a la ventana de descongestión declarada por el servicio remoto.

#### 2. El riesgo de cachear respuestas de error transitorio (`HTTP 500`)
La decisión de restringir la persistencia en disco exclusivamente a respuestas exitosas (`allowable_codes=(200,)`) protege la consistencia del dataset:
* Un `HTTP 500 Internal Server Error` o `503 Service Unavailable` refleja una falla transitoria del backend en ese momento particular, como se comprobó en la prueba local donde los códigos 404 y 500 llegaron las dos veces al servidor sin ser interceptados por el disco.
* Si el cliente almacenara errores 500 con la expiración configurada de 24 horas, una caída de pocos segundos quedaría guardada como fallo permanente durante un día completo. Las ejecuciones posteriores no consultarían la API y asumirían de forma errónea que el registro no existe, introduciendo sesgos artificiales en la recolección.

#### 3. Métodos seguros y prevención de efectos secundarios
La verificación con un método `POST` frente a un error 500 confirmó que el adaptador no reintentó la solicitud (1 sola petición):
* El estándar HTTP permite reintentar métodos idempotentes (como `PUT` o `DELETE`), pero la política implementada adoptó un criterio más estricto limitándose únicamente a **métodos seguros** (`GET`, `HEAD`, `OPTIONS`).
* Dado que un método seguro no modifica el estado del recurso, se garantiza que los reintentos automáticos jamás provocarán duplicaciones ni mutaciones imprevistas en el backend si una petición previa sí llegó a procesarse.

#### 4. Evaluación de los reintentos para el pipeline de tesis
Para una recolección masiva de estudios clínicos o secuencias, configurar 3 reintentos (4 peticiones en total: 1 original + 3 reintentos) con `backoff_factor=1` resulta una decisión equilibrada:
* **Margen de recuperación transitoria:** Permite sortear reinicios breves de servicios o micro-cortes de conexión sin abortar trabajos por lotes que llevan horas de ejecución.
* **Tiempo acumulado acotado:** Con `urllib3` (2.8.0), la secuencia de pausas antes de cada reintento corresponde a `[0, 2.0, 4.0, 8.0]` segundos. Si se configuraran 4 reintentos (5 peticiones en total), la espera total sumaría exactamente 14.0 s; con 3 reintentos (4 peticiones), la espera acumulada es de apenas 6.0 s (`0 + 2.0 + 4.0`). Ambos márgenes son lo bastante ágiles como para no demorar el pipeline si un endpoint realmente quedó fuera de servicio.
* **Transparencia en el diagnóstico:** Con `raise_on_status=False`, el adaptador devuelve la respuesta final para que el cliente genere un `HTTPError` estándar de `requests`. Esto conserva el objeto `response` íntegro y permite registrar en los logs el identificador exacto que falló para un reprocesamiento posterior.

## Actividad 5 — Guardar el crudo

Código: `clientes/crudo.py` (guardado con sobre de metadatos) y `clientes/descargar_crudo.py` (descarga de las tres fuentes). Salidas en `evidencia/act5_descarga.txt` y `evidencia/act5_verificacion.txt`. Los datos están en `data/raw/` (ignorado por git).

### Qué se guardó
Se descargó el 2026-10-14 y se guardó cada respuesta en su propio archivo JSON, **antes de transformar nada**.

| Fuente | Archivos | Contenido | Tamaño |
|---|---|---|---|
| ClinicalTrials.gov | 44 | Todos los estudios de `gastric cancer`: 4 347, en páginas de 100 | 97 MB |
| PubMed | 31 | Conteo de artículos por año (2000-2026, 27 consultas), los 500 IDs más recientes y su resumen (`esummary`) | 1.3 MB |
| openFDA | 6 | Conteo de reacciones adversas de capecitabina con indicación gástrica sobre todos los reportes (5 759), más 500 reportes completos | 12 MB |

Cada archivo lleva un "sobre" con la fuente, la fecha de descarga (UTC), si vino de la caché, la URL completa, los parámetros, el código HTTP y, aparte, la respuesta tal como llegó.

### Verificación
- ClinicalTrials.gov: 44 páginas, `totalCount` = 4 347, estudios guardados = 4 347 y NCT únicos = 4 347 (sin faltantes ni duplicados).
- PubMed: 27 años contados y 500 resúmenes.
- openFDA: 500 reportes completos y el conteo de reacciones.

### Decisiones sobre el alcance
- **ClinicalTrials.gov completo:** son 44 peticiones y unos 97 MB; la pregunta de los ensayos activos y su ubicación necesita todo el conjunto.
- **openFDA, conteo en el servidor:** es más barato y exacto que bajar miles de reportes de 38 KB cada uno; la muestra de 500 reportes completos sirve para validar con Pydantic (actividad 6).
- **PubMed por año:** el tope de `esearch` es 9,999 registros, así que la tendencia anual se obtiene con una consulta de conteo por año y no descargando artículos.
- El año 2026 está incompleto (datos hasta el 14 de octubre).

### Hallazgo: `limit=1000` en openFDA
La documentación dice que el máximo es 1000, pero sin llave `limit=1000` devolvió **403 `API_KEY_MISSING`**; `limit=999` y los valores menores funcionaron. Se usó `limit=500` para el conteo y `limit=100` para los reportes.

### Límites de lo guardado
El campo `respuesta` es el JSON parseado y vuelto a escribir: es idéntico en contenido, pero no byte a byte (puede cambiar el espaciado o el escape de caracteres). Y la caché del cliente no sustituye al crudo: expira a las 24 h, mientras que `data/raw/` es un registro permanente de qué datos se usaron.

### Observaciones propias

### 1. Reproducibilidad frente a bases de datos vivas
Bases como PubMed y ClinicalTrials.gov incorporan o modifican registros diariamente. Guardar la respuesta cruda congela una instantánea inmutable del conjunto de datos: sin este respaldo local, cualquier cifra o conteo reportado en la tesis (como los 4,347 estudios de hoy) dejaría de ser reproducible en corridas futuras al variar el catálogo remoto.

### 2. Trazabilidad metodológica y desacoplamiento del pipeline
El uso de un "sobre" de metadatos resuelve dos requerimientos analíticos fundamentales:
* **Auditoría exacta de la consulta:** Registrar la URL original, los parámetros, el código HTTP y la marca temporal precisa —respetando la fecha de origen si proviene de caché— documenta el linaje completo del dato (*provenance*), permitiendo verificar o replicar el experimento bajo idénticas condiciones.
* **Separación entre ingesta y transformación:** Desacopla la extracción web del análisis posterior. Si más adelante se corrigen criterios de filtrado, esquemas de tablas o scripts de procesamiento bioinformático, no es necesario volver a golpear las APIs ni arriesgarse a cambios en los datos remotos.

### 3. Límites técnicos observados: la anomalía de OpenFDA y la fidelidad del archivo
* **Comportamiento no documentado en OpenFDA:** Aunque la documentación oficial lista un tope de `limit=1000`, la API rechaza peticiones anónimas con ese valor devolviendo `HTTP 403 API_KEY_MISSING`, mientras que `limit=999` tiene éxito. Este hallazgo sugiere que la documentación y el comportamiento no coinciden tal como los leímos (quizá por un umbral estricto que exige autenticación al alcanzar el millar), justificando el ajuste pragmático en el código.
* **Límite honesto de serialización:** Al recibir el JSON, parsearlo a estructura nativa de Python y reescribirlo en disco (`json.dump`), el contenido semántico y los valores son idénticos, y el orden de inserción de las claves se conserva. Sin embargo, el archivo resultante no preserva la igualdad byte a byte respecto a la respuesta original debido a diferencias en espaciado, des-escape de caracteres Unicode (e.g. `\u00e1` a `á`) y formateo numérico (donde `2.50` se serializa como `2.5` o `1e3` como `1000.0`), un detalle relevante a considerar al comparar representaciones de texto en datos científicos.

## Actividad 6 — Validar en la frontera

Código: `clientes/modelos.py` (modelos de Pydantic), `clientes/validar.py` (validación de `data/raw/`) y `clientes/inducidos.py` (fallos provocados). Salidas en `evidencia/act6_validacion.txt`, `act6_inducidos.txt` y `act6_comprobaciones.txt`.

### Qué se hizo
- Un modelo por fuente (`EstudioCT`, `ReporteFDA`, `ResumenPubMed`) con **solo los campos que usarán las preguntas de la actividad 7**; Pydantic ignora el resto del JSON.
- Campos imprescindibles obligatorios (identificador, estado, fecha del reporte, `uid`) y el resto opcional, porque los datos reales vienen incompletos.
- Los registros válidos siguen; los rechazados se **registran** (`data/logs/validacion.log` y `data/rechazados/*.jsonl`, ambos ignorados por git) y se **saltan** sin detener el proceso.

### Reglas aplicadas

| Fuente | Regla | Tipo de regla |
|---|---|---|
| ClinicalTrials.gov | `inscritos` ≥ 0 | rango |
| ClinicalTrials.gov | `estado` dentro de los 14 oficiales | conjunto |
| ClinicalTrials.gov | fecha de fin no anterior a la de inicio; fechas con solo mes se completan con el día 1 y, al ser la de fin, cuentan como el último día del mes | entre campos |
| openFDA | edad entre 0 y 120 años, convertida a años según su unidad (el texto `"8"` en décadas es 80 años) | tipo y rango |
| openFDA | fecha `YYYYMMDD` real y no futura; al menos una reacción | tipo y contenido |
| PubMed | `uid` numérico; año entre 1800 y el año actual + 1 | tipo y rango |

### Resultados sobre los datos reales

| Fuente | Llegaron | Pasaron | Rechazados |
|---|---|---|---|
| ClinicalTrials.gov | 4 347 | 4 347 | 0 |
| openFDA | 500 | 500 | 0 |
| PubMed | 500 | 500 | 0 |

**Ningún registro real falló.** Es lo esperable en datos oficiales. Para comprobar que esto no se debe a reglas demasiado laxas, se verificó que lo que pasó quedó bien convertido:
- La edad de `8` con unidad `800` (décadas) quedó como **80.0 años**; las demás edades van de 24 a 88 años y 116 reportes no traen edad (opcional).
- ClinicalTrials.gov: 1 419 fechas de inicio y 1 646 de fin vienen solo con mes y fueron aceptadas; 60 estudios no tienen inscritos, 376 no tienen país y 16 no tienen fecha de inicio (todos opcionales, no son errores).
- PubMed: 495 artículos de 2026 y **5 de 2027**. Son artículos en línea con número impreso del año siguiente, y por eso se acepta hasta el año actual + 1.

### Tres fallos con su motivo (INDUCIDOS, no reales)
Como no hubo fallos reales, se corrompieron a propósito registros reales, uno por regla. Aquí tres; los 10 casos están en `evidencia/act6_inducidos.txt` y **todos fueron rechazados**.

| Corrupción provocada | Motivo devuelto por Pydantic |
|---|---|
| Estudio con `inscritos = -50` | `inscritos: Input should be greater than or equal to 0` |
| Estudio con fin `2023-01-10` e inicio `2024-07-15` | `Value error, la fecha de fin (2023-01-10) es anterior a la de inicio (2024-07-15)` |
| Reporte de openFDA con edad de 150 años | `edad_anios: Input should be less than or equal to 120` |

### Límites
- Los códigos de unidad de edad de openFDA (800 décadas, 801 años, 802 meses...) vienen de su documentación; en nuestros datos solo aparecen 800 y 801, así que las demás conversiones no se han probado con datos reales.
- Los modelos validan los 500 reportes de openFDA y los 500 resúmenes de PubMed descargados, no todo lo que hay en las bases.

### Observaciones propias

### 1. Datos faltantes vs. datos inválidos: la regla del identificador frente a campos opcionales
Un registro sin número de participantes inscritos (`enrollmentInfo.count`) se acepta como válido (`None`), pero uno sin identificador principal (`nct_id`, `uid` o `safetyreportid`) se rechaza de inmediato:
* **El identificador es la clave primaria del registro:** Sin un identificador unívoco no existe trazabilidad, se pierde la capacidad de desduplicar y es imposible contrastar el dato con la fuente original. Un registro sin ID es estructuralmente inservible.
* **El dato ausente refleja la naturaleza del registro:** Al examinar los 60 estudios que carecen de `enrollmentInfo.count`, se observa que ninguno está en fase activa de reclutamiento. Una parte (8 estudios en estados como `AVAILABLE`, `NO_LONGER_AVAILABLE` o `APPROVED_FOR_MARKETING`) corresponde a registros de acceso expandido o fármacos comercializados donde la noción de reclutamiento clínico no aplica directamente; mientras que la causa en los 39 estudios en estado `COMPLETED` sin este dato queda como una incógnita abierta en el catálogo. Asimismo, conviene distinguir metodológicamente entre la ausencia de información (`None`, 60 casos) y un conteo explícito de cero (`count = 0`, presente en 83 estudios), pues representan estados conceptualmente distintos para la Actividad 7.

### 2. Impacto en los conteos de la Actividad 7 si no se valida en la frontera
Omitir la validación y transformación previa al análisis downstream generaría tres distorsiones graves:
* **Fallas en agregaciones cuantitativas:** En openFDA, la edad del paciente llega codificada con claves de unidad (e.g. código `800` para décadas, `801` para años). Si no se normaliza a una escala común en la frontera, un paciente de 8 décadas se sumaría como edad "8" en lugar de "80", alterando promedios y distribuciones demográficas.
* **Incompatibilidad de tipos:** Si las edades o conteos entran como cadenas de texto (`str`), las operaciones de ordenamiento fallarían lexicográficamente (`"100"` menor que `"20"`), y las funciones estadísticas lanzarían excepciones o producirían agregaciones incorrectas.
* **Calibración de reglas temporales en PubMed:** Una regla estricta que corte en el año en curso habría rechazado erróneamente los 5 artículos fechados en 2027 (publicaciones electrónicas anticipadas o *ahead of print*); por el contrario, prescindir por completo de una validación temporal habría permitido el ingreso de valores aberrantes (e.g. año 2099). La regla de tolerancia (`año actual + 1`) resolvió ambos problemas.

### 3. Interpretación metodológica del 100% de éxito en datos reales
Que los 5,347 registros reales descargados hayan superado la validación sin un solo rechazo no implica que las fuentes gocen de una curación exhaustiva:
* **Cumplimiento de reglas mínimas vs. completitud:** El resultado demuestra únicamente que los datos satisfacen las restricciones obligatorias que definimos, las cuales son deliberadamente permisivas con los campos opcionales. La validación no detecta la omisión de datos: 60 estudios sin inscritos, 376 sin país y 116 reportes de openFDA sin edad pasaron el filtro sin alertar. Esto es crítico para los conteos por país de la Actividad 7, donde esos 376 registros quedarán forzosamente excluidos. Además, tratándose de openFDA, los reportes provienen de farmacovigilancia espontánea, sujetos a alta heterogeneidad de llenado.
* **El valor de las pruebas con errores inducidos:** La efectividad del esquema no se demostró con los datos reales —cuyos `.jsonl` de rechazos quedaron vacíos—, sino al confrontar los modelos contra los 10 registros corrompidos a propósito en `clientes/inducidos.py`. Como quedó registrado en la salida de `evidencia/act6_inducidos.txt`, cada violación (de rango, pertenencia al conjunto de 14 estados oficiales o ausencia de campos requeridos) disparó el error correspondiente, garantizando que el pipeline cuenta con poder de discriminación ante eventuales actualizaciones de esquemas o valores fuera de norma.

## Actividad 7 — Consolidar

Código: `clientes/consolidar.py` (DataFrames y Parquet) y `notebooks/consolidado.ipynb` (análisis, ejecutado y guardado con sus resultados). Salida en `evidencia/act7_parquet.txt`. Los Parquet están en `data/procesado/` (ignorado por git).

### Qué se hizo
- Los DataFrames se construyen **desde los modelos ya validados** (actividad 6), así que los tipos son limpios: fechas reales, edad en años, estado como categoría.
- `pd.json_normalize` se usó donde el JSON anidado conviene aplanarlo tal cual: las sedes de cada estudio (`record_path` + `meta`) y el conteo de reacciones de openFDA.
- Tablas "largas" en vez de listas dentro de celdas:

| Tabla | Filas | Contenido |
|---|---|---|
| `estudios` | 4 347 | un estudio por fila (estado, inscritos, fechas, si es activo) |
| `estudios_paises` | 6 720 | un par estudio-país |
| `ubicaciones` | 39 474 | una sede por fila (país, ciudad), hecha con `json_normalize` |
| `reportes` | 500 | un reporte de openFDA por fila (edad en años) |
| `reportes_reacciones` | 1 539 | un par reporte-reacción |
| `reacciones_servidor` | 500 | conteo de reacciones sobre todos los reportes |
| `pubmed_por_anio` | 27 | publicaciones por año, con el último año marcado como parcial |

### Comprobación cruzada
Los pares estudio-país obtenidos de los modelos validados y los obtenidos con `json_normalize` son **idénticos** (3 971 estudios con país), así que las dos rutas coinciden.

### Dos trampas de `json_normalize` (encontradas al hacerlo)
1. **`record_path` exige que todos los elementos tengan esa ruta.** Los 376 estudios sin sedes lo rompieron (`KeyError: 'locations'`); hubo que filtrarlos antes.
2. **Con una ruta anidada en `meta`, falló en silencio.** `errors="ignore"` rellenó el identificador del estudio con `NaN` en las 39 474 filas, sin aviso, porque pandas buscó `nctId` relativo a cada sede. Con `errors="raise"` sí avisa. La solución fue subir el identificador al nivel superior y usar `errors="raise"`.

### Decisión sobre 2026 en PubMed
Los datos de 2026 llegan hasta el 14 de octubre. En lugar de recortar el análisis a 2025, se **documenta el alcance**: la tendencia se describe con los años completos (2000-2025) y 2026 se muestra aparte, marcado como parcial, para que no parezca un descenso real.

### Resultados (detalle y gráficas en el notebook)
- **Ensayos activos:** 1 291 de 4 347 (30 %). Por país lideran China (516), Estados Unidos (348) y Corea del Sur (126). 131 de los activos no tienen país y quedan fuera del análisis geográfico.
- **Eventos adversos de capecitabina** (5 759 reportes con indicación gástrica): diarrea (13.0 %), náusea (10.7 %) y vómito (9.5 %) encabezan la lista; el síndrome mano-pie (eritrodisestesia palmo-plantar) aparece en 5.7 %. Sin denominador, no se estima incidencia.
- **PubMed:** de 1 592 publicaciones en 2000 a 4 622 en 2025 (×2.9); el máximo entre años completos es 2022 (4 836) y de 2015 a 2025 el crecimiento es de solo ×1.08. 2026 (parcial) lleva 3 063.

## Observaciones propias

### 1. Interpretación farmacológica y oncológica de los eventos adversos (openFDA)
La distribución de eventos adversos refleja el perfil toxicológico conocido de la capecitabina, pero requiere cautela analítica al distinguir toxicidad farmacológica de desenlaces oncológicos:
* **Toxicidad gastrointestinal y dermatológica concordante:** La diarrea (13.0 %) y el síndrome mano-pie (eritrodisestesia palmo-plantar, 5.7 %) representan las toxicidades dosis-limitantes clásicas del fármaco, mientras que la náusea y el vómito suelen manifestarse con menor severidad clínica sin condicionar habitualmente la interrupción del tratamiento. La capecitabina actúa como un profármaco del 5-fluorouracilo (5-FU) activado intratumoralmente por la timidina fosforilasa; el daño directo al epitelio intestinal por recambio celular rápido sustenta la afección digestiva, mientras que el mecanismo molecular exacto del síndrome mano-pie aún no se encuentra plenamente esclarecido en la literatura (atribuyéndose de forma preliminar a la acumulación local de metabolitos o a la expresión enzimática diferencial en palmas y plantas).
* **Confusión entre evento adverso y progresión tumoral:** La presencia de "muerte" y "progresión de la enfermedad" dentro de los reportes evidencia los límites intrínsecos de MedDRA y los sistemas de notificación espontánea (FAERS/openFDA). En pacientes con adenocarcinoma gástrico avanzado, el fallecimiento y la progresión reflejan la evolución natural de la enfermedad subyacente y no necesariamente un efecto adverso atribuible al fármaco.
* **Frecuencia relativa vs. Incidencia real:** Al no disponer del denominador total de pacientes tratados con capecitabina (la cohorte real expuesta), estos porcentajes solo cuantifican la frecuencia relativa dentro de las notificaciones enviadas al sistema, no una tasa de incidencia epidemiológica.

### 2. Geografía de los ensayos clínicos activos: consideraciones epidemiológicas y sesgos de registro
La concentración de ensayos activos en China (516), Estados Unidos (348) y Corea del Sur (126) permite plantear hipótesis tanto epidemiológicas como operativas:
* **Hipótesis epidemiológica en Asia Oriental:** La alta prevalencia de cáncer gástrico en la región —ampliamente asociada a cepas virulentas de *Helicobacter pylori* (como CagA positiva) y factores dietéticos específicos— ofrece una base poblacional amplia para el reclutamiento. No obstante, los datos analizados corresponden únicamente a conteos de sedes registradas y no permiten establecer una relación causal directa con determinantes biológicos.
* **El sesgo de registro (el caso de Japón):** A pesar de que Japón presenta una de las tasas de incidencia más elevadas del mundo, figura en la séptima posición con solo 73 estudios. Esto subraya que ClinicalTrials.gov no representa un censo exhaustivo global: en Japón, gran parte de la investigación clínica local se inscribe preferentemente en registros nacionales integrados a la red primaria de la OMS (JAPIC, JMACCT o UMIN-CTR), lo que introduce un sesgo de cobertura territorial en la plataforma de la NLM.
* **Capacidad de inversión:** El liderazgo conjunto de China y Estados Unidos refleja primordialmente la concentración de infraestructura biofarmacéutica y grandes centros oncológicos con capacidad económica y regulatoria para sostener estudios multicéntricos.

### 3. Dinámica temporal en PubMed: estancamiento histórico y sesgos de indexación
La serie temporal de artículos indexados bajo el descriptor MeSH *Stomach Neoplasms* exhibe una dinámica más compleja que una simple caída reciente:
* **Cronología de la meseta (2014–2025):** Tras un incremento sostenido a inicios de siglo (crecimiento de ×1.52 entre 2010 y 2014, pasando de 2,888 a 4,381 artículos), el volumen global entró en una meseta prolongada (factor de ×1.08 entre 2015 y 2025). Dicha meseta tuvo oscilaciones marcadas: una contracción hacia 2017 (3,974), una recuperación sostenida entre 2018 y 2022 (alcanzando el pico máximo histórico de 4,836), y un posterior reajuste a la baja entre 2023 y 2025 (~4,630 artículos; un factor de ×0.98 respecto a 2020).
* **Consistencia del descriptor temático:** La estabilización del volumen total no puede explicarse simplemente por el auge de nuevas modalidades terapéuticas (inmunoterapia o terapias dirigidas), ya que el descriptor MeSH *Stomach Neoplasms* engloba la patología en su conjunto independientemente del enfoque experimental. Más que un abandono del área, la meseta general sugiere una maduración en la tasa global de publicaciones del campo o un desplazamiento en la terminología primaria empleada.
* **Retraso de curación (*indexing lag*) y corte de 2026:** Mantener 2026 documentado como año parcial (3,063 artículos acumulados a octubre) previene interpretaciones erróneas de desplome. Adicionalmente, debe considerarse la latencia inherente del NCBI en la asignación manual de términos MeSH a publicaciones recientes (frecuentemente indexadas inicialmente solo como registros en proceso), lo que explica que el volumen a tres cuartos de año quede por debajo de la proporción lineal esperada.

### 4. Vulnerabilidad en transformaciones complejas: la trampa silenciosa de `json_normalize`
La experiencia al desanidar estructuras jerárquicas dejó dos lecciones técnicas fundamentales:
* **Fallas silenciosas vs. Excepciones:** Mientras que los 376 estudios sin sedes levantaron un error explícito en `record_path` que obligó a contemplar ramas vacías, la extracción con rutas anidadas en `meta` derivó en una falla inadvertida: 39,474 registros con identificador nulo (`NaN`). Este tipo de anomalía asintomática, que no interrumpe la ejecución pero invalida por completo el enlace relacional entre entidades, demuestra la necesidad de auditar formalmente la cardinalidad y la integridad referencial tras cada transformación tabular.
* **Normalización de cadenas en cruces de datos:** La discrepancia de mayúsculas entre las reacciones de openFDA y los registros locales evidenció la necesidad de homogeneizar el texto libre (mediante transformaciones uniformes como `.str.upper()` en el código) antes de ejecutar agregaciones o combinaciones relacionales.
