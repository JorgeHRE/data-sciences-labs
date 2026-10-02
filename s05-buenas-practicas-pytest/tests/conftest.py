import pandas as pd
import pytest


@pytest.fixture
def df_pacientes_malicioso() -> pd.DataFrame:
    """
    DataFrame chico y malicioso: 8 filas que cubren, entre todas, los
    hallazgos de calidad de datos encontrados en el lab 2.

    Fila (person_id) -> hallazgo que cubre:
    - p1 (fila 1)  -> caso normal (adulto)
    - p2           -> menor de edad
    - p3           -> columna con NaN (hba1c)
    - p1 (fila 4)  -> person_id duplicado (repite el de la fila 1)
    - p5           -> fecha de visita anterior al nacimiento
    - p6           -> valor centinela: edad 180
    - p7           -> valor centinela: hba1c 0
    - p8           -> caso normal (adulto mayor)

    Columnas:
    - person_id : str
    - edad_anios : float
    - fecha_nacimiento : str (formato 'YYYY-MM-DD', sin parsear todavía)
    - fecha_visita : str (formato 'YYYY-MM-DD', sin parsear todavía)
    - hba1c : float, hemoglobina glicosilada en % (puede ser NaN)
    """
    return pd.DataFrame(
        {
            "person_id": ["p1", "p2", "p3", "p1", "p5", "p6", "p7", "p8"],
            "edad_anios": [30, 15, 40, 30, 25, 180, 50, 70],
            "fecha_nacimiento": [
                "1990-01-01",
                "2005-05-05",
                "1980-12-12",
                "1990-01-01",
                "2000-01-01",
                "1840-01-01",
                "1970-01-01",
                "1950-01-01",
            ],
            "fecha_visita": [
                "2020-01-01",
                "2020-01-01",
                "2020-01-01",
                "2020-01-01",
                "1999-12-31",
                "2020-01-01",
                "2020-01-01",
                "2020-01-01",
            ],
            "hba1c": [7.0, 5.0, None, 6.0, 6.0, 5.5, 0.0, 6.5],
        }
    )
