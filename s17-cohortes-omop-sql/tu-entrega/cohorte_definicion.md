# Definición de la cohorte — Lab 17

**Pregunta:** en adultos con hipertensión que empiezan tratamiento con un solo antihipertensivo, ¿cómo es la incidencia de demencia en los nuevos usuarios de lisinopril (un IECA) comparados con los de amlodipino (un calcioantagonista)?

Este lab construye y describe las dos cohortes; con los casos disponibles en una base sintética no se estima un efecto. Con la definición principal (índice desde 2017) quedan 3 y 2 demencias incidentes antes de los demás criterios: el desenlace queda definido, pero esta base no permite estudiarlo (actividad 3, decisión 9).

## PICOT

| | |
|---|---|
| **Población** | Adultos (≥ 18 años en la fecha índice) con hipertensión diagnosticada que empiezan tratamiento antihipertensivo, y a quienes la base estaba observando el año anterior. |
| **Exposición** | Primera receta de **lisinopril** (cualquier producto que lo contenga), sin lisinopril en los 365 días previos. La fecha de esa receta es la **fecha índice**. |
| **Comparador** | Primera receta de **amlodipino**, con la misma definición. Quien empieza los dos fármacos a la vez no es usuario «de uno» y no entra en ninguna de las dos cohortes. |
| **Desenlace** | Primer diagnóstico de **demencia** (cualquier tipo) después de la fecha índice, en personas sin demencia antes de ella. |
| **Tiempo** | Fecha índice desde el **2017-01-01** (periodo de estudio); 365 días hacia atrás para comprobar observación, ausencia del fármaco y criterios; seguimiento desde la fecha índice mientras dure la exposición continua (huecos de hasta 30 días) y nunca más allá del fin de la observación. |

## Por qué estas ventanas

- **365 días de observación previa.** Hace falta un año de historia para afirmar que una receta es la *primera* y para ver los diagnósticos que definen la población. Con 180 días entrarían como «nuevos» quienes tienen recetas cada 6 meses o más, o interrumpieron medio año y volvieron: serían usuarios previos mal clasificados. Con 730 días se perdería a quien lleva poco tiempo en la base, sin ganar mucho, porque las recetas crónicas se renuevan varias veces al año.
- **365 días de lavado (sin el fármaco).** La misma ventana, por la misma razón: un año sin el fármaco hace improbable que la persona ya lo tomara. Es un filtro distinto de la observación: uno dice «la estábamos viendo»; el otro, «y no lo tomaba».
- **Hueco de 30 días para la exposición continua.** Las recetas de antihipertensivos suelen cubrir unos 30 días, y un retraso de días o semanas en renovar no significa que la persona dejó el fármaco. Con 0 días, cada pequeño retraso cortaría la exposición y el seguimiento sería artificialmente corto. Con 90 días, se contaría como «expuesto» a alguien que lleva casi tres meses sin tomarlo.
- **Inicio del estudio en 2017-01-01.** La base registra con detalle desde 2016-2017: antes de 2016 solo 1 de cada 4 personas «observadas» tiene alguna visita en el año (control 0c), y las primeras recetas hacen un pico en 2015-2016 (665 de lisinopril y 545 de amlodipino en 2016) que no es una epidemia: son personas que ya tomaban el fármaco y aparecen como nuevas cuando empieza el registro detallado. Con índices desde 2017, el año previo cae en 2016 o después, cuando ya hay datos. Con inicio en 2016, el año previo caería en 2015 (57 % con visitas) y entraría el pico; con inicio en 2018 se perderían más personas sin ganar calidad (desde 2017 ≥ 94 % tienen visitas).
- **Fin de la observación como tope.** Después del fin del periodo de observación la base ya no registra nada: no se puede saber si la persona desarrolló demencia, así que el seguimiento se corta ahí.

> **Limitación de la base y cómo se trató (controles 0a-0c, decisión 9):** el periodo de observación empieza en la primera visita y abarca décadas (mediana 31.6 años), así que exigir 365 días de observación previa no quita a nadie y no corrige el pico de 2016. Por eso se añade el inicio del estudio en 2017-01-01. Como análisis de sensibilidad se construyen las mismas cohortes sin esa fecha (1711 lisinopril, 1712 amlodipino) para mostrar cuánto pesa el pico; no son resultados.

