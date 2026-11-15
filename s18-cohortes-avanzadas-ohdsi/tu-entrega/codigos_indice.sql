-- =====================================================================
-- Lab 18 — Actividad 6. ¿Qué códigos metieron a la gente?
-- Base: Postgres del lab 12. Solo lectura: lee results.cohort,
-- results.cohorte_parametros y cdm.*. Cada consulta corre sola:
--   docker exec -i lab12-omop-db-1 psql -U $POSTGRES_USER -d $POSTGRES_DB < codigos_indice.sql
-- Orden lógico de un SELECT: FROM → WHERE → GROUP BY → HAVING → SELECT → ORDER BY
-- «Entrar por un código» = el producto (drug_concept_id) de la receta del día
-- índice. El concept set de la cohorte es el ingrediente (lisinopril 1308216 /
-- amlodipino 1332418, de results.cohorte_parametros) y todos sus descendientes
-- en concept_ancestor, como en el lab 17.
-- =====================================================================

-- Consulta 1. Producto de entrada por cohorte, ordenado, con % y % acumulado.
-- Qué hace: une cada persona de la cohorte con su receta del día índice
-- (misma persona, drug_exposure_start_date = cohort_start_date, tipo receta
-- 32838) y se queda con las recetas que pertenecen al concept set. Cuenta
-- PERSONAS distintas por producto (DISTINCT: una persona con dos recetas del
-- mismo producto el mismo día cuenta una vez; 175 y 85 personas tenían dos
-- recetas el día índice, lab 17 control 2c).
-- Los JOIN: results.cohorte_parametros y concept son por clave primaria (1 fila
-- por cohorte / por concepto); concept_ancestor trae UNA fila por (ancestro,
-- descendiente), así que ningún JOIN multiplica personas. Se comprueba en la
-- consulta 2: la suma de personas por producto debe ser el N de la cohorte.
-- Funciones de ventana: sum() OVER (PARTITION BY cohorte) da el total de la
-- cohorte en cada fila (para el %), y el acumulado suma en el orden de la tabla.
-- Resultado esperado (2026-11-15):
--   1701 (122): 19080128 «lisinopril 10 MG Oral Tablet» 120 (98.4 %) · 1308251 «5 MG» 2 (1.6 %)
--   1702 (81):  19073094 «amlodipine 2.5 MG Oral Tablet» 81 (100 %)
SELECT c.cohort_definition_id                                          AS cohorte,
       d.drug_concept_id                                               AS concept_id,
       cn.concept_name,
       cn.concept_class_id,
       count(DISTINCT c.subject_id)                                    AS personas,
       round(100.0 * count(DISTINCT c.subject_id)
             / sum(count(DISTINCT c.subject_id)) OVER (PARTITION BY c.cohort_definition_id), 1) AS pct,
       round(100.0 * sum(count(DISTINCT c.subject_id)) OVER (PARTITION BY c.cohort_definition_id
                                  ORDER BY count(DISTINCT c.subject_id) DESC, d.drug_concept_id)
             / sum(count(DISTINCT c.subject_id)) OVER (PARTITION BY c.cohort_definition_id), 1) AS pct_acumulado
FROM results.cohort c
JOIN results.cohorte_parametros p USING (cohort_definition_id)
JOIN cdm.concept_ancestor ca ON ca.ancestor_concept_id = p.ingrediente_exp
JOIN cdm.drug_exposure d
  ON d.person_id = c.subject_id
 AND d.drug_exposure_start_date = c.cohort_start_date
 AND d.drug_type_concept_id = 32838
 AND d.drug_concept_id = ca.descendant_concept_id
JOIN cdm.concept cn ON cn.concept_id = d.drug_concept_id
WHERE c.cohort_definition_id IN (1701, 1702)
GROUP BY c.cohort_definition_id, d.drug_concept_id, cn.concept_name, cn.concept_class_id
ORDER BY c.cohort_definition_id, personas DESC, d.drug_concept_id;

