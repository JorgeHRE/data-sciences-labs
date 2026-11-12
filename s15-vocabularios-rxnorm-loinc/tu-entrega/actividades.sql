-- =====================================================================
-- Lab 15 — Consultas de exploración por actividad
-- Base: Postgres del lab 12 (lab12-omop-db-1, BD omop_lab12), solo lectura.
-- Vocabulario: v5.0 29-AUG-26 · RxNorm 20260601 · ATC 2026-02-01 · LOINC 2.82
-- Los concept sets finales van en concept_sets/ (actividad 9).
-- Orden lógico de un SELECT: FROM → WHERE → GROUP BY → HAVING → SELECT → ORDER BY
-- =====================================================================

-- Actividad 1b. Los conteos de RxNav (SCDF y BN), pero en nuestra base.
-- RxCUI = concept.concept_code. Desde el ingrediente:
--   'RxNorm ing of'  → sus formas clínicas (SCDF, clase Clinical Drug Form)
--   'Has brand name' → sus marcas (BN, clase Brand Name; no estándar)
-- Combinación = el SCDF o la marca está ligado a MÁS DE UN ingrediente.
-- Se cuenta con una subconsulta (cuántos IN apuntan a ese concepto) y no
-- con un JOIN a los ingredientes, que daría una fila por ingrediente y
-- contaría dos veces cada combinación (Trampa 2 de la actividad 2).
-- Esperado: 6 filas (RxNav del 2026-11-11 entre corchetes):
--   metformina     SCDF 26 [21] (4 solas / 22 comb.) · BN 23 [14] (7 / 16)
--   lisinopril     SCDF  3 [3]  (2 / 1)              · BN  8 [4]  (4 / 4)
--   empagliflozina SCDF  5 [5]  (1 / 4)              · BN  4 [4]  (1 / 3)
-- La base tiene más porque conserva productos que RxNorm ya marcó como
-- Obsolete (retirados del mercado de EE. UU.; p. ej. Fortamet, Avandamet).
WITH ingr AS (
    SELECT concept_id, concept_code AS rxcui, concept_name
    FROM cdm.concept
    WHERE vocabulary_id = 'RxNorm' AND concept_class_id = 'Ingredient'
      AND concept_code IN ('6809', '29046', '1545653')
),
ligados AS (           -- una fila por (ingrediente, SCDF o marca)
    SELECT i.concept_name AS ingrediente, i.rxcui, c.concept_id,
           c.concept_class_id,
           (SELECT count(*)                       -- ¿cuántos IN lo comparten?
            FROM cdm.concept_relationship r2
            JOIN cdm.concept i2 ON i2.concept_id = r2.concept_id_1
            WHERE r2.concept_id_2 = c.concept_id
              AND r2.relationship_id = r.relationship_id
              -- solo flechas que salen de un Ingredient: a una marca
              -- también apuntan con 'Has brand name' todos sus productos
              -- (Synjardy: 24 flechas, solo 2 de ingredientes)
              AND i2.concept_class_id = 'Ingredient') AS n_ingr
    FROM ingr i
    JOIN cdm.concept_relationship r ON r.concept_id_1 = i.concept_id
     AND r.relationship_id IN ('RxNorm ing of', 'Has brand name')
    JOIN cdm.concept c ON c.concept_id = r.concept_id_2
     AND c.concept_class_id IN ('Clinical Drug Form', 'Brand Name')
)
SELECT ingrediente, rxcui, concept_class_id,
       count(*)                            AS total,
       count(*) FILTER (WHERE n_ingr = 1)  AS un_ingrediente,
       count(*) FILTER (WHERE n_ingr > 1)  AS combinaciones
FROM ligados
GROUP BY ingrediente, rxcui, concept_class_id
ORDER BY ingrediente, concept_class_id DESC;

