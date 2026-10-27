-- Actividad 6: quince preguntas clínicas, de menor a mayor dificultad.
-- Se ejecuta sobre clinica.duckdb (ver carga.sql).

-- ===================== BÁSICAS =====================

-- 6.1 ¿Cuántos pacientes hay en la cohorte y cuántos siguen vivos?
-- "Vivo" aquí = sin fecha de muerte registrada (deathdate IS NULL). En un estudio
-- real esto depende de la fecha de corte y del seguimiento, no solo del dato.
-- Control: vivos + fallecidos = total.
SELECT
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE deathdate IS NULL) AS vivos,
    COUNT(deathdate) AS fallecidos
FROM patients;

-- 6.2 ¿Cómo se distribuye la cohorte por sexo?
-- La columna es gender (M/F); en un estudio real habría que distinguir sexo asignado
-- al nacer de identidad de género. Control: los conteos suman 5904 y los % suman 100.
SELECT
    gender,
    COUNT(*) AS n,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM patients
GROUP BY gender
ORDER BY n DESC;

-- 6.3 ¿Cuáles son los 10 diagnósticos más frecuentes de la cohorte?
-- Se cuentan pacientes distintos (prevalencia), no filas: un paciente con varios
-- episodios del mismo diagnóstico cuenta una vez. Se agrupa por code; 4 códigos
-- tienen más de una descripción, así que ANY_VALUE puede elegir cualquiera.
-- Ojo: la tabla mezcla ICD10 y SNOMED-CT, y 8 de los 10 primeros son (finding) o
-- (situation), no enfermedades (p. ej. "Medication review due" está en el 100 %).
-- Para un estudio habría que filtrar por tipo y unificar el sistema de codificación.
SELECT
    code,
    ANY_VALUE(description) AS diagnostico,
    COUNT(DISTINCT patient) AS n_pacientes,
    ROUND(100.0 * COUNT(DISTINCT patient) / (SELECT COUNT(*) FROM patients), 2) AS prevalencia_pct
FROM conditions
GROUP BY code
ORDER BY n_pacientes DESC
LIMIT 10;

-- 6.4 ¿Cuántos pacientes nacieron antes de 1960 y cuántos de ellos siguen vivos?
-- Se compara birthdate contra un literal de fecha (no YEAR(birthdate)), y "antes de
-- 1960" deja fuera el 1 de enero de 1960. Control: vivos + fallecidos = n_nacidos_antes_1960.
SELECT
    COUNT(*) AS n_nacidos_antes_1960,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM patients), 2) AS pct_total,
    COUNT(*) FILTER (WHERE deathdate IS NULL) AS vivos,
    COUNT(*) FILTER (WHERE deathdate IS NOT NULL) AS fallecidos
FROM patients
WHERE birthdate < DATE '1960-01-01';

-- 6.5 ¿Cuántos encuentros hay por año?
-- Salto brusco entre 2016 (12 940) y 2017 (26 892), y meseta de ~27 000 hasta 2025.
-- No se encontró la causa: hay encuentros desde 1916 y la mezcla de encounterclass es
-- casi igual antes y después de 2017, así que no se explica por pérdida de historia ni
-- de tipos de encuentro. Es un artefacto del generador, no un cambio clínico real.
-- 2026 está incompleto (corte en octubre), no es comparable.
-- Control: la suma de los años es 429 640, igual al total de encounters.
SELECT
    YEAR(start) AS anio,
    COUNT(*) AS n_encuentros
FROM encounters
GROUP BY anio
ORDER BY anio ASC;

-- ===================== INTERMEDIAS =====================

-- 6.6 ¿Cuál es el número medio y mediano de encuentros por paciente?
-- Agregación en dos niveles: primero el conteo por paciente (CTE), luego AVG y MEDIAN
-- sobre esos conteos. Se parte de patients con LEFT JOIN y se cuenta e.Id (no COUNT(*))
-- para incluir a quien no tuviera encuentros; en esta cohorte nadie tiene 0.
-- Media (72.77) >> mediana (39): distribución asimétrica, con una cola de pacientes
-- con cientos de encuentros (máximo 990). Control: media = 429 640 / 5 904.
WITH por_paciente AS (
    SELECT
        p.Id AS patient,
        COUNT(e.Id) AS n_encuentros
    FROM patients p
    LEFT JOIN encounters e
      ON p.Id = e.patient
    GROUP BY p.Id
)
SELECT
    ROUND(AVG(n_encuentros), 2) AS media_encuentros,
    MEDIAN(n_encuentros) AS mediana_encuentros,
    MIN(n_encuentros) AS min_encuentros,
    MAX(n_encuentros) AS max_encuentros
