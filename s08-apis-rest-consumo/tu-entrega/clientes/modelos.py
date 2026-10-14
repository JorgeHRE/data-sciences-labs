"""Actividad 6: modelos de Pydantic para validar en la frontera.

Solo se modelan los campos que usarán las preguntas de la actividad 7; Pydantic
ignora el resto del JSON. Los campos imprescindibles son obligatorios y los
demás opcionales (los datos reales vienen incompletos: no es un error que a un
estudio le falte el número de inscritos, pero sí que le falte su identificador).

Tipos de regla que aparecen aquí:
  - de TIPO:      convertir texto a entero / fecha / año
  - de RANGO:     inscritos >= 0, edad entre 0 y 120 años
  - de CONJUNTO:  el estado del estudio debe ser uno de los oficiales
  - ENTRE CAMPOS: la fecha de fin no puede ser anterior a la de inicio
"""

import calendar
import re
from datetime import date
from enum import Enum

from pydantic import BaseModel, Field, field_validator, model_validator


def _sin_nulos(**campos) -> dict:
    """Quita los campos ausentes (None) para que, si faltan, Pydantic diga 'Field required'
    en vez de un confuso 'Input should be a valid string'."""
    return {k: v for k, v in campos.items() if v is not None}


# ---------------------------------------------------------------------------
# ClinicalTrials.gov
# ---------------------------------------------------------------------------
class EstadoEstudio(str, Enum):
    """Estados oficiales de ClinicalTrials.gov. Si la API añade uno nuevo, el
    registro se rechaza y aparece en el log: así nos enteramos del cambio."""
    ACTIVE_NOT_RECRUITING = "ACTIVE_NOT_RECRUITING"
    COMPLETED = "COMPLETED"
    ENROLLING_BY_INVITATION = "ENROLLING_BY_INVITATION"
    NOT_YET_RECRUITING = "NOT_YET_RECRUITING"
    RECRUITING = "RECRUITING"
    SUSPENDED = "SUSPENDED"
    TERMINATED = "TERMINATED"
    WITHDRAWN = "WITHDRAWN"
    AVAILABLE = "AVAILABLE"
    NO_LONGER_AVAILABLE = "NO_LONGER_AVAILABLE"
    TEMPORARILY_NOT_AVAILABLE = "TEMPORARILY_NOT_AVAILABLE"
    APPROVED_FOR_MARKETING = "APPROVED_FOR_MARKETING"
    WITHHELD = "WITHHELD"
    UNKNOWN = "UNKNOWN"


# La API da fechas completas ("2024-07-15") o solo con mes ("2024-07")
_FECHA_RE = re.compile(r"^(\d{4})-(\d{2})(?:-(\d{2}))?$")


def _partir_fecha(texto: str) -> tuple[date, bool]:
    """'2024-07' -> (2024-07-01, solo_mes=True). Lanza ValueError si no existe en el calendario."""
    anio, mes, dia = _FECHA_RE.match(texto).groups()
    return date(int(anio), int(mes), int(dia or 1)), dia is None


class EstudioCT(BaseModel):
    nct_id: str = Field(pattern=r"^NCT\d{8}$")
    titulo: str = Field(min_length=1)
    estado: EstadoEstudio
    inscritos: int | None = Field(default=None, ge=0)  # RANGO: nunca negativo
    inicio_txt: str | None = Field(default=None, pattern=_FECHA_RE.pattern)
    fin_txt: str | None = Field(default=None, pattern=_FECHA_RE.pattern)
    paises: list[str] = Field(default_factory=list)

    @field_validator("inicio_txt", "fin_txt")
    @classmethod
    def _fecha_existe(cls, v):
        if v is not None:
            _partir_fecha(v)  # lanza ValueError si, p. ej., el mes es 13
        return v

    @property
    def inicio(self) -> date | None:
        return _partir_fecha(self.inicio_txt)[0] if self.inicio_txt else None

    @property
    def fin(self) -> date | None:
        return _partir_fecha(self.fin_txt)[0] if self.fin_txt else None

    @model_validator(mode="after")
    def _fin_no_anterior_a_inicio(self):
        """ENTRE CAMPOS. Una fecha de fin con solo mes cuenta como el último día de ese mes,
        para no rechazar un estudio que empieza el 20 y termina 'ese mismo mes'."""
        if self.inicio_txt and self.fin_txt:
            ini = self.inicio
            fin, solo_mes = _partir_fecha(self.fin_txt)
            if solo_mes:
                fin = fin.replace(day=calendar.monthrange(fin.year, fin.month)[1])
            if fin < ini:
                raise ValueError(f"la fecha de fin ({self.fin_txt}) es anterior a la de inicio ({self.inicio_txt})")
        return self

    @classmethod
    def desde_crudo(cls, estudio: dict) -> "EstudioCT":
        """Extrae los campos del JSON anidado de la API y los valida."""
        p = estudio.get("protocolSection") or {}
        ident, estado = p.get("identificationModule") or {}, p.get("statusModule") or {}
        ubic = (p.get("contactsLocationsModule") or {}).get("locations") or []
        return cls(**_sin_nulos(
            nct_id=ident.get("nctId"),
            titulo=ident.get("briefTitle"),
            estado=estado.get("overallStatus"),
            inscritos=((p.get("designModule") or {}).get("enrollmentInfo") or {}).get("count"),
            inicio_txt=(estado.get("startDateStruct") or {}).get("date"),
            fin_txt=(estado.get("completionDateStruct") or {}).get("date"),
            paises=sorted({u["country"] for u in ubic if u.get("country")}),
        ))