-- Actividad 2. Los 20 drug_concept_id más frecuentes y su(s) ingrediente(s).
-- Decisión 3: «frecuente» = filas de drug_exposure (se añade pacientes).
-- Decisión 4: ancestros de clase Ingredient INCLUIDO el nivel 0, con
-- LEFT JOIN para que las vacunas (sin ingrediente) no desaparezcan.
-- Granularidad: top20 = 1 fila por producto; con_ingr = 1 fila por
-- (producto, ingrediente), así que las combinaciones MULTIPLICAN filas;
-- el GROUP BY final vuelve a 1 fila por producto (string_agg los junta).
-- Control de filas: top20 20 → con_ingr 23 (20 + 3 segundos ingredientes
-- de las combinaciones) → resultado 20. Esperado: 2 productos con 0
-- ingredientes (vacunas CVX), 15 con 1 y 3 con 2.
WITH top20 AS (
    SELECT drug_concept_id,
           count(*)                  AS filas,
           count(DISTINCT person_id) AS pacientes
    FROM cdm.drug_exposure
    GROUP BY drug_concept_id
    ORDER BY filas DESC, drug_concept_id   -- desempate fijo y reproducible
    LIMIT 20
),
ingr AS (   -- pares (concepto, ingrediente); nivel 0 incluido (decisión 4)
    SELECT a.descendant_concept_id, i.concept_name AS ingrediente
    FROM cdm.concept_ancestor a
    JOIN cdm.concept i ON i.concept_id = a.ancestor_concept_id
    WHERE i.vocabulary_id = 'RxNorm' AND i.concept_class_id = 'Ingredient'
),
con_ingr AS (
    -- Un solo LEFT JOIN, contra los pares ya filtrados. Si se hiciera
    -- LEFT JOIN a concept_ancestor y luego a concept, entrarían TODOS los
    -- ancestros (formas, clases ATC…) como filas con ingrediente NULL.
    SELECT t.*, g.ingrediente
    FROM top20 t
    LEFT JOIN ingr g ON g.descendant_concept_id = t.drug_concept_id
)
SELECT c.drug_concept_id, left(p.concept_name, 60) AS nombre, p.concept_class_id,
       c.filas, c.pacientes,
       count(c.ingrediente)                                    AS n_ingredientes,
       string_agg(c.ingrediente, ' + ' ORDER BY c.ingrediente) AS ingredientes
FROM con_ingr c
JOIN cdm.concept p ON p.concept_id = c.drug_concept_id
GROUP BY c.drug_concept_id, p.concept_name, p.concept_class_id, c.filas, c.pacientes
ORDER BY c.filas DESC;

-- Actividad 3a. De la clase ATC A10B a los ingredientes, a los productos
-- de la base y a los pacientes. Decisión 5: A10B tal cual (incluye GLP-1
-- inyectables).
-- Camino: ATC A10B ─concept_ancestor→ Ingredient RxNorm ─concept_ancestor→
-- productos (drug_concept_id) que aparecen en drug_exposure.
-- Los productos de la base se calculan primero con DISTINCT (drug_exposure
-- no tiene índice en drug_concept_id; ver paso 0c). Un producto combinado
-- podría colgar de dos ingredientes de A10B y salir dos veces en el JOIN:
-- por eso todo se cuenta con count(DISTINCT …).
-- Esperado: 42 ingredientes · 2 productos en la base (metformina ER
-- 500 mg y liraglutida) · 231 pacientes (los 2 de liraglutida también
-- toman metformina).
WITH a10b_ingr AS (
    SELECT DISTINCT i.concept_id, i.concept_name
    FROM cdm.concept atc
    JOIN cdm.concept_ancestor a ON a.ancestor_concept_id = atc.concept_id
    JOIN cdm.concept i          ON i.concept_id = a.descendant_concept_id
    WHERE atc.vocabulary_id = 'ATC' AND atc.concept_code = 'A10B'
      AND i.vocabulary_id = 'RxNorm' AND i.concept_class_id = 'Ingredient'
),
productos_base AS (
    SELECT DISTINCT drug_concept_id FROM cdm.drug_exposure
),
a10b_prod AS (          -- 1 fila por (ingrediente A10B, producto de la base)
    SELECT g.concept_name AS ingrediente, p.drug_concept_id
    FROM a10b_ingr g
    JOIN cdm.concept_ancestor a ON a.ancestor_concept_id = g.concept_id
    JOIN productos_base p       ON p.drug_concept_id = a.descendant_concept_id
)
SELECT (SELECT count(*) FROM a10b_ingr)                 AS ingredientes,
       (SELECT count(DISTINCT drug_concept_id) FROM a10b_prod) AS productos_base,
       (SELECT count(DISTINCT de.person_id)
        FROM cdm.drug_exposure de
        WHERE de.drug_concept_id IN (SELECT drug_concept_id FROM a10b_prod))
                                                         AS pacientes,
       (SELECT string_agg(DISTINCT ingrediente, ', ') FROM a10b_prod)
                                                         AS ingredientes_en_base;

