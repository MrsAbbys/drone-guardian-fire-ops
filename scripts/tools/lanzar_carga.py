from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


RAIZ_PROYECTO = Path(__file__).resolve().parents[2]
ROLES_POR_JUGADOR = ("explorador", "cisterna", "tactico", "explorador", "cisterna", "explorador")


@dataclass
class BotLanzado:
    nombre: str
    codigo_sala: str
    ruta_estado: Path
    ruta_log: Path
    comando: list[str]
    proceso: subprocess.Popen[bytes]


def _argumentos() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Lanza bots headless para una prueba de carga.")
    parser.add_argument("--salas", type=int, default=4)
    parser.add_argument("--bots-por-sala", type=int, default=6)
    parser.add_argument("--duracion", type=int, default=300)
    parser.add_argument("--directorio", default=os.environ.get("DIRECTORY_URL", "http://127.0.0.1:8080"))
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--cliente-binario", type=Path)
    parser.add_argument("--proyecto", type=Path, default=RAIZ_PROYECTO)
    parser.add_argument("--logs", type=Path, default=RAIZ_PROYECTO / "logs" / "carga")
    parser.add_argument("--timeout-inicial", type=int, default=120)
    parser.add_argument("--reconectar-despues", type=int, default=15)
    return parser.parse_args()


def _solicitar_json(url: str, datos: dict[str, Any] | None = None) -> dict[str, Any]:
    cuerpo = json.dumps(datos).encode("utf-8") if datos is not None else None
    cabeceras = {"Content-Type": "application/json"} if cuerpo is not None else {}
    solicitud = Request(url, data=cuerpo, headers=cabeceras)
    try:
        with urlopen(solicitud, timeout=10) as respuesta:
            contenido = json.loads(respuesta.read().decode("utf-8"))
    except HTTPError as error:
        detalle = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"El directorio respondió HTTP {error.code}: {detalle}") from error
    except (OSError, URLError, json.JSONDecodeError) as error:
        raise RuntimeError(f"No se pudo consultar {url}: {error}") from error
    if not isinstance(contenido, dict):
        raise RuntimeError(f"El directorio devolvió JSON inválido en {url}.")
    return contenido


def _crear_sala(url_directorio: str, bots: int) -> dict[str, Any]:
    sala = _solicitar_json(
        f"{url_directorio.rstrip('/')}/salas",
        {
            "escenario": "aguarague",
            "dificultad": "media",
            "max_jugadores": bots,
        },
    )
    for campo in ("codigo", "host", "puerto"):
        if campo not in sala:
            raise RuntimeError(f"La respuesta de creación de sala no incluye {campo}.")
    return sala


def _comando_bot(
    argumentos: argparse.Namespace,
    valores: list[str],
) -> list[str]:
    if argumentos.cliente_binario:
        return [
            str(argumentos.cliente_binario.resolve()),
            "--headless",
            "--",
            *valores,
        ]
    return [
        argumentos.godot,
        "--headless",
        "--path",
        str(argumentos.proyecto.resolve()),
        "--",
        *valores,
    ]


def _lanzar_bot(
    argumentos: argparse.Namespace,
    codigo_sala: str,
    nombre: str,
    rol: str,
    indice: int,
    esperar_reconexion: bool = False,
) -> BotLanzado:
    identificador = f"{codigo_sala}-{indice:02d}"
    ruta_estado = (argumentos.logs / f"bot-{identificador}.json").resolve()
    ruta_log = (argumentos.logs / f"bot-{identificador}.log").resolve()
    ruta_estado.unlink(missing_ok=True)
    valores = [
        "--bot",
        f"--directory={argumentos.directorio.rstrip('/')}",
        f"--room-code={codigo_sala}",
        f"--name={nombre}",
        f"--role={rol}",
        f"--bots-in-room={argumentos.bots_por_sala}",
        f"--status-file={ruta_estado}",
        "--transport=websocket",
    ]
    if esperar_reconexion:
        valores.append("--expect-reconnect")
    comando = _comando_bot(argumentos, valores)
    with ruta_log.open("ab") as salida:
        proceso = subprocess.Popen(
            comando,
            cwd=argumentos.proyecto.resolve(),
            stdout=salida,
            stderr=subprocess.STDOUT,
        )
    return BotLanzado(nombre, codigo_sala, ruta_estado, ruta_log, comando, proceso)


def _estado_bot(bot: BotLanzado) -> dict[str, Any]:
    try:
        datos = json.loads(bot.ruta_estado.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}
    except (OSError, json.JSONDecodeError):
        return {}
    return datos if isinstance(datos, dict) else {}


def _esperar_estado(
    bots: list[BotLanzado],
    estados_aceptados: set[str],
    tiempo_limite: float,
) -> None:
    limite = time.monotonic() + tiempo_limite
    pendientes = list(bots)
    while pendientes and time.monotonic() < limite:
        for bot in pendientes.copy():
            if bot.proceso.poll() is not None:
                raise RuntimeError(
                    f"El bot {bot.nombre} terminó antes de estar listo. Revisa {bot.ruta_log}."
                )
            estado = _estado_bot(bot)
            if estado.get("status") == "failed":
                raise RuntimeError(f"Falló el bot {bot.nombre}: {estado.get('message', 'sin detalle')}")
            if estado.get("status") in estados_aceptados:
                pendientes.remove(bot)
        if pendientes:
            time.sleep(0.25)
    if pendientes:
        nombres = ", ".join(bot.nombre for bot in pendientes)
        raise TimeoutError(f"Tiempo agotado esperando bots listos: {nombres}.")