FROM por_paciente;

-- 6.7 ¿A qué edad media se diagnostica por primera vez la diabetes tipo 2?
-- Condición elegida: SNOMED 44054006 "Diabetes mellitus type 2 (disorder)", 444 pacientes.
-- No se incluyen prediabetes ni complicaciones (nefropatía, retinopatía...), que son
-- otros códigos. Se toma el primer diagnóstico por paciente (MIN(start)) antes de
-- promediar, y la edad en años con fracción (días / 365.25).
-- Resultado principal: 45.67 años (mediana 46.05). Análisis de sensibilidad: 4 pacientes
-- tienen el diagnóstico antes de los 18 años (el mínimo es 0.94 años, sin evidencia de
-- que sea un error); excluirlos mueve la media solo +0.32 años, así que se reportan todos.
WITH primer_diagnostico AS (
    SELECT
        c.patient,
        p.birthdate,
        MIN(c.start) AS primera_fecha,
        DATEDIFF('day', p.birthdate, MIN(c.start)) / 365.25 AS edad_al_debut
    FROM conditions c
    JOIN patients p
      ON c.patient = p.Id
    WHERE c.code = '44054006'
    GROUP BY c.patient, p.birthdate
)
SELECT
    -- Cohorte completa (sin exclusiones)
    COUNT(*) AS n_total,
    ROUND(AVG(edad_al_debut), 2) AS media_todos,
    ROUND(MEDIAN(edad_al_debut), 2) AS mediana_todos,

    -- Sensibilidad: excluyendo menores de 18 años
    COUNT(*) FILTER (WHERE edad_al_debut >= 18) AS n_filtrados,
    ROUND(AVG(edad_al_debut) FILTER (WHERE edad_al_debut >= 18), 2) AS media_ge18,
    ROUND(MEDIAN(edad_al_debut) FILTER (WHERE edad_al_debut >= 18), 2) AS mediana_ge18,

    -- Impacto de la exclusión sobre la media
    ROUND(
        AVG(edad_al_debut) FILTER (WHERE edad_al_debut >= 18) - AVG(edad_al_debut),
        2
    ) AS delta_media_anios
FROM primer_diagnostico;

-- 6.8 ¿Qué diagnósticos tienen más de 50 pacientes distintos?
-- "Más de 50" es estrictamente > 50: salen 196 códigos (con >= 50 serían 198, porque
-- dos códigos tienen exactamente 50). Se cuentan pacientes distintos, no filas.
-- Control: con HAVING > 0 salen los 720 códigos distintos de conditions.
-- HAVING filtra grupos ya agregados; WHERE no puede, porque se ejecuta antes del GROUP BY.
SELECT
    code,
    ANY_VALUE(description) AS diagnostico,
    COUNT(DISTINCT patient) AS n_pacientes
FROM conditions
GROUP BY code
HAVING COUNT(DISTINCT patient) > 50
ORDER BY n_pacientes DESC;

-- 6.9 ¿Cómo se distribuye la hemoglobina glucosilada (HbA1c)?
-- Analito: LOINC 4548-4 "Hemoglobin A1c/Hemoglobin.total in Blood", 58 969 mediciones de
-- 2 565 pacientes, única unidad (%), sin valores no numéricos. value es VARCHAR, así que
-- se filtra type = 'numeric' y se convierte con TRY_CAST.
-- Resultado: mín 2.3, p10 2.9, mediana 4.0, media 4.37, p90 6.2, máx 10.9.
-- Sospechoso: en clínica lo normal es 4-5.6 % y la diabetes se diagnostica con >= 6.5 %,
-- pero aquí el 48.6 % de las mediciones es < 4.0 %. Es una limitación de los datos
-- sintéticos: se reporta como sospechosa, no se interpreta clínicamente.
-- Ojo: se miden mediciones, no pacientes (~23 por paciente); los pacientes con más
-- seguimiento pesan más. Un valor por paciente requeriría una función de ventana.
WITH valores_limpios AS (
    SELECT
        TRY_CAST(value AS DOUBLE) AS val_num
    FROM observations
    WHERE code = '4548-4'
      AND type = 'numeric'
      AND value IS NOT NULL
)
SELECT
    COUNT(*) AS n_mediciones,
    ROUND(MIN(val_num), 2) AS min_val,
    ROUND(QUANTILE_CONT(val_num, 0.10), 2) AS p10,
    ROUND(MEDIAN(val_num), 2) AS mediana,
    ROUND(AVG(val_num), 2) AS media,
    ROUND(QUANTILE_CONT(val_num, 0.90), 2) AS p90,
    ROUND(MAX(val_num), 2) AS max_val
