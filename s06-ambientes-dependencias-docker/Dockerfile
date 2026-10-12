# 1. Imagen base
FROM python:3.12-slim

# 2. Directorio de trabajo en el contenedor
WORKDIR /app

# 3. Copiar TODO el proyecto de golpe (código + configuración)
COPY s05-buenas-practicas-pytest/ ./

# 4. Instalar dependencias DESPUÉS de copiar todo el código
RUN pip install --no-cache-dir .

# 5. Comando por defecto al arrancar el contenedor
CMD ["python", "-c", "import clinlab"]