-- Impacto, en la cohorte final 1701, de las diferencias de código entre el SQL
-- que genera CIRCE (ATLAS) y el del lab 17 (actividad 8). Se pega después del
-- bloque de banderas de atricion.sql (mismo uso que huerfanos_pa.sql). Una fila.
--   final                      = personas de la cohorte final (todas las banderas)
--   A_dx_hta_antes_del_periodo = de ellas, con algún diagnóstico de hipertensión
--                                (hasta el índice) ANTES del inicio de su periodo de
--                                observación: CIRCE no lo contaría (ventanas recortadas)
--   A_hta_solo_antes_del_periodo = las que cumplirían hipertensión SOLO por esos (cambiaría la cohorte)
--   B_primera_sin_365_previos  = personas cuya primera receta NO tiene 365 días de
--                                observación previa (CIRCE tomaría otra receta como índice)
--   B_dos_recetas_dia_indice   = personas con ≥ 2 recetas el día índice (empate; CIRCE desempata por event_id)
--   C_recetas_sin_fin          = recetas de lisinopril con drug_exposure_end_date nulo
--   C_recetas_fin_antes_inicio = recetas con fin anterior al inicio (CIRCE no las corrige; greatest(fin, inicio) sí)
--   E_conceptos_invalidos      = conceptos inválidos en los concept sets (CIRCE los excluye)
-- CTE dxh (no «hta»: ese nombre ya lo usa el bloque de banderas). Los JOIN a
-- observation_period son por persona (1 fila por persona, lab 17 control 0a).
-- Resultado (2026-11-15), 1 fila: 122 · 0 · 0 · 0 · 44 · 0 · 83 · 0
, fin AS (
    SELECT b.person_id, b.fecha_indice FROM banderas b
    WHERE b.cohort_definition_id = 1701 AND b.f_estudio AND b.f_obs AND b.f_lavado AND b.f_adulto
      AND b.f_hta AND b.f_visitas AND b.f_sin_demencia AND b.f_sin_otro AND b.f_sin_combo
),
dxh AS (
    SELECT f.person_id,
           count(*) FILTER (WHERE co.condition_start_date <  op.observation_period_start_date) AS antes,
           count(*) FILTER (WHERE co.condition_start_date >= op.observation_period_start_date) AS dentro
    FROM fin f
    JOIN cdm.observation_period op ON op.person_id = f.person_id
    JOIN cdm.condition_occurrence co ON co.person_id = f.person_id AND co.condition_start_date <= f.fecha_indice
    JOIN cdm.concept_ancestor ca ON ca.descendant_concept_id = co.condition_concept_id AND ca.ancestor_concept_id = 316866
    GROUP BY f.person_id
),
lis AS (   -- recetas de lisinopril (tipo receta), por persona y fecha
    SELECT d.person_id, d.drug_exposure_start_date AS fecha, count(*) AS n
    FROM cdm.drug_exposure d
    JOIN cdm.concept_ancestor ca ON ca.descendant_concept_id = d.drug_concept_id AND ca.ancestor_concept_id = 1308216
    WHERE d.drug_type_concept_id = 32838
    GROUP BY d.person_id, d.drug_exposure_start_date
)
SELECT
  (SELECT count(*) FROM fin)                                                      AS final,
  (SELECT count(*) FROM dxh WHERE antes > 0)                                      AS A_dx_hta_antes_del_periodo,
  (SELECT count(*) FROM dxh WHERE dentro = 0)                                     AS A_hta_solo_antes_del_periodo,
  (SELECT count(*) FROM banderas WHERE cohort_definition_id = 1701 AND NOT f_obs) AS B_primera_sin_365_previos,
  (SELECT count(*) FROM fin f JOIN lis l ON l.person_id = f.person_id AND l.fecha = f.fecha_indice WHERE l.n > 1) AS B_dos_recetas_dia_indice,
  (SELECT count(*) FROM cdm.drug_exposure d JOIN cdm.concept_ancestor ca ON ca.descendant_concept_id = d.drug_concept_id AND ca.ancestor_concept_id = 1308216
    WHERE d.drug_exposure_end_date IS NULL)                                       AS C_recetas_sin_fin,
  (SELECT count(*) FROM cdm.drug_exposure d JOIN cdm.concept_ancestor ca ON ca.descendant_concept_id = d.drug_concept_id AND ca.ancestor_concept_id = 1308216
    WHERE d.drug_exposure_end_date < d.drug_exposure_start_date)                  AS C_recetas_fin_antes_inicio,
  (SELECT count(*) FROM cdm.concept_ancestor ca JOIN cdm.concept c ON c.concept_id = ca.descendant_concept_id
    WHERE ca.ancestor_concept_id IN (1308216, 1332418, 316866, 4182210, 9201, 9202, 9203)
      AND c.invalid_reason IS NOT NULL)                                           AS E_conceptos_invalidos;
