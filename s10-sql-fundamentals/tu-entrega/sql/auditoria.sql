-- Actividad 5: auditar antes de confiar.
-- Se ejecuta sobre clinica.duckdb (ver carga.sql). Resultado esperado en esta carga: 0 filas / 0 %.

-- 5.1 ¿Hay Id duplicados en patients?
-- (La columna se llama Id, no patient_id.) Si no hay duplicados, devuelve 0 filas.
SELECT
    Id,
    COUNT(*) AS veces
FROM patients
GROUP BY Id
HAVING COUNT(*) > 1;

-- 5.2 ¿Hay encuentros con fecha anterior al nacimiento del paciente?
-- start es TIMESTAMP y birthdate es DATE; DuckDB convierte el DATE a medianoche al comparar.
SELECT
    e.Id AS encounter_id,
    e.patient,
    e.start AS encounter_start,
    p.birthdate AS patient_birthdate
FROM encounters e
JOIN patients p
  ON e.patient = p.Id
WHERE e.start < p.birthdate;

-- 5.3 ¿Qué porcentaje de observations tiene el valor nulo?
-- value es VARCHAR, así que se mide también la cadena vacía.
-- 100.0 (no 100) evita la división entera.
SELECT
    COUNT(*) AS total_observaciones,

    COUNT(*) FILTER (WHERE value IS NULL) AS nulos_count,
    ROUND(100.0 * COUNT(*) FILTER (WHERE value IS NULL) / COUNT(*), 4) AS nulos_pct,

    COUNT(*) FILTER (WHERE value = '') AS vacios_count,
    ROUND(100.0 * COUNT(*) FILTER (WHERE value = '') / COUNT(*), 4) AS vacios_pct,

    COUNT(*) FILTER (WHERE value IS NULL OR value = '') AS total_sin_dato_count,
    ROUND(100.0 * COUNT(*) FILTER (WHERE value IS NULL OR value = '') / COUNT(*), 4) AS total_sin_dato_pct
FROM observations;

-- 5.4 ¿Cuántos encuentros apuntan a un paciente que no existe en patients?
-- Anti-join con NOT EXISTS (subconsulta correlacionada: se evalúa por cada encuentro).
SELECT COUNT(*) AS encuentros_huerfanos
FROM encounters e
WHERE NOT EXISTS (
    SELECT 1
    FROM patients p
    WHERE p.Id = e.patient
);
