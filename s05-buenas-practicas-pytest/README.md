<!--
  BORRADOR COMENTADO. Los bloques de comentario como este NO se ven en GitHub
  (comentarios HTML dentro de Markdown); explican por qué existe cada
  sección. Bórralos cuando el README quede como lo quieres entregar.
-->

# clinlab

<!--
  BADGE DEL CI (paso 10): lo primero que se ve es si la suite está en verde.
  Lo genera GitHub Actions a partir de .github/workflows/ci.yml.
-->
[![CI](https://github.com/JorgeHRE/s05-buenas-practicas-pytest/actions/workflows/ci.yml/badge.svg)](https://github.com/JorgeHRE/s05-buenas-practicas-pytest/actions/workflows/ci.yml)

<!--
  QUÉ ES, en una o dos frases. Quien llega al repo (incluido tu profesor)
  necesita saber de qué trata antes de instalar nada.
-->
Paquete de Python con las funciones de análisis clínico del laboratorio 2
(pacientes Synthea), extraídas del notebook como funciones puras, tipadas y
probadas con `pytest`. Entrega del laboratorio **s05-buenas-practicas-pytest**
(ver [`ENUNCIADO.md`](ENUNCIADO.md)).

## Funciones

<!--
  Un vistazo rápido de qué ofrece el paquete. Una línea por función basta; el
  detalle (unidades, parámetros, errores) ya está en los docstrings.
-->
| Módulo | Función | Qué hace |
|---|---|---|
| `clasificacion` | `clasificar_grupo_etario` | Pediátrico (0–17), adulto (18–64) o adulto mayor (≥65) |
| `preprocesamiento` | `optimizar_dtypes` | Convierte columnas a `category` y `datetime64` |
| `auditoria` | `detectar_fechas_imposibles` | Marca visitas anteriores al nacimiento |
| `auditoria` | `contar_duplicados` | Cuenta copias sobrantes de un identificador |
| `auditoria` | `marcar_valores_implausibles` | Marca valores fuera de un rango fisiológico |
| `union` | `unir_con_validacion` | `merge` que valida la cardinalidad (evita multiplicar filas) |
| `clinico` | `calcular_egfr_ckd_epi` | eGFR con CKD-EPI 2021 (sin raza), en mL/min/1.73 m² |

## Instalación (desde un clon limpio)

<!--
  Es un criterio de evaluación: `pip install -e ".[dev]" && pytest` debe
  funcionar en un clon limpio. Por eso los pasos van completos y en orden,
  sin suponer nada de la máquina de quien lo lee.
-->
Requiere Python 3.10 o superior.

```bash
git clone https://github.com/JorgeHRE/s05-buenas-practicas-pytest.git
cd s05-buenas-practicas-pytest

# Entorno virtual: aísla las dependencias de este proyecto.
python3 -m venv .venv            # en Windows: python -m venv .venv
source .venv/bin/activate        # en Windows: .venv\Scripts\activate

# Instala clinlab en modo editable (-e) con las herramientas de desarrollo.
pip install -e ".[dev]"
```

### ⚠️ Paso obligatorio: activar pre-commit

<!--
  Esta sección la pide el enunciado explícitamente. .git/hooks/ no viaja con
  `git clone`, así que el .pre-commit-config.yaml solo no hace nada: cada
  persona tiene que instalar el hook una vez en su clon. Va con su propio
  título y un ⚠️ para que nadie se lo salte ("la trampa clásica").
-->
```bash
pre-commit install
```

Sin este comando, `.pre-commit-config.yaml` no hace nada: el hook vive en
`.git/hooks/`, que no se copia al clonar. Una vez instalado, cada `git commit`
corre automáticamente:

- **ruff** (lint, con `--fix` para lo que es seguro arreglar solo)
- **ruff-format** (formato)
- **mypy** (tipos, solo sobre `src/`)

Si algún hook falla o modifica archivos, el commit se rechaza: revisa los
cambios, vuelve a hacer `git add` y repite el commit. Para revisar todo el
repo de una vez: `pre-commit run --all-files`.

## Correr los tests

<!--
  Aclarar que la cobertura sale sola evita que alguien piense que falta un
  paso (y explica por qué pytest puede fallar aunque todos los tests pasen).
-->
```bash
pytest
```

La cobertura se mide automáticamente (configurada en `pyproject.toml` con
`addopts`): muestra las líneas no cubiertas y **falla si baja de 80 %**.

Revisión de tipos y lint a mano:

```bash
mypy
ruff check .
```

## Datos de prueba

<!--
  El enunciado pide no subir los CSV. Explicar por qué evita que alguien crea
  que falta algo, y muestra que es una decisión, no un olvido.
-->
Los CSV de Synthea **no se suben** al repositorio (están en `.gitignore`).
Los tests no los necesitan: usan la fixture `df_pacientes_malicioso`
(`tests/conftest.py`), un DataFrame de 8 filas que reproduce los hallazgos de
calidad de datos del laboratorio 2 (menor de edad, NaN, `person_id`
duplicado, visita antes del nacimiento y valores centinela).

## Documentación y evidencias

<!--
  Enlaces a lo que se evalúa y que no es código. Quien corrige lo encuentra
  en un clic, sin tener que recorrer carpetas.
-->
- [`docs/evidencia_rojo_verde.md`](docs/evidencia_rojo_verde.md): pruebas vistas en rojo antes del verde.
- [`docs/analisis_cobertura.md`](docs/analisis_cobertura.md): análisis de lo cubierto y lo no cubierto.
- [`docs/evidencia_precommit.md`](docs/evidencia_precommit.md): commit rechazado por pre-commit, corregido y aceptado.

## Uso de IA

<!--
  Tu CLAUDE.md ya está en el repo como evidencia de transparencia. Una línea
  aquí lo hace visible sin que haya que buscarlo.
-->
Este laboratorio se trabajó con apoyo de Claude Code en modo tutor; las
instrucciones de uso están en [`CLAUDE.md`](CLAUDE.md).

## Notebook

<!--
  Paso 2 del enunciado: el análisis del lab 2 reescrito para que la lógica
  venga de clinlab. Se versiona CON salidas porque los CSV no están en el
  repo: así se puede leer el resultado sin tener los datos.
-->
[`notebooks/analisis_pacientes.ipynb`](notebooks/analisis_pacientes.ipynb)
reescribe el análisis del laboratorio 2: carga los datos, llama a las
funciones de `clinlab` y explica los resultados. Se puede leer directamente en
GitHub, porque está guardado con sus salidas.

Para ejecutarlo se necesitan los CSV de Synthea (`patients.csv`,
`encounters.csv`, `observations.csv`), que no están en el repo por su tamaño:

```bash
# Con el entorno virtual activado:
pip install -e ".[dev,notebook]"   # agrega JupyterLab
jupyter lab                        # y abrir notebooks/analisis_pacientes.ipynb
```

La ruta a los CSV se configura en una sola línea (`RUTA_DATOS`, sección 0 del
notebook); por defecto apunta a `../../data`, relativa a `notebooks/`.
