# Registro de decisiones — Lab 12 (OMOP CDM)

Formato: qué se decidió, qué alternativas había y por qué se eligió esta.

## 1. Estructura del repo y archivos pesados
- **Decisión:** el `ENUNCIADO.md` y los vocabularios de ATHENA quedan fuera de git (`.gitignore`); `tu-entrega/` guarda solo código, documentación y resultados.
- **Alternativas:** subir los vocabularios (descartado: licencia no redistribuible y ~3 GB) o guardarlos dentro de `tu-entrega/` (descartado: se confunde con la entrega).
- **Por qué:** reproducibilidad vía comandos documentados, no vía datos subidos.

## 2. Orden de las actividades
- **Decisión:** vocabularios (act. 3) antes de la conversión (act. 2).
- **Alternativa:** seguir el orden numérico del enunciado.
- **Por qué:** el propio enunciado advierte que sin vocabularios todo mapea a `concept_id = 0`; convertir primero obligaría a repetir el ETL.