FROM valores_limpios;

-- 6.10 ¿Cuántos pacientes hay por grupo etario y sexo?
-- Edad = a la fecha de la muerte para los fallecidos y a la fecha de corte para los vivos,
-- por eso se separan ambos estados: los grupos no son una foto en un momento único.
-- Fecha de corte = último encuentro registrado (MAX(start) de encounters, 2026-10-26).
-- Una versión inicial con corte fijo 2026-10-01 dejaba a 6 pacientes con edad negativa
-- dentro de '0-17'; el control de suma (5 904) no lo detectaba, sí lo hizo mirar la edad mínima.
-- edad_max = 18.0 en 0-17 es redondeo de visualización (17.998), no mala clasificación.
-- Control: las 8 celdas suman 5 904. El vivo más viejo tiene 110.8 años (sospechoso).
WITH parametros AS (
    SELECT CAST(MAX(start) AS DATE) AS fecha_corte
    FROM encounters
),
etiquetado AS (
    SELECT
        p.gender,
        CASE
            WHEN p.deathdate IS NULL THEN 'Vivo (edad al corte)'
            ELSE 'Fallecido (edad al morir)'
        END AS estado_vital,
        (DATEDIFF('day', p.birthdate, COALESCE(p.deathdate, param.fecha_corte)) / 365.25) AS edad,
        CASE
            WHEN (DATEDIFF('day', p.birthdate, COALESCE(p.deathdate, param.fecha_corte)) / 365.25) < 18 THEN '0-17'
            WHEN (DATEDIFF('day', p.birthdate, COALESCE(p.deathdate, param.fecha_corte)) / 365.25) < 40 THEN '18-39'
            WHEN (DATEDIFF('day', p.birthdate, COALESCE(p.deathdate, param.fecha_corte)) / 365.25) < 65 THEN '40-64'
            ELSE '65+'
        END AS grupo_etario
    FROM patients p
    CROSS JOIN parametros param
)
SELECT
    grupo_etario,
    estado_vital,
    COUNT(*) FILTER (WHERE gender = 'F') AS mujeres,
    COUNT(*) FILTER (WHERE gender = 'M') AS hombres,
    COUNT(*) AS total_grupo,
    ROUND(MIN(edad), 2) AS edad_min,
    ROUND(MAX(edad), 2) AS edad_max
FROM etiquetado
GROUP BY grupo_etario, estado_vital
ORDER BY MIN(edad), estado_vital;

-- ===================== AVANZADAS =====================

-- 6.11 ¿Cuántos pacientes tienen diabetes tipo 2 Y hipertensión?
-- Cada diagnóstico es una fila distinta en conditions, así que se agrupa por paciente y
-- se exige tener los dos códigos: SNOMED 44054006 (diabetes tipo 2) y 59621000
-- (hipertensión esencial). HAVING COUNT(DISTINCT code) = 2 significa "tiene ambos".
-- Resultado: 309 pacientes (69.59 % de los diabéticos; la hipertensión en toda la cohorte
-- es 36.3 %, casi la mitad), lo que apunta a una fuerte asociación entre ambas.
-- Verificación: INTERSECT de las dos listas de pacientes da también 309, y los diabéticos
-- SIN hipertensión (NOT EXISTS sobre conditions) son 135: 309 + 135 = 444 diabéticos.
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

-- 6.12 ¿Cuántos pacientes con diabetes tipo 2 no tienen ninguna medición de HbA1c?
-- Anti-join con NOT EXISTS: diabéticos (SNOMED 44054006) sin ninguna fila en observations
-- con LOINC 4548-4. Resultado: 0; los 444 diabéticos tienen al menos una HbA1c.
-- Verificación: con EXISTS (el complemento) salen 444, y 0 + 444 = 444.
-- En datos reales esta misma consulta suele revelar una brecha de cuidado (diabéticos sin
-- seguimiento); en esta cohorte sintética no hay ninguna.
SELECT COUNT(DISTINCT c.patient) AS diabeticos_sin_hba1c
FROM conditions c
WHERE c.code = '44054006'
  AND NOT EXISTS (
      SELECT 1
      FROM observations o
      WHERE o.patient = c.patient
        AND o.code = '4548-4'
  );