-- Consulta 2. Control: cada persona entra por UN solo producto.
-- Qué mide: personas de la cohorte, personas con receta del concept set el día
-- índice, y personas con más de un producto DISTINTO ese día. Si esta última
-- no fuera 0, la suma de la consulta 1 superaría el N (una persona contaría en
-- dos filas). HAVING filtra grupos (después del GROUP BY), no filas.
-- Resultado esperado (2026-11-15): 1701: 122 · 122 · 0   1702: 81 · 81 · 0
SELECT c.cohort_definition_id AS cohorte,
       count(DISTINCT c.subject_id)                                   AS personas,
       count(DISTINCT x.person_id)                                    AS con_receta_indice,
       count(DISTINCT x.person_id) FILTER (WHERE x.productos > 1)     AS con_mas_de_un_producto
FROM results.cohort c
LEFT JOIN (
    SELECT c2.cohort_definition_id, c2.subject_id AS person_id,
           count(DISTINCT d.drug_concept_id) AS productos
    FROM results.cohort c2
    JOIN results.cohorte_parametros p USING (cohort_definition_id)
    JOIN cdm.concept_ancestor ca ON ca.ancestor_concept_id = p.ingrediente_exp
    JOIN cdm.drug_exposure d
      ON d.person_id = c2.subject_id AND d.drug_exposure_start_date = c2.cohort_start_date
     AND d.drug_type_concept_id = 32838 AND d.drug_concept_id = ca.descendant_concept_id
    WHERE c2.cohort_definition_id IN (1701, 1702)
    GROUP BY c2.cohort_definition_id, c2.subject_id
) x ON x.cohort_definition_id = c.cohort_definition_id AND x.person_id = c.subject_id
WHERE c.cohort_definition_id IN (1701, 1702)
GROUP BY c.cohort_definition_id
ORDER BY c.cohort_definition_id;

-- Consulta 3. ¿Cuánto del concept set se usa? Por cohorte y clase de concepto:
--   en_el_set      = conceptos del ingrediente y sus descendientes
--   con_recetas    = los que tienen al menos una receta (tipo 32838) en la base
--   como_indice    = los que son el producto del índice de la cohorte final
-- Un concepto «decorativo» está en el set y no se usa: no cambia quién entra.
-- Resultado esperado (2026-11-15): lisinopril 98 conceptos en el set, 9 con
-- recetas (todos de clase Clinical Drug), 2 como índice de 1701; el resto
-- (marcas, dosis agrupadas, componentes) sin una sola receta.
WITH conj AS (
    SELECT p.cohort_definition_id AS cohorte, ca.descendant_concept_id AS concepto
    FROM results.cohorte_parametros p
    JOIN cdm.concept_ancestor ca ON ca.ancestor_concept_id = p.ingrediente_exp
    WHERE p.cohort_definition_id IN (1701, 1702)
),
con_recetas AS (
    SELECT DISTINCT j.cohorte, j.concepto
    FROM conj j
    JOIN cdm.drug_exposure d ON d.drug_concept_id = j.concepto AND d.drug_type_concept_id = 32838
),
como_indice AS (
    SELECT DISTINCT c.cohort_definition_id AS cohorte, d.drug_concept_id AS concepto
    FROM results.cohort c
    JOIN conj j ON j.cohorte = c.cohort_definition_id
    JOIN cdm.drug_exposure d
      ON d.person_id = c.subject_id AND d.drug_exposure_start_date = c.cohort_start_date
     AND d.drug_type_concept_id = 32838 AND d.drug_concept_id = j.concepto
    WHERE c.cohort_definition_id IN (1701, 1702)
)
SELECT j.cohorte, cn.concept_class_id AS clase,
       count(*)                                  AS en_el_set,
       count(r.concepto)                         AS con_recetas,
       count(i.concepto)                         AS como_indice
