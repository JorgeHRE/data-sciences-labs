# Actividad 1 — RxCUI del ingrediente en RxNav

**Fecha de consulta:** 2026-11-11 (RxNav, versión vigente de RxNorm ese día).

| Fármaco | RxCUI | TTY | SCDF (formas clínicas) | BN (marcas) |
|---|---|---|---|---|
| metformina | 6809 | IN | 21 | 14 |
| lisinopril | 29046 | IN | 3 | 4 |
| empagliflozina | 1545653 | IN | 5 | 4 |

**Método.** El RxCUI y el TTY se tomaron de la web de RxNav, eligiendo el término con `TTY = IN` (no el PIN con la sal, como «metformin hydrochloride», ni las combinaciones MIN). La vista principal de la web no muestra una caja de SCDF, así que los conteos de SCDF y BN se tomaron de la API oficial de RxNav, que es la misma fuente:

```
https://rxnav.nlm.nih.gov/REST/rxcui/<RxCUI>/related.json?tty=SCDF+BN
```

## Cuánto de cada conteo son combinaciones

| Fármaco | SCDF de un solo ingrediente | SCDF combinadas | BN de un solo ingrediente | BN combinadas |
|---|---|---|---|---|
| metformina | 3 | 18 | 3 (Glucophage, Glumetza, Riomet) | 11 |
| lisinopril | 2 | 1 (con hidroclorotiazida) | 3 (Prinivil, Zestril, Qbrelis) | 1 (Zestoretic) |
| empagliflozina | 1 | 4 (con metformina y/o linagliptina) | 1 (Jardiance) | 3 (Glyxambi, Synjardy, Trijardy) |

Las SCDF combinadas se distinguen por el « / » del nombre. Las marcas no lo dicen; su reparto se hizo con conocimiento de cada producto y se verificó después contra la base (ver la comparación).

## Lo que muestra la tabla

- **El peso de las combinaciones depende del fármaco:** son 18 de 21 formas en metformina, 4 de 5 en empagliflozina y 1 de 3 en lisinopril. La decisión de la actividad 4 (incluir o no las combinaciones) cambia mucho el concept set de metformina y poco el de lisinopril.
- **Una combinación pertenece a todos sus ingredientes:** Synjardy y Trijardy aparecen en las listas de metformina y de empagliflozina. Si se estudian las dos como exposiciones distintas, el mismo paciente cuenta como expuesto a ambas.
- **7 de las 18 combinaciones de metformina llevan un iSGLT2** (canagliflozina 2, dapagliflozina 1, empagliflozina 3, ertugliflozina 1), fármacos con efecto protector del riñón. Esto es relevante para la pregunta de función renal de la actividad 4.

## Comparación con nuestra base (RxNorm 20260601)

Consulta: `actividades.sql`, actividad 1b. Formato: total (un solo ingrediente / combinaciones).

| Fármaco | SCDF RxNav | SCDF base | BN RxNav | BN base |
|---|---|---|---|---|
| metformina | 21 (3 / 18) | **26** (4 / 22) | 14 (3 / 11) | **23** (7 / 16) |
| lisinopril | 3 (2 / 1) | 3 (2 / 1) | 4 (3 / 1) | **8** (4 / 4) |
| empagliflozina | 5 (1 / 4) | 5 (1 / 4) | 4 (1 / 3) | 4 (1 / 3) |

**Por qué la base tiene más.** RxNav solo devuelve los conceptos que RxNorm considera vigentes hoy. La base conserva también los que RxNorm marcó como *Obsolete*, es decir, productos retirados del mercado de EE. UU. Se comprobó en el historial de RxNorm (API `historystatus`): Fortamet (activo de 2005-09 a 2024-07), Avandamet (2005-04 a 2025-01), «metformin Extended Release Suspension» (2019-10 a 2026-07) y «chlorpropamide / metformin Oral Tablet» (2005-06 a 2005-07) figuran todos como *Obsolete*. Lo mismo las 4 marcas extra de lisinopril: Carace, Carace Plus y Prinize (retiradas en 2013-03) y Prinzide (2022-02). Glucophage figura como *Active*.

En OMOP esos conceptos siguen vigentes (`invalid_reason` NULL): un registro clínico de 2015 pudo dispensar Fortamet, y el concept set tiene que encontrarlo. **Para un estudio con datos históricos, la referencia correcta es el vocabulario de la base, no RxNav de hoy.**

El reparto entre un solo ingrediente y combinación que se hizo a mano para las marcas de RxNav queda confirmado por la base: empagliflozina coincide exactamente, y en metformina y lisinopril las marcas que se habían clasificado como de un solo ingrediente aparecen así también en la base.
