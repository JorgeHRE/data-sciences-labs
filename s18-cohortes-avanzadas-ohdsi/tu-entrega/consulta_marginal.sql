-- Costo MARGINAL de cada criterio: cuántas personas más tendría la cohorte
-- final si ese criterio (y solo ese) se quitara de la definición. Se pega
-- después del bloque de banderas. Una fila por cohorte.
--   n_final    = cumplen los nueve criterios.
--   sin_<crit> = cumplen los OTROS ocho (da igual si cumplen <crit>).
-- Costo marginal de <crit> = sin_<crit> − n_final. No depende del orden: se
-- dejan todos los demás criterios y se quita uno. En la tabla de atrición, lo
-- que quita un criterio es MAYOR O IGUAL que su costo marginal (entre quienes
-- pasan los criterios anteriores hay más fallos que entre quienes pasan todos
-- los demás), y es IGUAL solo cuando ese criterio va ÚLTIMO.
-- Resultado (2026-11-15), 1701: n_final 122 · sin estudio 242 · sin visitas 255
--   · sin otro fármaco 171; 1702: 81 · 131 · 135 · 163.
SELECT cohort_definition_id AS cohorte,
       count(*) FILTER (WHERE f_estudio AND f_obs AND f_lavado AND f_adulto AND f_hta
                          AND f_visitas AND f_sin_demencia AND f_sin_otro AND f_sin_combo) AS n_final,
       count(*) FILTER (WHERE f_obs AND f_lavado AND f_adulto AND f_hta AND f_visitas
                          AND f_sin_demencia AND f_sin_otro AND f_sin_combo)               AS sin_estudio,
       count(*) FILTER (WHERE f_estudio AND f_lavado AND f_adulto AND f_hta AND f_visitas
                          AND f_sin_demencia AND f_sin_otro AND f_sin_combo)               AS sin_obs,
       count(*) FILTER (WHERE f_estudio AND f_obs AND f_adulto AND f_hta AND f_visitas
                          AND f_sin_demencia AND f_sin_otro AND f_sin_combo)               AS sin_lavado,
       count(*) FILTER (WHERE f_estudio AND f_obs AND f_lavado AND f_hta AND f_visitas
                          AND f_sin_demencia AND f_sin_otro AND f_sin_combo)               AS sin_adulto,
       count(*) FILTER (WHERE f_estudio AND f_obs AND f_lavado AND f_adulto AND f_visitas
                          AND f_sin_demencia AND f_sin_otro AND f_sin_combo)               AS sin_hta,
       count(*) FILTER (WHERE f_estudio AND f_obs AND f_lavado AND f_adulto AND f_hta
                          AND f_sin_demencia AND f_sin_otro AND f_sin_combo)               AS sin_visitas,
       count(*) FILTER (WHERE f_estudio AND f_obs AND f_lavado AND f_adulto AND f_hta
                          AND f_visitas AND f_sin_otro AND f_sin_combo)                    AS sin_demencia,
       count(*) FILTER (WHERE f_estudio AND f_obs AND f_lavado AND f_adulto AND f_hta
                          AND f_visitas AND f_sin_demencia AND f_sin_combo)                AS sin_otro,
       count(*) FILTER (WHERE f_estudio AND f_obs AND f_lavado AND f_adulto AND f_hta
                          AND f_visitas AND f_sin_demencia AND f_sin_otro)                 AS sin_combo
FROM banderas
GROUP BY cohort_definition_id
ORDER BY cohort_definition_id;
