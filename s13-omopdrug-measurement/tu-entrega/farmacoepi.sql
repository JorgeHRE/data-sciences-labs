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

-- =====================================================================
-- Actividad 1. ¿Qué tipo de exposición tenemos? (drug_type_concept_id)
-- Por qué: el tipo dice qué tan cerca está el registro de la toma real
-- (prescripción < dispensación < administración). Hay que saberlo ANTES de
-- interpretar cualquier conteo de "pacientes expuestos".
-- Orden lógico: FROM/JOIN → GROUP BY → SELECT (ventana sobre el agregado)
-- → ORDER BY.
-- =====================================================================
SELECT
    de.drug_type_concept_id,
    ct.concept_name                         AS tipo_exposicion,
    -- Vocabulario del fármaco: separa RxNorm (medicamentos) de CVX (vacunas).
    cd.vocabulary_id                        AS vocabulario_farmaco,
    count(*)                                AS filas,
    count(DISTINCT de.person_id)            AS personas,
    round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct_filas
FROM cdm.drug_exposure de
-- LEFT JOIN: si un tipo no existiera en el vocabulario, la fila no se pierde
-- (saldría con nombre NULL y lo veríamos). concept_id es clave primaria de
-- concept, así que estos JOIN no pueden multiplicar filas.
LEFT JOIN cdm.concept ct ON ct.concept_id = de.drug_type_concept_id
LEFT JOIN cdm.concept cd ON cd.concept_id = de.drug_concept_id
GROUP BY de.drug_type_concept_id, ct.concept_name, cd.vocabulary_id
ORDER BY filas DESC;

-- Control: la suma de las categorías debe ser igual al total de la tabla
-- (467,590). Si difiere, algún JOIN duplicó o perdió filas.
SELECT
    (SELECT count(*) FROM cdm.drug_exposure)                  AS total_tabla,
    (SELECT count(*) FROM cdm.drug_exposure de
       LEFT JOIN cdm.concept ct ON ct.concept_id = de.drug_type_concept_id
       LEFT JOIN cdm.concept cd ON cd.concept_id = de.drug_concept_id) AS total_tras_join,
    (SELECT count(*) FROM cdm.drug_exposure
      WHERE drug_type_concept_id IS NULL OR drug_type_concept_id = 0) AS tipo_nulo_o_cero;
