-- =====================================================================
-- Lab 18 — Actividad 7. Conceptos huérfanos
-- Un huérfano es un código que (1) aparece con frecuencia en la base, (2) se
-- parece a lo que buscabas y (3) NO está en tu concept set. Es el único
-- diagnóstico que detecta lo que FALTA; los demás auditan lo que ya pusiste.
-- Base: Postgres del lab 12. Solo lectura. Cada consulta corre sola:
--   docker exec -i lab12-omop-db-1 psql -U $POSTGRES_USER -d $POSTGRES_DB < huerfanos.sql
-- Orden lógico de un SELECT: FROM → WHERE → GROUP BY → HAVING → SELECT → ORDER BY
-- Los concept sets son los del lab 17: ingrediente (o condición) + todos sus
-- descendientes en concept_ancestor.
-- =====================================================================

-- Consulta 1. Búsqueda por texto: resumen por concept set.
-- Método de la actividad: buscar en CONCEPT por texto los términos de la
-- condición, quedarse con los que tienen registros en la base y restar los
-- que ya están en el set. Se hace en dos niveles: «estricto» (el nombre mismo
-- de lo que se busca) y «ampliado» (términos cercanos, para ver qué más hay).
-- Se parte de los conceptos USADOS en la base (pocos miles) y se unen con
-- concept por clave primaria: así el filtro de texto (regex, ~*) solo corre
-- sobre lo que tiene registros, no sobre todo el vocabulario.
-- Se devuelve UNA FILA POR CONJUNTO Y NIVEL aunque no haya huérfanos: un
-- INNER JOIN dejaría «0 filas», que se confunde con «no se midió».
-- Resultado esperado (2026-11-15), 6 filas:
--   estrictos: lisinopril 0 huérfanos · amlodipino 0 · hipertensión 0 · demencia 0
--   ampliado hipertensión: 4 huérfanos (ver consulta 2) · ampliado demencia: 0
WITH conjuntos(conjunto, nivel, tabla, regex, ancestro) AS (
    VALUES ('lisinopril',    'estricto', 'drug',      'lisinopril',                                         1308216),
           ('amlodipino',    'estricto', 'drug',      'amlodipine',                                         1332418),
           ('hipertensión',  'estricto', 'condition', 'hypertens',                                          316866),
           ('hipertensión',  'ampliado', 'condition', 'hypertens|blood pressure|proteinuria|albuminuria|eclampsia', 316866),
           ('demencia',      'estricto', 'condition', 'dementia|alzheimer',                                 4182210),
           ('demencia',      'ampliado', 'condition', 'dementia|alzheimer|cognit|memory|amnes|delirium|lewy|neurodegen', 4182210)
),
usos AS (   -- conceptos con registros y a cuántas personas
    SELECT 'drug' AS tabla, drug_concept_id AS concepto, count(DISTINCT person_id) AS personas
    FROM cdm.drug_exposure GROUP BY drug_concept_id
    UNION ALL
    SELECT 'condition', condition_concept_id, count(DISTINCT person_id)
    FROM cdm.condition_occurrence GROUP BY condition_concept_id
),
cand AS (   -- conceptos USADOS cuyo nombre coincide con el texto del conjunto
    SELECT cj.conjunto, cj.nivel, cj.ancestro, c.concept_id, c.concept_name, u.personas,
           EXISTS (SELECT 1 FROM cdm.concept_ancestor ca
                   WHERE ca.ancestor_concept_id = cj.ancestro
                     AND ca.descendant_concept_id = c.concept_id) AS en_el_set
    FROM conjuntos cj
    JOIN usos u ON u.tabla = cj.tabla
    JOIN cdm.concept c ON c.concept_id = u.concepto AND c.concept_name ~* cj.regex
)
SELECT cj.conjunto, cj.nivel,
       count(c.concept_id)                              AS coinciden_con_registros,
       count(c.concept_id) FILTER (WHERE c.en_el_set)   AS en_el_set,
       count(c.concept_id) FILTER (WHERE NOT c.en_el_set) AS huerfanos
