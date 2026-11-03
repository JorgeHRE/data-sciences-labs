# Diagrama ER del CDM cargado (esquema `cdm`)

Generado a partir de `information_schema` de la base `omop_lab12`, no de la documentación.
Se muestran las llaves (PK/FK) y las columnas principales; se omiten las `*_source_value`
y las columnas de datetime para mantenerlo legible.

Convenciones:
- `PK` = llave primaria **declarada** en la base. `FK` = llave foránea **lógica** del estándar v5.4.
- La base tiene 0 llaves foráneas declaradas, así que las líneas punteadas (`..`) son relaciones
  del modelo, no restricciones que Postgres haga cumplir.

## Bloque 1: persona, observación, visitas y condiciones

```mermaid
erDiagram
    person {
        int person_id PK
        int gender_concept_id FK
        int year_of_birth
        int race_concept_id FK
        int ethnicity_concept_id FK
        int location_id FK
        int provider_id FK
        int care_site_id FK
    }
    observation_period {
        int observation_period_id PK
        int person_id FK
        date observation_period_start_date
        date observation_period_end_date
        int period_type_concept_id FK
    }
    visit_occurrence {
        int visit_occurrence_id PK
        int person_id FK
        int visit_concept_id FK
        date visit_start_date
        date visit_end_date
        int visit_type_concept_id FK
        int preceding_visit_occurrence_id FK
    }
    condition_occurrence {
        int condition_occurrence_id PK
        int person_id FK
        int condition_concept_id FK
        date condition_start_date
        int condition_type_concept_id FK
        int visit_occurrence_id FK
        int condition_source_concept_id FK
    }
    death {
        int person_id FK "sin PK declarada"
        date death_date
        int cause_concept_id FK
    }

    person ||..o{ observation_period : "tiene"
    person ||..o{ visit_occurrence : "tiene"
    person ||..o{ condition_occurrence : "tiene"
    person ||..o| death : "puede tener"
    visit_occurrence |o..o{ condition_occurrence : "contiene"
    visit_occurrence |o..o| visit_occurrence : "visita previa"
```

## Bloque 2: eventos clínicos (drogas, procedimientos, mediciones, observaciones)

Las cuatro tablas comparten el patrón de `condition_occurrence`: PK propia, `person_id`,
`visit_occurrence_id` (opcional), un `*_concept_id` estándar y un `*_source_concept_id` de origen.

```mermaid
erDiagram
    drug_exposure {
        int drug_exposure_id PK
        int person_id FK
        int drug_concept_id FK
        date drug_exposure_start_date
        int drug_type_concept_id FK
        int visit_occurrence_id FK
        int drug_source_concept_id FK
    }
    procedure_occurrence {
        int procedure_occurrence_id PK
        int person_id FK
        int procedure_concept_id FK
        date procedure_date
        int procedure_type_concept_id FK
        int visit_occurrence_id FK
        int procedure_source_concept_id FK
    }
    measurement {
        int measurement_id PK
        int person_id FK
        int measurement_concept_id FK
        date measurement_date
        int unit_concept_id FK
        int value_as_concept_id FK
        int visit_occurrence_id FK
        int measurement_source_concept_id FK
    }
    observation {
        int observation_id PK
        int person_id FK
        int observation_concept_id FK
        date observation_date
        int value_as_concept_id FK
        int visit_occurrence_id FK
        int observation_source_concept_id FK
    }

    person ||..o{ drug_exposure : "tiene"
    person ||..o{ procedure_occurrence : "tiene"
    person ||..o{ measurement : "tiene"
    person ||..o{ observation : "tiene"
    visit_occurrence |o..o{ drug_exposure : "contiene"
    visit_occurrence |o..o{ procedure_occurrence : "contiene"
    visit_occurrence |o..o{ measurement : "contiene"
    visit_occurrence |o..o{ observation : "contiene"
```

## Bloque 3: vocabulario y su relación con las tablas clínicas

Por legibilidad se dibuja **una línea por tabla clínica**, la de su concepto principal (decisión 3).
Las demás columnas `*_concept_id` (tipo, unidad, valor, origen…) también apuntan a `concept`.
`concept_relationship` tiene PK compuesta (tres columnas). `concept_ancestor` **no tiene PK declarada**.

