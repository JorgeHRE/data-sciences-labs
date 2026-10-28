-- =============================================================================
-- Actividad 1: Validación de equivalencia formal y auditoría de 6.12
-- Archivo: s11-sql-avanzado/tu-entrega/analitica_longitudinal.sql
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. CONSULTA ORIGINAL (Lab 10, 6.12: anti-join con subconsulta correlacionada)
-- -----------------------------------------------------------------------------
-- Pregunta clínica: ¿qué pacientes con diabetes tipo 2 no tienen ninguna
-- medición de HbA1c? (brecha de seguimiento). Resultado esperado: 0 filas.
SELECT DISTINCT c.patient
FROM conditions c
WHERE c.code = '44054006' -- Diabetes mellitus tipo 2
  AND NOT EXISTS (
      SELECT 1
      FROM observations o
      WHERE o.patient = c.patient
        AND o.code = '4548-4' -- HbA1c
  );

-- -----------------------------------------------------------------------------
-- 2. CONSULTA REESCRITA (CTEs con nombre y anti-join explícito)
-- -----------------------------------------------------------------------------
-- Misma pregunta. Cada conjunto (A: diabéticos, B: con HbA1c) tiene nombre y se
-- puede inspeccionar por separado (SELECT * FROM con_hba1c).
WITH diabeticos AS (
    SELECT DISTINCT patient
    FROM conditions
    WHERE code = '44054006'
),
con_hba1c AS (
    SELECT DISTINCT patient
    FROM observations
    WHERE code = '4548-4'
)
SELECT d.patient
FROM diabeticos d
LEFT JOIN con_hba1c h
  ON d.patient = h.patient
WHERE h.patient IS NULL;

-- Qué se ganó:
-- Legibilidad y depuración: A y B se nombran y se pueden ejecutar por separado, y
-- el anti-join se lee como "A menos B" en lugar de una subconsulta correlacionada.
-- Rendimiento: sin ganancia demostrada. EXPLAIN muestra que DuckDB descorrelaciona
-- también la original (hash join MARK frente a RIGHT_ANTI); se medirá en la act. 10.


-- -----------------------------------------------------------------------------
-- 3. DEMOSTRACIÓN FORMAL DE EQUIVALENCIA (Bidirectional EXCEPT)
-- -----------------------------------------------------------------------------
-- Prueba que no existen registros en la original que no estén en la reescrita,
-- ni registros en la reescrita que no estén en la original.
WITH q_original AS (
    SELECT DISTINCT c.patient
    FROM conditions c
    WHERE c.code = '44054006'
      AND NOT EXISTS (
          SELECT 1
          FROM observations o
          WHERE o.patient = c.patient
            AND o.code = '4548-4'
      )
),
diabeticos AS (
    SELECT DISTINCT patient
    FROM conditions
    WHERE code = '44054006'
),
con_hba1c AS (
    SELECT DISTINCT patient
    FROM observations
    WHERE code = '4548-4'
),
q_reescrita AS (
    SELECT d.patient
    FROM diabeticos d
    LEFT JOIN con_hba1c h 
      ON d.patient = h.patient
    WHERE h.patient IS NULL
),
diferencias_a_menos_b AS (
    -- Elementos en Original pero ausentes en Reescrita
    SELECT patient, 'Original no en Reescrita' AS origen 
    FROM (SELECT patient FROM q_original EXCEPT SELECT patient FROM q_reescrita)
),
diferencias_b_menos_a AS (
    -- Elementos en Reescrita pero ausentes en Original
    SELECT patient, 'Reescrita no en Original' AS origen 
    FROM (SELECT patient FROM q_reescrita EXCEPT SELECT patient FROM q_original)
)
SELECT * FROM diferencias_a_menos_b
UNION ALL
SELECT * FROM diferencias_b_menos_a;


