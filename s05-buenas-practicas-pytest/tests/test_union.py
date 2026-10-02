import pandas as pd
import pytest
from pandas.errors import MergeError

from clinlab.union import unir_con_validacion


def test_unir_con_validacion_person_id_duplicado_lanza_error(df_pacientes_malicioso):
    # Hallazgo lab 2: person_id duplicado en la tabla de pacientes; un join
    # sin validar multiplicaría las filas de ese paciente en silencio.

    # ARRANGE: tabla de encuentros (lado "muchos", va a la IZQUIERDA).
    # Que p1 tenga dos visitas es normal y NO debe causar error: lo que
    # queremos atrapar es el duplicado en la tabla de pacientes.
    df_encuentros = pd.DataFrame(
        {
            "person_id": ["p1", "p1", "p2"],
            "visita_id": ["v1", "v2", "v3"],
        }
    )

    # La fixture hace de tabla de pacientes (lado "uno", va a la DERECHA).
    # Trae p1 repetido, así que viola la regla "m:1" (derecha única).

    # ACT + ASSERT
    with pytest.raises(MergeError):
        unir_con_validacion(
            df_encuentros,
            df_pacientes_malicioso,
            llave_izquierda="person_id",
            llave_derecha="person_id",
            # how y validate se quedan con sus defaults ("left" y "m:1"): así
            # probamos que la protección viene activada sin tener que pedirla.
        )


def test_unir_con_validacion_tablas_limpias_une_correctamente():
    # Hueco detectado por cobertura (paso 8): union.py línea 56 (el return)
    # nunca se ejecutaba; solo estaba probado el camino del MergeError.

    # ARRANGE: tablas chicas y limpias, creadas aquí (no usamos la fixture
    # porque trae p1 duplicado y el join tronaría).
    # Encuentros (IZQUIERDA, lado "muchos"): p1 tiene dos visitas, lo normal.
    df_encuentros = pd.DataFrame(
        {
            "person_id": ["p1", "p1", "p2"],
            "visita_id": ["v1", "v2", "v3"],
        }
    )
    # Pacientes (DERECHA, lado "uno"): cada person_id una sola vez.
    # p3 existe pero no tiene visitas: sirve para pensar qué hace un
    # left join con los pacientes que no aparecen a la izquierda.
    df_pacientes = pd.DataFrame(
        {
            "person_id": ["p1", "p2", "p3"],
            "edad_anios": [30, 15, 40],
        }
    )

    # ACT: mismos defaults que en producción (how="left", validate="m:1").
    resultado = unir_con_validacion(
        df_encuentros,
        df_pacientes,
        llave_izquierda="person_id",
        llave_derecha="person_id",
    )

    # ASSERT propiedad 2 (columnas): el resultado trae columnas de AMBAS
    # tablas. Como las dos llaves se llaman igual, pandas deja una sola
    # columna person_id (no person_id_x / person_id_y).
    assert list(resultado.columns) == ["person_id", "visita_id", "edad_anios"]

    # ASSERT propiedad 1 (número de filas)
    assert len(resultado) == 3

    # ASSERT propiedad 3 (emparejamiento)
    assert resultado["edad_anios"].tolist() == [30, 30, 15]
