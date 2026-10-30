# Conversión Synthea → OMOP CDM v5.4 (actividad 2)

ETL-Synthea (R, OHDSI) en Docker sobre el Postgres del lab. Los vocabularios ya están cargados
en `cdm` (actividad 3); el ETL solo crea las tablas clínicas y convierte los datos.

## Cómo reproducirlo
```bash
cd s12-omop-cdm-introduccion/tu-entrega
cp .env.example .env            # y pon una contraseña
docker compose up -d db         # Postgres 16.15, puerto 5433
# vocabularios (actividad 3): sql/01_ddl..., ./cargar_vocab.sh <tablas>, sql/02_indices...
docker compose run --rm etl     # construye la imagen la primera vez; ~45 min en total
```
Entrada: CSV de Synthea v3.3.0 (5,000 vivos + 904 fallecidos = 5,904 pacientes), montados en solo lectura.

## Versiones
R 4.5.3 · CommonDataModel v5.4.3 · ETL-Synthea v2.1.1 · DatabaseConnector 7.1.0 ·
JDBC postgresql-42.7.3 · Java 17 · Postgres 16.15.

## Pasos de `run_etl_synthea.R` (corrida de referencia: 43 min)
1. Crear las tablas clínicas del CDM (esquema temporal `cdm_tmp` → las 30 no-vocabulario se mueven a `cdm`).
2. Cargar los 18 CSV a `native` (2.3 min) y reparar los ceros iniciales que pierde la carga.
3. Tablas de mapeo y roll-up + índices extra (0.5 min).
4. Cargar las tablas de eventos (40.4 min), **sin** el paso `cost` (ver abajo).

## Filas por tabla OMOP
| Tabla | Filas | Tabla | Filas |
|---|---|---|---|
| measurement | 4,008,280 | device_exposure | 9,255 |
| observation | 1,929,625 | observation_period | 5,904 |
| drug_exposure | 467,590 | person | 5,904 |
| procedure_occurrence | 454,821 | care_site / provider | 1,082 |
| visit_occurrence / visit_detail | 385,971 | death | 829 |
| condition_occurrence | 101,699 | location | 557 |
| condition_era | 100,233 | cdm_source | 1 |
| payer_plan_period | 58,185 | cost | 0 (omitida) |
| drug_era | 50,407 | | |

## Problemas encontrados
- **Ceros iniciales perdidos** al cargar (`fread` adivina tipos): `immunizations.code` (`08`→`8`, 2,866 vacunas) y los `zip`. Se repara tras la carga (decisión 8). Los conteos de filas no lo detectaron; sí la comparación de valores.
- **Vocabularios incompletos:** la primera descarga no traía Gender, Race, Ethnicity ni CVX (decisión 6).
- **`cost` omitida:** su `INSERT` no terminó en más de 70 min (decisión 9). `cdm.cost` queda vacía a propósito.
- **`death` = 829 y no 904, y `condition_occurrence` < `conditions`:** el ETL enruta por dominio del concepto estándar y descarta lo no mapeable sin error (decisión 10).
- **+33 visitas entre dos corridas** idénticas (decisión 11).
- Tablas auxiliares que **no** son del CDM oficial: `all_visits`, `assign_all_visit_ids`, `final_visit_ids`, `states_map`, `source_to_standard_vocab_map`, `source_to_source_vocab_map`.
