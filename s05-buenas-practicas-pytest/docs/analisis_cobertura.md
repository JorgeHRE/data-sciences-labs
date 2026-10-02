# Análisis de cobertura (paso 8)

Configuración en `pyproject.toml`:
`addopts = "--cov=clinlab --cov-report=term-missing --cov-fail-under=80"`.
Para reproducirlo basta con correr `pytest` desde la raíz del repo.

## Los tres renglones

1. **Qué encontró la cobertura:** la primera medición dio 86 % y mostró
   cuatro huecos reales: las ramas "pediátrico" y "adulto mayor" de
   `clasificar_grupo_etario`, `contar_duplicados` sin ningún test, el
   `return` de `unir_con_validacion` (solo estaba probado el camino del
   `MergeError`, nunca un join exitoso) y las validaciones de entrada de
   `calcular_egfr_ckd_epi`. Los cuatro se cubrieron con tests de límites y
   de contrato, y la cobertura llegó a 100 %.
2. **Qué sigue sin probar aunque diga 100 %:** `calcular_egfr_ckd_epi`
   acepta edades de 0 a 17 años sin avisar, aunque CKD-EPI 2021 está
   validada en adultos; y `marcar_valores_implausibles` trata un `NaN` como
   plausible (devuelve `False`). Ninguna línea queda sin ejecutar, pero son
   decisiones de diseño que la cobertura no puede evaluar.
3. **Por qué 100 % no es garantía:** la cobertura mide qué líneas se
   ejecutaron, no qué se verificó. En este lab lo vimos dos veces: un test
   sin `assert` pasaba en verde y ya "cubría" la función, y la cobertura
   marcó 100 % mientras un test estaba en rojo. Lo que da confianza son los
   casos límite y los contratos que prueban los tests, no el porcentaje.

## Evolución

| Paso | Test agregado | Cobertura total |
|---|---|---|
| Medición inicial | — | 86 % |
| Join exitoso | `test_unir_con_validacion_tablas_limpias_une_correctamente` | 88 % |
| Límites de edad | `test_clasificar_grupo_etario_limites` | 92 % |
| Contrato de duplicados | `test_contar_duplicados` | 94 % |
| Entradas inválidas de eGFR | `test_calcular_egfr_ckd_epi_entrada_invalida_lanza_error` | 100 % |
