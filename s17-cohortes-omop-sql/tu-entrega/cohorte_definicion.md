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

Valen igual para las dos cohortes: en la de amlodipino se intercambian los papeles de los dos fármacos. Las ventanas se escriben en días relativos a la fecha índice (día 0). Lo marcado *(provisional)* se confirma con datos en la actividad 5 y entonces se actualiza aquí.

### 1. Evento inicial
La primera receta del fármaco en toda la historia de la persona (cualquier producto que lo contenga). Su fecha es la fecha índice, y cada persona aparece una sola vez.

### 2. Criterios de inclusión
Antes de los criterios clínicos se aplican tres filtros, que se reportan por separado:
- **Periodo de estudio:** la fecha índice (la primera receta de toda la historia) es el 2017-01-01 o posterior. Se aplica después de buscar la primera receta, no antes: quien empezó en 2015 y tiene otra receta en 2018 no es nuevo usuario en 2018.
- **Observación previa:** el periodo de observación contiene la fecha índice y empieza al menos 365 días antes.
- **Lavado:** ninguna exposición al fármaco en [−365, −1]: ninguna receta que empezara antes del índice y siguiera activa (fin ≥ índice − 365) dentro de la ventana. Mirar solo la fecha de inicio dejaría pasar a quien tiene una receta antigua que dura años. Como el índice es la primera receta de toda la historia, este filtro quita 0 por construcción; se escribe igual para que la definición lo diga (decisión 10).

Criterios de inclusión, cada uno con su ventana:
- **Edad ≥ 18 años en la fecha índice.** El estudio es sobre adultos. Se comprueba aunque se espera que no quite a nadie (0 menores entre los nuevos usuarios de lisinopril).
- **Hipertensión diagnosticada** (*Hypertensive disorder* y descendientes) en (−∞, 0]. Es la indicación que hace comparables a los dos fármacos. La ventana es abierta hacia atrás porque la hipertensión es crónica y suele registrarse una sola vez, al diagnosticarse: limitada a [−365, 0], quedarían 388 de 1,522 *(provisional)*.
- **Al menos 2 visitas en [−365, −1].** Exige actividad real en el año previo, no solo un periodo de observación abierto (controles 0a-0c). Es el criterio de tipo «al menos N en la ventana W» *(provisional: el número y la ventana se deciden en la actividad 5; con el inicio del estudio en 2017, el pico ya no depende de este criterio)*.

Criterios de exclusión:
- **Demencia** (*Dementia* y descendientes) en (−∞, 0]. Sin ella, el desenlace no sería incidente: contaríamos demencias que ya existían.
- **Uso del otro fármaco** (amlodipino para la cohorte de lisinopril, y al revés) en (−∞, 0], incluido el mismo día 0. Quien empezó los dos a la vez, o ya tomaba el otro, no es nuevo usuario de uno solo. Caso borde *(provisional)*: 3 personas empiezan amlodipino con una combinación que contiene otro IECA u otro antihipertensivo.

### 3. Estrategia de salida
La persona sale de la cohorte cuando termina la exposición continua al fármaco del índice. Las recetas se unen en un tramo continuo si entre el fin de una y el inicio de la siguiente hay 30 días o menos. La fecha de salida es el fin del tramo que empieza en la fecha índice. *(Pendiente para la actividad 6: si al fin del tramo se suman 30 días de persistencia, y si empezar el otro fármaco después del índice también termina la permanencia.)*

### 4. Censura
El seguimiento nunca pasa del fin del periodo de observación de la persona: la fecha de salida es la menor entre el fin de la exposición continua y el fin de la observación. Después de esa fecha la base no registra eventos, así que una demencia posterior no se vería.
