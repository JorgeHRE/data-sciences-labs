# Definición de la cohorte — Lab 17

**Pregunta:** en adultos con hipertensión que empiezan tratamiento con un solo antihipertensivo, ¿cómo es la incidencia de demencia en los nuevos usuarios de lisinopril (un IECA) comparados con los de amlodipino (un calcioantagonista)?

Este lab construye y describe las dos cohortes; con los casos disponibles en una base sintética no se estima un efecto.

## PICOT

| | |
|---|---|
| **Población** | Adultos (≥ 18 años en la fecha índice) con hipertensión diagnosticada que empiezan tratamiento antihipertensivo, y a quienes la base estaba observando el año anterior. |
| **Exposición** | Primera receta de **lisinopril** (cualquier producto que lo contenga), sin lisinopril en los 365 días previos. La fecha de esa receta es la **fecha índice**. |
| **Comparador** | Primera receta de **amlodipino**, con la misma definición. Quien empieza los dos fármacos a la vez no es usuario «de uno» y no entra en ninguna de las dos cohortes. |
| **Desenlace** | Primer diagnóstico de **demencia** (cualquier tipo) después de la fecha índice, en personas sin demencia antes de ella. |
| **Tiempo** | 365 días hacia atrás para comprobar observación, ausencia del fármaco y criterios; seguimiento desde la fecha índice mientras dure la exposición continua (huecos de hasta 30 días) y nunca más allá del fin de la observación. |

## Por qué estas ventanas

- **365 días de observación previa.** Hace falta un año de historia para afirmar que una receta es la *primera* y para ver los diagnósticos que definen la población. Con 180 días entrarían como «nuevos» quienes tienen recetas cada 6 meses o más, o interrumpieron medio año y volvieron: serían usuarios previos mal clasificados. Con 730 días se perdería a quien lleva poco tiempo en la base, sin ganar mucho, porque las recetas crónicas se renuevan varias veces al año.
- **365 días de lavado (sin el fármaco).** La misma ventana, por la misma razón: un año sin el fármaco hace improbable que la persona ya lo tomara. Es un filtro distinto de la observación: uno dice «la estábamos viendo»; el otro, «y no lo tomaba».
- **Hueco de 30 días para la exposición continua.** Las recetas de antihipertensivos suelen cubrir unos 30 días, y un retraso de días o semanas en renovar no significa que la persona dejó el fármaco. Con 0 días, cada pequeño retraso cortaría la exposición y el seguimiento sería artificialmente corto. Con 90 días, se contaría como «expuesto» a alguien que lleva casi tres meses sin tomarlo.
- **Fin de la observación como tope.** Después del fin del periodo de observación la base ya no registra nada: no se puede saber si la persona desarrolló demencia, así que el seguimiento se corta ahí.

> **Limitación conocida (controles 0a-0c):** el periodo de observación de esta base empieza en la primera visita y abarca décadas, pero antes de 2016 solo 1 de cada 4 personas «observadas» tiene alguna visita en el año. Para índices anteriores a 2016, el año de observación previa y el lavado son débiles. Cómo tratarlo se decide en la actividad 3.

## Los cuatro componentes

Valen igual para las dos cohortes: en la de amlodipino se intercambian los papeles de los dos fármacos. Las ventanas se escriben en días relativos a la fecha índice (día 0). Lo marcado *(provisional)* se confirma con datos en la actividad 5 y entonces se actualiza aquí.

### 1. Evento inicial
La primera receta del fármaco en toda la historia de la persona (cualquier producto que lo contenga). Su fecha es la fecha índice, y cada persona aparece una sola vez.

### 2. Criterios de inclusión
Antes de los criterios clínicos se aplican dos filtros, que se reportan por separado:
- **Observación previa:** el periodo de observación contiene la fecha índice y empieza al menos 365 días antes.
- **Lavado:** ninguna receta del fármaco en [−365, −1].

Criterios de inclusión, cada uno con su ventana:
- **Edad ≥ 18 años en la fecha índice.** El estudio es sobre adultos. Se comprueba aunque se espera que no quite a nadie (0 menores entre los nuevos usuarios de lisinopril).
- **Hipertensión diagnosticada** (*Hypertensive disorder* y descendientes) en (−∞, 0]. Es la indicación que hace comparables a los dos fármacos. La ventana es abierta hacia atrás porque la hipertensión es crónica y suele registrarse una sola vez, al diagnosticarse: limitada a [−365, 0], quedarían 388 de 1,522 *(provisional)*.
- **Al menos 2 visitas en [−365, −1].** Exige actividad real en el año previo, no solo un periodo de observación abierto (controles 0a-0c). Es el criterio de tipo «al menos N en la ventana W» *(provisional: el número y la ventana se deciden en las actividades 3 y 5)*.

Criterios de exclusión:
- **Demencia** (*Dementia* y descendientes) en (−∞, 0]. Sin ella, el desenlace no sería incidente: contaríamos demencias que ya existían.
- **Uso del otro fármaco** (amlodipino para la cohorte de lisinopril, y al revés) en (−∞, 0], incluido el mismo día 0. Quien empezó los dos a la vez, o ya tomaba el otro, no es nuevo usuario de uno solo. Caso borde *(provisional)*: 3 personas empiezan amlodipino con una combinación que contiene otro IECA u otro antihipertensivo.

### 3. Estrategia de salida
La persona sale de la cohorte cuando termina la exposición continua al fármaco del índice. Las recetas se unen en un tramo continuo si entre el fin de una y el inicio de la siguiente hay 30 días o menos. La fecha de salida es el fin del tramo que empieza en la fecha índice. *(Pendiente para la actividad 6: si al fin del tramo se suman 30 días de persistencia, y si empezar el otro fármaco después del índice también termina la permanencia.)*

### 4. Censura
El seguimiento nunca pasa del fin del periodo de observación de la persona: la fecha de salida es la menor entre el fin de la exposición continua y el fin de la observación. Después de esa fecha la base no registra eventos, así que una demencia posterior no se vería.
