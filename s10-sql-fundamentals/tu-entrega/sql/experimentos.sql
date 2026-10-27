-- Actividades 7 y 8: experimentos con joins.
-- Se ejecuta sobre clinica.duckdb (ver carga.sql).

-- ===================== 7. EL JOIN QUE MULTIPLICA =====================
-- Métrica: costo medio de un encuentro (total_claim_cost). Se une encounters con
-- conditions por PACIENTE (no por encuentro), lo que empareja cada encuentro con todas las
-- condiciones del paciente: cada paciente aporta (n.º encuentros) x (n.º condiciones) filas.
--
--   Correcto : 429 640 filas, costo medio 2 206.65, mediana 704.20, total 948 M
--   Inflado  : 36 343 013 filas (x84.6), costo medio 1 648.87, mediana 704.20, total 59 925 M
--   Corregido: 429 640 filas, costo medio 2 206.65 (igual que el correcto)
--
-- El inflado SUBE el conteo y el total (x63) y BAJA la media: en el join pesan más los
-- pacientes con muchas condiciones, y esos tienen encuentros más baratos. La mediana no cambia.
-- Estimar con el producto de promedios (72.8 x 39.9 x 5 904 = 17 M) se queda corto porque
-- encuentros y condiciones por paciente están correlacionados (0.66); la suma real es 36.3 M.
--
-- Por qué "se ve bien": no da error y devuelve un promedio monetario plausible.
-- Cómo detectarlo sin conocer la cifra: auditar el conteo y la granularidad; si el COUNT(*)
-- del cruce supera al de la tabla base, o COUNT(*) > COUNT(DISTINCT e.Id), hubo fan-out.

-- 7.1 Correcto: el grano es un encuentro.
SELECT
    COUNT(*) AS n_filas,
    ROUND(AVG(total_claim_cost), 2) AS costo_medio,
    ROUND(MEDIAN(total_claim_cost), 2) AS costo_mediano,
    ROUND(SUM(total_claim_cost), 2) AS costo_total
FROM encounters;

-- 7.2 Inflado: el join por paciente repite cada encuentro una vez por condición.
SELECT
    COUNT(*) AS n_filas_infladas,
    COUNT(DISTINCT e.Id) AS encuentros_distintos,
    ROUND(AVG(e.total_claim_cost), 2) AS costo_medio_inflado,
    ROUND(MEDIAN(e.total_claim_cost), 2) AS costo_mediano_inflado,
    ROUND(SUM(e.total_claim_cost), 2) AS costo_total_inflado
FROM encounters e
JOIN conditions c
  ON e.patient = c.patient;

-- 7.3 Corregido: semi-join con EXISTS por paciente. Filtra "encuentros de pacientes con al
-- menos una condición" sin multiplicar filas, porque EXISTS solo comprueba que haya una.
-- (Con c.encounter = e.Id sería OTRA pregunta: el subgrupo de 153 325 encuentros en los
-- que se registró un diagnóstico, con costo medio 1 982.00; no es comparable con el total.)
SELECT
    COUNT(*) AS n_encuentros,
    ROUND(AVG(e.total_claim_cost), 2) AS costo_medio,
    ROUND(MEDIAN(e.total_claim_cost), 2) AS costo_mediano,
    ROUND(SUM(e.total_claim_cost), 2) AS costo_total
FROM encounters e
WHERE EXISTS (
    SELECT 1
    FROM conditions c
    WHERE c.patient = e.patient
);

-- ===================== 8. LEFT JOIN: FILTRO EN WHERE vs EN ON =====================
-- Cohorte base: 5 904 pacientes. Condición: diabetes tipo 2 (SNOMED 44054006).
--
--   Filtro en WHERE: 444 filas, 444 pacientes  (el LEFT JOIN se vuelve INNER JOIN)
--   Filtro en ON   : 5 904 filas, 5 904 pacientes  (se conserva toda la cohorte)
--
-- El WHERE se evalúa DESPUÉS del join: las filas sin coincidencia traen c.code = NULL, y
-- NULL = '44054006' no es verdadero, así que se descartan. El ON decide qué se empareja;
-- los pacientes sin coincidencia sobreviven con NULL en las columnas de conditions.
-- Cuándo usar cada uno: WHERE para "solo los diabéticos"; ON para "todos los pacientes,
-- con su diagnóstico de diabetes si lo tienen".
-- Ojo: las cifras coinciden porque cada diabético tiene un único registro de este código
-- (444 filas en conditions para 444 pacientes). Con registros repetidos, el ON habría
-- superado 5 904 filas (fan-out, como en la actividad 7).

-- 8.1 Variante 1: filtro en WHERE (INNER JOIN encubierto; restringe la cohorte)
SELECT
    COUNT(*) AS total_filas,
    COUNT(DISTINCT p.Id) AS pacientes_distintos
FROM patients p
LEFT JOIN conditions c
  ON p.Id = c.patient
WHERE c.code = '44054006';

-- 8.2 Variante 2: filtro en ON (preserva la cohorte completa intacta)
SELECT
    COUNT(*) AS total_filas,
    COUNT(DISTINCT p.Id) AS pacientes_distintos
FROM patients p
LEFT JOIN conditions c
  ON p.Id = c.patient
 AND c.code = '44054006';
