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

### Método y tabla de resultados

Los tamaños se midieron con la columna `SIZE` de `docker images`, construyendo cada variante desde la raíz del repositorio con la opción `-f` apuntando a los archivos en `s06-ambientes-dependencias-docker/tamanos/` (`Dockerfile.0-ingenuo` a `Dockerfile.5-alpine`):

```bash
docker build -f s06-ambientes-dependencias-docker/tamanos/Dockerfile.<paso> -t clinlab:<tag> .
docker images clinlab
```

En cada paso se modificó una sola cosa respecto al anterior, **salvo en dos transiciones** donde el cambio de tamaño combina dos ajustes necesarios para que la imagen funcionara:
* **`t3` → `t4`:** Además de separar en dos etapas (multi-stage), se introdujo un entorno virtual con `python -m venv` que `t3` no tenía.
* **`clinlab:bueno` → `clinlab:final`:** Además de pasar de una etapa a dos etapas, se añadió la opción `--no-editable` en el segundo `uv sync`.

| Paso | Imagen | Qué cambia | Tamaño | Diferencia |
| :--- | :--- | :--- | :--- | :--- |
| **0** | `clinlab:t0` | `python:3.12`, `COPY` de la carpeta `s05` entera, `pip install .` sin `--no-cache-dir`, sin `.dockerignore` | 2.28 GB | — |
| **1** | `clinlab:t1` | base `python:3.12-slim` | 857 MB | −1 423 MB |
| **2** | `clinlab:t2` | `pip install --no-cache-dir .` | 800 MB | −57 MB |
| **3** | `clinlab:t3` | `Dockerfile.3-ignore.dockerignore` (excluye `.venv`, `.env*`, cachés, `__pycache__`, `*.pyc`, `.git`) | 384 MB | −416 MB |
| **4** | `clinlab:t4` | multi-stage con `venv` + `pip` (añade `python -m venv`) | 385 MB | +1 MB |
| **Aparte** | `clinlab:t5` | `python:3.12-alpine` en lugar de `slim` (con paso 3) | 303 MB | −81 MB respecto a `t3` |
| **Final** | `clinlab:bueno` → `clinlab:final` | Dockerfile con `uv`: una etapa → dos etapas + `uv sync --no-editable` | 385 MB → 307 MB | −78 MB |

El objetivo del enunciado era dejar la imagen por debajo de 500 MB; el resultado final (`clinlab:final`) fue de **307 MB**.

#### Capas medidas con `docker history`

| Capa | `t0` (`python:3.12`) | `t1` (`slim`) | `t2` | `t3` |
| :--- | :--- | :--- | :--- | :--- |
| **`COPY` de la carpeta `s05`** | 323 MB | 323 MB | 323 MB | 1.13 MB (contexto: 3.02 kB) |
| **`pip install`** | 189 MB | 189 MB | 160 MB (`--no-cache-dir`) | 160 MB |

---

### El hallazgo del multi-stage: `pip` vs. `uv`

* **Con `pip` (`t3` → `t4`, de 384 MB a 385 MB):** El multi-stage no redujo el tamaño y sumó 1 MB. En `t3` (una sola etapa sin entorno virtual), la capa `COPY` pesó 1.13 MB y la capa `pip install` pesó 160 MB (dentro de ella, `site-packages` ocupaba 154 MB —`pandas` 72 MB, `numpy` 43 MB, `numpy.libs` 27 MB y `pip` 12 MB— y `/root/.cache` ocupaba 2 MB). Al pasar a `t4`, se creó un entorno virtual con `python -m venv` en la etapa de construcción para copiarlo a la etapa final: la capa `COPY /app/.venv` resultante en `t4` pesó **162 MB**, superando por un estrecho margen las capas de `pip install` (160 MB) y `COPY` (1.13 MB) de `t3`. Como las librerías se instalaron desde *wheels* precompilados y no se instalaron compiladores adicionales en la etapa de build, no había herramientas pesadas que descartar.
* **Con `uv` (`clinlab:bueno` → `clinlab:final`, de 385 MB a 307 MB):** Aquí el cambio redujo **78 MB** (combinando la separación en dos etapas y el flag `--no-editable`). En el Dockerfile de una sola etapa (`clinlab:bueno`), la imagen cargaba con la capa del binario de `uv` (45.1 MB), la caché en `/root/.cache` (5.6 MB) y el código fuente en `src/`. En la versión de dos etapas (`clinlab:final`), la etapa final parte de `python:3.12-slim` limpia y solo copia `/app/.venv`, dejando atrás tanto el binario de `uv` (`which uv` ya no lo encuentra) como `src/`.
* **El efecto de `--no-editable`:** Con `uv sync` por defecto (modo editable), el entorno virtual contiene el archivo `__editable__.clinlab-0.1.0.pth` que apunta a `/app/src`. Como en la etapa final esa carpeta no existe, ejecutar `import clinlab` fallaba con `ModuleNotFoundError`. Al añadir `--no-editable`, la carpeta `clinlab` se instala directamente dentro de `site-packages` y `docker run --rm clinlab:final` termina con código 0.

