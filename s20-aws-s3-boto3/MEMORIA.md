# MEMORIA — Lab 20 (estado del proyecto)

> El Constructor actualiza este archivo tras cada trozo verificado (2-3 líneas:
> qué se completó, resultado clave, siguiente punto de `SPECS.md`).

## 2026-11-16 — Fase 0/1 (Arquitecto)
- Generados `GUIA_ESTUDIO.md` y `SPECS.md`. Revisado el enunciado, los
  entregables del lab 19 y los datos Synthea locales (4.3 GB, sin modificar).
- 9 decisiones pendientes (D1-D9) marcadas en `SPECS.md` §2; ninguna resuelta.
- Protocolo ajustado (rama s20/ajustes-protocolo): Fase 4 de corrección y reauditoría, escalado de decisiones al Arquitecto, evidencia obligatoria (SPECS §6), un dueño por tipo de información, regla de datos remitida a D1.
- Plan aprobado por el usuario; SPECS, MEMORIA y AGENTS versionados (PR #142).
- D1 decidida (B: 15 tablas clínicas de Synthea, 1.41 GiB; minimización de datos). Registrada en SPECS §2 y tu-entrega/DECISIONES.md.
- D2 decidida (B: CLI, bucket `omop-tesis-jhr-2026` en us-east-2).
- D3 decidida (`observations` particionada por `anio=`; filtros por fecha).
- D4 (A: excepciones propias, 403 ≠ no existe) y D5 (B: perfil + cliente cacheado) decididas.
- D6 decidida (D: moto + Stubber para AccessDenied + integración marcada, sin subida masiva).
- D7 (A: `tmp/paginacion/` + expiración) y D8 (R1+R2+R3 sin `raw/`, R4 documentada) decididas.
- D9 decidida (política solo-HTTPS en el paso 11). **D1-D9 cerradas.**
- **Siguiente:** Fase 2 (Constructor), `SPECS.md` Paso 0, desde `main` tras mergear el PR del protocolo y las decisiones.