```mermaid
erDiagram
    concept {
        int concept_id PK
        string concept_name
        string domain_id FK
        string vocabulary_id FK
        string concept_class_id
        string standard_concept "S, C o NULL"
        string concept_code
    }
    concept_relationship {
        int concept_id_1 PK
        int concept_id_2 PK
        string relationship_id PK
        date valid_start_date
        date valid_end_date
        string invalid_reason
    }
    concept_ancestor {
        int ancestor_concept_id FK
        int descendant_concept_id FK
        int min_levels_of_separation
        int max_levels_of_separation
    }
    vocabulary {
        string vocabulary_id PK
        string vocabulary_name
        string vocabulary_version
    }
    domain {
        string domain_id PK
        string domain_name
    }

    vocabulary ||..o{ concept : "clasifica"
    domain ||..o{ concept : "clasifica"
    concept ||..o{ concept_relationship : "concept_id_1"
    concept ||..o{ concept_relationship : "concept_id_2"
    concept ||..o{ concept_ancestor : "ancestor"
    concept ||..o{ concept_ancestor : "descendant"
    concept ||..o{ person : "gender_concept_id"
    concept ||..o{ visit_occurrence : "visit_concept_id"
    concept ||..o{ condition_occurrence : "condition_concept_id"
    concept ||..o{ drug_exposure : "drug_concept_id"
    concept ||..o{ procedure_occurrence : "procedure_concept_id"
    concept ||..o{ measurement : "measurement_concept_id"
    concept ||..o{ observation : "observation_concept_id"
```

## Tablas fuera del diagrama

Conteos medidos en `cdm` (2026-11-02). "PK" indica si la base la declara.

**Del CDM v5.4, con datos (13)**

| Tabla | Filas | PK | Nota |
|---|---:|:-:|---|
| `visit_detail` | 385,971 | sí | mismo conteo que `visit_occurrence` |
| `device_exposure` | 9,255 | sí | tabla de eventos clínicos; no se dibujó para no recargar |
| `condition_era` | 100,233 | sí | derivada de `condition_occurrence` |
| `drug_era` | 50,407 | sí | derivada de `drug_exposure` |
| `payer_plan_period` | 58,185 | sí | |
| `care_site` / `provider` | 1,082 / 1,082 | sí | |
| `location` | 557 | sí | |
| `cdm_source` | 1 | no | metadatos de la carga |
| `concept_class` | 433 | sí | |
| `relationship` | 724 | sí | |
| `concept_synonym` | 2,504,964 | no | |
| `drug_strength` | 209,849 | no | |

**Del CDM v5.4, vacías (12):** `cost`, `dose_era`, `episode`, `episode_event`, `fact_relationship`,
`metadata`, `note`, `note_nlp`, `specimen`, `source_to_concept_map`, `cohort`, `cohort_definition`.
(`cost` se omitió a propósito, decisión 9.)

**Auxiliares, no son del CDM oficial (6):** `all_visits` (387,993), `assign_all_visit_ids` (410,561),
`final_visit_ids` (403,938), `states_map` (51), `source_to_standard_vocab_map` (1,254,595),
`source_to_source_vocab_map` (2,028,013). Las crea ETL-Synthea para su propio trabajo; ninguna tiene PK.

## Dos diferencias frente a la especificación v5.4

Referencia: <https://ohdsi.github.io/CommonDataModel/cdm54.html>

| # | Diferencia | Estándar v5.4 | Esta base | ¿Error o simplificación? |
|---|---|---|---|---|
| 1 | Llaves foráneas | La especificación marca cada FK (p. ej. `person_id` de `condition_occurrence` → `PERSON`) | 0 FK declaradas en `pg_constraint`; las relaciones del diagrama son lógicas | **Simplificación legítima.** Las FK se suelen añadir después de una carga masiva para no frenarla. Riesgo: nada impide filas huérfanas, así que hay que comprobarlas con consultas. |
| 2 | Tabla `cost` | Tabla del CDM | 0 filas | **Hueco real, decisión propia.** Su `INSERT` no terminó en más de 70 min y se omitió con `LoadEventTables(sqlOnly=TRUE)` (decisión 9). No afecta a las consultas de las act. 5-8, pero la base no es un CDM completo. |

Nota: `death` y `concept_ancestor` no tienen PK declarada, y eso **coincide** con el estándar
(Primary Key = FALSE en todos sus campos); no es una diferencia.