## Los cuatro componentes

Valen igual para las dos cohortes: en la de amlodipino se intercambian los papeles de los dos fármacos. Las ventanas se escriben en días relativos a la fecha índice (día 0). Los criterios clínicos de la actividad 5 ya están medidos (decisiones 11 y 12). Lo que sigue provisional se marca así y se confirma en la actividad 6.

### 1. Evento inicial
La primera receta del fármaco en toda la historia de la persona (cualquier producto que lo contenga). Su fecha es la fecha índice, y cada persona aparece una sola vez.

### 2. Criterios de inclusión
Antes de los criterios clínicos se aplican tres filtros, que se reportan por separado:
- **Periodo de estudio:** la fecha índice (la primera receta de toda la historia) es el 2017-01-01 o posterior. Se aplica después de buscar la primera receta, no antes: quien empezó en 2015 y tiene otra receta en 2018 no es nuevo usuario en 2018.
- **Observación previa:** el periodo de observación contiene la fecha índice y empieza al menos 365 días antes.
- **Lavado:** ninguna exposición al fármaco en [−365, −1]: ninguna receta que empezara antes del índice y siguiera activa (fin ≥ índice − 365) dentro de la ventana. Mirar solo la fecha de inicio dejaría pasar a quien tiene una receta antigua que dura años. Como el índice es la primera receta de toda la historia, este filtro quita 0 por construcción; se escribe igual para que la definición lo diga (decisión 10).

Criterios de inclusión, cada uno con su ventana:
- **Edad ≥ 18 años en la fecha índice.** El estudio es sobre adultos. Se comprueba aunque se espera que no quite a nadie (0 menores entre los nuevos usuarios de lisinopril).
- **Hipertensión diagnosticada** (*Hypertensive disorder* y descendientes) en (−∞, 0]. Es la indicación que hace comparables a los dos fármacos. La ventana es abierta hacia atrás porque la hipertensión es crónica y suele registrarse una sola vez, al diagnosticarse: limitada a [−365, 0], quedarían 388 de 1,522 en la versión sin inicio de estudio (con el inicio en 2017 las dos ventanas casi coinciden: quitan 26 y 36 de 346). El criterio quita 26 de 346 (lisinopril) y 1 de 238 (amlodipino). La HTA se registra una sola vez por persona (339 de 346 tienen menos de 2 registros), así que no sirve para un criterio «al menos N».
- **Al menos 2 visitas en [−365, −1].** Exige actividad real en el año previo, no solo un periodo de observación abierto (controles 0a-0c). Es el criterio de tipo «al menos N en la ventana W»; no se resuelve con `EXISTS` porque hay que contar (JOIN + `GROUP BY` + `HAVING count(*) >= 2`). N = 2 porque una sola visita puede ser la del propio diagnóstico y 2 exige continuidad; la ventana termina en −1 porque el día 0 es la visita donde se receta, no evidencia de contacto previo. Es el criterio más costoso: quita 147 de 320 (46 %) en lisinopril y 72 de 237 (30 %) en amlodipino; con N = 1 quitaría 80 y 35, con N = 3 más de la mitad (decisión 11).

Criterios de exclusión:
- **Demencia** (*Dementia* y descendientes) en (−∞, 0]. Sin ella, el desenlace no sería incidente: contaríamos demencias que ya existían.
- **Uso del otro fármaco** (amlodipino para la cohorte de lisinopril, y al revés) en (−∞, 0], incluido el mismo día 0. Quien empezó los dos a la vez, o ya tomaba el otro, no es nuevo usuario de uno solo. 
- **Combinación en el día índice.** El producto del índice tiene más de un ingrediente (lisinopril/HCTZ, amlodipino/benazepril, Tribenzor): inicia dos clases a la vez aunque la otra no sea el comparador. Se excluye (decisión 12). En las cohortes principales quita 0, porque las dos personas que sobrevivían hasta ahí ya tomaban el otro fármaco y salen por el criterio anterior; en la sensibilidad quita 4.

