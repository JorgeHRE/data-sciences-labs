# Lab 11 — Analítica longitudinal con SQL avanzado

Consultas con CTEs y funciones de ventana sobre la base clínica sintética (Synthea) del lab 10.
Todo el análisis está en `analitica_longitudinal.sql` (cada actividad con su pregunta, decisiones
declaradas y resultados medidos) y la evidencia gráfica en `analitica_longitudinal.ipynb`.

## Datos

`../../s10-sql-fundamentals/tu-entrega/clinica.duckdb` (DuckDB, solo lectura): `patients` 5,904 ·
`encounters` 429,640 · `conditions` 235,504 · `medications` 388,658 · `observations` 5,719,327.
La base no se sube a git; se genera con `carga.py` del lab 10. Son datos sintéticos: ningún resultado
describe pacientes reales.

## Cómo ejecutar

Desde `s11-sql-avanzado/tu-entrega/`, con el entorno del lab 10 (DuckDB, pandas, matplotlib, Jupyter):

```bash
PY=../../s10-sql-fundamentals/tu-entrega/.venv/bin
$PY/jupyter nbconvert --to notebook --execute --inplace analitica_longitudinal.ipynb
```

El notebook lee las consultas del `.sql`, las ejecuta y verifica con `assert` las cifras de abajo. Para
correr una consulta suelta: `duckdb.connect(ruta, read_only=True)`.

## Actividades

| # | Pregunta | Resultado medido |
|---|----------|------------------|
| 1 | ¿Se pueden reescribir con CTEs las consultas 6.12 y 6.11 del lab 10 sin cambiar el resultado? | 6.12: 0 filas (diabéticos sin HbA1c). 6.11: 309 pacientes con diabetes e hipertensión (69.59 % de los diabéticos, 5.23 % de la población). `EXCEPT` en ambas direcciones: 0 filas. Sin ganancia de velocidad demostrada. |
| 2 | ¿Se puede depurar la CTE más larga bloque por bloque? | Bloques de la Prueba B de la 6.11, cada uno con predicción y conteo real. Falló la predicción de hipertensos (esperaba 1,200–1,400; hay 2,145, prevalencia acumulada de por vida). |
| 3 | Primera y última visita por paciente (`GROUP BY` frente a ventanas) | 5,904 pacientes, 429,640 visitas en ambos caminos; se prefiere `GROUP BY` por simplicidad. |
| 4 | Días entre visitas consecutivas (`LAG`) | Mediana 12 días; 5,904 `NULL` (una primera visita por paciente); 17,820 ceros. Con un día por paciente: mediana 14. |
| 5 | Readmisión a 30 días | 1,171 readmisiones sobre 7,660 altas elegibles = 15.29 %, en 336 pacientes. Con `< 30`: 13.08 %; sin contar el mismo día: 12.04 %. |
| 6 | Episodios de tratamiento (gaps and islands), gaps de 30, 60 y 90 días | Epoetina alfa: 785 / 369 / 319 episodios. Lisinopril (contraste): 1,432 en los tres gaps. |
| 7 | Última observación por (paciente, analito) con `ROW_NUMBER` | 5,719,327 → 384,983 filas; `QUALIFY` da lo mismo. 870 pares con empate en su última fecha, 746 con valores distintos. |
| 8 | Media acumulada frente a media móvil de 3 (HbA1c) | Un paciente de 12 mediciones; la móvil sigue la caída a 5.8 y la acumulada reacciona más lento. |
| 9 | HbA1c más cercana al primer diagnóstico de diabetes tipo 2 (±90 días) | Política A (sin posteriores): 103 de 444 pacientes. Política B (con posteriores): 139, es decir 36 valores posteriores al índice. |
| 10 | Ventana contra self-join (`EXPLAIN ANALYZE`) | Mismo resultado. Ventana ~0.025 s, self-join ~0.23 s (unas 9 veces más); el self-join materializa 54.8 M de pares. |

## Decisiones declaradas

- **Readmisión (5):** cuentan todas las readmisiones, no solo la primera por paciente; el día 30 entra;
  un ingreso el mismo día del alta cuenta (puede ser un traslado); se excluyen los 89 ingresos solapados
  y las altas de pacientes fallecidos (118) del numerador y del denominador.
- **Episodios (6):** el fin acumulado máximo de las recetas previas (no `LAG`) para absorber solapes; un
  episodio nuevo empieza si el hueco es mayor que el gap (con 30, un hueco de exactamente 30 días no corta);
  una receta sin `stop` se trata como activa hasta el corte de los datos (2026-10-26) y el episodio se marca
  `censurado`.