FROM conj j
JOIN cdm.concept cn ON cn.concept_id = j.concepto
LEFT JOIN con_recetas r ON r.cohorte = j.cohorte AND r.concepto = j.concepto
LEFT JOIN como_indice i ON i.cohorte = j.cohorte AND i.concepto = j.concepto
GROUP BY j.cohorte, cn.concept_class_id
ORDER BY j.cohorte, en_el_set DESC, clase;

-- Consulta 4. ¿La concentración nace en el índice o ya está en la base?
-- Compara el peso del producto más frecuente en cuatro etapas, por cohorte:
--   1. todas las recetas del ingrediente (unidad = receta)
--   2. la primera receta de cada persona, toda la historia (unidad = persona; el evento inicial)
--   3. la cohorte sin inicio de estudio (1711 / 1712)
--   4. la cohorte final (1701 / 1702)
-- Si ya es alta entre TODAS las recetas, no la crea la definición de la cohorte:
-- es una propiedad de cómo la base codifica el fármaco.
-- UNION ALL (no UNION): apila las cuatro etapas sin quitar duplicados (cada fila
-- es una unidad distinta; UNION las fundiría si coincidieran). Las unidades
-- son recetas en la etapa 1 y personas en las demás: se declara en la columna.
-- Orden lógico: FROM (etapas apiladas) → GROUP BY etapa, producto → ventana de
-- total por etapa → se queda con el producto más frecuente de cada etapa.
-- Resultado (2026-11-15), pct del producto más frecuente por etapa (1701 / 1702):
--   1 todas las recetas  (42,085 / 34,475): 98.1 % / 100.0 %   (9 / 6 productos)
--   2 primeras recetas   (1,522 / 1,104):   93.0 % /  99.7 %   (9 / 4 productos)
--   3 sin inicio estudio (242 / 131):       94.6 % / 100.0 %   (5 / 1 productos)
--   4 cohorte final      (122 / 81):        98.4 % / 100.0 %   (2 / 1 productos)
WITH etapas AS (
    SELECT p.cohort_definition_id AS cohorte, 1 AS etapa, 'todas las recetas' AS nombre, 'receta' AS unidad,
           d.drug_exposure_id::bigint AS unidad_id, d.drug_concept_id AS concepto
    FROM results.cohorte_parametros p
    JOIN cdm.concept_ancestor ca ON ca.ancestor_concept_id = p.ingrediente_exp
    JOIN cdm.drug_exposure d ON d.drug_concept_id = ca.descendant_concept_id AND d.drug_type_concept_id = 32838
    WHERE p.cohort_definition_id IN (1701, 1702)
    UNION ALL
    SELECT f.cohorte, 2, 'primera receta (toda la historia)', 'persona', f.person_id, d.drug_concept_id
    FROM (SELECT p.cohort_definition_id AS cohorte, p.ingrediente_exp, d2.person_id, min(d2.drug_exposure_start_date) AS fecha
          FROM results.cohorte_parametros p
          JOIN cdm.concept_ancestor ca2 ON ca2.ancestor_concept_id = p.ingrediente_exp
          JOIN cdm.drug_exposure d2 ON d2.drug_concept_id = ca2.descendant_concept_id AND d2.drug_type_concept_id = 32838
          WHERE p.cohort_definition_id IN (1701, 1702)
          GROUP BY p.cohort_definition_id, p.ingrediente_exp, d2.person_id) f
    JOIN cdm.concept_ancestor ca ON ca.ancestor_concept_id = f.ingrediente_exp
    JOIN cdm.drug_exposure d ON d.person_id = f.person_id AND d.drug_exposure_start_date = f.fecha
                            AND d.drug_type_concept_id = 32838 AND d.drug_concept_id = ca.descendant_concept_id
    UNION ALL
    SELECT c.cohort_definition_id - 10, 3, 'cohorte sin inicio de estudio', 'persona', c.subject_id, d.drug_concept_id
    FROM results.cohort c
    JOIN results.cohorte_parametros p ON p.cohort_definition_id = c.cohort_definition_id
    JOIN cdm.concept_ancestor ca ON ca.ancestor_concept_id = p.ingrediente_exp
    JOIN cdm.drug_exposure d ON d.person_id = c.subject_id AND d.drug_exposure_start_date = c.cohort_start_date
                            AND d.drug_type_concept_id = 32838 AND d.drug_concept_id = ca.descendant_concept_id
    WHERE c.cohort_definition_id IN (1711, 1712)
    UNION ALL
    SELECT c.cohort_definition_id, 4, 'cohorte final', 'persona', c.subject_id, d.drug_concept_id
    FROM results.cohort c
    JOIN results.cohorte_parametros p ON p.cohort_definition_id = c.cohort_definition_id
    JOIN cdm.concept_ancestor ca ON ca.ancestor_concept_id = p.ingrediente_exp
    JOIN cdm.drug_exposure d ON d.person_id = c.subject_id AND d.drug_exposure_start_date = c.cohort_start_date
                            AND d.drug_type_concept_id = 32838 AND d.drug_concept_id = ca.descendant_concept_id
    WHERE c.cohort_definition_id IN (1701, 1702)
),
por_producto AS (
    SELECT cohorte, etapa, nombre, unidad, concepto, count(DISTINCT unidad_id) AS n
    FROM etapas
    GROUP BY cohorte, etapa, nombre, unidad, concepto
)
SELECT cohorte, etapa, nombre, unidad,
       sum(n)                                          AS total,
       count(*)                                        AS productos_distintos,
       max(n)                                          AS n_producto_top,
       round(100.0 * max(n) / sum(n), 1)               AS pct_top