def _terminar_proceso(bot: BotLanzado) -> None:
    if bot.proceso.poll() is not None:
        return
    bot.proceso.terminate()
    try:
        bot.proceso.wait(timeout=10)
    except subprocess.TimeoutExpired:
        bot.proceso.kill()
        bot.proceso.wait(timeout=5)


def _validar_argumentos(argumentos: argparse.Namespace) -> None:
    if argumentos.salas < 1:
        raise ValueError("--salas debe ser mayor que cero.")
    if not 2 <= argumentos.bots_por_sala <= 6:
        raise ValueError("--bots-por-sala debe estar entre 2 y 6.")
    if argumentos.duracion < 1:
        raise ValueError("--duracion debe ser mayor que cero.")
    if argumentos.timeout_inicial < 1 or argumentos.reconectar_despues < 1:
        raise ValueError("Los tiempos de espera deben ser mayores que cero.")
    if argumentos.cliente_binario:
        if not argumentos.cliente_binario.is_file():
            raise FileNotFoundError(f"No existe el cliente exportado: {argumentos.cliente_binario}")
    elif not Path(argumentos.godot).is_file() and not shutil.which(argumentos.godot):
        raise FileNotFoundError(f"No se encontró Godot: {argumentos.godot}")
    elif Path(argumentos.godot).is_file():
        argumentos.godot = str(Path(argumentos.godot).resolve())


def ejecutar() -> int:
    argumentos = _argumentos()
    _validar_argumentos(argumentos)
    argumentos.logs.mkdir(parents=True, exist_ok=True)
    base = argumentos.directorio.rstrip("/")
    _solicitar_json(f"{base}/health")
    if not argumentos.cliente_binario:
        subprocess.run(
            [
                argumentos.godot,
                "--headless",
                "--editor",
                "--path",
                str(argumentos.proyecto.resolve()),
                "--quit",
            ],
            check=True,
        )

    bots: list[BotLanzado] = []
    try:
        salas = [_crear_sala(base, argumentos.bots_por_sala) for _ in range(argumentos.salas)]
        for indice_sala, sala in enumerate(salas):
            codigo = str(sala["codigo"])
            for indice_bot in range(argumentos.bots_por_sala):
                nombre = f"carga-{codigo}-{indice_bot + 1:02d}"
                rol = ROLES_POR_JUGADOR[indice_bot]
                bots.append(_lanzar_bot(argumentos, codigo, nombre, rol, indice_bot + 1))

        print(f"Esperando {len(bots)} bots en {len(salas)} salas...")
        _esperar_estado(bots, {"ready"}, argumentos.timeout_inicial)

        # Mantiene un cliente conectado para que el servidor conserve la sala durante la reconexión.
        victima = next(bot for bot in bots if bot.codigo_sala == str(salas[0]["codigo"]) and bot.nombre.endswith("-02"))
        rol_victima = str(_estado_bot(victima).get("role", ROLES_POR_JUGADOR[1]))
        time.sleep(min(argumentos.reconectar_despues, max(argumentos.duracion, 1)))
        _terminar_proceso(victima)
        time.sleep(2.0)
        reemplazo = _lanzar_bot(
            argumentos,
            victima.codigo_sala,
            victima.nombre,
            rol_victima,
            2,
            esperar_reconexion=True,
        )
        bots[bots.index(victima)] = reemplazo
        _esperar_estado([reemplazo], {"recovered"}, argumentos.timeout_inicial)
        estado_reconexion = _estado_bot(reemplazo)
        if estado_reconexion.get("role") != ROLES_POR_JUGADOR[1] or int(estado_reconexion.get("drone_id", 0)) <= 0:
            raise RuntimeError("La reconexión no recuperó el rol y el dron originales.")
        print(
            "Reconexión verificada: "
            f"{reemplazo.nombre}, rol={estado_reconexion['role']}, dron={estado_reconexion['drone_id']}."
        )

        fin = time.monotonic() + argumentos.duracion
        print(f"Prueba de carga activa durante {argumentos.duracion} s.")
        while time.monotonic() < fin:
            for bot in bots:
                if bot.proceso.poll() is not None:
                    estado = _estado_bot(bot)
                    raise RuntimeError(
                        f"El bot {bot.nombre} terminó durante la carga: "
                        f"{estado.get('message', bot.ruta_log)}."
                    )
                estado = _estado_bot(bot)
                if estado.get("status") == "failed":
                    raise RuntimeError(f"Falló el bot {bot.nombre}: {estado.get('message', 'sin detalle')}")
            time.sleep(1.0)
        print(
            "Carga terminada. CSV del directorio: "
            f"{argumentos.logs.parent / 'servidor_metricas.csv'}"
        )
        return 0
    except (OSError, RuntimeError, TimeoutError, ValueError) as error:
        print(f"Error en la prueba de carga: {error}", file=sys.stderr)
        return 1
    finally:
        for bot in bots:
            _terminar_proceso(bot)


if __name__ == "__main__":
    raise SystemExit(ejecutar())
