-- Carga de las 5 tablas de Synthea en DuckDB.
-- Reproducible: se puede correr varias veces (CREATE OR REPLACE recrea cada tabla).
-- Uso (desde tu-entrega/):  python carga.py   (o: duckdb clinica.duckdb < sql/carga.sql)
-- Los CSV de Synthea se esperan en data/synthea/csv/ (ver README para generarlos).
--
-- Decisión de tipos: las fechas con hora (UTC, formato ISO con 'Z') se cargan
-- como TIMESTAMP, para no perder la hora del encuentro; las fechas de nacimiento
-- y defunción vienen sin hora y van como DATE.
-- Las llaves primarias y foráneas NO se declaran aquí: se descubren en la
-- actividad 4 y se verifican con la auditoría de la actividad 5.

CREATE OR REPLACE TABLE patients (
    id                  VARCHAR,
    birthdate           DATE,
    deathdate           DATE,
    ssn                 VARCHAR,
    drivers             VARCHAR,
    passport            VARCHAR,
    prefix              VARCHAR,
    first               VARCHAR,
    middle              VARCHAR,
    last                VARCHAR,
    suffix              VARCHAR,
    maiden              VARCHAR,
    marital             VARCHAR,
    race                VARCHAR,
    ethnicity           VARCHAR,
    gender              VARCHAR,
    birthplace          VARCHAR,
    address             VARCHAR,
    city                VARCHAR,
    state               VARCHAR,
    county              VARCHAR,
    fips                VARCHAR,
    zip                 VARCHAR,
    lat                 DOUBLE,
    lon                 DOUBLE,
    healthcare_expenses DOUBLE,
    healthcare_coverage DOUBLE,
    income              INTEGER
);
INSERT INTO patients
SELECT * FROM read_csv('data/synthea/csv/patients.csv', header = true,
    dateformat = '%Y-%m-%d',
    types = {'Id': 'VARCHAR', 'BIRTHDATE': 'DATE', 'DEATHDATE': 'DATE', 'FIPS': 'VARCHAR', 'ZIP': 'VARCHAR'});

CREATE OR REPLACE TABLE encounters (
    id                  VARCHAR,
    start               TIMESTAMP,
    stop                TIMESTAMP,
    patient             VARCHAR,
    organization        VARCHAR,
    provider            VARCHAR,
    payer               VARCHAR,
    encounterclass      VARCHAR,
    code                VARCHAR,
    description         VARCHAR,
    base_encounter_cost DOUBLE,
    total_claim_cost    DOUBLE,
    payer_coverage      DOUBLE,
    reasoncode          VARCHAR,
    reasondescription   VARCHAR
);
INSERT INTO encounters
SELECT * FROM read_csv('data/synthea/csv/encounters.csv', header = true,
    timestampformat = '%Y-%m-%dT%H:%M:%SZ',
    types = {'START': 'TIMESTAMP', 'STOP': 'TIMESTAMP', 'CODE': 'VARCHAR', 'REASONCODE': 'VARCHAR'});

CREATE OR REPLACE TABLE conditions (
    start       DATE,
    stop        DATE,
    patient     VARCHAR,
    encounter   VARCHAR,
    system      VARCHAR,
    code        VARCHAR,
    description VARCHAR
);
INSERT INTO conditions
SELECT * FROM read_csv('data/synthea/csv/conditions.csv', header = true,
    dateformat = '%Y-%m-%d',
    types = {'START': 'DATE', 'STOP': 'DATE', 'CODE': 'VARCHAR'});

CREATE OR REPLACE TABLE medications (
    start             TIMESTAMP,
    stop              TIMESTAMP,
    patient           VARCHAR,
    payer             VARCHAR,
    encounter         VARCHAR,
    code              VARCHAR,
    description       VARCHAR,
    base_cost         DOUBLE,
    payer_coverage    DOUBLE,
    dispenses         INTEGER,
    totalcost         DOUBLE,
    reasoncode        VARCHAR,
    reasondescription VARCHAR
);
INSERT INTO medications
SELECT * FROM read_csv('data/synthea/csv/medications.csv', header = true,
    timestampformat = '%Y-%m-%dT%H:%M:%SZ',
    types = {'START': 'TIMESTAMP', 'STOP': 'TIMESTAMP', 'CODE': 'VARCHAR', 'REASONCODE': 'VARCHAR'});

-- VALUE queda como VARCHAR: mezcla números ("58.8") y texto ("Never smoker").
CREATE OR REPLACE TABLE observations (
    date        TIMESTAMP,
    patient     VARCHAR,
    encounter   VARCHAR,
    category    VARCHAR,
    code        VARCHAR,
    description VARCHAR,
    value       VARCHAR,
    units       VARCHAR,
    type        VARCHAR
);
INSERT INTO observations
SELECT * FROM read_csv('data/synthea/csv/observations.csv', header = true,
    timestampformat = '%Y-%m-%dT%H:%M:%SZ',
    types = {'DATE': 'TIMESTAMP', 'CODE': 'VARCHAR', 'VALUE': 'VARCHAR'});

-- Conteo de filas por tabla (entrega de la actividad 3).
SELECT 'patients' AS tabla, count(*) AS filas FROM patients
UNION ALL SELECT 'encounters',   count(*) FROM encounters
UNION ALL SELECT 'conditions',   count(*) FROM conditions
UNION ALL SELECT 'medications',  count(*) FROM medications
UNION ALL SELECT 'observations', count(*) FROM observations;