-- Actividad 3b. Productos de la base SIN ningún ancestro ATC.
-- Por qué: cualquier selección por clase ATC (A10B u otra) los pierde sin
-- avisar; el enunciado pide contarlos porque ese número es parte del
-- resultado. Patrón de «detectar ausencias» (paso 0a): se parte de lo que
-- debería estar (los productos de la base) y se pregunta con NOT EXISTS si
-- tienen ancestro ATC. NOT EXISTS no multiplica filas.
-- Las filas y pacientes de cada producto se agregan una sola vez (CTE
-- uso); el JOIN con concept no multiplica (concept_id es clave primaria).
-- Esperado: 22 de 365 productos = 19 vacunas CVX + 3 RxNorm (pancreatina,
-- levalbuterol inhalador, parche de etinilestradiol/norelgestromina).
-- En conjunto: 79,158 de 467,590 filas (16.9 %) y 5,896 pacientes
-- distintos; las 3 RxNorm suman solo 268 filas. Ninguno es antidiabético:
-- a la selección A10B no le quitan nada, pero a una clase de vacunas
-- (ATC J07) le quitarían todo.
WITH uso AS (
    SELECT drug_concept_id,
           count(*)                  AS filas,
           count(DISTINCT person_id) AS pacientes
    FROM cdm.drug_exposure
    GROUP BY drug_concept_id
),
sin_atc AS (
    SELECT u.*
    FROM uso u
    WHERE NOT EXISTS (
        SELECT 1
        FROM cdm.concept_ancestor a
        JOIN cdm.concept x ON x.concept_id = a.ancestor_concept_id
        WHERE a.descendant_concept_id = u.drug_concept_id
          AND x.vocabulary_id = 'ATC')
)
SELECT c.vocabulary_id, s.drug_concept_id, left(c.concept_name, 60) AS nombre,
       s.filas, s.pacientes,
       -- peso de cada producto sobre el total de drug_exposure
       round(100.0 * s.filas / (SELECT sum(filas) FROM uso), 2) AS pct_filas
FROM sin_atc s
JOIN cdm.concept c ON c.concept_id = s.drug_concept_id
ORDER BY c.vocabulary_id DESC, s.filas DESC;

