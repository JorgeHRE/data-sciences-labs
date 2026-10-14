"""Actividad 3: compara generador vs lista midiendo memoria con tracemalloc.

Se ejecuta con:  uv run python -m clientes.comparar_memoria
"""

import inspect
import tracemalloc

import requests

from clientes.paginacion import acumular_estudios, generar_estudios

CONDICION = "gastric cancer"
N = 500  # el enunciado pide al menos 300 registros


def procesar(estudio: dict) -> int:
    """Tarea de ejemplo: devuelve el nº de inscritos previsto (0 si no viene)."""
    diseno = estudio["protocolSection"].get("designModule", {})
    return diseno.get("enrollmentInfo", {}).get("count", 0)


def medir(nombre: str, funcion) -> None:
    tracemalloc.start()
    resultado = funcion()
    _, pico = tracemalloc.get_traced_memory()  # pico = máximo alcanzado
    tracemalloc.stop()
    print(f"{nombre:<10} registros={resultado[0]:>4}  inscritos_totales={resultado[1]:>9,}  "
          f"pico de memoria={pico / 1024 / 1024:6.2f} MB")


def con_generador():
    n = total = 0
    for estudio in generar_estudios(CONDICION, maximo=N):
        total += procesar(estudio)  # se procesa y se descarta: no se acumula nada
        n += 1
    return n, total


def con_lista():
    estudios = acumular_estudios(CONDICION, maximo=N)  # todo en memoria a la vez
    return len(estudios), sum(procesar(e) for e in estudios)


def demostrar_pereza() -> None:
    """Prueba directa de que es un generador: no hace nada hasta que se lo piden."""
    llamadas = 0
    get_original = requests.get

    def get_contador(*args, **kwargs):  # envuelve requests.get para contar peticiones reales
        nonlocal llamadas
        llamadas += 1
        return get_original(*args, **kwargs)

    requests.get = get_contador
    try:
        print("\n--- Demostración de pereza ---")
        print("¿Es función generadora?:", inspect.isgeneratorfunction(generar_estudios))
        gen = generar_estudios(CONDICION, maximo=150, tamano_pagina=100)
        print("Tras crear el generador, peticiones:", llamadas)  # esperado: 0
        next(gen)
        print("Tras pedir el 1.er estudio, peticiones:", llamadas)  # esperado: 1 (página 1)
        for _ in range(99):
            next(gen)
        print("Tras consumir 100 estudios, peticiones:", llamadas)  # esperado: 1 (aún la 1.ª página)
        next(gen)
        print("Tras pedir el estudio 101, peticiones:", llamadas)  # esperado: 2 (página 2)
    finally:
        requests.get = get_original  # restaurar siempre


if __name__ == "__main__":
    print(f"Condición: {CONDICION!r} | registros pedidos: {N}\n")
    medir("generador", con_generador)
    medir("lista", con_lista)
    demostrar_pereza()
