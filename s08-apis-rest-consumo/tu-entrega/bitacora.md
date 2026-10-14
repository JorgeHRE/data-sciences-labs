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