-- Actividad 4a. «Exposición a metformina» en tres versiones (decisión 6).
--   A = descendientes estándar de metformina con UN solo ingrediente
--   B = todos los descendientes estándar (combinaciones incluidas)
--   C = B menos los que contienen un ingrediente de la clase ATC A10BK
--       (iSGLT2); exclusión por jerarquía, no por lista de nombres.
-- Solo standard_concept = 'S': los Dose Group ('C') no aparecen en
-- drug_exposure. El propio ingrediente entra (nivel 0, decisión 4).
-- Granularidad de cs: 1 fila por (versión, concept_id).
-- Esperado: A 83 / B 400 / C 249 conceptos; 231 pacientes en las tres.
WITH b AS (
    SELECT c.concept_id
    FROM cdm.concept_ancestor a
    JOIN cdm.concept c ON c.concept_id = a.descendant_concept_id
    WHERE a.ancestor_concept_id = 1503297          -- metformin (RxCUI 6809)
      AND c.standard_concept = 'S'
),
n_ingr AS (     -- cuántos ingredientes tiene cada concepto de B
    SELECT b.concept_id, count(*) AS n
    FROM b
    JOIN cdm.concept_ancestor a ON a.descendant_concept_id = b.concept_id
    JOIN cdm.concept i ON i.concept_id = a.ancestor_concept_id
    WHERE i.vocabulary_id = 'RxNorm' AND i.concept_class_id = 'Ingredient'
    GROUP BY b.concept_id
),
isglt2 AS (     -- conceptos con algún ingrediente de ATC A10BK
    SELECT DISTINCT a2.descendant_concept_id AS concept_id
    FROM cdm.concept atc
    JOIN cdm.concept_ancestor a1 ON a1.ancestor_concept_id = atc.concept_id
    JOIN cdm.concept i ON i.concept_id = a1.descendant_concept_id
                      AND i.vocabulary_id = 'RxNorm' AND i.concept_class_id = 'Ingredient'
    JOIN cdm.concept_ancestor a2 ON a2.ancestor_concept_id = i.concept_id
    WHERE atc.vocabulary_id = 'ATC' AND atc.concept_code = 'A10BK'
),
cs AS (
    SELECT 'A' AS version, concept_id FROM n_ingr WHERE n = 1
    UNION ALL SELECT 'B', concept_id FROM b
    UNION ALL SELECT 'C', concept_id FROM b
              WHERE concept_id NOT IN (SELECT concept_id FROM isglt2)
)
SELECT cs.version,
       count(*) AS conceptos,
       (SELECT count(DISTINCT de.person_id) FROM cdm.drug_exposure de
        WHERE de.drug_concept_id IN (SELECT concept_id FROM cs c2
                                     WHERE c2.version = cs.version)) AS pacientes
FROM cs
GROUP BY cs.version
ORDER BY cs.version;


-- =====================================================================
-- Actividad 5. Leer tres códigos LOINC: los seis ejes
-- =====================================================================
-- Actividad 5a. Tabla 3 × 6 (Component, Property, Time, System, Scale, Method).
-- En OMOP cada eje es un concepto aparte, unido al código por una relación
-- «Has …» en concept_relationship. Granularidad cruda: 1 fila por (código, eje);
-- el GROUP BY la colapsa a 1 fila por código (orden lógico: FROM/JOIN → WHERE
-- → GROUP BY → SELECT, así que los FILTER trabajan sobre cada grupo-código).
-- Method: 'Has method' existe en la base (143,014 filas) pero no para estos
-- tres → NULL real, no fallo de carga; LOINC lo deja vacío si no importa el método.
-- Esperado: 3 filas; Method = '(sin método)' en las tres.
SELECT c.concept_code AS loinc,
       max(e.concept_name) FILTER (WHERE cr.relationship_id = 'Has component')   AS component,
       max(e.concept_name) FILTER (WHERE cr.relationship_id = 'Has property')    AS property,
       max(e.concept_name) FILTER (WHERE cr.relationship_id = 'Has time aspect') AS time_aspect,
       max(e.concept_name) FILTER (WHERE cr.relationship_id = 'Has system')      AS system,
       max(e.concept_name) FILTER (WHERE cr.relationship_id = 'Has scale type')  AS scale,
       coalesce(max(e.concept_name) FILTER (WHERE cr.relationship_id = 'Has method'),
                '(sin método)')                                                  AS method
