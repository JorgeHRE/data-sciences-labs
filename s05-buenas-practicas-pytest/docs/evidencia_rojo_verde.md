# Evidencia del ciclo rojo → verde

Test afectado: `tests/test_clasificacion.py::test_clasificar_grupo_etario_caso_normal`
Función bajo prueba: `clasificar_grupo_etario` (`src/clinlab/clasificacion.py`)

Para generar esta evidencia, se introdujo un bug intencional en el límite
pediátrico/adulto (`< 18` cambiado por `< 19`) y se corrió la prueba antes
y después de revertirlo.

## 🔴 Rojo — con el bug intencional (`< 19` en vez de `< 18`)

```
tests/test_clasificacion.py::test_clasificar_grupo_etario_caso_normal FAILED [ 50%]
tests/test_clasificacion.py::test_clasificar_grupo_etario_edad_negativa_lanza_error PASSED [100%]

=================================== FAILURES ===================================
___________________ test_clasificar_grupo_etario_caso_normal ___________________

    def test_clasificar_grupo_etario_caso_normal():
        definir_edad = 18
        resultado = clasificar_grupo_etario(definir_edad)
>       assert resultado == "adulto"
E       AssertionError: assert 'pediátrico' == 'adulto'
E
E         - adulto
E         + pediátrico

tests/test_clasificacion.py:9: AssertionError
=========================== short test summary info ============================
FAILED tests/test_clasificacion.py::test_clasificar_grupo_etario_caso_normal - AssertionError: assert 'pediátrico' == 'adulto'
========================= 1 failed, 1 passed in 0.03s ==========================
```

## 🟢 Verde — con el límite corregido (`< 18`)

```
tests/test_clasificacion.py::test_clasificar_grupo_etario_caso_normal PASSED [ 50%]
tests/test_clasificacion.py::test_clasificar_grupo_etario_edad_negativa_lanza_error PASSED [100%]

============================== 2 passed in 0.01s ===============================
```

## Cómo reproducirlo (para capturas de pantalla propias)

1. Abrí `src/clinlab/clasificacion.py` y cambiá `if edad_anios < 18:` por
   `if edad_anios < 19:`.
2. Corré `pytest tests/test_clasificacion.py -v` — debería fallar
   `test_clasificar_grupo_etario_caso_normal`. Capturá esta pantalla (rojo).
3. Revertí el cambio (volvé a `< 18`).
4. Corré `pytest tests/test_clasificacion.py -v` de nuevo — ambos tests
   deberían pasar. Capturá esta pantalla (verde).

---

# Segundo ejemplo: `validate` en `unir_con_validacion`

Test afectado: `tests/test_union.py::test_unir_con_validacion_person_id_duplicado_lanza_error`
Función bajo prueba: `unir_con_validacion` (`src/clinlab/union.py`)

El test espera que un join contra una tabla de pacientes con `person_id`
duplicado lance `MergeError` (hallazgo del lab 2: el join multiplicaba filas
en silencio). Para comprobar que el test depende de verdad de esa protección,
se cambió el default `validate="m:1"` por `validate="m:m"` (que no exige
llaves únicas en ningún lado) y se corrió la prueba antes y después de
revertirlo.

## 🔴 Rojo — con el bug intencional (`validate="m:m"`)

```
tests/test_union.py::test_unir_con_validacion_person_id_duplicado_lanza_error FAILED [100%]

=================================== FAILURES ===================================
___________ test_unir_con_validacion_person_id_duplicado_lanza_error ___________
    ...
        # ACT + ASSERT
>       with pytest.raises(MergeError):
E       Failed: DID NOT RAISE MergeError

tests/test_union.py:23: Failed
=========================== short test summary info ============================
FAILED tests/test_union.py::test_unir_con_validacion_person_id_duplicado_lanza_error
============================== 1 failed in 0.03s ===============================
```

`pytest.raises` falla cuando el error esperado **no** llega: sin la
validación, el join multiplica las filas de `p1` sin avisar.

## 🟢 Verde — con el default corregido (`validate="m:1"`)

```
tests/test_union.py::test_unir_con_validacion_person_id_duplicado_lanza_error PASSED [100%]

============================== 1 passed in 0.01s ===============================
```

## Cómo reproducirlo

1. En `src/clinlab/union.py`, cambiá el default `validate: ... = "m:1"` por
   `= "m:m"`.
2. Corré `pytest tests/test_union.py -v` — debería fallar con
   `DID NOT RAISE MergeError` (rojo).
3. Revertí el cambio (volvé a `"m:1"`).
4. Corré `pytest tests/test_union.py -v` de nuevo — debería pasar (verde).

> ⚠️ Trampa encontrada al generar esta evidencia: si el cambio y la
> reversión ocurren dentro del mismo segundo y el archivo queda del mismo
> tamaño (`"m:1"` y `"m:m"` miden lo mismo), Python reutiliza el bytecode
> viejo de `src/clinlab/__pycache__/` y el test sigue rojo aunque el código
> ya esté corregido. Si pasa, borrá `src/clinlab/__pycache__/union.*.pyc`
> y volvé
> a correr.