FROM por_producto
GROUP BY cohorte, etapa, nombre, unidad
ORDER BY cohorte, etapa;

-- Consulta 5. ¿Por qué el producto más frecuente de lisinopril pasa de 93.0 %
-- (primeras recetas) a 98.4 % (cohorte final)? Separa a quienes inician con el
-- producto más frecuente (19080128, 10 mg; el de la consulta 1) de quienes
-- inician con cualquier otro, y cuenta cuántos de cada grupo quedan fuera por
-- el inicio de estudio y cuántos llegan a la cohorte final. Solo lisinopril (1701).
-- Una fila por persona en `prod` (DISTINCT; 0 personas con 2 productos el día
-- índice, consulta 2), así que los conteos son personas.
-- Resultado (2026-11-15), 2 filas:
--   10 mg:          1,415 primeras · 318 con índice desde 2017 · 1,097 antes · 120 en la cohorte final
--   otro producto:    107 primeras ·  28 con índice desde 2017 ·    79 antes ·   2 en la cohorte final
WITH idx AS (
    SELECT d.person_id, min(d.drug_exposure_start_date) AS fecha
    FROM cdm.drug_exposure d
    JOIN cdm.concept_ancestor ca ON ca.descendant_concept_id = d.drug_concept_id AND ca.ancestor_concept_id = 1308216
    WHERE d.drug_type_concept_id = 32838
    GROUP BY d.person_id
),
prod AS (
    SELECT DISTINCT i.person_id, i.fecha, d.drug_concept_id
    FROM idx i
    JOIN cdm.drug_exposure d
      ON d.person_id = i.person_id AND d.drug_exposure_start_date = i.fecha AND d.drug_type_concept_id = 32838
    JOIN cdm.concept_ancestor ca ON ca.descendant_concept_id = d.drug_concept_id AND ca.ancestor_concept_id = 1308216
)
SELECT CASE WHEN drug_concept_id = 19080128 THEN '10 mg' ELSE 'otro producto' END AS producto,
       count(*)                                                    AS primeras,
       count(*) FILTER (WHERE fecha >= DATE '2017-01-01')          AS indice_desde_2017,
       count(*) FILTER (WHERE fecha <  DATE '2017-01-01')          AS indice_antes_2017,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM results.cohort c
                                      WHERE c.cohort_definition_id = 1701 AND c.subject_id = prod.person_id)) AS en_cohorte_final
FROM prod
GROUP BY 1
ORDER BY 1;
