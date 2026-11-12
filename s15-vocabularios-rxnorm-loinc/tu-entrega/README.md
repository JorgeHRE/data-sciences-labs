# Lab 15 — Vocabularios de fármacos y laboratorio: RxNorm, ATC y LOINC

Construcción de concept sets de **fármacos** (RxNorm, ATC) y de **analitos de laboratorio** (LOINC) sobre la base OMOP sintética del lab 12, auditoría de unidades de tres analitos y mapeo de un catálogo local de farmacia hospitalaria mexicana. Vocabularios: RxNorm 20260601, ATC 2026-02-01, LOINC 2.82 (release OMOP v5.0 29-AUG-26); RxNorm Extension no está cargado (decisión 1).

## Entregables

| Archivo | Contenido |
|---|---|
| `concept_sets/` | **Los 7 concept sets** como SQL ejecutables, cada uno con encabezado (qué define, versión de vocabulario y fecha, cuántos conceptos devuelve, decisiones). Todos por jerarquía o por regla, ninguno con listas de ids. |
| `mapeo_catalogo_local.csv` | 15 claves ficticias de farmacia hospitalaria mapeadas a OMOP, con confianza (alta / dudosa / no mapeable) y quién y por qué. |
| `auditoria_unidades.md` | Auditoría de unidades de HbA1c, glucosa y creatinina: tabla, histogramas, validación por estadio de ERC y veredicto por analito. |
| `README.md` | Este archivo. |

### Concept sets

| Archivo | Define | Construcción | Conceptos | En la base |
|---|---|---|---|---|
| `cs_metformina_a.sql` | metformina, productos de un solo ingrediente | descendientes de metformin con 1 ancestro Ingredient | 83 | 231 pac. |
| `cs_metformina_b.sql` | metformina, combinaciones incluidas | descendientes de metformin (1503297) | 400 | 231 pac. |
| `cs_metformina_c.sql` | B sin combinaciones con iSGLT2 (**elegida** para función renal) | B − descendientes de los ingredientes de ATC A10BK | 249 | 231 pac. |
| `cs_atc_a10b.sql` | fármacos de la clase ATC A10B | A10B → 42 ingredientes → descendientes | 1,467 | 2 productos, 231 pac. |
| `cs_hba1c.sql` | HbA1c por cualquier método o escala | Component «Hemoglobin A1c/Hemoglobin.total…» + Lab Test | 8 | 4548-4: 58,969 med. |
| `cs_glucosa.sql` | glucosa puntual en sangre o suero/plasma | ejes LOINC; sin desafíos («--») | 4 | 2 códigos: 118,590 med. |
| `cs_creatinina.sql` | creatinina puntual en sangre o suero/plasma | ejes LOINC | 5 | 2 códigos: 118,590 med. |

## Archivos de trabajo

| Archivo | Contenido |
|---|---|
| `actividades.sql` | Todas las consultas de exploración, por actividad (encabezados `-- Actividad Xy.`), con el porqué y el resultado esperado en comentarios. Solo lectura. |
| `verificacion_vocabularios.sql` | Paso 0: vocabularios y versiones cargados, productos sin ingrediente. |
| `act1_rxnav.md` … `act8_catalogo.md` | Resultado y discusión de cada actividad (la 7 es `auditoria_unidades.md`). |
| `figura_metformina.py` / `.png` | Conceptos y pacientes por versión de metformina (actividad 4). |
| `figura_unidades.py` / `.png` | Histogramas de `value_as_number` por código y unidad (actividad 7). |
| `DECISIONES.md` | Las 14 decisiones del lab: qué se eligió, qué alternativas había y por qué. |
| `requirements.txt` | Entorno de las figuras (pandas, SQLAlchemy, psycopg2, matplotlib, python-dotenv). |

## Cómo reproducirlo

Requiere la base del lab 12 con el vocabulario de ATHENA cargado (contenedor `lab12-omop-db-1`, BD y credenciales en `../../s12-omop-cdm-introduccion/tu-entrega/.env`, esquema `cdm`). Todo es de solo lectura: no se crean tablas ni vistas.

```bash
# 1. Encender la base del lab 12
cd s12-omop-cdm-introduccion/tu-entrega && docker compose up -d && cd -
set -a; . s12-omop-cdm-introduccion/tu-entrega/.env; set +a
T=s15-vocabularios-rxnorm-loinc/tu-entrega

# 2. Un concept set (devuelve sus conceptos)
docker exec -i lab12-omop-db-1 psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" < $T/concept_sets/cs_hba1c.sql

# 3. Todas las consultas de exploración (~10 s) o un solo trozo
docker exec -i lab12-omop-db-1 psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 < $T/actividades.sql
sed -n '/-- Actividad 7a\./,/^ORDER BY k.analito;/p' $T/actividades.sql | docker exec -i lab12-omop-db-1 psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"

# 4. Figuras (leen sus consultas de actividades.sql y validan cifras con assert)
python -m venv $T/.venv && $T/.venv/bin/pip install -r $T/requirements.txt
$T/.venv/bin/python $T/figura_metformina.py
$T/.venv/bin/python $T/figura_unidades.py
```

Comprobado el 2026-11-12: `verificacion_vocabularios.sql` y `actividades.sql` completos corren sin errores; los 7 concept sets devuelven 83 / 400 / 249 / 1,467 / 8 / 4 / 5 conceptos; las dos figuras se regeneran idénticas.

## Resultados por actividad

| # | Pregunta | Resultado |
|---|---|---|
| 1 | RxNav: metformina, lisinopril, empagliflozina | La base tiene más SCDF/BN que RxNav: OMOP conserva productos obsoletos en RxNorm. |
| 2 | Top-20 fármacos → ingrediente | 2 vacunas CVX sin ingrediente; 3 combinaciones con 2 ingredientes. |
| 3 | ATC A10B → ingredientes → productos | 42 ingredientes, 231 pacientes. **22 de 365 productos de la base sin ATC** (16.9 % de las filas, casi todo vacunas). |
| 4 | Metformina A / B / C | 83 / 400 / 249 conceptos, 231 pacientes en las tres; C para estudiar función renal. |
| 5 | Seis ejes de 4548-4, 2160-0, 2345-7 | Method vacío; la base mezcla sangre total y suero/plasma en glucosa y creatinina (24,827 persona-días con ambos paneles). |
| 6 | Concept set de HbA1c | 8 códigos (fuera la meta y la masa/volumen); en la base solo 4548-4: igual que «solo 4548-4», la diferencia es de portabilidad. |
| 7 | Auditoría de unidades | 1 unidad por analito, 0 % sin unidad. Creatinina en sangre bimodal por ERC, no por µmol/L; 232 valores ≥ 40 mg/dL en estadio 4. HbA1c sí; glucosa y creatinina no se promedian tal cual. |
| 8 | Catálogo local de 15 | **73.3 % con confianza alta** (11), 3 dudosas, 1 no mapeable (gasa: dominio Device). |
| 9 | Empaquetar | 7 concept sets en `concept_sets/`. |

**Limitación general:** Synthea registra cada analito con un solo código y cada fármaco con pocos productos, así que las definiciones cambian mucho (conceptos) sin que cambien los pacientes. Las diferencias entre versiones se verían en una base real o en otra base donde se ejecuten estos concept sets.