-- -----------------------------------------------------------------------------
-- 4. CONTROL DEL COMPLEMENTO (Auditoría empírica independiente)
-- -----------------------------------------------------------------------------
-- Dado que ambos conjuntos son vacíos (0 filas), el EXCEPT devuelve 0 filas
-- de forma trivial. Este control verifica contra las tablas base que el cero
-- responde a cobertura total (444 diabéticos con HbA1c) y no a un error de filtro.
SELECT 
    (SELECT COUNT(DISTINCT patient) FROM conditions WHERE code = '44054006') AS total_diabeticos,
    COUNT(DISTINCT c.patient) AS diabeticos_con_hba1c,
    (SELECT COUNT(DISTINCT patient) FROM conditions WHERE code = '44054006') - COUNT(DISTINCT c.patient) AS residuo_sin_hba1c
FROM conditions c
JOIN observations o 
  ON c.patient = o.patient
WHERE c.code = '44054006'
  AND o.code = '4548-4';

-- =============================================================================
-- Actividad 1 (Continuación): Consulta 6.11 - Comorbilidad DM2 e Hipertensión
-- Pregunta clínica: ¿Qué proporción de pacientes con diabetes tipo 2 presenta
--                   también diagnóstico de hipertensión esencial?
-- =============================================================================

-- -----------------------------------------------------------------------------
-- VERSIÓN ORIGINAL (Lab 10: CTE para la cohorte + subconsultas escalares en SELECT)
-- -----------------------------------------------------------------------------
WITH pacientes_ambos AS (
    SELECT patient
    FROM conditions
    WHERE code IN ('44054006', '59621000')
    GROUP BY patient
    HAVING COUNT(DISTINCT code) = 2
)
SELECT
    COUNT(*) AS pacientes_con_ambas_condiciones,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(DISTINCT patient) FROM conditions WHERE code = '44054006'), 2) AS pct_sobre_diabeticos,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM patients), 2) AS pct_sobre_poblacion_total
FROM pacientes_ambos;


-- -----------------------------------------------------------------------------
-- VERSIÓN REESCRITA (Lab 11: Grafo plano de CTEs desacopladas sin anidamientos)
-- -----------------------------------------------------------------------------
WITH pacientes_con_ambas AS (
    -- 1. Cohorte con ambas patologías (309 filas)
    SELECT patient
    FROM conditions
    WHERE code IN ('44054006', '59621000')
    GROUP BY patient
    HAVING COUNT(DISTINCT code) = 2
),
conteo_ambas AS (
    -- 2. Numerador escalar (1 fila)
    SELECT COUNT(*) AS total_con_ambas
    FROM pacientes_con_ambas
),
conteo_diabeticos AS (
    -- 3. Denominador específico de diabetes (1 fila)
    SELECT COUNT(DISTINCT patient) AS total_diabeticos
    FROM conditions
    WHERE code = '44054006'
),
conteo_poblacion AS (
    -- 4. Denominador censal global (1 fila)
    SELECT COUNT(*) AS total_poblacion
    FROM patients
)
-- Cruce seguro entre tablas de cardinalidad 1x1x1
SELECT 
    num.total_con_ambas AS pacientes_con_ambas_condiciones,
    ROUND(100.0 * num.total_con_ambas / den_d.total_diabeticos, 2) AS pct_sobre_diabeticos,
    ROUND(100.0 * num.total_con_ambas / den_p.total_poblacion, 2) AS pct_sobre_poblacion_total
FROM conteo_ambas num
CROSS JOIN conteo_diabeticos den_d
CROSS JOIN conteo_poblacion den_p;

-- ¿Qué se ganó con la reescritura?
-- Honestamente, no se gana prácticamente nada: sin ganancia demostrada en velocidad ni
-- memoria (se medirá en la act. 10), y se triplican las líneas. La original ya era compacta y
-- clara. Lo único que aporta es aislar cada métrica en su propio bloque plano,
-- lo que permite inspeccionar por separado el numerador o los denominadores.