-- 6.13 Para cada paciente: su primer y su último encuentro.
-- Una fila por paciente (5 904), con MIN/MAX de start y el seguimiento entre ambos. Como
-- el resultado completo no se lee, se muestran los 10 con mayor seguimiento.
-- Seguimiento medio por paciente: 11 998 días (32.85 años), mediana 11 544; los encuentros
-- se registran desde el nacimiento, no solo los últimos años. 9 pacientes tienen todos
-- sus encuentros el mismo día (seguimiento 0).
-- Control: hay 5 904 filas y la suma de n_encuentros es 429 640, igual que encounters.
SELECT
    patient,
    MIN(start) AS primer_encuentro,
    MAX(start) AS ultimo_encuentro,
    COUNT(*) AS n_encuentros,
    DATEDIFF('day', MIN(start), MAX(start)) AS dias_seguimiento,
    ROUND(DATEDIFF('day', MIN(start), MAX(start)) / 365.25, 2) AS anios_seguimiento
FROM encounters
GROUP BY patient
ORDER BY dias_seguimiento DESC
LIMIT 10;

-- 6.14 ¿Cuál es el medicamento más frecuente entre los pacientes con diabetes tipo 2?
-- Cohorte: SNOMED 44054006 (444 pacientes). La CTE usa SELECT DISTINCT patient para que el
-- JOIN con medications no multiplique filas, y se cuentan pacientes distintos (no recetas).
-- Resultado: metformina 500 mg ER (231 pacientes, 52.03 %), pero solo por 1 paciente sobre
-- nitroglicerina (230). Cuatro de los cinco primeros no tratan la diabetes (nitroglicerina,
-- metoprolol, paracetamol, simvastatina): son comunes en toda la cohorte o por comorbilidad.
-- "Más frecuente entre diabéticos" no es "propio de los diabéticos"; para eso habría que
-- comparar contra el % en el resto de la cohorte.
-- Control: los 444 diabéticos tienen al menos un medicamento (0 sin medicación).
WITH cohort_diabeticos AS (
    SELECT DISTINCT patient
    FROM conditions
    WHERE code = '44054006'
)
SELECT
    m.code,
    ANY_VALUE(m.description) AS medicamento,
    COUNT(DISTINCT m.patient) AS n_pacientes,
    ROUND(100.0 * COUNT(DISTINCT m.patient) / (SELECT COUNT(*) FROM cohort_diabeticos), 2) AS pct_penetracion
FROM medications m
JOIN cohort_diabeticos d
  ON m.patient = d.patient
GROUP BY m.code
ORDER BY n_pacientes DESC
LIMIT 5;

-- 6.15 ¿Cuántos encuentros de urgencias no tienen ningún diagnóstico registrado, y a
-- cuántos pacientes afectan?
-- Anti-join con NOT EXISTS sobre conditions.encounter. Se usa encounterclass = 'emergency'
-- (no se incluye 'urgentcare': es atención urgente no hospitalaria) y cualquier fila de
-- conditions cuenta como diagnóstico, incluidos los (finding) y (situation): son registros
-- clínicos del encuentro, y filtrarlos exigiría un criterio por tipo que no está en la tabla.
-- Resultado: 5 272 de 15 958 encuentros de urgencias (33.04 %), 1 873 pacientes.
-- Control: 10 686 con diagnóstico + 5 272 sin diagnóstico = 15 958.
-- Ojo: conditions.encounter es el encuentro donde SE DIAGNOSTICÓ la condición, así que
-- "sin diagnóstico" significa "sin condición nueva registrada en ese encuentro", no que el
-- paciente carezca de diagnósticos. En toda la cohorte, 85.5 % de los ambulatorios
-- tampoco tiene diagnóstico asociado.
WITH urgencias_sin_diagnostico AS (
    SELECT
        e.Id AS encounter_id,
        e.patient
    FROM encounters e
    WHERE e.encounterclass = 'emergency'
      AND NOT EXISTS (
          SELECT 1
          FROM conditions c
          WHERE c.encounter = e.Id
      )
)
SELECT
    COUNT(*) AS encuentros_urgencias_sin_diagnostico,
    COUNT(DISTINCT patient) AS pacientes_afectados
FROM urgencias_sin_diagnostico;
