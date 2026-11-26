from __future__ import annotations

import argparse
import csv
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path


RAIZ_PROYECTO = Path(__file__).resolve().parents[1]
CAMPOS_REQUERIDOS = {"paradigma", "unidades", "N", "steps", "tiempo_segundos"}


@dataclass(frozen=True)
class Medicion:
    paradigma: str
    unidades: int
    n: int
    pasos: int
    segundos: float


def leer_mediciones(ruta: Path) -> list[Medicion]:
    try:
        with ruta.open(newline="", encoding="utf-8") as archivo:
            lector = csv.DictReader(archivo)
            faltantes = CAMPOS_REQUERIDOS - set(lector.fieldnames or [])
            if faltantes:
                raise ValueError(f"Faltan columnas en {ruta}: {', '.join(sorted(faltantes))}.")
            mediciones = []
            for numero_fila, fila in enumerate(lector, start=2):
                paradigma = (fila.get("paradigma") or "").strip().lower()
                if paradigma not in {"secuencial", "openmp", "mpi"}:
                    raise ValueError(f"Paradigma inválido en la fila {numero_fila}: {paradigma!r}.")
                try:
                    unidades = int(fila["unidades"])
                    n = int(fila["N"])
                    pasos = int(fila["steps"])
                    segundos = float(fila["tiempo_segundos"])
                except (TypeError, ValueError) as error:
                    raise ValueError(f"Medición no numérica en la fila {numero_fila}.") from error
                if unidades <= 0 or n <= 0 or pasos <= 0 or segundos <= 0:
                    raise ValueError(f"Unidades, tamaño, pasos y tiempo deben ser positivos en la fila {numero_fila}.")
                mediciones.append(Medicion(paradigma, unidades, n, pasos, segundos))
    except OSError as error:
        raise ValueError(f"No se pudo leer {ruta}: {error}") from error

    if not mediciones:
        raise ValueError(f"El CSV no contiene mediciones: {ruta}.")
    if not any(item.paradigma == "secuencial" and item.unidades == 1 for item in mediciones):
        raise ValueError("El CSV debe incluir la medición secuencial de referencia con una unidad.")
    if len({(item.n, item.pasos) for item in mediciones}) != 1:
        raise ValueError("Las mediciones deben tener el mismo N y número de pasos para compararse.")
    return mediciones


def generar_graficas(mediciones: list[Medicion], salida: Path) -> list[Path]:
    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError as error:
        raise RuntimeError("Falta matplotlib. Instálalo con: python -m pip install matplotlib") from error

    salida.mkdir(parents=True, exist_ok=True)
    tiempos_base = [
        item.segundos for item in mediciones
        if item.paradigma == "secuencial" and item.unidades == 1
    ]
    tiempo_secuencial = sum(tiempos_base) / len(tiempos_base)
    paralelas: dict[str, list[Medicion]] = defaultdict(list)
    for item in mediciones:
        if item.paradigma in {"openmp", "mpi"}:
            paralelas[item.paradigma].append(item)
    for valores in paralelas.values():
        valores.sort(key=lambda item: item.unidades)

    generadas: list[Path] = []

    figura, eje = plt.subplots(figsize=(8, 5))
    eje.axhline(tiempo_secuencial, color="black", linestyle="--", label="Secuencial (referencia)")
    for paradigma, etiqueta in (("openmp", "OpenMP (hilos)"), ("mpi", "OpenMPI (procesos)")):
        valores = paralelas.get(paradigma, [])
        if valores:
            eje.plot(
                [item.unidades for item in valores],
                [item.segundos for item in valores],
                marker="o",
                label=etiqueta,
            )
    eje.set_title(
        f"Tiempo de ejecución por unidades de cómputo ({mediciones[0].n} x "
        f"{mediciones[0].n}, {mediciones[0].pasos} pasos)"
    )
    eje.set_xlabel("Hilos OpenMP / procesos MPI")
    eje.set_ylabel("Tiempo (s)")
    eje.grid(True, alpha=0.3)
    eje.legend()
    figura.tight_layout()
    ruta = salida / "tiempo_vs_hilos.png"
    figura.savefig(ruta, dpi=160)
    plt.close(figura)
    generadas.append(ruta)

    series = (
        ("speedup.png", "Speedup", "S = T_s / T_p", lambda s, p: s),
        ("eficiencia.png", "Eficiencia paralela", "E = S / p", lambda s, p: s / p),
    )
    for nombre, titulo, etiqueta_y, calcular in series:
        figura, eje = plt.subplots(figsize=(8, 5))
        for paradigma, etiqueta in (("openmp", "OpenMP"), ("mpi", "OpenMPI")):
            valores = paralelas.get(paradigma, [])
            if valores:
                eje.plot(
                    [item.unidades for item in valores],
                    [calcular(tiempo_secuencial / item.segundos, item.unidades) for item in valores],
                    marker="o",
                    label=etiqueta,
                )
        eje.set_title(titulo)
        eje.set_xlabel("Unidades de cómputo (p)")
        eje.set_ylabel(etiqueta_y)
        eje.grid(True, alpha=0.3)
        eje.legend()
        figura.tight_layout()
        ruta = salida / nombre
        figura.savefig(ruta, dpi=160)
        plt.close(figura)
        generadas.append(ruta)

    figura, eje = plt.subplots(figsize=(8, 5))
    for paradigma, etiqueta in (("openmp", "OpenMP"), ("mpi", "OpenMPI")):
        valores = [item for item in paralelas.get(paradigma, []) if item.unidades > 1]
        if valores:
            eje.plot(
                [item.unidades for item in valores],
                [
                    (item.unidades / (tiempo_secuencial / item.segundos) - 1.0)
                    / (item.unidades - 1.0)
                    for item in valores
                ],
                marker="o",
                label=etiqueta,
            )
    eje.axhline(0.0, color="black", linewidth=0.8)
    eje.set_title("Fracción serial estimada por la ley de Amdahl")
    eje.set_xlabel("Unidades de cómputo (p)")
    eje.set_ylabel("Fracción serial estimada")
    eje.grid(True, alpha=0.3)
    eje.legend()
    figura.tight_layout()
    ruta = salida / "fraccion_serial_amdahl.png"
    figura.savefig(ruta, dpi=160)
    plt.close(figura)
    generadas.append(ruta)
    return generadas


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Genera las gráficas de rendimiento desde data/benchmark_results.csv."
    )
    parser.add_argument(
        "csv",
        nargs="?",
        type=Path,
        default=RAIZ_PROYECTO / "data" / "benchmark_results.csv",
    )
    parser.add_argument(
        "--salida",
        type=Path,
        default=RAIZ_PROYECTO / "docs" / "graficas",
    )
    argumentos = parser.parse_args()
    try:
        rutas = generar_graficas(leer_mediciones(argumentos.csv), argumentos.salida)
    except (RuntimeError, ValueError) as error:
        print(f"Error al generar las gráficas: {error}", file=sys.stderr)
        return 1
    for ruta in rutas:
        print(f"Gráfica guardada en {ruta.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