-- -----------------------------------------------------------------------------
-- VALIDACIÓN Y CONTROL DE EQUIVALENCIA FORMAL (Harness plano de prueba)
-- -----------------------------------------------------------------------------
-- Se definen en un único nivel plano las dos versiones para contrastar sus tuplas
-- con EXCEPT. Si ambas devuelven exactamente los mismos valores, la consulta
-- debe arrojar 0 filas.
WITH original_pacientes AS (
    SELECT patient
    FROM conditions
    WHERE code IN ('44054006', '59621000')
    GROUP BY patient
    HAVING COUNT(DISTINCT code) = 2
),
original_resultado AS (
    SELECT
        COUNT(*) AS n_ambas,
        ROUND(100.0 * COUNT(*) / (SELECT COUNT(DISTINCT patient) FROM conditions WHERE code = '44054006'), 2) AS pct_dm2,
        ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM patients), 2) AS pct_pob
    FROM original_pacientes
),
reescrita_pacientes AS (
    SELECT patient
    FROM conditions
    WHERE code IN ('44054006', '59621000')
    GROUP BY patient
    HAVING COUNT(DISTINCT code) = 2
),
reescrita_conteo_ambas AS (
    SELECT COUNT(*) AS total_con_ambas
    FROM reescrita_pacientes
),
reescrita_conteo_diabeticos AS (
    SELECT COUNT(DISTINCT patient) AS total_diabeticos
    FROM conditions
    WHERE code = '44054006'
),
reescrita_conteo_poblacion AS (
    SELECT COUNT(*) AS total_poblacion
    FROM patients
),
reescrita_resultado AS (
    SELECT 
        num.total_con_ambas AS n_ambas,
        ROUND(100.0 * num.total_con_ambas / den_d.total_diabeticos, 2) AS pct_dm2,
        ROUND(100.0 * num.total_con_ambas / den_p.total_poblacion, 2) AS pct_pob
    FROM reescrita_conteo_ambas num
    CROSS JOIN reescrita_conteo_diabeticos den_d
    CROSS JOIN reescrita_conteo_poblacion den_p
)
SELECT *, 'En Original pero no en Reescrita' AS discrepancia 
FROM (SELECT * FROM original_resultado EXCEPT SELECT * FROM reescrita_resultado)
UNION ALL
SELECT *, 'En Reescrita pero no en Original' AS discrepancia 
FROM (SELECT * FROM reescrita_resultado EXCEPT SELECT * FROM original_resultado);


-- -----------------------------------------------------------------------------
-- PRUEBA B: Verificación independiente del numerador (INTERSECT vs Reescrita)
-- -----------------------------------------------------------------------------
-- Flujo 100% plano sin subconsultas anidadas en el FROM.
-- Compara el conteo obtenido por álgebra de conjuntos directa (INTERSECT)
-- frente al cálculo por agregación de la consulta reescrita.
WITH diabeticos_lista AS (
    -- Lista A: Pacientes con diabetes tipo 2
    SELECT patient 
    FROM conditions 
    WHERE code = '44054006'
),
hipertensos_lista AS (
    -- Lista B: Pacientes con hipertensión esencial
    SELECT patient 
    FROM conditions 
    WHERE code = '59621000'
),
cohorte_intersect AS (
    -- Intersección pura de conjuntos (sin subconsultas anidadas)
    SELECT patient FROM diabeticos_lista
    INTERSECT
    SELECT patient FROM hipertensos_lista
),
conteo_intersect AS (
    -- Conteo escalar derivado de la intersección
    SELECT COUNT(*) AS n_intersect
    FROM cohorte_intersect
),
pacientes_con_ambas AS (
    -- Cohorte idéntica a la CTE de la consulta reescrita
    SELECT patient
    FROM conditions
    WHERE code IN ('44054006', '59621000')
    GROUP BY patient
    HAVING COUNT(DISTINCT code) = 2
),
conteo_reescrita AS (
    -- Conteo escalar del agrupamiento
    SELECT COUNT(*) AS n_reescrita
    FROM pacientes_con_ambas
)
SELECT 
    i.n_intersect AS numerador_algebraico,
    r.n_reescrita AS numerador_agrupado,
    (i.n_intersect - r.n_reescrita) AS discrepancia
FROM conteo_intersect i
CROSS JOIN conteo_reescrita r;