---

### El experimento con Alpine

* **Hipótesis inicial:** La predicción constaba de dos partes: que la imagen con Alpine **sería más chica**, pero que **`pip install` fallaría compilando** al no contar con compiladores de C para construir `pandas` y `numpy`.
* **Qué pasó y por qué:** Se cumplió la mitad de la hipótesis (sí fue más chica) y falló la otra mitad (no hubo error de compilación). La construcción terminó sin errores y dejó la imagen en **303 MB** (−81 MB respecto a los 384 MB de `t3`). No hizo falta compilar nada porque PyPI ya distribuye *wheels* precompilados para sistemas basados en `musl`: el registro del build mostró la descarga de `pandas-3.0.6-...musllinux_1_2_x86_64.whl` (11.8 MB) y `numpy-2.5.4-...musllinux_1_2_x86_64.whl` (18.5 MB). Esos binarios `musllinux` son un poco más grandes que sus equivalentes `manylinux` en `slim` (10.8 MB y 16.7 MB), por lo que la capa `pip install` en Alpine pesó 170 MB frente a los 160 MB en `t3`. La prueba `import clinlab, pandas` funcionó sin problemas (pandas 3.0.6 sobre Alpine Linux), aunque no se corrieron los tests en esta imagen.

---

### Discrepancias y salvedades

#### Estimaciones frente a mediciones reales

| Qué | Estimado | Medido |
| :--- | :--- | :--- |
| **Tamaño de `t0`** | ~1.4–1.5 GB | 2.28 GB |
| **Ahorro del `.dockerignore`** | ~300 MB | 416 MB |
| **Ahorro del multi-stage con `pip`** | ~100 MB | +1 MB |
| **Resultado de `alpine`** | `pip install` falla compilando | no falló (*wheels* `musllinux`) |
| **Ahorro del multi-stage con `uv`** | ~50 MB | 78 MB |

* **La suma de las capas de `docker history` no coincide con `docker images`:**
  * Las capas de la base `slim` suman ~134 MB (87.7 + 4.94 + 41.4 MB). En `t1`, al sumar esa base con el `COPY` (323 MB) y el `pip install` (189 MB) se obtienen ~646 MB, pero `docker images` reporta **857 MB** (una diferencia de ~210 MB sin causa identificada). De igual modo, en `t2` la suma por capas da ~617 MB frente a los **800 MB** que muestra `docker images`.
  * Las reducciones en el tamaño total de `docker images` también fueron mayores que la diferencia individual de la capa modificada: al pasar de `t1` a `t2`, la capa `pip install` bajó 29 MB (de 189 a 160 MB) y la imagen total bajó **57 MB** (de 857 a 800 MB); al pasar de `t2` a `t3`, la capa `COPY` bajó 322 MB (de 323 a 1.13 MB) y la imagen total bajó **416 MB** (de 800 a 384 MB).
* **Corrida única:** Cada medición corresponde a una sola ejecución.

---

### Moraleja

Optimizar el peso de una imagen de Docker exige medir en lugar de asumir: más del 90 % del ahorro total provino de dos decisiones básicas —elegir la imagen base adecuada (−1 423 MB) y excluir el entorno local con `.dockerignore` (−416 MB)—, mientras que patrones más complejos como el *multi-stage* solo aportan valor real cuando la etapa de construcción introduce peso extra que no pertenece a producción (como el binario de `uv`).
## 5. `.dockerignore` y contexto

### Cómo se midió el contexto

Para medir el tamaño real del contexto enviado al demonio de Docker se ejecutó la construcción desactivando BuildKit desde la raíz del repositorio:

```bash
DOCKER_BUILDKIT=0 docker build -f s06-ambientes-dependencias-docker/Dockerfile -t clinlab:final .
```

El flag `DOCKER_BUILDKIT=0` es necesario porque fuerza el uso del builder clásico, el cual empaqueta todo el directorio y muestra en su primera línea (`Sending build context to Docker daemon...`) el peso total transferido. El constructor por defecto (BuildKit) solo transfiere archivos de manera incremental según los `COPY` del Dockerfile y no sirve para medir el volumen total del contexto.

---

