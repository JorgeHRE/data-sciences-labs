-- =====================================================================
-- Lab 18 — Actividades 9 y 10. Variantes de lavado: 180, 365 y 730 días
-- Base: Postgres del lab 12. Crea UNA TABLA TEMPORAL de la sesión (`variantes`);
-- no escribe nada persistente. Lee results.cohorte_parametros y cdm.*.
-- Orden lógico de un SELECT: FROM → WHERE → GROUP BY → HAVING → SELECT → ORDER BY
--
-- Definición de la variante W (decisión 19): «nuevo usuario con lavado de W
-- días y W días de observación previa». W se aplica a las dos ventanas:
--   · observación previa: el periodo de observación empieza ≤ índice − W y contiene el índice
--   · lavado: ninguna receta del fármaco ACTIVA en [−W, −1] (inicio < índice y fin ≥ índice − W)
-- El índice es la PRIMERA receta, desde el inicio de estudio, que cumple las dos
-- (no la primera de toda la historia): con un lavado «relajado» el índice puede
-- moverse con W. El resto de la definición no cambia (adulto, hipertensión,
-- ≥ 2 visitas en [−365, −1], sin demencia previa, sin el otro fármaco, sin
-- combinación; salida = least(fin del tramo + 30, fin de observación, inicio del
-- otro fármaco)). Las ventanas de los criterios clínicos se quedan en 365 días:
-- solo se mueve el lavado.
-- Control (lo comprueba comparar el script): la variante W = 365 reproduce
-- results.cohort 1701 / 1702 persona por persona, con la misma fecha índice y de salida.
--
-- Una fila por (cohorte, W, persona) de la cohorte final de esa variante:
--   c · w · pid · idx (fecha índice) · salida
-- Para correr solo esto con psql (la tabla vive en esa sesión):
--   cat variantes.sql | docker exec -i lab12-omop-db-1 psql -U $POSTGRES_USER -d $POSTGRES_DB
-- =====================================================================
CREATE TEMP TABLE variantes AS
WITH w(w) AS (VALUES (180), (365), (730)),
-- recetas del fármaco de cada cohorte (igual que el lab 17, actividad 2b)
rec AS (
    SELECT p.cohort_definition_id AS c, p.inicio_estudio, d.person_id AS pid,
           d.drug_concept_id AS producto,
           d.drug_exposure_start_date AS ini, d.drug_exposure_end_date AS fin
    FROM results.cohorte_parametros p
    JOIN cdm.concept_ancestor ca ON ca.ancestor_concept_id = p.ingrediente_exp
    JOIN cdm.drug_exposure d     ON d.drug_concept_id = ca.descendant_concept_id
    WHERE d.drug_type_concept_id = 32838
      AND p.cohort_definition_id IN (1701, 1702)
),
-- Dos «fin máximo anterior», con dos ventanas de fila distintas (decisión del lab 17):
--  · fin_prev_dia  = fin más tardío entre recetas que empezaron un día ANTES o más:
--                    RANGE con INTERVAL deja fuera las recetas del mismo día (inicio < índice).
--                    Sirve para el lavado: hay exposición activa en [−W, −1] si fin_prev_dia ≥ índice − W.
--  · fin_prev_fila = fin más tardío de las filas anteriores en el orden (inicio, fin):
--                    sirve para numerar los tramos con hueco > 30 días (gaps and islands).
-- greatest(fin, inicio): 83 recetas de lisinopril tienen fin < inicio.
rec2 AS (
    SELECT r.*,
           max(greatest(r.fin, r.ini)) OVER (PARTITION BY r.c, r.pid ORDER BY r.ini
                RANGE BETWEEN UNBOUNDED PRECEDING AND INTERVAL '1 day' PRECEDING) AS fin_prev_dia,
           max(greatest(r.fin, r.ini)) OVER (PARTITION BY r.c, r.pid ORDER BY r.ini, r.fin
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)                 AS fin_prev_fila
    FROM rec r
),
rec3 AS (   -- número de tramo (isla): sube cuando la receta empieza > 30 días después del fin previo
    SELECT r.*,
           sum(CASE WHEN r.fin_prev_fila IS NULL OR r.ini - r.fin_prev_fila > 30 THEN 1 ELSE 0 END)
               OVER (PARTITION BY r.c, r.pid ORDER BY r.ini, r.fin ROWS UNBOUNDED PRECEDING) AS isla
    FROM rec2 r
),
op AS (
    SELECT person_id AS pid, observation_period_start_date AS s, observation_period_end_date AS e
    FROM cdm.observation_period      -- 1 fila por persona (lab 17, control 0a): los JOIN no multiplican
),
-- Índice de cada variante: la primera receta ≥ inicio de estudio que cumple la
-- observación previa de W días Y el lavado de W días. GROUP BY → una fila por (cohorte, W, persona).
idx AS (
    SELECT r.c, w.w, r.pid, min(r.ini) AS idx
    FROM rec3 r
    CROSS JOIN w
    JOIN op ON op.pid = r.pid AND op.e >= r.ini AND op.s <= r.ini - w.w
    WHERE r.ini >= r.inicio_estudio
      AND (r.fin_prev_dia IS NULL OR r.fin_prev_dia < r.ini - w.w)
    GROUP BY r.c, w.w, r.pid
),
-- Criterios clínicos: primera fecha por persona de cada diagnóstico o fármaco
-- (una fila por persona; «hay un diagnóstico en (−∞, índice]» ⇔ su primera fecha ≤ índice).
hta AS (
    SELECT co.person_id AS pid, min(co.condition_start_date) AS primera
    FROM cdm.condition_occurrence co
    JOIN cdm.concept_ancestor ca ON ca.descendant_concept_id = co.condition_concept_id AND ca.ancestor_concept_id = 316866
    GROUP BY co.person_id
),
dem AS (
    SELECT co.person_id AS pid, min(co.condition_start_date) AS primera
    FROM cdm.condition_occurrence co
    JOIN cdm.concept_ancestor ca ON ca.descendant_concept_id = co.condition_concept_id AND ca.ancestor_concept_id = 4182210
    GROUP BY co.person_id
),
otro_all AS (   -- todas las recetas del OTRO fármaco de cada cohorte
    SELECT p.cohort_definition_id AS c, d.person_id AS pid, d.drug_exposure_start_date AS ini
    FROM results.cohorte_parametros p
    JOIN cdm.concept_ancestor ca ON ca.ancestor_concept_id = p.ingrediente_otro
    JOIN cdm.drug_exposure d     ON d.drug_concept_id = ca.descendant_concept_id
    WHERE d.drug_type_concept_id = 32838 AND p.cohort_definition_id IN (1701, 1702)
),
otro AS (SELECT c, pid, min(ini) AS primera FROM otro_all GROUP BY c, pid),
otro_post AS (  -- primer inicio del otro fármaco DESPUÉS del índice (corte de la salida)
    SELECT i.c, i.w, i.pid, min(o.ini) AS fecha_otro
    FROM idx i
    JOIN otro_all o ON o.c = i.c AND o.pid = i.pid AND o.ini > i.idx
    GROUP BY i.c, i.w, i.pid
),
vis AS (        -- visitas en [−365, −1]: JOIN (una fila por visita) + GROUP BY (de vuelta a una por persona)
    SELECT i.c, i.w, i.pid, count(*) AS n
    FROM idx i
    JOIN cdm.visit_occurrence v ON v.person_id = i.pid AND v.visit_start_date BETWEEN i.idx - 365 AND i.idx - 1
    GROUP BY i.c, i.w, i.pid
),
combo AS (      -- la receta del día índice es una combinación (producto con > 1 ingrediente)
    SELECT DISTINCT i.c, i.w, i.pid
    FROM idx i
    JOIN rec r ON r.c = i.c AND r.pid = i.pid AND r.ini = i.idx
    WHERE r.producto IN (SELECT drug_concept_id FROM cdm.drug_strength
                         GROUP BY drug_concept_id HAVING count(DISTINCT ingredient_concept_id) > 1)
),
-- Salida: el tramo (isla) de exposición continua que contiene la receta del índice.
isla_idx AS (
    SELECT i.c, i.w, i.pid, min(r.isla) AS isla
    FROM idx i
    JOIN rec3 r ON r.c = i.c AND r.pid = i.pid AND r.ini = i.idx
    GROUP BY i.c, i.w, i.pid
),
tramo AS (
    SELECT ii.c, ii.w, ii.pid, max(greatest(r.fin, r.ini)) AS fin_tramo
    FROM isla_idx ii
    JOIN rec3 r ON r.c = ii.c AND r.pid = ii.pid AND r.isla = ii.isla
    GROUP BY ii.c, ii.w, ii.pid
)
SELECT i.c, i.w, i.pid, i.idx,
       least(t.fin_tramo + 30, op.e, ot.fecha_otro) AS salida   -- least ignora NULL en Postgres