-- =============================================================================
-- TABLA DE PREDICCIONES AJUSTADA POR BLOQUE (PRUEBA B - CONSULTA 6.11)
-- =============================================================================
-- Bloque / CTE         | Predicción COUNT(*) | Predicción DISTINCT | Justificación y relación con actividad 1
-- ---------------------+---------------------+---------------------+---------------------------------------------------------------------
-- diabeticos_lista     | 444 filas           | 444 pacientes       | 309 / 0.6959 = 444. Synthea emite 1 fila por debut crónico (COUNT* = DISTINCT).
-- hipertensos_lista    | ~1,200–1,400 filas  | ~1,200–1,400 pac.   | Representa el 20–24% de los 5,904 pacientes (esperable >> 5.23% comórbido).
-- cohorte_intersect    | 309 filas           | 309 pacientes       | Referencia fija de la Act. 1; INTERSECT deduplica implícitamente.
-- conteo_intersect     | 1 fila              | N/A (escalar)       | COUNT(*) colapsa la cohorte algebraica al valor escalar 309.
-- pacientes_con_ambas  | 309 filas           | 309 pacientes       | Agrupamiento por paciente con HAVING COUNT(DISTINCT code) = 2.
-- conteo_reescritura   | 1 fila              | N/A (escalar)       | COUNT(*) colapsa la lista agrupada al valor escalar 309.
-- consulta_final       | 1 fila (3 cols)     | N/A                 | CROSS JOIN 1x1; la predicción central es discrepancia = 0 (consistencia).
-- =============================================================================



-- =============================================================================
-- TABLA DE RESULTADOS EMPÍRICOS VS. PREDICCIONES (PRUEBA B - CONSULTA 6.11)
-- =============================================================================
-- Bloque / CTE         | Predicción COUNT(*) | COUNT(*) Real | DISTINCT Real | ¿Coincide? | Diagnóstico / Observaciones
-- ---------------------+---------------------+---------------+---------------+------------+--------------------------------------------------------------
-- diabeticos_lista     | 444 filas           | 444           | 444           | Sí         | Hipótesis confirmada: 1 fila por debut crónico en conditions.
-- hipertensos_lista    | ~1,200–1,400 filas  | 2,145         | 2,145         | No         | Subestimación de prevalencia acumulada (36.33% vs 20–24%).
-- cohorte_intersect    | 309 filas           | 309           | 309           | Sí         | Álgebra de conjuntos idéntica a agregación previa.
-- conteo_intersect     | 1 fila              | 1             | N/A           | Sí         | Escalar puro derivado del INTERSECT (309).
-- pacientes_con_ambas  | 309 filas           | 309           | 309           | Sí         | HAVING COUNT(DISTINCT code) = 2 aísla exactamente 309.
-- conteo_reescritura   | 1 fila              | 1             | N/A           | Sí         | Escalar puro derivado del agrupamiento (309).
-- consulta_final       | 1 fila (discrep. 0) | 1 fila        | N/A           | Sí         | Discrepancia = 0 (309 algebraico vs 309 agrupado).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- NOTA METODOLÓGICA: ¿POR QUÉ FALLÓ LA PREDICCIÓN DE HIPERTENSOS?
-- -----------------------------------------------------------------------------
-- 1. Prevalencia puntual vs. Prevalencia acumulada de por vida (Lifetime prevalence):
--    La intuición teórica del 20–24% correspondía a la prevalencia puntual de una
--    encuesta comunitaria transversal. Sin embargo, la tabla `conditions` de Synthea
--    almacena el registro longitudinal de toda la trayectoria de vida de los pacientes.
--    Al avanzar la edad en la simulación, probablemente la hipertensión es una condición con alta
--    incidencia acumulada.
--
-- 2. Sesgo de cohorte clínica:
--    El dataset no representa un censo abierto y sano, sino individuos registrados
--    en un sistema de salud con encuentros clínicos activos, lo que incrementa la
--    densidad diagnóstica frente a una muestra poblacional general.
--
-- 3. Aprendizaje analítico:
--    - Se validó empíricamente que en Synthea no hay duplicidad de registros crónicos
--      para el mismo paciente (COUNT(*) = COUNT(DISTINCT) = 2,145), por lo que la
--      ausencia de DISTINCT en la CTE no introduce inflación de filas.
--    - En estudios de Real-World Data (RWD), extrapolar tasas epidemiológicas
--      transversales a tablas longitudinales de eventos crónicos subestima el volumen
--      de pacientes si no se acota el horizonte temporal con un filtro de fecha.