FROM cdm.concept c
JOIN cdm.concept_relationship cr ON cr.concept_id_1 = c.concept_id
                                AND cr.invalid_reason IS NULL      -- solo relaciones vigentes
JOIN cdm.concept e ON e.concept_id = cr.concept_id_2
WHERE c.vocabulary_id = 'LOINC'
  AND c.concept_code IN ('4548-4', '2160-0', '2345-7')
  AND cr.relationship_id LIKE 'Has %'
GROUP BY c.concept_code
ORDER BY c.concept_code;

-- Actividad 5a (verificación). Mismos FROM/JOIN/WHERE que 5a, pero contando
-- en vez de pivotar: si filas = ejes_distintos en cada código, ningún eje está
-- duplicado y el max() de 5a no esconde un segundo valor.
-- ROLLUP añade una fila de total (concept_code vacío).
-- Esperado: 5 | 5 en cada código y 15 en el total.
SELECT c.concept_code,
       count(*)                           AS filas,
       count(DISTINCT cr.relationship_id) AS ejes_distintos
FROM cdm.concept c
JOIN cdm.concept_relationship cr ON cr.concept_id_1 = c.concept_id
                                AND cr.invalid_reason IS NULL
JOIN cdm.concept e ON e.concept_id = cr.concept_id_2
WHERE c.vocabulary_id = 'LOINC'
  AND c.concept_code IN ('4548-4', '2160-0', '2345-7')
  AND cr.relationship_id LIKE 'Has %'
GROUP BY ROLLUP (c.concept_code)
ORDER BY c.concept_code;

-- Actividad 5b. La trampa del eje System: ¿la base mezcla sangre total con
-- suero/plasma para «el mismo» analito? Cuatro códigos: los dos de 5a y sus
-- gemelos de sangre total (2339-0 glucosa, 38483-4 creatinina).
-- Rendimiento: measurement se agrega UNA vez en la CTE med (un solo barrido
-- filtrado por IN) y luego se une a 4 filas; nada de subconsultas por código.
-- LEFT JOIN a med: si un código no tuviera mediciones, saldría con 0, no desaparecería.
-- Esperado: 4 filas; sangre 69,106 y suero/plasma 49,484 en ambos analitos.
WITH codigos AS (
    SELECT c.concept_id, c.concept_code, c.concept_name, s.concept_name AS system
    FROM cdm.concept c
    JOIN cdm.concept_relationship cr ON cr.concept_id_1 = c.concept_id
                                    AND cr.relationship_id = 'Has system'
                                    AND cr.invalid_reason IS NULL
    JOIN cdm.concept s ON s.concept_id = cr.concept_id_2
    WHERE c.vocabulary_id = 'LOINC'
      AND c.concept_code IN ('2345-7', '2339-0', '2160-0', '38483-4')
),
med AS (
    SELECT measurement_concept_id,
           count(*)                  AS mediciones,
           count(DISTINCT person_id) AS pacientes
    FROM cdm.measurement
    WHERE measurement_concept_id IN (SELECT concept_id FROM codigos)
    GROUP BY measurement_concept_id
)
SELECT k.concept_code AS loinc, k.system, k.concept_name,
       coalesce(m.mediciones, 0) AS mediciones,
       coalesce(m.pacientes, 0)  AS pacientes
FROM codigos k
LEFT JOIN med m ON m.measurement_concept_id = k.concept_id
ORDER BY k.concept_name ~* 'creatinine', k.system;   -- glucosa primero, luego creatinina

