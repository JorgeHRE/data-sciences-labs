-- Orden B (actividad 3, decisión 8): igual que orden_lab17.sql pero con DOS
-- criterios intercambiados: «sin otro fármaco» pasa al paso 6 y «≥ 2 visitas»
-- al paso 8. Los demás pasos no se mueven. Se usa igual que orden_lab17.sql:
--   cat <(sed -n '/^-- \[INICIO banderas\]/,/^-- \[FIN banderas\]/p' atricion.sql) \
--       orden_b.sql consulta_atricion.sql | psql ...
, orden(paso, criterio, bandera) AS (
    VALUES (1, 'índice desde 2017-01-01',            'f_estudio'),
           (2, '+ 365 d de observación previa',      'f_obs'),
           (3, '+ lavado de 365 d',                  'f_lavado'),
           (4, '+ edad ≥ 18',                        'f_adulto'),
           (5, '+ hipertensión (−∞, 0]',             'f_hta'),
           (6, '− otro fármaco previo',              'f_sin_otro'),
           (7, '− demencia previa',                  'f_sin_demencia'),
           (8, '+ ≥ 2 visitas en [−365, −1]',        'f_visitas'),
           (9, '− combinación en el índice',         'f_sin_combo')
)