### Contexto antes y después

| Dato | Valor |
| :--- | :--- |
| **Contexto antes (sin exclusiones, builder clásico)** | **337.2 MB** (`Sending build context to Docker daemon`, `DOCKER_BUILDKIT=0`) |
| **Contexto después (`.dockerignore` de lista blanca)** | **716.3 kB** (reducción de ~99.8 %) |
| **Archivos que llegan al contexto** | **8** (casi todo el peso corresponde a `uv.lock` con ~690 kB; el código fuente ocupa unas decenas de kB) |
| **Estado de la imagen final** | **308 MB** (antes 307 MB; arranca con código 0 y la diferencia de 1 MB es ruido de medición sin cambio de contenido) |

#### Lo que se enviaba sin querer en los 337.2 MB

Al ejecutar el build desde la raíz del monorepo sin reglas de exclusión, Docker empaquetaba y enviaba en el contexto directorios y cachés que `clinlab` no necesita para construirse:

* **`s05-buenas-practicas-pytest/` (309 MB en total):** Incluye el entorno virtual `.venv/` (290 MB), `.mypy_cache/` (18 MB) y el resto de archivos (~1 MB, dentro de los cuales están los 716.3 kB de `pyproject.toml`, `uv.lock` y `src/` que sí requiere la imagen).
* **`.mypy_cache/` de la raíz (18 MB):** Caché de verificación de tipos generada en la raíz del monorepo.
* **`Lab3/` (8 MB):** Carpeta de otra práctica que por sí sola aportaba más peso al contexto que el propio historial de Git.
* **`.git/` (7 MB):** Historial de commits y objetos del repositorio.
* **`.ruff_cache/`, `Lab2/`, `s04-git-github/`, `s06-ambientes-dependencias-docker/`, `.github/` y archivos sueltos (~1 MB o menos cada uno):** Cachés adicionales, prácticas previas, los propios Dockerfiles de prueba y archivos de configuración de la raíz (`.pre-commit-config.yaml`, `README.md`).

En conjunto, la suma de estos directorios explica el tamaño total del contexto inicial: 309 + 18 + 8 + 7 + el resto ≈ **337 MB** (337.2 MB medidos con el builder clásico).

---

### La decisión de diseño: Opción C (lista blanca en la raíz + archivos vacíos)

Para cumplir con el estándar de tener un `.dockerignore` en la raíz sin arruinar los experimentos de la sección 4, se evaluaron tres alternativas:
* **Opción A (`.dockerignore` solo en la raíz):** Es el estándar compatible con todos los builders y sistemas de CI, pero afectaría también a las variantes `0-ingenuo`, `1-slim` y `2-nocache`, que dejarían de ser construcciones «sin exclusiones».
* **Opción B (mantener solo `<Dockerfile>.dockerignore` por archivo):** No altera los experimentos, pero depende exclusivamente de BuildKit y no reduce el contexto con el builder antiguo.
* **Opción C (elegida — `.dockerignore` en la raíz + archivos vacíos para las variantes 0–2):** Se creó un `.dockerignore` en la raíz estructurado como **lista blanca** (excluyendo todo con `*`, des-excluyendo únicamente `!s05-buenas-practicas-pytest/pyproject.toml`, `!s05-buenas-practicas-pytest/uv.lock` y `!s05-buenas-practicas-pytest/src/`, y volviendo a excluir cachés al final) y se añadieron tres archivos vacíos (`Dockerfile.0-ingenuo.dockerignore`, `Dockerfile.1-slim.dockerignore` y `Dockerfile.2-nocache.dockerignore`). Así se entrega un archivo estándar en la raíz y, al mismo tiempo, las variantes 0–2 conservan su reproducibilidad en BuildKit a cambio de mantener tres archivos vacíos adicionales.

---

### Hallazgos durante la implementación

1. **Diferencia entre BuildKit y el builder clásico con `<Dockerfile>.dockerignore`:**
   * Al medir `Dockerfile.3-ignore` (que tenía su propio `Dockerfile.3-ignore.dockerignore`) usando `DOCKER_BUILDKIT=0`, el contexto enviado siguió siendo de **337.2 MB**, mientras que en BuildKit sí había bajado a **3.02 kB**.
   * Esto reveló que los archivos con nombre `<Dockerfile>.dockerignore` solo los lee **BuildKit**. El builder clásico busca únicamente un archivo llamado `.dockerignore` en la raíz del contexto. Como consecuencia, el truco de la Opción C (usar un `Dockerfile.N.dockerignore` vacío para pisar al `.dockerignore` de la raíz) funciona en BuildKit, pero con el builder clásico el archivo vacío es ignorado y prevalece el `.dockerignore` de la raíz.