### 3. Estrategia de salida
La persona sale de la cohorte cuando termina la exposición continua al fármaco del índice. Las recetas se unen en un tramo continuo si entre el fin de una y el inicio de la siguiente hay 30 días o menos (se usa el fin más tardío de todas las recetas anteriores, no solo el de la inmediata, para que un solape no parta un tramo; un hueco de exactamente 30 días no corta). El tramo de interés es el que empieza en la fecha índice; si la persona vuelve tras un hueco mayor, ese tramo posterior no cuenta. A su fin se suman **30 días de persistencia** (decisión 13): la última receta puede haberse agotado sin que la persona haya dejado el fármaco, y así quien tiene una receta de 0 días (fin = inicio, «en curso» del ETL: 12 y 5 personas) no sale el mismo día del índice. Además, la persona sale el día en que **empieza el otro fármaco** después del índice (decisión 14): ya no es usuaria de uno solo y el desenlace no se atribuiría a un fármaco.

### 4. Censura
El seguimiento nunca pasa del fin del periodo de observación de la persona: la fecha de salida es la **menor** entre las tres fechas (fin del tramo + 30 días, inicio del otro fármaco, fin de la observación). Después de esa fecha la base no registra eventos, así que una demencia posterior no se vería.

## Resultado de la actividad 5 (inclusión y exclusión)

Cada criterio lee solo del anterior, así que el reparto de la pérdida depende del orden (la cohorte final no). Cifras de la definición principal, lisinopril / amlodipino:

| Criterio | Tipo y ventana | Quedan | Pierde en secuencia | Pierde solo |
|---|---|---|---|---|
| (tras el lavado) | | 346 / 238 | | |
| Edad ≥ 18 | inclusión, en el índice | 346 / 238 | 0 / 0 | 0 / 0 |
| Hipertensión | inclusión, (−∞, 0] | 320 / 237 | 26 / 1 | 26 / 1 |
| ≥ 2 visitas | inclusión, [−365, −1], N = 2 | 173 / 165 | 147 / 72 | 147 / 72 |
| Demencia previa | exclusión, (−∞, 0] | 172 / 164 | 1 / 1 | 4 / 1 |
| Otro fármaco | exclusión, (−∞, 0] | 122 / 81 | 50 / 83 | 63 / 102 |
| Combinación en el índice | exclusión, día 0 | 122 / 81 | 0 / 0 | |

Cohorte tras la actividad 5: **122 de lisinopril y 81 de amlodipino**. La salida (actividad 6) todavía no se aplica.

## Resultado de la actividad 6 (salida)

Duración del seguimiento en días desde la fecha índice, por motivo de salida (definición principal; el detalle está en `distribucion_salida.sql`):

| Cohorte | Motivo | Personas | Mediana | Cuartiles |
|---|---|---|---|---|
| Lisinopril | fin de observación | 61 | 1,853 | 1,127 – 2,597 |
| | fin de exposición + 30 d | 21 | 1,143 | 30 – 2,256 |
| | otro fármaco | 40 | 30 | 30 – 60 |
| | **todos** | **122** | **928** | 30 – 1,869 |
| Amlodipino | fin de observación | 36 | 1,476 | 723 – 2,123 |
| | fin de exposición + 30 d | 19 | 1,484 | 202 – 2,226 |
| | otro fármaco | 26 | 30 | 30 – 30 |
| | **todos** | **81** | **401** | 30 – 1,514 |

Validaciones: 0 salidas antes del índice y 0 después del fin de la observación. La mediana sin el corte por otro fármaco (1,514 y 1,484 días) coincide con una consulta de islas escrita aparte.

Lo que más pesa es el otro fármaco: el 33 % y el 32 % salen por empezarlo, con una mediana de exactamente 30 días (el añadido en la primera renovación). Esas 66 personas aportan 98 días o menos de seguimiento. Solo el 57 % y el 56 % superan un año. Para un desenlace como la demencia, de aparición lenta, eso limita lo que esta base puede decir (decisión 14).

## Resultado de la actividad 7 (results.cohort)

Las cohortes están en `results.cohort` (cuatro columnas estándar de OMOP; `subject_id` = persona, `cohort_start_date` = fecha índice, `cohort_end_date` = fecha de salida, inclusiva): 1701 lisinopril (122), 1702 amlodipino (81) y, como sensibilidad, 1711 (242) y 1712 (131); 576 filas. Se carga con `./insertar_cohorte.sh` (borra y vuelve a insertar solo las cohortes de este lab dentro de una transacción). Verificado: ninguna fila con fin anterior al inicio, ninguna fecha fuera del periodo de observación y el inicio coincide con la primera receta recalculada (controles 7a-7c); la tabla rechaza duplicados y fines anteriores al inicio (decisiones 15 y 16).

