-- Orden de los criterios del lab 17 (cohorte_definicion.sql, actividades 3-5).
-- Se pega justo después del bloque de banderas de atricion.sql:
--   cat <(sed -n '/^-- \[INICIO banderas\]/,/^-- \[FIN banderas\]/p' atricion.sql) \
--       orden_lab17.sql consulta_atricion.sql | psql ...
-- Cada fila: paso, nombre del criterio y la COLUMNA de banderas que lo evalúa.
-- Para reordenar basta cambiar el orden de las filas (columna paso); el SQL
-- de la consulta no cambia.
, orden(paso, criterio, bandera) AS (
    VALUES (1, 'índice desde 2017-01-01',            'f_estudio'),
           (2, '+ 365 d de observación previa',      'f_obs'),
           (3, '+ lavado de 365 d',                  'f_lavado'),
           (4, '+ edad ≥ 18',                        'f_adulto'),
           (5, '+ hipertensión (−∞, 0]',             'f_hta'),
           (6, '+ ≥ 2 visitas en [−365, −1]',        'f_visitas'),
           (7, '− demencia previa',                  'f_sin_demencia'),
           (8, '− otro fármaco previo',              'f_sin_otro'),
           (9, '− combinación en el índice',         'f_sin_combo')
)