2. **El artefacto `egg-info` infiltrado dentro de `src/`:**
   * Aunque la lista blanca del `.dockerignore` solo abría paso a `pyproject.toml`, `uv.lock` y `src/`, la primera medición dejó pasar los metadatos generados en `src/clinlab.egg-info/` porque vivían dentro de una carpeta permitida (`!s05-buenas-practicas-pytest/src/`).
   * Como en `.dockerignore` gana la última regla que coincide, fue necesario agregar explícitamente `**/*.egg-info` en el tercer bloque (junto a `**/__pycache__` y `**/*.pyc`) para volver a excluir esos artefactos, dejando el contexto en los **716.3 kB** finales (8 archivos).

---

### Moraleja

En un monorepo, escribir un `.dockerignore` como lista blanca (`*` seguido de excepciones con `!`) es mucho más seguro y fácil de mantener que una lista negra interminable, pero exige recordar dos reglas: que abrir una carpeta como `src/` también deja entrar los artefactos ocultos que se generen dentro de ella (`__pycache__`, `*.egg-info`), y que las funciones avanzadas como `<Dockerfile>.dockerignore` dependen de BuildKit y son ignoradas por el builder clásico.

## 6. Usuario no-root

### El riesgo mitigado
Evita que un atacante con ejecución de código en la aplicación pueda instalar malware o alterar archivos críticos del sistema. Al aplicar el principio de mínimo privilegio y defensa en profundidad, el daño queda contenido y se reduce el riesgo de afectar a la máquina anfitriona mediante volúmenes o fallos del *runtime*.

### Estado anterior e implementación
Por defecto, la etapa final (`python:3.12-slim`) no especificaba un usuario, por lo que la instrucción `docker run --rm clinlab:final id` devolvía privilegios absolutos: `uid=0(root) gid=0(root) groups=0(root)`.

Para aislar el proceso, se añadieron tres instrucciones al final del `Dockerfile` (en la etapa de ejecución), estrictamente en este orden:

1. **`RUN useradd -m appuser`**: Crea el usuario local dentro de la imagen. Es obligatorio que exista antes de intentar usarlo o asignarle archivos.
2. **`COPY --from=0 --chown=appuser:appuser /app/.venv /app/.venv`**: Transfiere el entorno virtual. Usar el *flag* `--chown` aquí (antes de las rutas) asigna la propiedad al vuelo, evitando usar un `RUN chown` posterior que duplicaría el peso de los archivos en una nueva capa.
3. **`USER appuser`**: Se coloca justo antes del `CMD`, asegurando que las tareas administrativas previas se hagan como root y que solo se bajen los privilegios en el instante final para ejecutar la aplicación.

*Nota sobre el proceso:* Llegar a esta estructura requirió iteración. Los errores comunes incluyeron colocar estas instrucciones en la etapa *builder* en lugar de la final, incluir un `COPY . /app` que arrastraba el contexto completo rompiendo el `.dockerignore`, y colocar el `--chown` al final de la línea, donde Docker lo interpreta erróneamente como una ruta de destino.

### Evidencia y validación

Tras corregir la sintaxis y el orden, la construcción fue exitosa, el tamaño de la imagen se mantuvo intacto (~307 MB) y la aplicación (`import clinlab`) arrancó sin errores con el nuevo usuario.

| Prueba en ejecución | Usuario activo | Resultado |
| :--- | :--- | :--- |
| `docker run --rm clinlab:final id` | `appuser` (por defecto) | `uid=1000(appuser) gid=1000(appuser) groups=1000(appuser)` |
| `docker run --rm clinlab:final sh -c 'touch /etc/x'` | `appuser` (por defecto) | `Permission denied` (escritura en sistema bloqueada) |
| `docker run --user root --rm clinlab:final sh -c 'touch /etc/x'` | `root` (forzado) | El archivo se creó exitosamente |

### Salvedades y moraleja

* **El límite de la directiva `USER`:** Como demuestra la tabla de pruebas, `USER` establece un comportamiento seguro por defecto, pero no es un candado inquebrantable. Alguien con acceso al demonio de Docker en el *host* puede sobrescribirlo usando `--user root`. Esta medida protege contra atacantes que vulneran la aplicación desde la red, no contra administradores maliciosos.
* **Tipología de usuario (`-m` vs. `--system`):** El comando `useradd -m` creó un usuario estándar (UID `1000`) con un directorio *home*. Para reducir aún más la superficie de ataque, sería preferible configurar un usuario de sistema (`--system --no-create-home --shell /usr/sbin/nologin` con un UID bajo), aunque a efectos prácticos de permisos de escritura, el nivel de bloqueo actual cumple el objetivo.

