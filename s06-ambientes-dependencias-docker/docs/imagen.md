# Imagen de clinlab: mediciones

<!-- Aquí va cada número que midas, con el comando que lo produjo. -->

## 0. Contexto de build inicial

### Medición inicial del repositorio
Para evaluar el volumen de datos que Docker transferiría al daemon durante el proceso de construcción, se midió el tamaño del directorio raíz mediante:

```bash
du -sh .                           # total con .git
du -sh --exclude=.git .            # total sin .git
du -sh s05-buenas-practicas-pytest/.venv
```

- Tamaño total con `.git`: ~339 MB
- Tamaño total sin `.git`: ~334 MB
- `.venv`: ~290 MB
- Código fuente útil (`src/`, `tests/`, `docs/`): ~0.4 MB

La carpeta que pesa en gran medida es `.venv`, con unos 290 MB. No debería agregarse a la imagen: los entornos virtuales incluyen binarios compilados y optimizados para el entorno local, y podrían no funcionar en otro sistema o distribución de Linux. Esto choca con la idea de que la imagen de Docker es reproducible.

Además, enviar cientos de MB innecesarios puede ralentizar drásticamente el paso "Sending build context to Docker daemon", invalida la caché de Docker y genera imágenes redundantes e infladas.

## 1. Lockfile y dependencias transitivas

### Herramienta y comando
<!-- Qué usaste (uv lock), desde qué carpeta lo corriste y dónde quedó el uv.lock.
     Incluye cuántos paquetes resolvió. -->
Se usó `uv` como gestor de paquetes y entornos en Python. Se corrió desde la carpeta `s05-buenas-practicas-pytest`, y ahí mismo quedó el archivo `uv.lock`.

`uv lock` resolvió 135 paquetes.

### Por qué es determinista
<!-- En 2-3 líneas: qué fija el lockfile que el pyproject.toml no fija
     (versiones exactas y hashes). -->
El pyproject.toml solo define dependencias directas sin fijar versión (ej. pandas), mientras que el lockfile fija las versiones exactas de todo el árbol (incluyendo dependencias transitivas), sus hashes criptográficos de integridad y la resolución exacta por plataforma/arquitectura.

### Tres dependencias transitivas
<!-- Una tabla o lista con: transitiva | directa de la que viene | cadena. -->
| Transitiva | La trae | Cadena |
| :--- | :--- | :--- |
| numpy | pandas | clinlab → pandas → numpy |
| python-dateutil | pandas | clinlab → pandas → python-dateutil |
| arrow | jupyterlab | clinlab →(extra notebook)→ jupyterlab →<br>jupyter-server → jupyter-events → jsonschema →<br>isoduration → arrow |

### Por qué el .venv pesa 290 MB
<!-- Tu respuesta a la pregunta pendiente. Pistas: cuántos paquetes tiene
     el lock y qué extras instalaste en ese .venv. -->
El archivo tiene ese peso debido a que incluye librerías como numpy o pandas que están compiladas en otros lenguajes de programación (como C, C++ o Rust), las cuales son extremadamente pesadas, llegando a pesar para este caso concreto 140 MB.

Se incluyen diferentes herramientas como mypy, pesando bastante (54 MB). pip pesa unos 16 MB y finalmente el resto de paquetes consume cerca de 80 MB repartidos entre pytest, ruff, hypothesis, virtualenv, pre-commit.

Herramientas como mypy, pytest, ruff o hypothesis provienen exclusivamente del extra dev y no forman parte del núcleo de clinlab; cargarlas en el entorno es la razón directa de que el .venv duplique su peso con utilidades que solo sirven para desarrollar y no para ejecutar.

Consecuencia para Docker: Instalar dependencias de desarrollo en el contenedor genera una imagen innecesariamente pesada, más lenta de construir y desplegar, y con una mayor superficie de vulnerabilidades de seguridad.

### Moraleja
<!-- 2-3 líneas con tus palabras. -->
El lockfile resuelve el universo completo de dependencias y plataformas posibles, pero el .venv y la imagen de producción solo deben materializar lo indispensable para su entorno específico; distinguir entre dependencias de runtime y de desarrollo evita que las librerías transitivas inflen el peso del contenedor y del disco sin aportar valor funcional.

## 2. Orden malo del Dockerfile

Para evaluar el impacto de la invalidación de la caché en esta estructura, se cronometraron dos ejecuciones con comandos distintos:

1. **Construcción inicial desde cero (19.9 s):** Se forzó a ignorar cualquier caché previa mediante la opción `--no-cache`:
   ```bash
   time docker build --no-cache -f s06-ambientes-dependencias-docker/Dockerfile -t clinlab:malo .
   ```
2. **Reconstrucción tras cambio en código (17.7 s):** Tras agregar únicamente un comentario al código fuente (`src/clinlab/`), se ejecutó permitiendo el uso normal de caché:
   ```bash
   time docker build -f s06-ambientes-dependencias-docker/Dockerfile -t clinlab:malo .
   ```

 Cabe destacar que para una medición justa y honesta, la imagen base (`python:3.12-slim`) ya se encontraba previamente descargada en el sistema local, por lo que ese tiempo no incluye la descarga inicial de capas base.

Al hacer el rebuild, Docker sí aprovechó la caché en las primeras dos capas (`WORKDIR` marcó `CACHED`). Sin embargo, el mecanismo se rompió inmediatamente en la tercera instrucción (`COPY s05-buenas-practicas-pytest/ ./`) al detectar la modificación del archivo, arrastrando consigo en cascada a `RUN pip install --no-cache-dir .`.

