from __future__ import annotations

import argparse
import csv
import sys
from collections import defaultdict
from pathlib import Path


RAIZ_PROYECTO = Path(__file__).resolve().parents[2]
CAMPOS_REQUERIDOS = {
    "room_code",
    "sample_ms",
    "tick_ms_promedio",
    "tick_ms_p95",
    "tick_ms_max",
    "jugadores",
    "bytes_s_por_jugador",
    "ram_mb",
    "cpu_pct",
}


def leer_metricas(ruta: Path) -> list[dict[str, str]]:
    try:
        with ruta.open(newline="", encoding="utf-8") as archivo:
            lector = csv.DictReader(archivo)
            faltantes = CAMPOS_REQUERIDOS - set(lector.fieldnames or [])
            if faltantes:
                raise ValueError(f"Faltan columnas en el CSV: {', '.join(sorted(faltantes))}.")
            filas = list(lector)
    except OSError as error:
        raise ValueError(f"No se pudo leer {ruta}: {error}") from error
    if not filas:
        raise ValueError(f"El CSV no contiene muestras: {ruta}.")
    return filas


def _numero(fila: dict[str, str], campo: str) -> float | None:
    valor = fila.get(campo, "").strip()
    if not valor:
        return None
    try:
        return float(valor)
    except ValueError:
        return None


def generar_png(filas: list[dict[str, str]], salida: Path) -> None:
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError as error:
        raise RuntimeError(
            "Falta matplotlib. Instálalo con: python -m pip install -r requirements-load-test.txt"
        ) from error

    por_sala: dict[str, list[dict[str, str]]] = defaultdict(list)
    for fila in filas:
        por_sala[fila["room_code"]].append(fila)

    figura, ejes = plt.subplots(3, 1, figsize=(12, 12), sharex=True)
    eje_tick, eje_recursos, eje_red = ejes
    eje_ram = eje_recursos.twinx()
    for codigo, muestras in sorted(por_sala.items()):
        muestras.sort(key=lambda fila: int(float(fila.get("sample_ms", 0) or 0)))
        inicio_ms = _numero(muestras[0], "sample_ms") or 0.0
        tiempos = [
            ((_numero(fila, "sample_ms") or inicio_ms) - inicio_ms) / 60000.0
            for fila in muestras
        ]
        tick_promedio = [_numero(fila, "tick_ms_promedio") for fila in muestras]
        tick_p95 = [_numero(fila, "tick_ms_p95") for fila in muestras]
        tick_max = [_numero(fila, "tick_ms_max") for fila in muestras]
        cpu = [_numero(fila, "cpu_pct") for fila in muestras]
        ram = [_numero(fila, "ram_mb") for fila in muestras]
        red_kb = [
            valor / 1024.0 if valor is not None else None
            for valor in (_numero(fila, "bytes_s_por_jugador") for fila in muestras)
        ]

        eje_tick.plot(tiempos, tick_promedio, label=f"{codigo} promedio", alpha=0.65)
        eje_tick.plot(tiempos, tick_p95, label=f"{codigo} p95")
        eje_tick.plot(tiempos, tick_max, label=f"{codigo} máx.", linestyle=":")
        eje_recursos.plot(tiempos, cpu, label=f"{codigo} CPU")
        eje_ram.plot(tiempos, ram, label=f"{codigo} RAM", linestyle="--")
        eje_red.plot(tiempos, red_kb, label=f"{codigo} ancho/jugador")

    eje_tick.set_title("Tiempo de tick por sala")
    eje_tick.set_ylabel("Milisegundos")
    eje_tick.grid(True, alpha=0.25)
    eje_tick.legend(ncol=3, fontsize="small")

    eje_recursos.set_title("Recursos del proceso del servidor")
    eje_recursos.set_ylabel("CPU (%)")
    eje_ram.set_ylabel("RAM (MiB)")
    eje_recursos.grid(True, alpha=0.25)
    lineas_cpu, etiquetas_cpu = eje_recursos.get_legend_handles_labels()
    lineas_ram, etiquetas_ram = eje_ram.get_legend_handles_labels()
    eje_recursos.legend(lineas_cpu + lineas_ram, etiquetas_cpu + etiquetas_ram, ncol=2, fontsize="small")

    eje_red.axhline(20.0, color="red", linestyle="--", label="Meta 20 KiB/s")
    eje_red.set_title("Ancho de banda enviado por jugador")
    eje_red.set_ylabel("KiB/s")
    eje_red.set_xlabel("Tiempo desde el inicio de cada sala (min)")
    eje_red.grid(True, alpha=0.25)
    eje_red.legend(ncol=3, fontsize="small")

    figura.suptitle("Prueba de carga de DRONE GUARDIAN: FIRE OPS")
    figura.tight_layout()
    salida.parent.mkdir(parents=True, exist_ok=True)
    figura.savefig(salida, dpi=150)
    plt.close(figura)


def main() -> int:
    parser = argparse.ArgumentParser(description="Genera una gráfica PNG desde servidor_metricas.csv.")
    parser.add_argument(
        "csv",
        nargs="?",
        type=Path,
        default=RAIZ_PROYECTO / "logs" / "servidor_metricas.csv",
    )
    parser.add_argument(
        "--salida",
        type=Path,
        default=RAIZ_PROYECTO / "logs" / "servidor_metricas.png",
    )
    argumentos = parser.parse_args()
    try:
        filas = leer_metricas(argumentos.csv)
        generar_png(filas, argumentos.salida)
    except (RuntimeError, ValueError) as error:
        print(f"Error al generar la gráfica: {error}", file=sys.stderr)
        return 1
    print(f"Gráfica guardada en {argumentos.salida.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
