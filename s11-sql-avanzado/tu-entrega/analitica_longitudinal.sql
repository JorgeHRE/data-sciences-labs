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


-- =============================================================================
-- Actividad 3: Trayectoria de encuentros (GROUP BY vs. Funciones de Ventana)
-- Pregunta analítica: Por paciente, calcular fecha índice (primera visita),
--                     fin de seguimiento (última visita) y volumen de contactos.
-- =============================================================================

-- =============================================================================
-- TABLA DE PREDICCIONES (ACTIVIDAD 3 - CAMINO 1: GROUP BY)
-- =============================================================================
-- Métrica / Pregunta          | Predicción                  | Justificación analítica
-- ----------------------------+-----------------------------+------------------------------------------------------------------
-- 1. Filas devueltas          | 5,904 filas                 | 1 fila por paciente único con al menos un encuentro registrado.
-- 2. Columnas proyectadas     | 4 columnas                  | patient, primera_visita, ultima_visita, total_visitas.
-- 3. Volumen de visitas       | Mín: 1, Mediana: ~39,       | Validado en Act. 6.6: la media fue 72.8 y el máximo 990 visitas, mediana validada igual.
--                             | Máx: 990                    | 
-- 4. Rango temporal global    | Mín: ~1915–1940             | min(primera_visita) corresponde al encuentro más antiguo de la
--    [min(primera_visita) a   | Máx: Década de 2020         | base (nacimiento/infancia de los pacientes más longevos).
--     max(ultima_visita)]     | (~2020–2025+)               | max(ultima_visita) refleja el contacto más reciente registrado
--                             |                             | en la simulación antes de que cese la generación de eventos.
-- 5. Ventana sin deduplicar   | 429,640 filas               | 1 fila por cada registro original de la tabla encounters.
--    Ventana deduplicada (rn=1)| 5,904 filas                | Colapsa al mismo grano de pacientes únicos que el GROUP BY.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- CAMINO 1: Agregación con GROUP BY (Colapso relacional estricto)
-- -----------------------------------------------------------------------------
SELECT 
    e.patient,
    MIN(e.start) AS primera_visita,
    MAX(e.start) AS ultima_visita,
    COUNT(*)     AS total_visitas
FROM encounters e
GROUP BY e.patient;