# ---------------------------------------------------------------------------
# openFDA (eventos adversos)
# ---------------------------------------------------------------------------
# Códigos de la unidad de edad (patientonsetageunit) -> factor para pasar a años.
# Según la documentación de openFDA; en nuestros datos solo aparecen 800 y 801.
FACTOR_EDAD_A_ANIOS = {"800": 10, "801": 1, "802": 1 / 12, "803": 7 / 365.25, "804": 1 / 365.25, "805": 1 / 8766}


class ReporteFDA(BaseModel):
    id_reporte: str = Field(min_length=1)
    fecha_recepcion: date
    edad_anios: float | None = Field(default=None, ge=0, le=120)  # RANGO plausible
    reacciones: list[str] = Field(min_length=1)  # un reporte sin reacción no sirve

    @field_validator("fecha_recepcion", mode="before")
    @classmethod
    def _fecha_compacta(cls, v):
        """TIPO: 'YYYYMMDD' (texto) -> date."""
        if isinstance(v, str):
            if not re.fullmatch(r"\d{8}", v):
                raise ValueError(f"fecha con formato inesperado: {v!r} (se esperaba YYYYMMDD)")
            return date(int(v[:4]), int(v[4:6]), int(v[6:]))
        return v

    @field_validator("fecha_recepcion")
    @classmethod
    def _no_futura(cls, v):
        if v > date.today():
            raise ValueError(f"fecha de recepción en el futuro: {v}")
        return v

    @classmethod
    def desde_crudo(cls, reporte: dict) -> "ReporteFDA":
        paciente = reporte.get("patient") or {}
        edad = None
        if paciente.get("patientonsetage") is not None:
            unidad = str(paciente.get("patientonsetageunit"))
            if unidad not in FACTOR_EDAD_A_ANIOS:
                raise ValueError(f"unidad de edad desconocida: {unidad!r}")
            edad = float(paciente["patientonsetage"]) * FACTOR_EDAD_A_ANIOS[unidad]  # TIPO: texto -> años
        return cls(**_sin_nulos(
            id_reporte=reporte.get("safetyreportid"),
            fecha_recepcion=reporte.get("receivedate"),
            edad_anios=edad,
            reacciones=[x["reactionmeddrapt"] for x in paciente.get("reaction") or [] if x.get("reactionmeddrapt")],
        ))


# ---------------------------------------------------------------------------
# PubMed (esummary)
# ---------------------------------------------------------------------------
class ResumenPubMed(BaseModel):
    uid: str = Field(pattern=r"^\d+$")
    titulo: str = Field(min_length=1)
    anio: int

    @field_validator("anio")
    @classmethod
    def _anio_plausible(cls, v):
        """Se acepta hasta el año actual + 1: hay artículos en línea cuyo número impreso
        sale el año siguiente (p. ej. pubdate '2027 Feb 1' visto en octubre de 2026)."""
        if not 1800 <= v <= date.today().year + 1:
            raise ValueError(f"año de publicación fuera de rango: {v}")
        return v

    @classmethod
    def desde_crudo(cls, resumen: dict) -> "ResumenPubMed":
        m = re.match(r"(\d{4})", resumen.get("pubdate") or "")
        return cls(**_sin_nulos(uid=resumen.get("uid"), titulo=resumen.get("title"),
                                anio=int(m.group(1)) if m else None))
