# Bitácora — Lab 07: stack clínico con Docker Compose

## Actividad 1 — El stack mínimo (Postgres + Adminer)

### Decisión: qué puertos se publican

Publicar un puerto (`"host:contenedor"`) abre el servicio en una interfaz de
mi máquina. Los servicios del mismo `compose.yml` se hablan por la red interna
sin publicar nada.

| Servicio | Puerto | ¿Publicado? | Por qué |
|---|---|---|---|
| Adminer | 8080 | Sí, como `127.0.0.1:8080:8080` | Lo necesito desde el navegador. Limitado al loopback: solo esta máquina lo ve. |
| Postgres | 5432 | **No** (por ahora) | Adminer llega por la red interna (`db:5432`), no hace falta abrirlo. |

**Por qué `127.0.0.1` y no `"8080:8080"`:** sin la IP, Docker publica en
`0.0.0.0`, es decir, en todas las interfaces. Cualquiera en mi red podría llegar
al panel y probar contraseñas. El 8080 es además un puerto muy escaneado.
Comprobación tras el `up`: `ss -ltn` muestra `127.0.0.1:8080`, no `0.0.0.0:8080`.

**Lo que `127.0.0.1` no cubre:** procesos de mi propia máquina, páginas web
maliciosas que usen el navegador para llegar a localhost, vulnerabilidades de
Adminer en sí, y contraseñas débiles. Por eso: contraseña larga y, en la
actividad 7, Adminer pasará a un perfil para que no esté siempre encendido.

**Pendiente:** Postgres se publicará en `127.0.0.1:5432` en la actividad 2, que
exige conectarse desde fuera de Docker.

### Evidencia

Adminer conectado a la base `clinico` (System: PostgreSQL, Server: `db`):

![Adminer conectado](evidencia/adminer-conectado.png)

### Problema encontrado: «password authentication failed»

- **Qué pasó:** cambié la contraseña en el archivo de variables después del
  primer `up` y Adminer dejó de poder entrar:
  `FATAL: password authentication failed for user "clinico"`.
- **Causa:** `POSTGRES_PASSWORD` solo se lee cuando se crea el volumen por
  primera vez. La contraseña queda guardada dentro de los datos, así que el
  cambio posterior se ignora.
- **Solución:** `docker compose down -v` y `up` de nuevo (el volumen estaba
  vacío, no se perdió nada). Con datos reales esto sería destructivo.
- **Otro error:** el campo *System* de Adminer venía en MySQL por defecto; hay
  que cambiarlo a PostgreSQL.

## Actividad 2 — Los servicios se hablan por nombre

### Qué se añadió

- Servicio `jupyter`, construido con `Dockerfile.jupyter`: imagen oficial
  `quay.io/jupyter/base-notebook:2026-10-12` + `psycopg[binary]`, `sqlalchemy` y
  `pandas`. Así las dependencias quedan escritas y no hay que hacer `pip install`
  a mano cada vez que se recrea el contenedor.
- Jupyter publicado solo en `127.0.0.1:8888` y protegido con token (`.env`).
- Postgres publicado ahora en `127.0.0.1:5432`: es lo que permite conectarme
  desde fuera de Docker. Sigue sin estar abierto a la red.
- La contraseña llega al notebook por variables de entorno (`PGHOST`, `PGUSER`,
  `PGPASSWORD`...), no escrita en el `.ipynb`.

### Las dos cadenas de conexión

| Desde dónde | Host | Cadena (sin contraseña) |
|---|---|---|
| Notebook (dentro de Docker) | `db` | `postgresql+psycopg://clinico:<clave>@db:5432/clinico` |
| Mi máquina (fuera de Docker) | `127.0.0.1` | `postgresql+psycopg://clinico:<clave>@127.0.0.1:5432/clinico` |

Comprobado: las dos devuelven la base `clinico` y llegan al mismo servidor
(`172.19.0.2`). Desde mi máquina, `db` no se resuelve (`getent hosts db` no
devuelve nada).

### Evidencia

Notebook dentro de Docker (host `db`):

![Notebook conectado a db](evidencia/jupyter-conexion-db.png)

Terminal en mi máquina (host `127.0.0.1`):

![Terminal conectada a 127.0.0.1](evidencia/terminal-conexion-127.png)

### ¿Por qué difieren?

Las cadenas difieren porque las conexiones se realizan desde dos contextos de red distintos, el 
primero es dentro de Docker, el cual crea una red interna para el stack, proporcionando un 
servidor DNS integrado. El segundo va por fuera de Docker, mi máquina física no forma parte de
la red interna de Docker, ni tiene acceso a su DNS.

### Comprobaciones de seguridad

- `ss -ltn`: los tres puertos (8080, 8888, 5432) escuchan en `127.0.0.1`.
- Jupyter sin token responde 403; con token, 200.