FROM idx i
JOIN results.cohorte_parametros p ON p.cohort_definition_id = i.c
JOIN op ON op.pid = i.pid
JOIN cdm.person pe ON pe.person_id = i.pid
JOIN tramo t ON t.c = i.c AND t.w = i.w AND t.pid = i.pid
LEFT JOIN hta h       ON h.pid = i.pid
LEFT JOIN dem d       ON d.pid = i.pid
LEFT JOIN otro oo     ON oo.c = i.c AND oo.pid = i.pid
LEFT JOIN otro_post ot ON ot.c = i.c AND ot.w = i.w AND ot.pid = i.pid
LEFT JOIN vis         ON vis.c = i.c AND vis.w = i.w AND vis.pid = i.pid
LEFT JOIN combo cb    ON cb.c = i.c AND cb.w = i.w AND cb.pid = i.pid
WHERE extract(year FROM i.idx) - pe.year_of_birth >= 18         -- adulto (misma aproximación por año del lab 17)
  AND coalesce(h.primera <= i.idx, false)                        -- hipertensión en (−∞, 0]
  AND coalesce(vis.n, 0) >= 2                                    -- ≥ 2 visitas en [−365, −1]
  AND NOT coalesce(d.primera <= i.idx, false)                    -- sin demencia previa
  AND NOT coalesce(oo.primera <= i.idx, false)                   -- sin el otro fármaco hasta el día 0
  AND cb.pid IS NULL;                                            -- sin combinación en el índice

-- Resultado esperado (2026-11-15): 1701: 122 / 122 / 121 · 1702: 81 / 81 / 81 (W = 180 / 365 / 730)
SELECT c AS cohorte, w, count(*) AS n, count(DISTINCT pid) AS personas
FROM variantes
GROUP BY c, w
ORDER BY c, w;
