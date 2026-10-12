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

## 4. Tamaño de la imagen

## 5. `.dockerignore` y contexto

## 6. Usuario no-root

## 7. Secretos en capas

## 8. Escaneo de vulnerabilidades

## 9. Pruebas dentro del contenedor

## 10. Publicación en ghcr.io
