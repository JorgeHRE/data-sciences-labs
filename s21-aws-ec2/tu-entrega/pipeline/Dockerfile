# Imagen del pipeline auditoria_obs (lab 21). Construir DESDE LA RAÍZ DEL REPO:
#   docker build -f s21-aws-ec2/tu-entrega/pipeline/Dockerfile -t auditoria-obs:0.2.0 .
# El contexto es la raíz porque pyproject.toml instala clinlab por ruta desde s05.
# Qué entra al contexto: Dockerfile.dockerignore (lista blanca), junto a este archivo.

# --- Etapa 1: builder (uv + dependencias; no llega a la imagen final) ---
FROM python:3.12-slim AS builder
COPY --from=ghcr.io/astral-sh/uv:0.13.0 /uv /bin/uv

# El venv se crea en la MISMA ruta que tendrá en la imagen final (guarda rutas absolutas).
# copy: sin hardlinks entre capas; bytecode precompilado: arranque más rápido.
ENV UV_PROJECT_ENVIRONMENT=/app/.venv UV_LINK_MODE=copy UV_COMPILE_BYTECODE=1 \
    UV_PYTHON_DOWNLOADS=never

# Se respeta el layout del repo para que la ruta ../../../s05-... del pyproject siga valiendo.
WORKDIR /build
COPY s05-buenas-practicas-pytest/pyproject.toml s05-buenas-practicas-pytest/
COPY s05-buenas-practicas-pytest/src/ s05-buenas-practicas-pytest/src/
COPY s21-aws-ec2/tu-entrega/pipeline/pyproject.toml s21-aws-ec2/tu-entrega/pipeline/uv.lock \
     s21-aws-ec2/tu-entrega/pipeline/

WORKDIR /build/s21-aws-ec2/tu-entrega/pipeline
# Capa pesada (pandas, pyarrow, boto3, clinlab): solo se rehace si cambia el lock o clinlab.
RUN uv sync --frozen --no-dev --no-install-project --no-editable

# Capa ligera: el código del pipeline, que es lo que más cambia.
COPY s21-aws-ec2/tu-entrega/pipeline/src/ src/
RUN uv sync --frozen --no-dev --no-editable

# --- Etapa 2: imagen final (solo el venv; sin uv, sin código fuente suelto) ---
FROM python:3.12-slim
RUN useradd --create-home appuser
COPY --from=builder --chown=appuser:appuser /app/.venv /app/.venv
ENV PATH="/app/.venv/bin:$PATH" PYTHONUNBUFFERED=1
USER appuser
WORKDIR /app

# ENTRYPOINT fijo + argumentos libres: docker run IMAGEN --salida results/...
# No hay credenciales aquí: en EC2 las pone el rol (IMDS); en la laptop, AWS_PROFILE.
ENTRYPOINT ["python", "-m", "auditoria_obs"]
