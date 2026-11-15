-- Tabla de atrición para el orden definido en el CTE `orden` (se concatena
-- después del bloque de banderas y de un archivo orden_*.sql).
-- Qué hace: para cada paso k cuenta las personas que cumplen TODAS las
-- banderas de los pasos 1..k (AND acumulado). Se expresa como «no existe un
-- paso o2 ≤ k cuya bandera sea falsa» (NOT EXISTS), que es lo mismo que el AND
-- de todas. to_jsonb(b) convierte la fila de banderas en JSON, y ->> nombre
-- lee la columna cuyo nombre viene de la lista `orden`: así el orden es un
-- dato (VALUES), no código.
-- Orden lógico: FROM banderas × orden → WHERE NOT EXISTS → GROUP BY → SELECT.
-- Trampa que evita: un paso donde no queda nadie no aparecería en un GROUP
-- BY; aquí no pasa (todos los pasos tienen sobrevivientes) y se comprueba
-- porque cada cohorte debe tener 10 filas (pasos 0-9).
, inicial AS (
    SELECT cohort_definition_id AS cohorte, count(*) AS n0
    FROM banderas GROUP BY cohort_definition_id
),
conteos AS (
    SELECT cohorte, 0 AS paso, 'primera receta (toda la historia)' AS criterio, n0 AS n
    FROM inicial
    UNION ALL
    SELECT b.cohort_definition_id, o.paso, o.criterio, count(*)
    FROM banderas b
    CROSS JOIN orden o
    WHERE NOT EXISTS (
        SELECT 1 FROM orden o2
        WHERE o2.paso <= o.paso
          AND NOT (to_jsonb(b) ->> o2.bandera)::boolean)
    GROUP BY b.cohort_definition_id, o.paso, o.criterio
)
-- Columnas: n = quedan; perdidos = N previo − n; pct_inicial = n / N del paso 0;
-- pct_perdida = perdidos / N previo (contra el paso anterior, no contra el inicial).
SELECT cohorte, paso, criterio, n,
       lag(n) OVER w - n                                          AS perdidos,
       round(100.0 * n / first_value(n) OVER w, 1)                AS pct_inicial,
       round(100.0 * (lag(n) OVER w - n) / lag(n) OVER w, 1)      AS pct_perdida
FROM conteos
WINDOW w AS (PARTITION BY cohorte ORDER BY paso)
ORDER BY cohorte, paso;