**Moraleja:** Un contenedor es un proceso aislado, no una caja fuerte. Si el mecanismo de aislamiento falla, la última línea de defensa son los permisos que el sistema operativo le concedió a ese proceso. Reducir esos permisos drásticamente cuesta apenas dos o tres líneas en un `Dockerfile`.

## 7. Secretos en capas

### El experimento y la falsa sensación de borrado
Para demostrar cómo Docker gestiona los archivos eliminados, se construyó una imagen de prueba (`secreto-prueba`) introduciendo un archivo `.env` falso (`API_KEY=falso-123-no-es-un-secreto-real`) y borrándolo inmediatamente en la siguiente instrucción. El `Dockerfile` constaba de tres pasos:

```dockerfile
FROM python:3.12-slim
COPY .env /app/.env      # Capa A: introduce el secreto
RUN rm /app/.env         # Capa B: intenta borrarlo
```

Al ejecutar un contenedor a partir de esta imagen (`docker run --rm secreto-prueba cat /app/.env`), el sistema devolvió `No such file or directory`. Aparentemente, el archivo había sido eliminado con éxito.

### Evidencia: recuperación del secreto
A pesar de que el archivo no era visible en el contenedor en ejecución, el secreto seguía vivo dentro de la imagen. La evidencia se recolectó por dos vías:
* **El historial de capas:** `docker history --no-trunc secreto-prueba` reveló que las instrucciones crearon dos capas separadas e intactas: una para `COPY .env /app/.env` (12.3 kB) y otra para `RUN rm /app/.env` (8.19 kB).
* **Inspección del sistema de archivos:** Al exportar la imagen con `docker save` y descomprimir el archivo `.tar`, se comprobó el contenido real de los directorios internos. La capa original (`435e8077…`) contenía el archivo `app/.env` con el valor del secreto expuesto en texto plano. La capa posterior (`356a2a9d…`) contenía únicamente un archivo llamado `app/.wh..env`.

### Por qué ocurre esto
Este comportamiento es inherente a la naturaleza de las capas en Docker (sistemas de archivos de unión o *UnionFS*) y no tiene relación con la caché de construcción.
* Cada instrucción `COPY` y `RUN` crea una capa inmutable y permanente. La imagen final es simplemente la superposición de todas ellas.
* La instrucción `rm` no elimina los datos físicos de la capa anterior; en su lugar, crea una nueva capa que contiene una **marca de borrado** (*whiteout*, representada por el prefijo `.wh.`). 
* El contenedor oculta el archivo en tiempo de ejecución al leer la marca `.wh.`, pero la capa original (Capa A) viaja siempre dentro de la imagen, permitiendo que cualquiera con acceso al archivo comprimido recupere el secreto.

### La forma correcta: inyección en tiempo de ejecución
La manera segura de manejar variables sensibles es pasarlas únicamente cuando el contenedor arranca, utilizando banderas como `-e API_KEY=falso...` o `--env-file .env`. De este modo, el valor vive exclusivamente en la memoria del proceso y nunca se consolida en el disco de la imagen. Adicionalmente, el archivo `.env` debe incluirse en el `.gitignore` (y ya se encuentra excluido del contexto de construcción gracias al `.dockerignore` de lista blanca).

### Salvedades y limitaciones
* **Otras vías de filtración:** Este riesgo aplica a cualquier tipo de dato sensible (contraseñas, tokens, claves SSH). Además, declarar variables con `ENV` o `ARG` dentro del `Dockerfile` también es inseguro, ya que sus valores quedan registrados permanentemente en el `docker history`.
* **Límites de la inyección por CLI:** Pasar secretos con `-e` en producción no es la práctica definitiva, ya que el valor queda visible al ejecutar `docker inspect` y en el historial de la terminal del *host*. Para entornos reales, se requiere el uso de gestores de secretos dedicados o la inyección segura durante la construcción con BuildKit (`--mount=type=secret`).
* **El alcance del `.dockerignore`:** Aunque el `.dockerignore` en la raíz evita arrastrar secretos desde el repositorio local, no ofrece ninguna protección si el secreto se descarga, genera o clona dinámicamente durante un comando `RUN` en el proceso de construcción.

**Moraleja:** En una imagen de Docker, borrar no es borrar; cada capa es permanente e inmutable. Lo que no debe estar en la imagen final, no debe entrar jamás en ninguna de sus capas.

## 8. Escaneo de vulnerabilidades

## 9. Pruebas dentro del contenedor

## 10. Publicación en ghcr.io
