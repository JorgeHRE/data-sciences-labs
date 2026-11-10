-- =====================================================================
-- Lab 13 — Farmacoepidemiología y calidad de mediciones en OMOP CDM
-- Base: Postgres del lab 12 (contenedor lab12-omop-db-1, puerto 5433,
--       BD omop_lab12). Esquema cdm = solo lectura; lo propio va a results.
-- Ejecutar completo:
--   docker exec -i lab12-omop-db-1 psql -U <usuario> -d omop_lab12 \
--     -v ON_ERROR_STOP=1 < farmacoepi.sql
-- Recordatorio del orden lógico de ejecución de un SELECT:
--   FROM → WHERE → GROUP BY → HAVING → SELECT → ORDER BY
-- =====================================================================

-- Paso 0. Esquema propio: separa los resultados del lab de las tablas
-- del CDM, para no tocar nunca lo que generó el ETL.
CREATE SCHEMA IF NOT EXISTS results;

-- Paso 0. Control de punto de partida: deben coincidir con el lab 12
-- (drug_exposure 467,590 · measurement 4,008,280 · observation 1,929,625 ·
--  drug_era 50,407 · condition_era 100,233 · concept_ancestor 12,077,497).
SELECT 'drug_exposure' AS tabla, count(*) AS filas FROM cdm.drug_exposure
UNION ALL SELECT 'measurement',      count(*) FROM cdm.measurement
UNION ALL SELECT 'observation',      count(*) FROM cdm.observation
UNION ALL SELECT 'drug_era',         count(*) FROM cdm.drug_era
UNION ALL SELECT 'condition_era',    count(*) FROM cdm.condition_era
UNION ALL SELECT 'concept_ancestor', count(*) FROM cdm.concept_ancestor;