Como consecuencia, el rebuild tardó apenas ~2 s menos que compilar desde cero (17.7 s vs. 19.9 s): la caché prácticamente no ayudó, ya que el paso más costoso en tiempo y descarga volvió a ejecutarse por completo.

## 3. Orden bueno y tabla comparativa

### El Dockerfile reordenado

| Aspecto | Orden malo (`ba41cfc`) | Orden bueno (actual) |
| :--- | :--- | :--- |
| **Copia** | La carpeta `s05-.../` entera de golpe | Primero solo `pyproject.toml` + `uv.lock`; el código (`src/`) después |
| **Instala con** | `pip install --no-cache-dir .` (una vez, al final) | `uv sync --frozen --no-dev --no-install-project` (dependencias) y luego `uv sync --frozen --no-dev` (el paquete `clinlab`) |
| **Entorno** | Paquetes en el Python del sistema | Entorno virtual en `/app/.venv`, activado con `ENV PATH` |
| **uv** | No se usaba | Copiado desde `ghcr.io/astral-sh/uv:0.13.0` |

* **Doble llamada a `uv sync`:** Aparece dos veces porque la primera instala únicamente las dependencias externas (`--no-install-project`) cuando aún no existe la carpeta `src/` en el contenedor, dejando esa capa pesada en caché; la segunda se ejecuta después de copiar el código fuente e instala únicamente el paquete local `clinlab`.
* **Versión de `uv` fijada (`0.13.0`):** Usar la etiqueta `latest` haría que la versión de la herramienta cambie con el tiempo, rompiendo la reproducibilidad. El archivo `uv.lock` fija las versiones de los paquetes de Python, pero no la versión de `uv` que los instala.
* **Uso de `--frozen`:** Obliga a `uv` a instalar exactamente las versiones registradas en `uv.lock` sin resolver ni recalcular el árbol de dependencias durante el build.

### Cómo se midió

Todas las pruebas se cronometraron con `time` ejecutando desde la raíz del repositorio:

* **Build desde cero:** `time docker build --no-cache -f s06-ambientes-dependencias-docker/Dockerfile -t clinlab:bueno .`
* **Rebuild tras cambiar código:** Se agregó un comentario en `clasificacion.py`, se guardó el archivo y se ejecutó `time docker build -f s06-ambientes-dependencias-docker/Dockerfile -t clinlab:bueno .` (sin `--no-cache`).
* **Rebuild tras cambiar una dependencia:** Se añadió `tabulate` a la lista `dependencies` en `pyproject.toml` como dependencia de prueba (después se revirtió), se regeneró el bloqueo con `uv lock` y se reconstruyó la imagen con la caché activa.
* **Medición del orden malo:** Las primeras dos mediciones se realizaron en la actividad 2, con el Dockerfile del repo en ese entonces; posteriormente, para la tercera medición, se recuperó el Dockerfile original del commit `ba41cfc` y se construyó apuntando con `-f` a un archivo temporal..

### Resultados

| Escenario | Orden malo | Orden bueno |
| :--- | :--- | :--- |
| **Build desde cero** | 19.9 s | 7.1 s |
| **Rebuild tras cambiar código** | 17.7 s | 1.8 s |
| **Rebuild tras cambiar una dependencia** | 19.1 s | 5.9 s |

* **Cambio de código (orden bueno):** Los pasos 2 al 5 se mantienen en caché (`CACHED`); únicamente se rehacen el `COPY` de `src/` (paso 6) y el segundo `uv sync` (paso 7).
* **Cambio de dependencia (orden bueno):** Solo los pasos 2 y 3 salen como `CACHED`; se rehacen en cascada desde el paso 4 hasta el 7 (incluyendo el paso 6 de copia de código, aunque este no haya cambiado).
* **Orden malo:** En cualquiera de los escenarios se invalida el `COPY` global de toda la carpeta y se rehace el `pip install`, volviendo a descargar e instalar `pandas` y `numpy` desde cero.

### Análisis y salvedades

La ventaja principal se obtiene al modificar el código fuente, donde el tiempo cae de **17.7 s a 1.8 s** (~10 veces más rápido), optimizando la tarea más frecuente durante el desarrollo. Cuando se añade una dependencia nueva el orden nuevo no mantiene la ventaja que había ganado, ya que es muy costosa en términos de tiempo la instalación que debe rehacerse. Por otro lado, el orden "malo" no tiene este problema al presentar una "tarifa" plana igual de mala siempre sin importar los cambios.

* **Efectos mezclados entre versiones:** Entre ambos Dockerfiles también cambió la herramienta (`pip` a `uv`) y el tamaño del contexto enviado al demonio de Docker (el orden malo enviaba el `.venv` local sumando ~298 MB de contexto, frente a solo 698 kB en el orden bueno). Por ello, las filas 1 y 3 mezclan el impacto de `uv` y del contexto reducido, mientras que la fila 2 es la que mejor aísla el efecto puro del orden de las capas.
* **Descarga de imágenes base:** La imagen `python:3.12-slim` ya estaba descargada localmente antes de medir; sin embargo, en el build desde cero del orden bueno sí se descargó por primera vez la imagen de `uv` (~20 MB).
* **Corrida única:** Cada valor registrado corresponde a una sola medición y no al promedio de varias ejecuciones.

### Moraleja

En un Dockerfile el orden de las instrucciones es sumamente importante, ya que esto nos permite determinar qué cosas se pueden reutilizar. 

## 4. Tamaño de la imagen

## 5. `.dockerignore` y contexto

## 6. Usuario no-root

## 7. Secretos en capas

## 8. Escaneo de vulnerabilidades

## 9. Pruebas dentro del contenedor

## 10. Publicación en ghcr.io