FROM conjuntos cj
LEFT JOIN cand c ON c.conjunto = cj.conjunto AND c.nivel = cj.nivel
GROUP BY cj.conjunto, cj.nivel
ORDER BY cj.conjunto, cj.nivel DESC;

-- Consulta 2. Los huérfanos que aparecieron (nivel ampliado), con cuántas
-- personas los tienen. Mismo método que la consulta 1; aquí se listan.
-- Resultado esperado (2026-11-15), 4 filas, todos de hipertensión ampliada:
--   45769905 Microalbuminuria due to type 2 diabetes mellitus  792 personas
--   45757499 Proteinuria due to type 2 diabetes mellitus       613
--   137613   Eclampsia in pregnancy                            120
--   4065875  Blood pressure within reference range               3
WITH usos AS (
    SELECT condition_concept_id AS concepto, count(DISTINCT person_id) AS personas
    FROM cdm.condition_occurrence GROUP BY condition_concept_id
)
SELECT c.concept_id, c.concept_name, u.personas
FROM usos u
JOIN cdm.concept c ON c.concept_id = u.concepto
WHERE c.concept_name ~* 'hypertens|blood pressure|proteinuria|albuminuria|eclampsia'
  AND NOT EXISTS (SELECT 1 FROM cdm.concept_ancestor ca
                  WHERE ca.ancestor_concept_id = 316866 AND ca.descendant_concept_id = c.concept_id)
ORDER BY u.personas DESC, c.concept_id;

-- Consulta 3. Huérfanos por códigos FUENTE y sin mapear (lo que hace
-- CohortDiagnostics además del texto de CONCEPT). Un registro sin mapear
-- (concept_id = 0) o mapeado a un concepto fuera del set, pero cuyo valor
-- fuente menciona lo buscado, es un huérfano que el texto de CONCEPT no ve.
-- Una fila con tres conteos (todos deben ser 0 para que no haya huérfanos
-- de este tipo); count(*) devuelve 0 si no hay filas, no «sin resultado».
-- Resultado esperado (2026-11-15): 0 · 0 · 0 · 0
SELECT
  (SELECT count(*) FROM cdm.condition_occurrence WHERE condition_concept_id = 0) AS condiciones_sin_mapear,
  (SELECT count(*) FROM cdm.drug_exposure        WHERE drug_concept_id = 0)      AS recetas_sin_mapear,
  (SELECT count(*) FROM cdm.condition_occurrence co
   WHERE co.condition_source_value ~* 'hypertens|dementia|alzheimer'
     AND NOT EXISTS (SELECT 1 FROM cdm.concept_ancestor ca
                     WHERE ca.descendant_concept_id = co.condition_concept_id
                       AND ca.ancestor_concept_id IN (316866, 4182210)))        AS fuente_condicion_fuera_del_set,
  (SELECT count(*) FROM cdm.drug_exposure d
   WHERE d.drug_source_value ~* 'lisinopril|amlodipine'
     AND NOT EXISTS (SELECT 1 FROM cdm.concept_ancestor ca
                     WHERE ca.descendant_concept_id = d.drug_concept_id
                       AND ca.ancestor_concept_id IN (1308216, 1332418)))        AS fuente_receta_fuera_del_set;

