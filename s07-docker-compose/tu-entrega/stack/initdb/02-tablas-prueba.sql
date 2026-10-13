-- 02-tablas-prueba.sql
-- Tablas mínimas para probar el stack. Datos INVENTADOS: no hay pacientes reales.

-- Subconjunto de columnas de la tabla "person" del modelo OMOP.
CREATE TABLE IF NOT EXISTS cdm.person (
    person_id         integer PRIMARY KEY,
    gender_concept_id integer NOT NULL,   -- 8507 = masculino, 8532 = femenino (conceptos OMOP)
    year_of_birth     integer NOT NULL
);

INSERT INTO cdm.person (person_id, gender_concept_id, year_of_birth) VALUES
    (1, 8532, 1984),
    (2, 8507, 1971),
    (3, 8532, 1999),
    (4, 8507, 1958),
    (5, 8532, 1990)
ON CONFLICT (person_id) DO NOTHING;

-- Tabla de resultados: pacientes por sexo, calculada desde cdm.person.
CREATE TABLE IF NOT EXISTS results.conteo_pacientes (
    gender_concept_id integer PRIMARY KEY,
    n_pacientes       integer NOT NULL
);

INSERT INTO results.conteo_pacientes (gender_concept_id, n_pacientes)
SELECT gender_concept_id, count(*)
FROM cdm.person
GROUP BY gender_concept_id
ON CONFLICT (gender_concept_id) DO NOTHING;