## Resultado de la actividad 8 (atrición)

La tabla completa y el análisis están en [atricion.md](atricion.md). Resumen de la definición principal (lisinopril / amlodipino): 1,522 / 1,104 personas con evento inicial → 346 / 238 con índice desde 2017 → 173 / 165 tras la inclusión → **122 / 81** tras la exclusión (8.0 % y 7.3 %). Costó más el inicio de estudio (77 %), y entre los criterios clínicos, las visitas en lisinopril y el otro fármaco en amlodipino. En esas cohortes no hay demencias incidentes en el seguimiento (0 en 373 y 216 años-persona), así que esta base no permite estudiar el desenlace.

## Resultado de la actividad 9 (caracterización)

La tabla 1 y la figura del seguimiento están en [caracterizacion.md](caracterizacion.md). Cohortes jóvenes (mediana de 40 y 44 años), mujeres alrededor del 58 %, seguimiento mediano de 2.5 y 1.1 años (42 % y 41 % salen en los primeros 6 meses). 8 de 17 filas tienen |SMD| > 0.1, pero con 122 y 81 personas el SMD es ruidoso (error típico ≈ 0.14). La ventana de 365 días subestima las enfermedades crónicas (decisión 18).

## Resultado de la actividad 10 (immortal time)

**Pregunta:** ¿algún criterio usa información posterior a la fecha índice para decidir quién entra, o para clasificar su exposición?

**Respuesta: no.** Revisé cada ventana del SQL (comprobaciones en `inmortal_time.sql`):

| Criterio | Ventana | ¿Mira después del índice? |
|---|---|---|
| Índice = 1.ª receta de toda la historia; inicio de estudio 2017 | pasado / calendario | No |
| Observación previa y lavado | [−365, −1] | No |
| Edad ≥ 18 | en el índice | No |
| HTA, demencia previa, otro fármaco | (−∞, 0] | No (incluyen el día 0, ver abajo) |
| ≥ 2 visitas | [−365, −1] | No (el día 0 queda fuera a propósito) |
| Combinación en el índice | día 0 | No |
| Salida: tramo, +30 d, corte por otro fármaco | posterior | Sí, pero es la **salida**, no la entrada ni la exposición |

Por qué no hay immortal time: la exposición se asigna en el índice (la persona entra en la cohorte del fármaco que recibe ese día) y el seguimiento empieza ese mismo día, así que no existe un periodo entre el inicio de la cohorte y el de la exposición durante el cual no pueda ocurrir el desenlace. No se clasifica a nadie por su exposición posterior («usuarios persistentes», «≥ 2 recetas»), que es la forma típica de crear immortal time. Comprobado con datos: el `JOIN` de la salida con el tramo del índice no pierde a nadie (122 / 81 / 242 / 131 antes y después) y la duración mínima del seguimiento es de 1 día (lisinopril) y 7 días (amlodipino).

**Lo que sí hay que decir (el día 0).** 73 de 122 (60 %) en lisinopril y 43 de 81 (53 %) en amlodipino cumplen el criterio de HTA **solo** por un diagnóstico registrado el propio día índice. No es información posterior, pero el ETL no dice si el diagnóstico se anotó antes o después de la receta. Si el diagnóstico se hizo *a raíz* de empezar el fármaco, esa parte de la inclusión dependería de algo que ocurre tras la decisión de tratar. Para demencia no ocurre (0 casos solo del día 0; las exclusiones son 1 / 1). Se mantiene (−∞, 0] porque la HTA del día 0 es la indicación de la receta y no su consecuencia, y la ventana no pasa del día 0; queda como limitación (decisión 20).

**Otra cosa que no es immortal time pero sí usa el futuro:** el corte de la salida cuando empieza el otro fármaco (actividad 6) es censura informativa, no tiempo inmortal. Cambia a quién se sigue, no cuándo empieza el riesgo (decisión 14).