-- Consulta 4. El candidato real, en toda la base: presión arterial elevada sin
-- diagnóstico de hipertensión. measurement tiene presión sistólica (3004249)
-- y diastólica (3012888) para las 5,904 personas. «Elevada» = sistólica ≥ 140 o
-- diastólica ≥ 90 (umbral habitual de la guía clínica; decisión 15); se cuentan
-- FECHAS distintas con esa condición, porque un valor aislado puede ser
-- transitorio. GROUP BY persona-fecha evita contar dos tomas del mismo día.
-- LEFT JOIN al diagnóstico de hipertensión: quien no tiene diagnóstico queda con
-- NULL (y se cuenta aparte; con un INNER JOIN desaparecería, que es justo lo
-- que se quiere ver).
-- Resultado esperado (2026-11-15), 1 fila: 2,078 personas con ≥ 2 fechas
-- elevadas · 1,163 con diagnóstico · 915 sin él · 2,207 personas con
-- diagnóstico de hipertensión en toda la base.
WITH pa AS (
    SELECT m.person_id, m.measurement_date AS fecha
    FROM cdm.measurement m
    WHERE (m.measurement_concept_id = 3004249 AND m.value_as_number >= 140)
       OR (m.measurement_concept_id = 3012888 AND m.value_as_number >= 90)
    GROUP BY m.person_id, m.measurement_date
),
n AS (SELECT person_id, count(*) AS fechas FROM pa GROUP BY person_id),
dx AS (
    SELECT DISTINCT co.person_id
    FROM cdm.condition_occurrence co
    JOIN cdm.concept_ancestor ca ON ca.descendant_concept_id = co.condition_concept_id
                                AND ca.ancestor_concept_id = 316866
)
SELECT count(*) FILTER (WHERE n.fechas >= 2)                                  AS pa_elevada_2_fechas,
       count(*) FILTER (WHERE n.fechas >= 2 AND dx.person_id IS NOT NULL)     AS con_dx_hta,
       count(*) FILTER (WHERE n.fechas >= 2 AND dx.person_id IS NULL)         AS sin_dx_hta,
       (SELECT count(*) FROM dx)                                              AS personas_con_dx_hta
FROM n
LEFT JOIN dx USING (person_id);

-- Consulta 5. El intruso: «Pre-eclampsia» (439393) es descendiente de 316866
-- «Hypertensive disorder», así que entra al criterio de hipertensión. Cuenta,
-- en toda la base, quién tiene ese código, quién tiene cualquier código del set
-- y a quién solo ese le haría cumplir el criterio. bool_and: verdadero si TODOS
-- los códigos de la persona son 439393. Los dos conceptos usados del set son
-- «Essential hypertension» (320128) y «Pre-eclampsia» (439393).
-- Resultado esperado (2026-11-15), 1 fila: 85 con pre-eclampsia · 2,207 con
-- algún código del set · 62 solo con pre-eclampsia.
WITH hx AS (
    SELECT co.person_id, co.condition_concept_id
    FROM cdm.condition_occurrence co
    JOIN cdm.concept_ancestor ca ON ca.descendant_concept_id = co.condition_concept_id
                                AND ca.ancestor_concept_id = 316866
)
SELECT count(DISTINCT person_id) FILTER (WHERE condition_concept_id = 439393) AS con_preeclampsia,
       count(DISTINCT person_id)                                              AS con_algun_codigo_set,
       (SELECT count(*) FROM (SELECT person_id FROM hx GROUP BY person_id
                              HAVING bool_and(condition_concept_id = 439393)) z) AS solo_preeclampsia
FROM hx;

-- Consulta 6. Otros inhibidores de la ECA en la base (ingredientes «-pril»).
-- Si la pregunta fuera «nuevos usuarios de un IECA», estos serían huérfanos
-- del concept set; con la pregunta del lab 17 (lisinopril contra amlodipino)
-- no lo son: son otros fármacos. Se cuentan personas con al menos una receta
-- de cada ingrediente (clase Ingredient) usando concept_ancestor.
-- DISTINCT: una persona con muchas recetas cuenta una vez.
-- Resultado (2026-11-15), 5 filas: lisinopril 1,522 · ramipril 14 · enalapril 13 ·
-- benazepril 9 · quinapril 2.
SELECT c.concept_name AS ingrediente, count(DISTINCT d.person_id) AS personas
FROM cdm.drug_exposure d
JOIN cdm.concept_ancestor ca ON ca.descendant_concept_id = d.drug_concept_id
JOIN cdm.concept c ON c.concept_id = ca.ancestor_concept_id AND c.concept_class_id = 'Ingredient'
WHERE d.drug_type_concept_id = 32838
  AND c.concept_name ~* 'pril$'
GROUP BY c.concept_name
ORDER BY personas DESC, c.concept_name;
