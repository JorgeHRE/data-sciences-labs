-- =====================================================================
-- Lab 18 — Actividades 2 y 3. Tabla de atrición con banderas reordenables
-- Base: Postgres del lab 12 (lab12-omop-db-1). Solo lectura: lee
-- results.cohorte_parametros / results.cohort (lab 17) y cdm.*.
-- Orden lógico de un SELECT: FROM → WHERE → GROUP BY → HAVING → SELECT → ORDER BY
--
-- Idea (decisión 6): en vez de filtrar paso a paso, se calcula UNA BANDERA
-- (true/false) por criterio sobre la MISMA población: las personas con
-- primera receta (índice ya fijado, 1,522 / 1,104). La atrición en cualquier
-- orden es entonces un AND acumulado: reordenar = cambiar el orden de los AND.
-- Las banderas replican los criterios del lab 17 (cohorte_definicion.sql) y
-- se validan contra results.cohort al final.
--
-- Para correr solo el bloque de banderas (marcadores anclados con ^):
--   sed -n '/^-- \[INICIO banderas\]/,/^-- \[FIN banderas\]/p' atricion.sql | psql ...
-- =====================================================================

-- [INICIO banderas] ====================================================
WITH
-- recetas: todas las recetas del fármaco de cada cohorte (igual que el lab 17,
-- actividad 2b). concept_ancestor expande el ingrediente a sus productos;
-- drug_type 32838 = receta (las vacunas, 32827, quedan fuera).
recetas AS (
    SELECT p.cohort_definition_id,
           d.person_id,
           d.drug_concept_id,
           d.drug_exposure_start_date AS inicio,
           d.drug_exposure_end_date   AS fin
    FROM results.cohorte_parametros p
    JOIN cdm.concept_ancestor ca ON ca.ancestor_concept_id = p.ingrediente_exp
    JOIN cdm.drug_exposure d     ON d.drug_concept_id = ca.descendant_concept_id
    WHERE d.drug_type_concept_id = 32838
      AND p.cohort_definition_id IN (1701, 1702)
),
-- evento_inicial: la PRIMERA receta de toda la historia, una fila por persona
-- y cohorte. Es el paso 0 de la tabla (1,522 / 1,104) y NO se reordena: define
-- cuál es el índice. Filtrar por fecha ANTES de tomar la primera receta daría
-- otra cohorte (1,233 en vez de 346: alguien que empezó en 2015 entraría como
-- «nuevo» en 2018). El inicio de estudio, en cambio, sí es una bandera.
evento_inicial AS (
    SELECT cohort_definition_id, person_id, min(inicio) AS fecha_indice
    FROM recetas
    GROUP BY cohort_definition_id, person_id
),
-- previas: cuántas recetas del fármaco están «activas» en [−365, −1] antes del
-- índice (inicio < índice y fin ≥ índice − 365). Es el criterio de lavado del
-- lab 17. JOIN + GROUP BY: una fila por (cohorte, persona) con alguna previa.
-- Con índice = primera receta de la historia no hay ninguna → el lavado no
-- quita a nadie por construcción; la bandera existe para que la definición
-- lo diga y para la sensibilidad de la actividad 9.
previas AS (
    SELECT e.cohort_definition_id, e.person_id, count(*) AS n_previas
    FROM evento_inicial e
    JOIN recetas r
      ON r.cohort_definition_id = e.cohort_definition_id
     AND r.person_id = e.person_id
     AND r.inicio < e.fecha_indice
     AND greatest(r.fin, r.inicio) >= e.fecha_indice - 365
    GROUP BY e.cohort_definition_id, e.person_id
),
-- obs: ¿hay UN periodo de observación que empiece ≤ índice − 365 y termine
-- ≥ índice? (las dos condiciones sobre el MISMO periodo, trampa 1 del lab 17).
-- observation_period tiene 1 fila por persona (lab 17, control 0a), así que
-- el JOIN no multiplica. Quien no tiene un periodo así queda con NULL (LEFT JOIN).
obs AS (
    SELECT e.cohort_definition_id, e.person_id, true AS ok
    FROM evento_inicial e
    JOIN cdm.observation_period op
      ON op.person_id = e.person_id
     AND op.observation_period_start_date <= e.fecha_indice - 365
     AND op.observation_period_end_date   >= e.fecha_indice
),
-- Primera fecha de cada diagnóstico por persona. «Hay un diagnóstico en
-- (−∞, índice]» equivale a «su primera fecha ≤ índice», y así se evita un
-- EXISTS correlacionado por persona (sin índice en person_id se colgaba, lab 17).
-- Una fila por persona: los JOIN siguientes no multiplican.
-- hta: 316866 «Hypertensive disorder» y descendientes (criterio 5b del lab 17).
hta AS (
    SELECT co.person_id, min(co.condition_start_date) AS primera
    FROM cdm.condition_occurrence co
    JOIN cdm.concept_ancestor ca ON ca.descendant_concept_id = co.condition_concept_id
    WHERE ca.ancestor_concept_id = 316866
    GROUP BY co.person_id
),
-- demencia: 4182210 «Dementia» y descendientes (criterio 5d).
demencia AS (
    SELECT co.person_id, min(co.condition_start_date) AS primera
    FROM cdm.condition_occurrence co
    JOIN cdm.concept_ancestor ca ON ca.descendant_concept_id = co.condition_concept_id
    WHERE ca.ancestor_concept_id = 4182210
    GROUP BY co.person_id
),
-- otro: primera receta del OTRO fármaco de cada cohorte (criterio 5e). Mismo
-- concept_ancestor que `recetas`, con ingrediente_otro.
otro AS (
    SELECT p.cohort_definition_id, de.person_id,
           min(de.drug_exposure_start_date) AS primera
    FROM results.cohorte_parametros p
    JOIN cdm.concept_ancestor ca ON ca.ancestor_concept_id = p.ingrediente_otro
    JOIN cdm.drug_exposure de    ON de.drug_concept_id = ca.descendant_concept_id
    WHERE de.drug_type_concept_id = 32838
      AND p.cohort_definition_id IN (1701, 1702)
    GROUP BY p.cohort_definition_id, de.person_id
),
-- visitas: cuántas visitas hay en [−365, −1] (criterio 5c, decisión 11 del
-- lab 17). Aquí SÍ hace falta contar: JOIN (una fila por visita) + GROUP BY
-- (de vuelta a una fila por persona). Quien no tiene ninguna no aparece.
visitas AS (
    SELECT e.cohort_definition_id, e.person_id, count(*) AS n
    FROM evento_inicial e
    JOIN cdm.visit_occurrence v
      ON v.person_id = e.person_id
     AND v.visit_start_date BETWEEN e.fecha_indice - 365 AND e.fecha_indice - 1
    GROUP BY e.cohort_definition_id, e.person_id
),
-- combo: personas cuya receta del día índice es una combinación (un producto
-- con más de un ingrediente en drug_strength; criterio 5f, decisión 12).
-- DISTINCT: dos recetas combinadas el mismo día seguirían siendo una persona.
combo AS (
    SELECT DISTINCT r.cohort_definition_id, r.person_id
    FROM recetas r
    JOIN evento_inicial e
      ON e.cohort_definition_id = r.cohort_definition_id
     AND e.person_id = r.person_id
     AND r.inicio = e.fecha_indice
    WHERE r.drug_concept_id IN (
        SELECT drug_concept_id
        FROM cdm.drug_strength
        GROUP BY drug_concept_id
        HAVING count(DISTINCT ingredient_concept_id) > 1)
),
banderas AS (
    SELECT e.cohort_definition_id, e.person_id, e.fecha_indice,
           -- Inicio de estudio: NULL en 1711/1712 = sin fecha, no filtra (lab 17).
           (p.inicio_estudio IS NULL OR e.fecha_indice >= p.inicio_estudio) AS f_estudio,
           coalesce(o.ok, false)                                            AS f_obs,
           (pr.n_previas IS NULL)                                           AS f_lavado,
           -- Edad aproximada por año, como en el lab 17 (actividad 5a).
           (extract(year FROM e.fecha_indice) - pe.year_of_birth >= 18)     AS f_adulto,
           -- Los NULL de los LEFT JOIN se vuelven false/true explícitos: un NULL
           -- en una bandera haría desaparecer a la persona de ambos lados.
           coalesce(h.primera <= e.fecha_indice, false)                     AS f_hta,
           (coalesce(v.n, 0) >= 2)                                          AS f_visitas,
           NOT coalesce(d.primera <= e.fecha_indice, false)                 AS f_sin_demencia,
           NOT coalesce(ot.primera <= e.fecha_indice, false)                AS f_sin_otro,
           (cb.person_id IS NULL)                                           AS f_sin_combo
    FROM evento_inicial e
    JOIN results.cohorte_parametros p USING (cohort_definition_id)
    JOIN cdm.person pe USING (person_id)
    LEFT JOIN previas pr USING (cohort_definition_id, person_id)
    LEFT JOIN obs o      USING (cohort_definition_id, person_id)
    LEFT JOIN hta h      USING (person_id)
    LEFT JOIN demencia d USING (person_id)
    LEFT JOIN otro ot    USING (cohort_definition_id, person_id)
    LEFT JOIN visitas v  USING (cohort_definition_id, person_id)
    LEFT JOIN combo cb   USING (cohort_definition_id, person_id)
)
-- [FIN banderas]
-- Control de las banderas (se pega después del bloque): una fila por persona y
-- cohorte (filas = personas distintas = 1,522 / 1,104; si algún LEFT JOIN
-- multiplicara, filas > personas) y cuántas cumplen cada bandera.
-- Resultado (2026-11-15), cohortes 1701 / 1702:
--   filas 1,522 / 1,104 · f_estudio 346 / 238 · f_obs, f_lavado, f_adulto = todas
SELECT cohort_definition_id AS cohorte,
       count(*) AS filas,
       count(DISTINCT person_id) AS personas,
       count(*) FILTER (WHERE f_estudio)       AS f_estudio,
       count(*) FILTER (WHERE f_obs)           AS f_obs,
       count(*) FILTER (WHERE f_lavado)        AS f_lavado,
       count(*) FILTER (WHERE f_adulto)        AS f_adulto,
       count(*) FILTER (WHERE f_hta)           AS f_hta,
       count(*) FILTER (WHERE f_visitas)       AS f_visitas,
       count(*) FILTER (WHERE f_sin_demencia)  AS f_sin_demencia,
       count(*) FILTER (WHERE f_sin_otro)      AS f_sin_otro,
       count(*) FILTER (WHERE f_sin_combo)     AS f_sin_combo
FROM banderas
GROUP BY cohort_definition_id
ORDER BY cohort_definition_id;
