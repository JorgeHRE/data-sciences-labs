-- Cuántas personas FALLAN cada criterio, mirado por separado (sin importar el
-- orden), sobre las 1,522 / 1,104 con primera receta. Se pega después del
-- bloque de banderas. Una fila por cohorte; cada columna cuenta f_x = false.
-- Es la otra cara de la atrición: en secuencia un criterio solo quita a quien
-- los anteriores no habían quitado; aquí se cuenta todo lo que quitaría solo.
-- Las filas con NULL no existen: las banderas son true/false explícitos.
SELECT cohort_definition_id AS cohorte,
       count(*) AS inicial,
       count(*) FILTER (WHERE NOT f_estudio)       AS estudio,
       count(*) FILTER (WHERE NOT f_obs)           AS obs,
       count(*) FILTER (WHERE NOT f_lavado)        AS lavado,
       count(*) FILTER (WHERE NOT f_adulto)        AS adulto,
       count(*) FILTER (WHERE NOT f_hta)           AS hta,
       count(*) FILTER (WHERE NOT f_visitas)       AS visitas,
       count(*) FILTER (WHERE NOT f_sin_demencia)  AS demencia,
       count(*) FILTER (WHERE NOT f_sin_otro)      AS otro,
       count(*) FILTER (WHERE NOT f_sin_combo)     AS combo
FROM banderas
GROUP BY cohort_definition_id
ORDER BY cohort_definition_id;
