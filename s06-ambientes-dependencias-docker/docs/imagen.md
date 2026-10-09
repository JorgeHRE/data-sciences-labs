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

## 2. Orden malo del Dockerfile

## 3. Orden bueno y tabla comparativa

## 4. Tamaño de la imagen

## 5. `.dockerignore` y contexto

## 6. Usuario no-root

## 7. Secretos en capas

## 8. Escaneo de vulnerabilidades

## 9. Pruebas dentro del contenedor

## 10. Publicación en ghcr.io
