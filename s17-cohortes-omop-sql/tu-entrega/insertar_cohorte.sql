-- =====================================================================
-- Actividad 7. Insertar las cohortes en results.cohort.
-- ESTO ES UNA PLANTILLA, no corre sola: la línea «-- {{CADENA}}» se
-- reemplaza por la cadena de CTE de cohorte_definicion.sql (desde
-- [INICIO cohorte] hasta [CONTEO]). Así la lógica de la cohorte vive en un
-- solo lugar y no hay dos copias que puedan divergir (decisión 15).
-- Se ejecuta con:   ./insertar_cohorte.sh
-- =====================================================================
BEGIN;

-- Las cuatro columnas estándar de OMOP (misma estructura que la cdm.cohort
-- vacía del CDM). cdm es de solo lectura en este lab; por eso va en results.
--   PRIMARY KEY: una persona entra UNA vez por cohorte con una fecha de
--     inicio; un duplicado haría fallar el INSERT en vez de inflar conteos.
--   CHECK: la base misma rechaza una fila con fin anterior al inicio.
-- cohort_end_date es INCLUSIVA (convención OMOP): una persona con inicio =
-- fin está un día en la cohorte.
CREATE TABLE IF NOT EXISTS results.cohort (
    cohort_definition_id integer NOT NULL,
    subject_id           integer NOT NULL,   -- = person_id
    cohort_start_date    date    NOT NULL,   -- = fecha índice
    cohort_end_date      date    NOT NULL,   -- = fecha de salida (actividad 6)
    PRIMARY KEY (cohort_definition_id, subject_id, cohort_start_date),
    CHECK (cohort_end_date >= cohort_start_date)
);

-- Re-ejecutable: borra SOLO las cohortes de este lab (las de
-- cohorte_parametros) y las vuelve a insertar, todo dentro de la misma
-- transacción. Si algo falla, el ROLLBACK deja la tabla como estaba. Un
-- ON CONFLICT no sirve aquí: no borraría a quien dejó de cumplir la definición.
DELETE FROM results.cohort
WHERE cohort_definition_id IN (SELECT cohort_definition_id
                               FROM results.cohorte_parametros);

INSERT INTO results.cohort
       (cohort_definition_id, subject_id, cohort_start_date, cohort_end_date)
-- {{CADENA}}
-- Una fila por persona y cohorte (salida, actividad 6). Solo se pasan las
-- cuatro columnas del estándar; el motivo de salida queda fuera de la tabla.
SELECT cohort_definition_id, person_id, fecha_indice, fecha_salida
FROM salida_motivo
ORDER BY cohort_definition_id, person_id;

COMMIT;