-- -----------------------------------------------------------------------------
-- CAMINO 2: Funciones de Ventana (Colapso relacional con ventana)
-- -----------------------------------------------------------------------------
WITH visitas_calculadas AS (
    SELECT 
        patient,
        start,
        FIRST_VALUE(start) OVER (
            PARTITION BY patient 
            ORDER BY start
        ) AS primera_visita,
        LAST_VALUE(start) OVER (
            PARTITION BY patient 
            ORDER BY start 
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS ultima_visita,
        COUNT(*) OVER (
            PARTITION BY patient
        ) AS total_visitas,
        ROW_NUMBER() OVER (
            PARTITION BY patient 
            ORDER BY start
        ) AS rn
    FROM encounters
)
SELECT 
    patient,
    primera_visita,
    ultima_visita,
    total_visitas
FROM visitas_calculadas
WHERE rn = 1;

-- -----------------------------------------------------------------------------
-- VALIDACIÓN DE EQUIVALENCIA FORMAL (Bidirectional EXCEPT)
-- -----------------------------------------------------------------------------
-- Se prueba que no existen registros en el resultado del GROUP BY que no estén
-- en el resultado de la ventana, ni registros en el resultado de la ventana que no estén en el resultado del GROUP BY.
-- Se esperan 0 filas de discrepancia, lo que confirma la equivalencia formal de ambos enfoques.
-- debido a que ambos producen exactamente 5,904 filas (1 por paciente único con al menos un encuentro).

WITH camino1_groupby AS (
    SELECT 
        patient,
        MIN(start) AS primera_visita,
        MAX(start) AS ultima_visita,
        COUNT(*)   AS total_visitas
    FROM encounters
    GROUP BY patient
),
ventana_base AS (
    SELECT 
        patient,
        FIRST_VALUE(start) OVER (
            PARTITION BY patient 
            ORDER BY start
        ) AS primera_visita,
        LAST_VALUE(start) OVER (
            PARTITION BY patient 
            ORDER BY start 
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS ultima_visita,
        COUNT(*) OVER (
            PARTITION BY patient
        ) AS total_visitas,
        ROW_NUMBER() OVER (
            PARTITION BY patient 
            ORDER BY start
        ) AS rn
    FROM encounters
),
camino2_ventanas AS (
    SELECT 
        patient,
        primera_visita,
        ultima_visita,
        total_visitas
    FROM ventana_base
    WHERE rn = 1
)
SELECT *, 'En GROUP BY pero ausente en Ventanas' AS discrepancia 
FROM (
    SELECT * FROM camino1_groupby 
    EXCEPT 
    SELECT * FROM camino2_ventanas
)
UNION ALL
SELECT *, 'En Ventanas pero ausente en GROUP BY' AS discrepancia 
FROM (
    SELECT * FROM camino2_ventanas 
    EXCEPT 
    SELECT * FROM camino1_groupby
);


-- -----------------------------------------------------------------------------
-- Control de independencia de tamaño y conservación de cardinalidad (Auditoría empírica)
-- -----------------------------------------------------------------------------
-- Se verifica que ambos caminos devuelvan el mismo número de pacientes únicos y el mismo número total de visitas, confirmando la equivalencia empírica.
-- La predicción es que ambos caminos deben devolver 5,904 filas (pacientes únicos) y 429,640 visitas totales.
-- Se prefiere el camino 1 (GROUP BY) por su menor complejidad, aunque ambos caminos son equivalentes formalmente.
WITH camino1_groupby AS (
    SELECT 
        patient,
        MIN(start) AS primera_visita,
        MAX(start) AS ultima_visita,
        COUNT(*)   AS total_visitas
    FROM encounters
    GROUP BY patient
),
ventana_base AS (
    SELECT 
        patient,
        FIRST_VALUE(start) OVER (PARTITION BY patient ORDER BY start) AS primera_visita,
        LAST_VALUE(start) OVER (
            PARTITION BY patient ORDER BY start 
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS ultima_visita,
        COUNT(*) OVER (PARTITION BY patient) AS total_visitas,
        ROW_NUMBER() OVER (PARTITION BY patient ORDER BY start) AS rn
    FROM encounters
),
camino2_ventanas AS (
    SELECT patient, primera_visita, ultima_visita, total_visitas
    FROM ventana_base
    WHERE rn = 1
),
control_independiente AS (
    SELECT 
        -- Verificación 1: Cardinalidad de filas (pacientes únicos)
        (SELECT COUNT(*) FROM patients)                  AS censo_pacientes_base,
        (SELECT COUNT(DISTINCT patient) FROM encounters) AS pacientes_con_visitas_base,
        (SELECT COUNT(*) FROM camino1_groupby)           AS filas_camino1,
        (SELECT COUNT(*) FROM camino2_ventanas)          AS filas_camino2,

        -- Verificación 2: Conservación de eventos (filas crudas de encuentros)
        (SELECT COUNT(*) FROM encounters)                AS encuentros_totales_base,
        (SELECT SUM(total_visitas) FROM camino1_groupby)  AS suma_visitas_camino1,
        (SELECT SUM(total_visitas) FROM camino2_ventanas) AS suma_visitas_camino2
)
SELECT 
    -- Auditoría de pacientes
    censo_pacientes_base,
    pacientes_con_visitas_base,
    filas_camino1,
    filas_camino2,
    (filas_camino1 - censo_pacientes_base) AS delta_pacientes_c1,
    (filas_camino2 - censo_pacientes_base) AS delta_pacientes_c2,

    -- Auditoría de eventos
    encuentros_totales_base,
    suma_visitas_camino1,
    suma_visitas_camino2,
    (suma_visitas_camino1 - encuentros_totales_base) AS delta_eventos_c1,
    (suma_visitas_camino2 - encuentros_totales_base) AS delta_eventos_c2,

    -- Veredicto global
    CASE 
        WHEN filas_camino1 = censo_pacientes_base 
         AND filas_camino2 = censo_pacientes_base
         AND suma_visitas_camino1 = encuentros_totales_base
         AND suma_visitas_camino2 = encuentros_totales_base
        THEN 'CORRECTO (Cardinalidad y eventos conservados)'
        ELSE 'REVISAR DISCREPANCIA'
    END AS estado_validacion
FROM control_independiente;

-- =============================================================================
-- Actividad 4: Días entre visitas consecutivas (LAG)
-- Pregunta analítica: por paciente, ¿cuántos días pasan entre una visita y la
--                     anterior? ¿Cuál es la mediana?
-- =============================================================================
-- DECISIONES DECLARADAS (confirmadas con el usuario):
--  (1) Visitas simultáneas: SE CONSERVAN (opción A). Hay 1,928 pares
--      (paciente, start) idénticos a nivel timestamp; a nivel de fecha son más
--      (ver ceros abajo). Son contactos reales, así que dan 0 días. El orden
--      usa (start, id) para que el LAG sea determinista entre empates.
--  (2) Unidad: días enteros sobre CAST(start AS DATE), con date_diff('day').
--      Restar TIMESTAMP daría fracciones de día; aquí se lee "días calendario".
--  (3) NULL de la primera visita: se dejan como NULL (no existe visita previa)
--      y se excluyen explícitamente del cálculo de la mediana.
-- -----------------------------------------------------------------------------
-- RESULTADOS MEDIDOS (opción A): 429,640 filas (una por encuentro, no se pierde
-- ninguna), 5,904 NULL (uno por paciente), 17,820 ceros, mínimo 0, máximo
-- 15,372 días, media 167.2 y MEDIANA = 12 días.
-- Contraste (opción B, un día por paciente): 411,820 filas, mediana = 14 días.
-- =============================================================================

-- Detalle: días desde la visita anterior, por paciente
WITH visitas AS (
    SELECT
        patient,
        id,
        CAST(start AS DATE) AS fecha,
        -- LAG mira la fila anterior DENTRO de cada paciente (PARTITION BY),
        -- ordenada cronológicamente; el id desempata visitas del mismo instante.
        LAG(CAST(start AS DATE)) OVER (
            PARTITION BY patient ORDER BY start, id
        ) AS fecha_previa
    FROM encounters
)
SELECT
    patient,
    id,
    fecha,
    fecha_previa,                                      -- NULL en la 1a visita
    date_diff('day', fecha_previa, fecha) AS dias_desde_previa
FROM visitas
ORDER BY patient, fecha, id;

-- Resumen: mediana y control de NULL / ceros
WITH visitas AS (
    SELECT
        CAST(start AS DATE) AS fecha,
        LAG(CAST(start AS DATE)) OVER (
            PARTITION BY patient ORDER BY start, id
        ) AS fecha_previa
    FROM encounters
),
intervalos AS (
    SELECT date_diff('day', fecha_previa, fecha) AS dias FROM visitas
)
SELECT
    COUNT(*)                                    AS filas,            -- esperado 429,640
    COUNT(*) FILTER (WHERE dias IS NULL)        AS nulos_primera,    -- esperado 5,904
    COUNT(*) FILTER (WHERE dias = 0)            AS ceros,            -- 17,820
    MEDIAN(dias) FILTER (WHERE dias IS NOT NULL) AS mediana_dias,    -- 12
    AVG(dias)                                   AS media_dias,       -- 167.2 (sesgada por colas largas)
    MAX(dias)                                   AS maximo_dias       -- 15,372
FROM intervalos;

-- Contraste (opción B): un día por paciente, sin visitas simultáneas
WITH dias_con_visita AS (
    SELECT DISTINCT patient, CAST(start AS DATE) AS fecha FROM encounters
),
intervalos AS (
    SELECT date_diff('day',
               LAG(fecha) OVER (PARTITION BY patient ORDER BY fecha),
               fecha) AS dias
    FROM dias_con_visita
)
SELECT COUNT(*) AS filas, MEDIAN(dias) AS mediana_dias_B               -- 411,820 / 14
FROM intervalos;


-- =============================================================================
-- Actividad 5: Readmisión a 30 días
-- Pregunta analítica: ¿qué proporción de las altas hospitalarias elegibles
--                     termina en un nuevo ingreso dentro de los 30 días?
-- =============================================================================
-- DECISIONES DECLARADAS (confirmadas con el usuario):
--  (1) TODAS las readmisiones cuentan (no solo la primera por paciente). La
--      unidad es el ALTA: cada alta se empareja con el SIGUIENTE ingreso del
--      mismo paciente (LEAD), así que un alta se readmite a lo sumo una vez.
--      Se reporta además cuántos pacientes distintos se readmiten.
--  (2) El día 30 ENTRA: readmisión = 0 <= dias_a_sig <= 30, con la diferencia
--      en días calendario entre fecha de alta y fecha del siguiente ingreso.
--      Sensibilidad con < 30 en la consulta de resumen.
--  (3) Ingreso el MISMO día del alta (diferencia 0): SÍ cuenta (249 casos).
--      Puede ser un traslado y no una readmisión clínica; se reporta aparte.
--      Ingreso ANTES del alta previa (solape, 89 casos): dato inconsistente;
--      se EXCLUYE del numerador y del denominador, sin corregirlo.
--  (4) Alta elegible = alta de un ingreso 'inpatient' cuyo paciente no murió
--      en la fecha del alta o antes (118 excluidas) y sin solape (89).
--      7,867 altas totales = 7,660 elegibles + 118 fallecido + 89 solape.
-- -----------------------------------------------------------------------------
-- RESULTADOS MEDIDOS: 1,171 readmisiones sobre 7,660 altas elegibles
--   => tasa 15.29 %, en 336 pacientes distintos.
--   Sensibilidades: con < 30 días 1,002 (13.08 %); sin contar el mismo día
--   922 (12.04 %).
-- =============================================================================

WITH ingresos AS (
    SELECT
        e.id,
        e.patient,
        CAST(e.start AS DATE)      AS fecha_ingreso,
        CAST(e.stop  AS DATE)      AS fecha_alta,
        CAST(p.deathdate AS DATE)  AS fallecimiento
    FROM encounters e
    JOIN patients p ON p.id = e.patient
    WHERE e.encounterclass = 'inpatient'
),
altas AS (
    SELECT
        *,
        -- Fecha del SIGUIENTE ingreso del mismo paciente (NULL si es el último)
        LEAD(fecha_ingreso) OVER (
            PARTITION BY patient ORDER BY fecha_ingreso, id
        ) AS sig_ingreso
    FROM ingresos
),
clasificadas AS (
    SELECT
        *,
        date_diff('day', fecha_alta, sig_ingreso) AS dias_a_sig,
        CASE
            WHEN fallecimiento IS NOT NULL AND fallecimiento <= fecha_alta THEN 'excl_fallecido'
            WHEN sig_ingreso < fecha_alta                                  THEN 'excl_solape'
            ELSE 'elegible'
        END AS estado
    FROM altas
)
SELECT
    COUNT(*)                                                             AS altas_totales,        -- 7,867
    COUNT(*) FILTER (WHERE estado = 'excl_fallecido')                    AS excl_fallecido,       -- 118
    COUNT(*) FILTER (WHERE estado = 'excl_solape')                       AS excl_solape,          -- 89
    COUNT(*) FILTER (WHERE estado = 'elegible')                          AS altas_elegibles,      -- 7,660
    COUNT(*) FILTER (WHERE estado = 'elegible' AND dias_a_sig <= 30)     AS readmisiones,         -- 1,171
    ROUND(100.0 * COUNT(*) FILTER (WHERE estado = 'elegible' AND dias_a_sig <= 30)
          / COUNT(*) FILTER (WHERE estado = 'elegible'), 2)              AS tasa_pct,             -- 15.29
    COUNT(DISTINCT patient) FILTER (WHERE estado = 'elegible' AND dias_a_sig <= 30)
                                                                         AS pacientes_readmitidos,-- 336
    COUNT(*) FILTER (WHERE estado = 'elegible' AND dias_a_sig = 0)       AS readm_mismo_dia,      -- 249
    COUNT(*) FILTER (WHERE estado = 'elegible' AND dias_a_sig < 30)      AS readm_estricto_lt30,  -- 1,002
    COUNT(*) FILTER (WHERE estado = 'elegible' AND dias_a_sig BETWEEN 1 AND 30)
                                                                         AS readm_sin_mismo_dia   -- 922
FROM clasificadas;

-- Control independiente: misma cifra SIN LEAD, con EXISTS sobre los ingresos.
-- Un alta elegible se readmite si existe algún ingreso del mismo paciente
-- entre su fecha de alta y alta + 30 días (el más cercano sería el siguiente).
WITH ingresos AS (
    SELECT e.id, e.patient, CAST(e.start AS DATE) AS fecha_ingreso,
           CAST(e.stop AS DATE) AS fecha_alta, CAST(p.deathdate AS DATE) AS fallecimiento
    FROM encounters e JOIN patients p ON p.id = e.patient
    WHERE e.encounterclass = 'inpatient'
),
elegibles AS (
    SELECT i.*
    FROM ingresos i
    WHERE (i.fallecimiento IS NULL OR i.fallecimiento > i.fecha_alta)
      -- sin solape: ningún OTRO ingreso empieza dentro de esta estancia ya iniciada
      -- (equivale a "el siguiente ingreso no empieza antes del alta previa")
      AND NOT EXISTS (
          SELECT 1 FROM ingresos s
          WHERE s.patient = i.patient AND s.id <> i.id
            AND (s.fecha_ingreso, s.id) > (i.fecha_ingreso, i.id)
            AND s.fecha_ingreso < i.fecha_alta
      )
)
SELECT
    COUNT(*) AS altas_elegibles,                                                -- 7,660
    COUNT(*) FILTER (WHERE EXISTS (
        SELECT 1 FROM ingresos s
        WHERE s.patient = elegibles.patient AND s.id <> elegibles.id
          AND (s.fecha_ingreso, s.id) > (elegibles.fecha_ingreso, elegibles.id)
          AND s.fecha_ingreso BETWEEN elegibles.fecha_alta
                                  AND elegibles.fecha_alta + INTERVAL 30 DAY
    )) AS readmisiones                                                          -- 1,171
FROM elegibles;


-- =============================================================================
-- Actividad 6: Episodios de tratamiento continuo (gaps and islands)
-- Fármaco principal: 1 ML Epoetin Alfa 4000 UNT/ML Injection [Epogen]
--                    (81,102 recetas, 272 pacientes, todas con stop)
-- Fármaco de contraste: lisinopril 10 MG Oral Tablet (41,278 recetas, 1,432 pac.)
-- Pregunta analítica: ¿cuántos episodios continuos de tratamiento hay por
--                     paciente y cuánto duran, con gaps de 30, 60 y 90 días?
-- =============================================================================
-- DECISIONES DECLARADAS (confirmadas con el usuario):
--  (1) Fármaco principal: Epoetina alfa. Se probó primero lisinopril y los gaps
--      de 30/60/90 dan lo mismo (1 episodio por paciente, 1,432 en total): los
--      crónicos orales se prescriben de forma continua hasta el corte y las
--      recetas largas (hasta 434 días) cubren los huecos. Pasa igual con
--      hidroclorotiazida, amlodipino, simvastatina, insulina, metformina,
--      tacrolimus, ibuprofeno y alendronato. Solo los intermitentes (Epoetina,
--      cisplatino, paclitaxel) hacen variar el gap, por eso Epoetina es el
--      principal y lisinopril queda como contraste.
--  (2) Receta SIN stop: se trata como activa hasta la fecha de corte de los
--      datos (MAX(start) de encounters = 2026-10-26) y el episodio se marca
--      `censurado`. En Epoetina no hay ninguna; afecta solo al contraste
--      (1,432 recetas abiertas de lisinopril, una por paciente).
--  (3) Recetas solapadas: no se usa LAG(fin) sino el FIN MÁXIMO ACUMULADO de
--      todas las recetas previas del paciente. Con LAG, un solape dejaría un
--      fin falso y partiría episodios continuos. En lisinopril la diferencia
--      es grande: LAG veía 94 huecos > 30 días y el acumulado, ninguno.
--  (4) Regla del hueco: una receta abre un episodio nuevo si
--      inicio - fin_acumulado_previo > gap. Con gap = 30, un hueco de exactamente
--      30 días NO corta (convención de DRUG_ERA de OMOP).
--  (5) Fechas en días calendario (CAST AS DATE). Filtro por description
--      (por código, lisinopril 10 mg es 314076; otros códigos son otras dosis).
-- -----------------------------------------------------------------------------
-- RESULTADOS MEDIDOS (episodios con gap 30 / 60 / 90):
--   Epoetina:   785 / 369 / 319 episodios (272 pacientes).
--   Lisinopril: 1,432 / 1,432 / 1,432 (1,432 pacientes).
--   Cisplatino y paclitaxel (solo explorados): 1,400 / 92 / 68 y 1,342 / 77 / 56.
-- =============================================================================

-- Episodios por paciente de Epoetina con gap = 30 días (detalle)
WITH corte AS (
    SELECT MAX(CAST(start AS DATE)) AS fecha_corte FROM encounters      -- 2026-10-26
),
recetas AS (
    SELECT
        m.patient,
        CAST(m.start AS DATE)                              AS ini,
        COALESCE(CAST(m.stop AS DATE), c.fecha_corte)      AS fin,      -- decisión (2)
        (m.stop IS NULL)                                   AS abierta
    FROM medications m
    CROSS JOIN corte c
    WHERE m.description = '1 ML Epoetin Alfa 4000 UNT/ML Injection [Epogen]'
),
con_fin_previo AS (
    SELECT
        *,
        -- Fin máximo de TODAS las recetas anteriores del paciente (decisión 3)
        MAX(fin) OVER (
            PARTITION BY patient ORDER BY ini, fin
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS fin_previo
    FROM recetas
),
con_episodio AS (
    SELECT
        *,
        -- Suma acumulada de los "cortes" = número de episodio dentro del paciente.
        -- Corte = primera receta, o hueco > 30 días (decisión 4).
        SUM(CASE WHEN fin_previo IS NULL OR date_diff('day', fin_previo, ini) > 30
                 THEN 1 ELSE 0 END) OVER (
            PARTITION BY patient ORDER BY ini, fin
            ROWS UNBOUNDED PRECEDING
        ) AS episodio
    FROM con_fin_previo
)
SELECT
    patient,
    episodio,
    MIN(ini)                                  AS inicio_episodio,
    MAX(fin)                                  AS fin_episodio,
    date_diff('day', MIN(ini), MAX(fin))      AS duracion_dias,
    COUNT(*)                                  AS n_recetas,
    BOOL_OR(abierta)                          AS censurado
FROM con_episodio
GROUP BY patient, episodio
ORDER BY patient, episodio;

-- Comparación de gaps 30 / 60 / 90 para Epoetina y lisinopril
-- (misma lógica; fármaco y gap entran como parámetros vía CROSS JOIN)
WITH corte AS (
    SELECT MAX(CAST(start AS DATE)) AS fecha_corte FROM encounters
),
gaps(gap) AS (VALUES (30), (60), (90)),
farmacos(description) AS (VALUES
    ('1 ML Epoetin Alfa 4000 UNT/ML Injection [Epogen]'),
    ('lisinopril 10 MG Oral Tablet')),
recetas AS (
    SELECT m.description, m.patient, CAST(m.start AS DATE) AS ini,
           COALESCE(CAST(m.stop AS DATE), c.fecha_corte) AS fin
    FROM medications m
    CROSS JOIN corte c
    WHERE m.description IN (SELECT description FROM farmacos)
),
con_fin_previo AS (
    SELECT *, MAX(fin) OVER (
               PARTITION BY description, patient ORDER BY ini, fin
               ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS fin_previo
    FROM recetas
),
con_episodio AS (
    SELECT g.gap, r.*,
           SUM(CASE WHEN r.fin_previo IS NULL
                      OR date_diff('day', r.fin_previo, r.ini) > g.gap
                    THEN 1 ELSE 0 END) OVER (
               PARTITION BY g.gap, r.description, r.patient ORDER BY r.ini, r.fin
               ROWS UNBOUNDED PRECEDING) AS episodio
    FROM con_fin_previo r CROSS JOIN gaps g
),
episodios AS (
    SELECT description, gap, patient, episodio,
           date_diff('day', MIN(ini), MAX(fin)) AS duracion_dias,
           COUNT(*) AS n_recetas
    FROM con_episodio
    GROUP BY description, gap, patient, episodio
)
SELECT
    left(description, 20)            AS farmaco,
    gap,
    COUNT(*)                         AS n_episodios,
    COUNT(DISTINCT patient)          AS n_pacientes,
    ROUND(COUNT(*) * 1.0 / COUNT(DISTINCT patient), 2) AS episodios_por_paciente,
    MEDIAN(duracion_dias)            AS mediana_duracion_dias,
    SUM(n_recetas)                   AS recetas_cubiertas     -- 81,102 / 41,278 en todos los gaps
FROM episodios
GROUP BY description, gap
ORDER BY description, gap;

-- Histograma de duraciones de episodios de Epoetina (gap = 30):
-- intervalos de 30 días, el último agrupa "360+"
WITH recetas AS (
    SELECT patient, CAST(start AS DATE) AS ini, CAST(stop AS DATE) AS fin
    FROM medications
    WHERE description = '1 ML Epoetin Alfa 4000 UNT/ML Injection [Epogen]'
),
con_fin_previo AS (
    SELECT *, MAX(fin) OVER (PARTITION BY patient ORDER BY ini, fin
               ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS fin_previo
    FROM recetas
),
con_episodio AS (
    SELECT *, SUM(CASE WHEN fin_previo IS NULL
                        OR date_diff('day', fin_previo, ini) > 30 THEN 1 ELSE 0 END)
              OVER (PARTITION BY patient ORDER BY ini, fin ROWS UNBOUNDED PRECEDING) AS episodio
    FROM con_fin_previo
),
episodios AS (
    SELECT patient, episodio, date_diff('day', MIN(ini), MAX(fin)) AS duracion_dias
    FROM con_episodio GROUP BY patient, episodio
),
cubetas AS (
    SELECT LEAST(duracion_dias // 30, 12) AS cubeta, COUNT(*) AS n
    FROM episodios GROUP BY 1
)
SELECT
    CASE WHEN cubeta = 12 THEN '360+'
         ELSE (cubeta * 30) || '-' || (cubeta * 30 + 29) END AS rango_dias,
    n,
    repeat('#', CAST(ROUND(60.0 * n / MAX(n) OVER ()) AS INTEGER)) AS barra
FROM cubetas
ORDER BY cubeta;

-- Control independiente (Epoetina, gap = 30): el número de episodios debe
-- coincidir con contar, SIN ventanas, las recetas para las que NO existe otra
-- receta previa del mismo paciente cuyo fin quede a <= 30 días de su inicio
-- (o después de él).
WITH r AS (
    SELECT row_number() OVER () AS rid, patient, CAST(start AS DATE) AS ini,
           CAST(stop AS DATE) AS fin
    FROM medications
    WHERE description = '1 ML Epoetin Alfa 4000 UNT/ML Injection [Epogen]'
)
SELECT COUNT(*) AS episodios_control                                  -- debe = 785
FROM r a
WHERE NOT EXISTS (
    SELECT 1 FROM r b
    WHERE b.patient = a.patient
      AND (b.ini, b.fin, b.rid) < (a.ini, a.fin, a.rid)
      AND date_diff('day', b.fin, a.ini) <= 30
);


-- =============================================================================
-- Actividad 7: Deduplicar con ROW_NUMBER (última medición por paciente y analito)
-- Pregunta analítica: quedarse con UNA observación por (paciente, analito): la
--                     más reciente.
-- =============================================================================
-- DECISIONES DECLARADAS (confirmadas con el usuario):
--  (1) Analito = `code` (LOINC), no `description`: 19 códigos traen dos
--      descripciones (p. ej. 'Glucose' y 'Glucose [Mass/volume] in Blood');
--      por descripción se partiría un mismo analito en dos
--      (388,099 pares frente a 384,983 por código).
--  (2) Desempate cuando hay misma fecha (14,934 grupos paciente-código-fecha con
--      más de una fila, 13,774 con valores distintos), en este orden:
--        a. date DESC                      -> la más reciente
--        b. valor numérico antes que texto -> más defendible clínicamente
--        c. encounter DESC, value DESC     -> solo para que sea reproducible;
--                                             este último criterio NO es clínico
--  (3) Alcance: TODAS las observaciones (numéricas y de texto, todas las
--      categorías). Las actividades 8 y 9 filtrarán laboratorio y valor numérico.
--  (4) Patrón principal: CTE + WHERE rn = 1. Contraste: QUALIFY (misma lógica).
-- Por qué rn = 1 NO puede ir en el WHERE de la misma consulta: el orden lógico es
-- FROM -> WHERE -> GROUP BY -> HAVING -> funciones de ventana -> SELECT, así que
-- cuando se evalúa el WHERE la columna `rn` todavía no existe. Hay que calcularla
-- en un nivel interno (CTE/subconsulta) y filtrarla en el externo, o usar QUALIFY.
-- -----------------------------------------------------------------------------
-- RESULTADOS MEDIDOS: 5,719,327 filas -> 384,983 (un renglón por paciente y
-- código, 0 pares duplicados, fecha elegida = máxima del par en todos). CTE y
-- QUALIFY dan el mismo resultado (EXCEPT en ambas direcciones: 0 filas). Solo
-- 870 pares tienen empate en su ÚLTIMA fecha y en 746 los valores difieren: ahí
-- el desempate decide el dato conservado (ver decisión 2).
-- =============================================================================

-- Conteos antes y después (sin deduplicar frente a un renglón por par)
SELECT
    COUNT(*)                                       AS filas_antes,         -- 5,719,327
    COUNT(DISTINCT (patient, code))                AS pares_paciente_analito  -- 384,983 = filas_despues
FROM observations;

-- Camino principal: CTE con ROW_NUMBER y filtro externo
WITH ordenadas AS (
    SELECT
        o.*,
        ROW_NUMBER() OVER (
            PARTITION BY patient, code                          -- un analito por paciente
            ORDER BY
                date DESC,                                      -- (2a) la más reciente
                CASE WHEN TRY_CAST(value AS DOUBLE) IS NOT NULL
                     THEN 0 ELSE 1 END,                         -- (2b) numérico primero
                encounter DESC,                                 -- (2c) reproducible
                value DESC
        ) AS rn
    FROM observations o
)
SELECT date, patient, encounter, category, code, description, value, units, type
FROM ordenadas
WHERE rn = 1;

-- Contraste con QUALIFY (DuckDB filtra por la ventana sin CTE) y verificación
-- de equivalencia con EXCEPT en ambas direcciones (deben dar 0 filas).
WITH principal AS (
    SELECT date, patient, encounter, code, value
    FROM (
        SELECT o.*, ROW_NUMBER() OVER (
            PARTITION BY patient, code
            ORDER BY date DESC,
                     CASE WHEN TRY_CAST(value AS DOUBLE) IS NOT NULL THEN 0 ELSE 1 END,
                     encounter DESC, value DESC) AS rn
        FROM observations o
    )
    WHERE rn = 1
),
con_qualify AS (
    SELECT date, patient, encounter, code, value
    FROM observations
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY patient, code
        ORDER BY date DESC,
                 CASE WHEN TRY_CAST(value AS DOUBLE) IS NOT NULL THEN 0 ELSE 1 END,
                 encounter DESC, value DESC) = 1
)
SELECT
    (SELECT COUNT(*) FROM principal)                                   AS filas_principal,   -- 384,983
    (SELECT COUNT(*) FROM con_qualify)                                 AS filas_qualify,     -- 384,983
    (SELECT COUNT(*) FROM (SELECT * FROM principal EXCEPT SELECT * FROM con_qualify)) AS solo_en_principal,  -- 0
    (SELECT COUNT(*) FROM (SELECT * FROM con_qualify EXCEPT SELECT * FROM principal)) AS solo_en_qualify;    -- 0

-- Control independiente (sin ventanas): un renglón por par y la fecha elegida
-- es la máxima del par. Se espera 0 pares duplicados y 0 fechas distintas del máximo.
WITH elegidas AS (
    SELECT patient, code, date
    FROM (
        SELECT patient, code, date, ROW_NUMBER() OVER (
            PARTITION BY patient, code
            ORDER BY date DESC,
                     CASE WHEN TRY_CAST(value AS DOUBLE) IS NOT NULL THEN 0 ELSE 1 END,
                     encounter DESC, value DESC) AS rn
        FROM observations
    )
    WHERE rn = 1
),
maximos AS (
    SELECT patient, code, MAX(date) AS fecha_max
    FROM observations
    GROUP BY patient, code
)
SELECT
    COUNT(*)                                                    AS filas_elegidas,           -- 384,983
    COUNT(*) - COUNT(DISTINCT (e.patient, e.code))              AS pares_duplicados,         -- 0
    COUNT(*) FILTER (WHERE e.date <> m.fecha_max)               AS fecha_distinta_del_maximo -- 0
FROM elegidas e
JOIN maximos m USING (patient, code);

-- Cuántos pares dependen del desempate: la fecha máxima del par tiene varias filas
-- y no todas coinciden en valor (aquí el criterio 2b/2c decide qué se conserva).
WITH por_par AS (
    SELECT patient, code, MAX(date) AS fecha_max FROM observations GROUP BY patient, code
)
SELECT
    COUNT(*)                                          AS pares_con_empate_en_ultima_fecha,
    COUNT(*) FILTER (WHERE valores_distintos > 1)     AS de_ellos_con_valores_distintos
FROM (
    SELECT p.patient, p.code, COUNT(*) AS filas, COUNT(DISTINCT o.value) AS valores_distintos
    FROM por_par p
    JOIN observations o
      ON o.patient = p.patient AND o.code = p.code AND o.date = p.fecha_max
    GROUP BY p.patient, p.code
    HAVING COUNT(*) > 1
);


-- =============================================================================
-- Actividad 8: Acumulado vs. media móvil de 3 mediciones (frames)
-- Analito: HbA1c (code 4548-4, laboratorio, valor numérico)
-- Pregunta analítica: ¿cómo difiere la media acumulada (frame por defecto) de
--                     la media móvil de 3 mediciones (ROWS declarado)?
-- =============================================================================
-- DECISIONES DECLARADAS (confirmadas con el usuario):
--  (1) Analito: HbA1c, filtrado por code = '4548-4' (media móvil con lectura
--      clínica de tendencia del control glucémico).
--  (2) Orden dentro del paciente: ORDER BY date, encounter (determinista).
--      El frame por defecto de una ventana con ORDER BY es
--      RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW: las filas con el
--      MISMO valor de ORDER BY son "pares" y se agregan juntas. Por eso se
--      muestra una tercera columna con el acumulado en ROWS, para ver si el
--      frame por defecto cambia algo en el paciente elegido.
--  (3) Acumulado = AVG(valor) con el frame por defecto. Media móvil =
--      AVG(valor) con ROWS BETWEEN 2 PRECEDING AND CURRENT ROW. En las dos
--      primeras mediciones la ventana tiene menos de 3 filas: se CONSERVAN y
--      se marca con n_en_ventana (1, 2, 3, 3, ...).
--  (4) Paciente: el primer id (orden alfabético) con exactamente 12 mediciones
--      numéricas de HbA1c, sin fechas empatadas y con al menos 4 valores
--      distintos. Regla escrita en el SQL, no elegido a mano. Ajuste sobre la
--      regla acordada: sin el requisito de valores distintos salía el paciente
--      0301e7fa-..., cuyas 12 mediciones valen todas 7.0 y las tres columnas
--      eran idénticas (no demuestra nada). Hay 140 pacientes de 12 mediciones
--      sin empates con valores no constantes.
-- Por qué difieren: el acumulado pesa TODAS las mediciones previas por igual, así
-- que reacciona cada vez más lento (la medición n pesa 1/n). La media móvil solo
-- recuerda las últimas 3 y sigue la tendencia reciente.
-- -----------------------------------------------------------------------------
-- RESULTADOS MEDIDOS (paciente 05e42e38-..., 12 mediciones, 2017-2026): acumulada
-- y acumulada con ROWS son idénticas en las 12 filas (no hay fechas empatadas).
-- Difieren de la móvil desde la 4a medición: al caer a 5.8 (2024-03-08) la móvil
-- baja a 6.000 y la acumulada solo a 6.178; en la última, móvil 6.133 y
-- acumulada 6.167. Control sin frames: 12 filas comparadas, 0 diferencias.
-- =============================================================================

WITH hba1c AS (
    SELECT
        patient,
        encounter,
        date,
        CAST(value AS DOUBLE) AS valor
    FROM observations
    WHERE code = '4548-4'
      AND category = 'laboratory'
      AND type = 'numeric'
),
paciente_elegido AS (
    -- Regla determinista (decisión 4)
    SELECT patient
    FROM hba1c
    GROUP BY patient
    HAVING COUNT(*) = 12
       AND COUNT(*) = COUNT(DISTINCT date)      -- sin fechas empatadas
       AND COUNT(DISTINCT valor) >= 4           -- valores que varían
    ORDER BY patient
    LIMIT 1
)
SELECT
    h.patient,
    h.date,
    h.valor,
    -- Acumulado: frame por defecto (RANGE ... UNBOUNDED PRECEDING AND CURRENT ROW)
    ROUND(AVG(h.valor) OVER (
        PARTITION BY h.patient ORDER BY h.date, h.encounter
    ), 3) AS media_acumulada,
    -- Mismo acumulado pero con ROWS: fila por fila, sin agrupar pares
    ROUND(AVG(h.valor) OVER (
        PARTITION BY h.patient ORDER BY h.date, h.encounter
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ), 3) AS media_acumulada_rows,
    -- Media móvil de 3 mediciones: frame declarado
    ROUND(AVG(h.valor) OVER (
        PARTITION BY h.patient ORDER BY h.date, h.encounter
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 3) AS media_movil_3,
    -- Cuántas filas entran realmente en la ventana móvil (parcial al inicio)
    COUNT(*) OVER (
        PARTITION BY h.patient ORDER BY h.date, h.encounter
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS n_en_ventana
FROM hba1c h
JOIN paciente_elegido USING (patient)
ORDER BY h.date, h.encounter;

-- Control independiente (sin frames): para el paciente elegido, la media
-- acumulada y la móvil de cada medición se recalculan con un self-join sobre el
-- orden (date, encounter) y deben coincidir con la consulta de ventanas.
-- Se espera 0 filas con diferencia.
WITH hba1c AS (
    SELECT patient, encounter, date, CAST(value AS DOUBLE) AS valor,
           ROW_NUMBER() OVER (PARTITION BY patient ORDER BY date, encounter) AS pos
    FROM observations
    WHERE code = '4548-4' AND category = 'laboratory' AND type = 'numeric'
),
paciente_elegido AS (
    SELECT patient FROM hba1c
    GROUP BY patient
    HAVING COUNT(*) = 12 AND COUNT(*) = COUNT(DISTINCT date) AND COUNT(DISTINCT valor) >= 4
    ORDER BY patient LIMIT 1
),
ventanas AS (
    SELECT h.pos,
           AVG(h.valor) OVER (PARTITION BY h.patient ORDER BY h.pos) AS acum_w,
           AVG(h.valor) OVER (PARTITION BY h.patient ORDER BY h.pos
                              ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS movil_w
    FROM hba1c h JOIN paciente_elegido USING (patient)
),
manual AS (
    SELECT a.pos,
           AVG(b.valor) FILTER (WHERE b.pos <= a.pos)                       AS acum_m,
           AVG(b.valor) FILTER (WHERE b.pos BETWEEN a.pos - 2 AND a.pos)    AS movil_m
    FROM hba1c a
    JOIN paciente_elegido USING (patient)
    JOIN hba1c b ON b.patient = a.patient
    GROUP BY a.patient, a.pos
)
SELECT COUNT(*) AS filas_comparadas,                                       -- 12
       COUNT(*) FILTER (WHERE ABS(w.acum_w - m.acum_m) > 1e-9
                           OR ABS(w.movil_w - m.movil_m) > 1e-9) AS filas_con_diferencia  -- 0
FROM ventanas w JOIN manual m USING (pos);


-- =============================================================================
-- Actividad 9: Valor de laboratorio más cercano a la fecha índice (±90 días)
-- Índice: primer diagnóstico de 'Diabetes mellitus type 2 (disorder)' (444 pac.)
-- Analito: HbA1c (code 4548-4, laboratorio, numérico)
-- =============================================================================
-- DECISIONES DECLARADAS (confirmadas con el usuario):
--  (1) Índice = MIN(start) del diagnóstico DM2 por paciente; analito = HbA1c.
--  (2) POLÍTICA SOBRE VALORES POSTERIORES (decisión obligatoria): NO se permiten.
--      Política A (principal): solo valores previos o del día 0, -90 <= días <= 0.
--      Un valor medido DESPUÉS del índice ya refleja el diagnóstico y el
--      tratamiento: usarlo como covariable basal es fuga de información (sesión 3,
--      punto 7 del checklist). Costo declarado: 36 pacientes (139 - 103) que solo
--      tienen HbA1c posterior quedan sin valor. Política B (+-90 días, con
--      posteriores) se calcula solo como CONTRASTE para medir cuánto cambiaría.
--  (3) "Más cercano" = menor ABS(días). Empate de distancia (uno antes y otro
--      después): gana el anterior. Mismo día: date DESC, encounter DESC,
--      value DESC (determinista, no clínico).
--  (4) El día 0 cuenta como "previo". LIMITACIÓN: no se puede saber el orden
--      dentro del mismo día; la HbA1c del día 0 probablemente es el examen que
--      dispara el diagnóstico. Con la versión estricta (días < 0) saldrían 0
--      pacientes: ninguno tiene HbA1c estrictamente anterior en +-90 días.
-- -----------------------------------------------------------------------------
-- RESULTADOS MEDIDOS: de 444 pacientes con índice, la política A da valor a 103
-- (todos con la HbA1c del día 0) y deja 341 con NULL. La política B da valor a
-- 139: añade 36 pacientes cuyo único valor cercano es POSTERIOR al índice; a los
-- 103 de A les asigna el mismo valor (0 cambios), porque el día 0 es siempre el
-- más cercano. Es decir, B no mejora la medición basal: solo agrega 36 valores
-- con fuga. Control sin ventanas: 103 elegidos, 0 duplicados, 0 fuera de ventana.
-- =============================================================================

-- Política A (principal): un renglón por paciente con índice (444); NULL si no
-- hay HbA1c previa o del día 0 en los 90 días anteriores.
WITH indice AS (
    SELECT patient, MIN(start) AS fecha_indice
    FROM conditions
    WHERE description = 'Diabetes mellitus type 2 (disorder)'
    GROUP BY patient
),
hba1c AS (
    SELECT patient, encounter, date, CAST(date AS DATE) AS fecha,
           CAST(value AS DOUBLE) AS valor
    FROM observations
    WHERE code = '4548-4' AND category = 'laboratory' AND type = 'numeric'
),
candidatos AS (
    SELECT i.patient, i.fecha_indice, h.encounter, h.date, h.fecha, h.valor,
           date_diff('day', i.fecha_indice, h.fecha) AS dias   -- <0 antes, >0 después
    FROM indice i
    JOIN hba1c h USING (patient)
),
elegidos AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY patient
               ORDER BY ABS(dias),                -- (3) el más cercano
                        CASE WHEN dias > 0 THEN 1 ELSE 0 END,  -- empate: el anterior
                        date DESC, encounter DESC, valor DESC
           ) AS rn
    FROM candidatos
    WHERE dias BETWEEN -90 AND 0                  -- (2) política A: sin posteriores
)
SELECT
    i.patient,
    i.fecha_indice,
    e.fecha  AS fecha_hba1c,
    e.dias   AS dias_desde_indice,
    e.valor  AS hba1c_basal
FROM indice i
LEFT JOIN elegidos e ON e.patient = i.patient AND e.rn = 1
ORDER BY i.patient;

-- Resumen A frente a B (contraste) y cuántos pacientes cambian de valor
WITH indice AS (
    SELECT patient, MIN(start) AS fecha_indice
    FROM conditions
    WHERE description = 'Diabetes mellitus type 2 (disorder)'
    GROUP BY patient
),
candidatos AS (
    SELECT i.patient, h.encounter, h.date, CAST(h.value AS DOUBLE) AS valor,
           date_diff('day', i.fecha_indice, CAST(h.date AS DATE)) AS dias
    FROM indice i
    JOIN observations h ON h.patient = i.patient
    WHERE h.code = '4548-4' AND h.category = 'laboratory' AND h.type = 'numeric'
),
ranking AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY patient
                              ORDER BY ABS(dias), CASE WHEN dias > 0 THEN 1 ELSE 0 END,
                                       date DESC, encounter DESC, valor DESC) AS rn_b,
           -- Política A: la misma ordenación pero SOLO entre los no posteriores
           ROW_NUMBER() OVER (PARTITION BY patient, (dias <= 0)
                              ORDER BY ABS(dias), date DESC, encounter DESC, valor DESC) AS rn_a
    FROM candidatos
    WHERE ABS(dias) <= 90
),
a AS (SELECT patient, valor, dias FROM ranking WHERE dias <= 0 AND rn_a = 1),
b AS (SELECT patient, valor, dias FROM ranking WHERE rn_b = 1)
SELECT
    (SELECT COUNT(*) FROM indice)                                   AS pacientes_indice,     -- 444
    (SELECT COUNT(*) FROM a)                                        AS con_valor_politica_A, -- 103
    (SELECT COUNT(*) FROM b)                                        AS con_valor_politica_B, -- 139
    (SELECT COUNT(*) FROM b WHERE dias > 0)                         AS B_elige_posterior,
    (SELECT COUNT(*) FROM a JOIN b USING (patient) WHERE a.valor <> b.valor) AS cambian_de_valor_A_vs_B,
    (SELECT COUNT(*) FROM a WHERE dias = 0)                         AS A_en_dia_0;

-- Control independiente de la política A (sin ventanas): ningún valor elegido
-- queda fuera de [-90, 0] y no existe otra medición más cercana ni igual de cercana
-- y más reciente. Se espera 0 violaciones.
WITH indice AS (
    SELECT patient, MIN(start) AS fecha_indice
    FROM conditions
    WHERE description = 'Diabetes mellitus type 2 (disorder)'
    GROUP BY patient
),
cand AS (
    SELECT i.patient, h.date, h.encounter, CAST(h.value AS DOUBLE) AS valor,
           date_diff('day', i.fecha_indice, CAST(h.date AS DATE)) AS dias
    FROM indice i
    JOIN observations h ON h.patient = i.patient
    WHERE h.code = '4548-4' AND h.category = 'laboratory' AND h.type = 'numeric'
      AND date_diff('day', i.fecha_indice, CAST(h.date AS DATE)) BETWEEN -90 AND 0
),
elegidos AS (
    -- Elegido = no existe otra candidata del paciente más cercana, o igual de
    -- cercana pero más tardía dentro del día (mismo orden que el principal)
    SELECT c.* FROM cand c
    WHERE NOT EXISTS (
        SELECT 1 FROM cand o
        WHERE o.patient = c.patient
          AND (ABS(o.dias), -epoch(o.date), o.encounter, o.valor)
              < (ABS(c.dias), -epoch(c.date), c.encounter, c.valor)
    )
)
SELECT
    COUNT(*)                                       AS filas_elegidas,                 -- 103
    COUNT(*) - COUNT(DISTINCT patient)             AS pacientes_con_mas_de_una,       -- 0
    COUNT(*) FILTER (WHERE dias > 0 OR dias < -90) AS fuera_de_ventana_o_posteriores  -- 0
FROM elegidos;