- **Deduplicar (7):** el analito es el `code` (19 códigos tienen dos descripciones); desempate por fecha, valor
  numérico antes que texto, y luego `encounter` y `value`, que solo sirven para que sea reproducible.
- **Frames (8):** el acumulado usa el frame por defecto a propósito (el enunciado lo pide) y se compara con
  `ROWS` declarado; la media móvil usa `ROWS BETWEEN 2 PRECEDING AND CURRENT ROW`.
- **Valores posteriores (9):** no se permiten (política A). Un valor medido después del índice ya refleja el
  diagnóstico y el tratamiento, es fuga de información. B se calcula solo como contraste.
- **Rendimiento (10):** `EXPLAIN ANALYZE` con 1 corrida de calentamiento descartada y 5 medidas; se reporta
  la mediana. El tiempo comparable es el `Total Time`; los milisegundos por operador son CPU sumada entre hilos.

## Hallazgos que cambiaron el plan

- **Lisinopril no sirve para comparar gaps (6):** todos los fármacos crónicos orales dan 1 episodio por
  paciente en cualquier gap, porque se prescriben de forma continua y las recetas largas cubren los huecos.
  Solo los intermitentes (Epoetina, cisplatino, paclitaxel) varían, por eso Epoetina es el fármaco principal.
- **Paciente de la actividad 8:** la regla "12 mediciones sin empates" eligió a uno con las 12 mediciones en
  7.0, y las tres columnas salían idénticas. Se añadió el requisito de al menos 4 valores distintos.
- **Actividad 9:** la HbA1c del día 0 es la única "previa" de los 103 pacientes con valor; ninguno tiene una
  estrictamente anterior.

## Limitaciones

- Datos sintéticos de Synthea; la prevalencia, las recetas continuas y los patrones de visita reflejan el
  simulador, no la práctica clínica real.
- Día 0 como previo (9): no se puede saber el orden dentro del mismo día; con la versión estricta (`días < 0`)
  salen 0 pacientes.
- Los desempates de la actividad 7 (`encounter`, `value`) son reproducibles pero no clínicos.
- Los tiempos de la actividad 10 son de DuckDB local (16 hilos) con la base en disco; no se extrapolan a otros
  motores. Entre corridas varían unos milisegundos y la razón ventana/self-join entre 8.6 y 9.2.

## Revisión de los criterios de evaluación

| Criterio | Estado | Dónde / excepciones |
|----------|--------|---------------------|
| Consultas con CTEs de nombre descriptivo | Cumple, con excepciones declaradas | Las consultas originales del lab 10 (actividad 1) se conservan anidadas a propósito, para compararlas con su reescritura. Las comparaciones `EXCEPT` entre dos CTEs se escriben en línea. Los alias de una letra (`a`, `b`) solo son alias de tabla en joins, no CTEs. |
| Cada consulta con su pregunta clínica | Cumple | Cabecera de cada actividad más comentario en cada consulta de apoyo (control, contraste, resumen). |
| Readmisión con criterios explícitos | Cumple | Actividad 5: ventana de 30 días con el día 30 incluido, todas las readmisiones, mismo día cuenta, solapes y fallecidos excluidos. |
| Episodios bien construidos y tres gaps | Cumple | Actividad 6: fin acumulado máximo; gaps 30, 60 y 90; control independiente con `NOT EXISTS`. |
| Frame de cada ventana declarado | Cumple | Toda función con `ORDER BY` lleva `ROWS` o `RANGE` explícito, incluidos `FIRST_VALUE` (actividad 3) y el acumulado de la actividad 8 (`RANGE ... CURRENT ROW`, el mismo que el por defecto, ahora declarado). `LAG`, `LEAD` y `ROW_NUMBER` no usan frame; `COUNT(*) OVER (PARTITION BY ...)` sin `ORDER BY` abarca toda la partición. |
| Por qué `rn = 1` va fuera de la CTE | Cumple | Actividad 7: el orden lógico FROM → WHERE → ventanas → SELECT. |
| Política sobre valores posteriores | Cumple | Actividad 9: política A (sin posteriores), B como contraste, y la limitación del día 0. |
| Ventana contra self-join con planes y tiempos | Cumple | Actividad 10: tabla de tiempos en el `.sql`; planes reales y corridas en el notebook. |

Los ajustes de la revisión final (frames declarados, subconsultas convertidas en CTEs, nombres descriptivos)
no cambian ningún resultado: las 36 sentencias del `.sql` devuelven las mismas filas, con el mismo contenido,
antes y después, y el notebook sigue pasando sus `assert`.