-- Actividad 5c. ¿Los cuatro códigos vienen en paneles? Granularidad de «dia»:
-- 1 fila por (persona, fecha) con al menos uno de los cuatro códigos; cada
-- columna cuenta cuántas veces aparece ese código ese día.
-- Si glucosa y creatinina de un mismo System siempre llevan el mismo número,
-- vienen juntas en un panel. Si un día tiene ambos System, hay doble panel.
-- Verificación: sum(mediciones) = 69,106·2 + 49,484·2 = 237,180.
WITH ids AS (
    SELECT concept_id, concept_code
    FROM cdm.concept
    WHERE vocabulary_id = 'LOINC'
      AND concept_code IN ('2345-7', '2339-0', '2160-0', '38483-4')
),
dia AS (
    SELECT m.person_id, m.measurement_date,
           count(*) FILTER (WHERE i.concept_code = '2339-0')  AS glu_sangre,
           count(*) FILTER (WHERE i.concept_code = '38483-4') AS cre_sangre,
           count(*) FILTER (WHERE i.concept_code = '2345-7')  AS glu_suero,
           count(*) FILTER (WHERE i.concept_code = '2160-0')  AS cre_suero
    FROM cdm.measurement m
    JOIN ids i ON i.concept_id = m.measurement_concept_id
    GROUP BY m.person_id, m.measurement_date
)
SELECT glu_sangre, cre_sangre, glu_suero, cre_suero,
       count(*)                                          AS persona_dias,
       sum(glu_sangre + cre_sangre + glu_suero + cre_suero) AS mediciones
FROM dia
GROUP BY glu_sangre, cre_sangre, glu_suero, cre_suero
ORDER BY persona_dias DESC;


-- =====================================================================
-- Actividad 6. Concept set de HbA1c
-- =====================================================================
-- Actividad 6a. Los 10 candidatos (Component «Hemoglobin A1c…») con la
-- decisión 8, cruzados con el vocabulario y con measurement.
-- Se parte de la lista (VALUES) y no de measurement: con LEFT JOIN, los
-- códigos sin mediciones salen con 0 en vez de desaparecer.
-- measurement se agrega UNA vez (CTE med) antes del JOIN → 1 fila por concepto,
-- así el JOIN no multiplica: 10 filas de lista → 10 filas de resultado.
-- Esperado: 10 filas, todas encontradas y estándar ('S'); solo 4548-4 con
-- mediciones (58,969 / 2,565 pac); 8 'incluir' y 2 'excluir'.
WITH candidatos (loinc, decision, conversion, motivo) AS (
    VALUES ('4548-4',  'incluir', NULL,              'HbA1c, cualquier método'),
           ('17856-6', 'incluir', NULL,              'por HPLC'),
           ('4549-2',  'incluir', NULL,              'por electroforesis'),
           ('62388-4', 'incluir', NULL,              'protocolo JDS/JSCC'),
           ('17855-8', 'incluir', NULL,              'calculada'),
           ('96595-4', 'incluir', NULL,              'gota de sangre seca (DBS)'),
           ('59261-8', 'incluir', '0.0915·x + 2.15', 'IFCC, mmol/mol'),
           ('71875-9', 'incluir', 'x · 100',         'fracción decimal'),
           ('86910-7', 'excluir', NULL,              'meta (goal), no es medición'),
           ('41995-2', 'excluir', NULL,              'masa/volumen, depende de la Hb total')
),
med AS (
    SELECT measurement_concept_id,
           count(*)                  AS mediciones,
           count(DISTINCT person_id) AS pacientes
    FROM cdm.measurement
    WHERE measurement_concept_id IN (
        SELECT concept_id FROM cdm.concept
        WHERE vocabulary_id = 'LOINC'
          AND concept_code IN (SELECT loinc FROM candidatos))
    GROUP BY measurement_concept_id
)
SELECT k.loinc, c.concept_id, c.standard_concept AS s, k.decision,
       k.conversion, k.motivo,
       coalesce(m.mediciones, 0) AS mediciones,
       coalesce(m.pacientes, 0)  AS pacientes
FROM candidatos k
LEFT JOIN cdm.concept c ON c.vocabulary_id = 'LOINC' AND c.concept_code = k.loinc
LEFT JOIN med m         ON m.measurement_concept_id = c.concept_id
ORDER BY k.decision DESC, mediciones DESC, k.loinc;
