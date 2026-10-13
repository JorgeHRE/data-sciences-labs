# Stack clínico: Postgres + Jupyter (+ Adminer opcional)

Entorno reproducible con Docker Compose: una base Postgres con datos de
ejemplo, un Jupyter ya preparado para conectarse a ella y, si lo pides,
Adminer como panel web.

## Requisitos

- Docker con Compose v2 (`docker compose version` debe responder).
- Puertos libres en tu máquina: **5432**, **8888** y (con Adminer) **8080**.
  Si alguno está ocupado, cambia el número en tu `.env` (ver abajo).
- Linux/macOS con tu usuario con uid **1000** (`id -u`). Si tienes otro uid, el
  bind mount de `notebooks/` puede dar errores de permisos al guardar.

## Levantarlo en tres líneas

```bash
cd s07-docker-compose/tu-entrega/stack
cp .env.example .env        # y edita las claves (ver "Configuración")
docker compose up -d
```

La primera vez construye la imagen de Jupyter y descarga las imágenes base;
tarda unos minutos. Jupyter espera a que Postgres esté sano antes de arrancar.

## Configuración (`.env`)

`.env` **no se sube a git**; `.env.example` es la plantilla. Los valores de la
plantilla funcionan, pero son de ejemplo: cambia al menos estos dos.

| Variable | Para qué | Cómo generarla |
|---|---|---|
| `POSTGRES_PASSWORD` | Clave de la base | `openssl rand -base64 18` |
| `JUPYTER_TOKEN` | Token de acceso a Jupyter | `openssl rand -hex 16` |

`POSTGRES_USER`, `POSTGRES_DB` y los puertos (`POSTGRES_PORT`, `ADMINER_PORT`,
`JUPYTER_PORT`) también están ahí. Todos los puertos escuchan solo en
`127.0.0.1`: únicamente tu máquina puede llegar a ellos.

> **Cuidado:** Postgres solo lee `POSTGRES_PASSWORD` al crear el volumen. Si la
> cambias después, Jupyter recibirá la nueva y la base seguirá con la vieja
> (error `password authentication failed`). Cámbiala antes del primer `up`, o
> bien usa `docker compose down -v` (borra los datos) para empezar de cero.

## Usarlo

| Servicio | Dirección | Acceso |
|---|---|---|
| Jupyter | `http://127.0.0.1:8888/?token=<JUPYTER_TOKEN>` | token de `.env` |
| Postgres | `127.0.0.1:5432` | usuario/clave/base de `.env` |
| Adminer (opcional) | `http://127.0.0.1:8080` | sistema *PostgreSQL*, servidor `db` |

Tus notebooks viven en `notebooks/` y se ven al instante dentro de Jupyter
(carpeta `work`). Desde un notebook, la conexión usa las variables `PG*` ya
definidas, sin escribir la clave en el `.ipynb`:

```python
import psycopg
conn = psycopg.connect()
```

## Adminer es opcional (perfil `dev`)

Por defecto **no** se levanta, por ser un panel de administración de la base.
Para usarlo, pasa el perfil tanto al levantar como al apagar:

```bash
docker compose --profile dev up -d
docker compose --profile dev down
```

Sin `--profile dev` en `down`, Adminer queda encendido y la red no se puede borrar.

## Apagar y empezar de cero

```bash
docker compose down        # apaga; los datos de Postgres se conservan
docker compose down -v     # apaga Y BORRA el volumen (los datos de la base)
```

Los scripts de `initdb/` (esquemas y tablas de ejemplo) se ejecutan **solo** la
primera vez, con el volumen vacío. Si los cambias, haz `down -v` y vuelve a
levantar. Los notebooks no se pierden con `down -v`: están en tu disco.

## Si algo falla

Método: `docker compose ps` → `docker compose logs <servicio>` →
`docker compose exec <servicio> ...`.

- **`port is already allocated`:** otro programa usa ese puerto; cambia el
  puerto correspondiente en `.env`.
- **`falta ... en .env`:** copiaste `.env.example` pero falta una variable.
- **`password authentication failed`:** cambiaste la clave con el volumen ya
  creado (ver la advertencia de arriba).
- **Jupyter no guarda en `notebooks/`:** revisa que tu uid sea 1000.

## Contenido

```text
compose.yml           servicios db, jupyter y adminer (perfil dev)
Dockerfile.jupyter    Jupyter + psycopg, sqlalchemy y pandas
.env.example          plantilla de configuración
initdb/               scripts SQL del primer arranque
notebooks/            tu trabajo (se monta dentro de Jupyter)
evidencia/            capturas de pantalla
bitacora.md           mediciones y experimentos de cada actividad
```
