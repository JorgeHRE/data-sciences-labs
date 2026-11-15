-- Control (actividad 5): ¿cómo termina observation_period? La regla de censura
-- de la base. Solo lectura; corre sola:
--   docker exec -i lab12-omop-db-1 psql -U $POSTGRES_USER -d $POSTGRES_DB < control_fin_observacion.sql
-- Pregunta: el efecto de borde de 2026 (la tasa con observation_period se
-- dispara) ¿viene de que el año está incompleto o de dónde termina el periodo
-- de cada persona? Las personas-año se miden en días, así que un año
-- incompleto por sí solo no infla la tasa: lo que la infla es que el periodo
-- termine ANTES de la fecha de corte.
-- Qué mide (una fila):
--   fin_igual_ultima_visita = personas cuyo periodo termina el día de su última visita
--                             (se toma el mayor entre inicio y fin de cada visita)
--   fin_posterior/anterior  = termina después / antes de la última visita
--   op_termina_antes_2026   = personas sin ningún día observado en 2026
--   op_llega_a_2026         = personas con algún día observado en 2026
--   op_en_fecha_de_corte    = personas observadas hasta el último día de los datos
-- LEFT JOIN con las visitas: una persona sin visitas saldría con NULL; se cuenta
-- aparte (sin_visitas) para que no desaparezca (resultado: 0).
-- Resultado (2026-11-15), 1 fila (fecha de corte = 2026-10-26):
--   personas 5,904 · fin_igual_ultima_visita 5,789 (98.1 %) · fin_posterior 115
--   · fin_anterior 0 · sin_visitas 0 · op_termina_antes_2026 1,518
--   · op_llega_a_2026 4,386 · op_en_fecha_de_corte 58
WITH ult AS (
    SELECT person_id,
           max(greatest(visit_start_date, coalesce(visit_end_date, visit_start_date))) AS ult_visita
    FROM cdm.visit_occurrence
    GROUP BY person_id
)
SELECT count(*)                                                                      AS personas,
       count(*) FILTER (WHERE op.observation_period_end_date = u.ult_visita)         AS fin_igual_ultima_visita,
       count(*) FILTER (WHERE op.observation_period_end_date > u.ult_visita)         AS fin_posterior,
       count(*) FILTER (WHERE op.observation_period_end_date < u.ult_visita)         AS fin_anterior,
       count(*) FILTER (WHERE u.person_id IS NULL)                                   AS sin_visitas,
       count(*) FILTER (WHERE op.observation_period_end_date < DATE '2026-01-01')    AS op_termina_antes_2026,
       count(*) FILTER (WHERE op.observation_period_end_date >= DATE '2026-01-01')   AS op_llega_a_2026,
       count(*) FILTER (WHERE op.observation_period_end_date =
                              (SELECT max(observation_period_end_date) FROM cdm.observation_period)) AS op_en_fecha_de_corte
FROM cdm.observation_period op
LEFT JOIN ult u USING (person_id);

-- Control 2. La otra parte de la regla: las defunciones. cdm.death tiene 829
-- filas y el periodo de observación termina el día de la muerte en 825. Entre
-- las 1,518 personas cuyo periodo termina antes de 2026, separa las que
-- murieron de las que no (LEFT JOIN: quien no tiene fila en death queda con NULL).
-- Resultado (2026-11-15), 1 fila: 1,518 · con muerte 805 · sin muerte con
-- última visita en 2025: 541 · sin muerte con última visita antes de 2025: 172.
SELECT count(*)                                                                    AS op_termina_antes_2026,
       count(*) FILTER (WHERE d.person_id IS NOT NULL)                             AS de_ellas_con_muerte,
       count(*) FILTER (WHERE d.person_id IS NULL
                          AND op.observation_period_end_date >= DATE '2025-01-01') AS sin_muerte_ultima_visita_2025,
       count(*) FILTER (WHERE d.person_id IS NULL
                          AND op.observation_period_end_date <  DATE '2025-01-01') AS sin_muerte_ultima_visita_antes_2025
FROM cdm.observation_period op
LEFT JOIN cdm.death d USING (person_id)
WHERE op.observation_period_end_date < DATE '2026-01-01';

-- Control 3. Las 115 personas cuyo periodo termina DESPUÉS de su última visita
-- (de 1 a 343 días). Ninguna tiene muerte registrada. En 64 el fin coincide con
-- el fin de su última receta y en 15 con su último diagnóstico o visita; el
-- resto (al menos 36, porque las dos categorías podrían solaparse) no se investigó. Es decir: el periodo termina en el último
-- registro de la persona, que casi siempre es una visita.
-- Resultado (2026-11-15), 1 fila: 115 · con muerte 0 · fin = fin de la última receta 64
--   · fin = último diagnóstico o visita 15 · entre 1 y 343 días después.
WITH ult AS (
    SELECT person_id, max(greatest(visit_start_date, coalesce(visit_end_date, visit_start_date))) AS ult_visita
    FROM cdm.visit_occurrence GROUP BY person_id
),
fin AS (
    SELECT op.person_id, op.observation_period_end_date AS fin_op, u.ult_visita,
           (SELECT max(drug_exposure_end_date) FROM cdm.drug_exposure d WHERE d.person_id = op.person_id) AS ult_fin_receta,
           (SELECT max(coalesce(condition_end_date, condition_start_date))
            FROM cdm.condition_occurrence c WHERE c.person_id = op.person_id) AS ult_cond,
           (SELECT death_date FROM cdm.death x WHERE x.person_id = op.person_id) AS muerte
    FROM cdm.observation_period op
    JOIN ult u USING (person_id)
)
SELECT count(*)                                                        AS fin_posterior_a_ult_visita,
       count(*) FILTER (WHERE muerte IS NOT NULL)                      AS con_muerte,
       count(*) FILTER (WHERE fin_op = ult_fin_receta)                 AS fin_igual_fin_ultima_receta,
       count(*) FILTER (WHERE fin_op = greatest(ult_cond, ult_visita)) AS fin_igual_ultima_condicion_o_visita,
       min(fin_op - ult_visita)                                        AS min_dias_despues,
       max(fin_op - ult_visita)                                        AS max_dias_despues
FROM fin
WHERE fin_op > ult_visita;
