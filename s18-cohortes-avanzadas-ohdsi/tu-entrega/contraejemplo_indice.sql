-- Lo que NO es reordenar: filtrar por fecha ANTES de tomar la primera receta.
-- Se pega después del bloque de banderas (usa su CTE `recetas`).
-- Reordenar criterios no cambia el índice; esto sí: se descartan las recetas
-- anteriores al inicio de estudio y la «primera» pasa a ser la primera de
-- 2017 en adelante. Cuenta las personas con alguna receta desde esa fecha.
-- Resultado (2026-11-15): 1,233 (1701) y 934 (1702), contra 346 y 238.
-- La diferencia (887 y 696) son usuarios previos que aparecerían como nuevos.
SELECT r.cohort_definition_id AS cohorte,
       count(DISTINCT r.person_id) AS con_receta_desde_inicio
FROM recetas r
JOIN results.cohorte_parametros p USING (cohort_definition_id)
WHERE r.inicio >= p.inicio_estudio
GROUP BY r.cohort_definition_id
ORDER BY r.cohort_definition_id;
