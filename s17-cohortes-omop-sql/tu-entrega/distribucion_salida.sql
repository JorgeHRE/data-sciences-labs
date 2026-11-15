-- =====================================================================
-- Actividad 6. Distribución de la duración y validación de la salida.
-- No corre solo: lee los CTE de cohorte_definicion.sql (los del bloque,
-- hasta el marcador [CONTEO]) y añade UN SELECT. Un WITH vale para una sola
-- sentencia, por eso es un único SELECT. Se corre así:
--   sed -n '/^-- \[INICIO cohorte\]/,/^-- \[CONTEO\]/p' cohorte_definicion.sql \
--     | cat - distribucion_salida.sql \
--     | docker exec -i lab12-omop-db-1 psql -U omop -d omop_lab12
-- Una fila por cohorte y motivo de salida, más una fila «todos» por cohorte
-- (GROUP BY ROLLUP: el nivel «todos» es la fila con motivo NULL).
-- Duración = fecha_salida − fecha_indice, en días (resta de date = entero).
-- percentile_cont(0.5) = mediana; 0.25 y 0.75 = cuartiles.
-- Las dos columnas «mal_*» deben ser 0: salida antes del índice, o salida
-- después del fin del periodo de observación (trampa del enunciado).
-- =====================================================================
SELECT cohort_definition_id AS cohorte,
       coalesce(motivo, '— todos —') AS motivo,
       count(*)                                          AS personas,
       count(*) FILTER (WHERE fecha_salida < fecha_indice) AS mal_antes_indice,
       count(*) FILTER (WHERE fecha_salida > op_fin)       AS mal_despues_op,
       min(fecha_salida - fecha_indice)                    AS dur_min,
       percentile_cont(0.25) WITHIN GROUP (ORDER BY fecha_salida - fecha_indice) AS q1,
       percentile_cont(0.5)  WITHIN GROUP (ORDER BY fecha_salida - fecha_indice) AS mediana,
       percentile_cont(0.75) WITHIN GROUP (ORDER BY fecha_salida - fecha_indice) AS q3,
       max(fecha_salida - fecha_indice)                    AS dur_max,
       count(*) FILTER (WHERE fecha_salida - fecha_indice <= 30)  AS hasta_30_d,
       count(*) FILTER (WHERE fecha_salida - fecha_indice > 365)  AS mas_de_1_anio
FROM salida_motivo
GROUP BY cohort_definition_id, ROLLUP (motivo)
ORDER BY cohort_definition_id, motivo NULLS LAST;
