# --- Etapa 1: Imagen de construcción (builder) ---
# 1. Imagen base
FROM python:3.12-slim AS builder

# 2. Copiar el binario oficial de uv
COPY --from=ghcr.io/astral-sh/uv:0.13.0 /uv /bin/uv

# 3. Directorio de trabajo
WORKDIR /app

# 4. Copiar SOLO manifiestos de dependencias (cambian poco)
COPY s05-buenas-practicas-pytest/pyproject.toml s05-buenas-practicas-pytest/uv.lock ./

# 5. Instalar dependencias externas respetando el lock (capa pesada, se cachea)
RUN uv sync --frozen --no-dev --no-install-project

# 6. Copiar el código fuente (cambia frecuentemente)
COPY s05-buenas-practicas-pytest/src/ ./src/

# 7. Instalar el paquete clinlab (capa ligera y rápida)
RUN uv sync --frozen --no-dev --no-editable


# --- Etapa 2: Imagen de pruebas (test) ---
FROM builder AS test

# Instalar dependencias de desarrollo (usando --extra porque están en [project.optional-dependencies])
RUN uv sync --frozen --extra dev

# Copiar los tests al contenedor (requiere actualizar .dockerignore)
COPY s05-buenas-practicas-pytest/tests/ ./tests/

# Activar el entorno virtual para esta etapa
ENV PATH="/app/.venv/bin:$PATH"

# Comando por defecto para correr los tests
CMD ["pytest"]


# --- Etapa 3: Imagen final de ejecución (producción) ---
FROM python:3.12-slim

WORKDIR /app

# Crear usuario restringido
RUN useradd -m appuser

# Traer únicamente el entorno virtual ya construido desde la etapa builder
COPY --from=builder --chown=appuser:appuser /app/.venv /app/.venv

# 8. Activar el entorno virtual para tiempo de ejecución
ENV PATH="/app/.venv/bin:$PATH"

# Usuario no root para seguridad
USER appuser

# 9. Comando por defecto al iniciar el contenedor
CMD ["python", "-c", "import clinlab"]
