from __future__ import annotations

import argparse
import json
import logging
import os
import secrets
import shutil
import socket
import subprocess
import threading
import time
from dataclasses import dataclass
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Callable
from urllib.parse import unquote, urlsplit


RAIZ_PROYECTO = Path(__file__).resolve().parents[2]
ESCENARIOS = {"aguarague", "campo_pajoso", "interfase_urbana"}
DIFICULTADES = {"baja", "media", "alta"}
TIEMPO_VACIA_SEGUNDOS = 60.0
MAXIMO_BODY_BYTES = 64 * 1024


class ErrorDirectorio(Exception):
    def __init__(self, mensaje: str, estado_http: int = HTTPStatus.BAD_REQUEST) -> None:
        super().__init__(mensaje)
        self.estado_http = estado_http


@dataclass
class Sala:
    codigo: str
    escenario: str
    dificultad: str
    max_jugadores: int
    host: str
    puerto: int
    token: str
    proceso: subprocess.Popen[Any]
    creada_en: float
    transporte: str
    vacia_desde: float | None = None
    jugadores: int = 0

    def resumen(self) -> dict[str, Any]:
        return {
            "codigo": self.codigo,
            "escenario": self.escenario,
            "jugadores": self.jugadores,
            "max_jugadores": self.max_jugadores,
            "dificultad": self.dificultad,
        }

    def ubicacion(self) -> dict[str, Any]:
        return {
            **self.resumen(),
            "host": self.host,
            "puerto": self.puerto,
            "transporte": self.transporte,
        }


class DirectorioSalas:
    def __init__(
        self,
        godot: str,
        proyecto: Path = RAIZ_PROYECTO,
        rango_puertos: tuple[int, int] = (9000, 9100),
        host_juego: str = "127.0.0.1",
        url_interna: str = "http://127.0.0.1:8080",
        max_salas: int = 12,
        transporte: str = "websocket",
        carpeta_logs: Path | None = None,
        crear_proceso: Callable[..., subprocess.Popen[Any]] = subprocess.Popen,
        reloj: Callable[[], float] = time.monotonic,
    ) -> None:
        inicio, fin = rango_puertos
        if inicio < 1 or fin > 65535 or inicio > fin:
            raise ValueError("El rango de puertos debe estar entre 1 y 65535.")
        if max_salas < 1:
            raise ValueError("max_salas debe ser mayor que cero.")
        if transporte not in {"websocket", "enet"}:
            raise ValueError("El transporte debe ser websocket o enet.")
        self.godot = godot
        self.proyecto = proyecto.resolve()
        self.puerto_inicio = inicio
        self.puerto_fin = fin
        self.host_juego = host_juego
        self.url_interna = url_interna.rstrip("/")
        self.max_salas = max_salas
        self.transporte = transporte
        self.carpeta_logs = carpeta_logs or Path(os.getenv("TEMP", "/tmp")) / "drone-guardian-directorio"
        self.crear_proceso = crear_proceso
        self.reloj = reloj
        self.salas: dict[str, Sala] = {}
        self._lock = threading.RLock()

    def crear_sala(self, datos: dict[str, Any]) -> dict[str, Any]:
        escenario, dificultad, max_jugadores = self._validar_configuracion(datos)
        self.limpiar_vencidas()
        with self._lock:
            if len(self.salas) >= self.max_salas:
                raise ErrorDirectorio("El directorio alcanzó el límite de salas.", HTTPStatus.SERVICE_UNAVAILABLE)
            codigo = self._nuevo_codigo()
            puerto = self._buscar_puerto_libre()
            token = secrets.token_urlsafe(24)
            comando = [
                self.godot,
                "--headless",
                "--path",
                str(self.proyecto),
                "--",
                "--server",
                f"--port={puerto}",
                f"--room={codigo}",
                f"--scenario={escenario}",
                f"--max-players={max_jugadores}",
                f"--difficulty={dificultad}",
                f"--transport={self.transporte}",
                f"--directory={self.url_interna}",
                f"--directory-token={token}",
            ]
            self.carpeta_logs.mkdir(parents=True, exist_ok=True)
            ruta_log = self.carpeta_logs / f"sala-{codigo}.log"
            try:
                with ruta_log.open("ab") as salida:
                    proceso = self.crear_proceso(
                        comando,
                        cwd=self.proyecto,
                        stdout=salida,
                        stderr=subprocess.STDOUT,
                        close_fds=True,
                    )
            except OSError as error:
                raise ErrorDirectorio(
                    f"No se pudo iniciar Godot: {error}",
                    HTTPStatus.SERVICE_UNAVAILABLE,
                ) from error

            ahora = self.reloj()
            sala = Sala(
                codigo=codigo,
                escenario=escenario,
                dificultad=dificultad,
                max_jugadores=max_jugadores,
                host=self.host_juego,
                puerto=puerto,
                token=token,
                proceso=proceso,
                creada_en=ahora,
                transporte=self.transporte,
                vacia_desde=ahora,
            )
            self.salas[codigo] = sala
            logging.info("Sala %s creada en %s:%d.", codigo, sala.host, sala.puerto)
            return sala.ubicacion()

    def listar_salas(self) -> list[dict[str, Any]]:
        self.limpiar_vencidas()
        with self._lock:
            return [sala.resumen() for sala in self.salas.values()]

    def obtener_sala(self, codigo: str) -> dict[str, Any]:
        self.limpiar_vencidas()
        with self._lock:
            sala = self.salas.get(codigo)
            if sala is None:
                raise ErrorDirectorio("No existe esa sala.", HTTPStatus.NOT_FOUND)
            return sala.ubicacion()

    def actualizar_latido(self, codigo: str, datos: dict[str, Any]) -> dict[str, Any]:
        jugadores = datos.get("jugadores")
        if isinstance(jugadores, bool) or not isinstance(jugadores, int) or jugadores < 0:
            raise ErrorDirectorio("jugadores debe ser un entero no negativo.")
        self.limpiar_vencidas()
        with self._lock:
            sala = self.salas.get(codigo)
            if sala is None:
                raise ErrorDirectorio("No existe esa sala.", HTTPStatus.NOT_FOUND)
            self._validar_token(sala, datos.get("token"))
            if jugadores > sala.max_jugadores:
                raise ErrorDirectorio("El número de jugadores supera el cupo.")
            if jugadores == 0:
                if sala.jugadores > 0 or sala.vacia_desde is None:
                    sala.vacia_desde = self.reloj()
            else:
                sala.vacia_desde = None
            sala.jugadores = jugadores
            return sala.resumen()

    def terminar_sala(self, codigo: str, datos: dict[str, Any]) -> None:
        with self._lock:
            sala = self.salas.get(codigo)
            if sala is None:
                raise ErrorDirectorio("No existe esa sala.", HTTPStatus.NOT_FOUND)
            self._validar_token(sala, datos.get("token"))
            self.salas.pop(codigo, None)
        self._detener_proceso(sala.proceso)
        logging.info("Sala %s terminada por el servidor de partida.", codigo)

    def limpiar_vencidas(self) -> None:
        with self._lock:
            expiradas = self._limpiar_vencidas_bajo_lock()
        for sala in expiradas:
            self._detener_proceso(sala.proceso)

    def cerrar(self) -> None:
        with self._lock:
            salas = list(self.salas.values())
            self.salas.clear()
        for sala in salas:
            self._detener_proceso(sala.proceso)

    def _limpiar_vencidas_bajo_lock(self) -> list[Sala]:
        ahora = self.reloj()
        expiradas: list[Sala] = []
        for codigo, sala in list(self.salas.items()):
            proceso_termino = sala.proceso.poll() is not None
            vacia_expirada = (
                sala.jugadores == 0
                and sala.vacia_desde is not None
                and ahora - sala.vacia_desde >= TIEMPO_VACIA_SEGUNDOS
            )
            if proceso_termino or vacia_expirada:
                expiradas.append(sala)
                self.salas.pop(codigo, None)
        return expiradas

    def _validar_configuracion(self, datos: dict[str, Any]) -> tuple[str, str, int]:
        escenario = datos.get("escenario", "aguarague")
        dificultad = datos.get("dificultad", "media")
        max_jugadores = datos.get("max_jugadores", 6)
        if not isinstance(escenario, str) or escenario not in ESCENARIOS:
            raise ErrorDirectorio("Escenario inválido o todavía no disponible.")
        if not isinstance(dificultad, str) or dificultad.lower() not in DIFICULTADES:
            raise ErrorDirectorio("Dificultad inválida.")
        if isinstance(max_jugadores, bool) or not isinstance(max_jugadores, int) or not 2 <= max_jugadores <= 6:
            raise ErrorDirectorio("max_jugadores debe estar entre 2 y 6.")
        return escenario, dificultad.lower(), max_jugadores

    def _nuevo_codigo(self) -> str:
        for _intento in range(10000):
            codigo = f"{secrets.randbelow(10000):04d}"
            if codigo not in self.salas:
                return codigo
        raise ErrorDirectorio("No quedan códigos de sala disponibles.", HTTPStatus.SERVICE_UNAVAILABLE)

    def _buscar_puerto_libre(self) -> int:
        puertos_usados = {sala.puerto for sala in self.salas.values()}
        for puerto in range(self.puerto_inicio, self.puerto_fin + 1):
            if puerto in puertos_usados:
                continue
            tipo_socket = socket.SOCK_DGRAM if self.transporte == "enet" else socket.SOCK_STREAM
            with socket.socket(socket.AF_INET, tipo_socket) as verificador:
                try:
                    verificador.bind(("0.0.0.0", puerto))
                except OSError:
                    continue
                return puerto
        raise ErrorDirectorio("No hay puertos libres en el rango configurado.", HTTPStatus.SERVICE_UNAVAILABLE)

    @staticmethod
    def _validar_token(sala: Sala, token: Any) -> None:
        if not isinstance(token, str) or not secrets.compare_digest(token, sala.token):
            raise ErrorDirectorio("Token de servidor inválido.", HTTPStatus.FORBIDDEN)

    @staticmethod
    def _detener_proceso(proceso: subprocess.Popen[Any]) -> None:
        if proceso.poll() is not None:
            return
        proceso.terminate()
        try:
            proceso.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proceso.kill()
            proceso.wait(timeout=3)


class ServidorDirectorio(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, direccion: tuple[str, int], directorio: DirectorioSalas) -> None:
        self.directorio = directorio
        super().__init__(direccion, ManejadorHTTP)


class ManejadorHTTP(BaseHTTPRequestHandler):
    server: ServidorDirectorio

    def do_OPTIONS(self) -> None:
        self.send_response(HTTPStatus.NO_CONTENT)
        self._cabeceras_cors()
        self.end_headers()

    def do_GET(self) -> None:
        ruta = urlsplit(self.path).path
        try:
            if ruta == "/health":
                self._responder(HTTPStatus.OK, {"estado": "ok"})
            elif ruta == "/salas":
                self._responder(HTTPStatus.OK, {"salas": self.server.directorio.listar_salas()})
            else:
                partes = self._partes_sala(ruta)
                if len(partes) != 1:
                    self._responder(HTTPStatus.NOT_FOUND, {"error": "Ruta no encontrada."})
                    return
                self._responder(HTTPStatus.OK, self.server.directorio.obtener_sala(partes[0]))
        except ErrorDirectorio as error:
            self._error(error)

    def do_POST(self) -> None:
        ruta = urlsplit(self.path).path
        try:
            datos = self._leer_json()
            if ruta == "/salas":
                sala = self.server.directorio.crear_sala(datos)
                self._responder(HTTPStatus.CREATED, sala)
                return
            partes = self._partes_sala(ruta)
            if len(partes) == 2 and partes[1] == "heartbeat":
                sala = self.server.directorio.actualizar_latido(partes[0], datos)
                self._responder(HTTPStatus.OK, sala)
            elif len(partes) == 2 and partes[1] == "terminar":
                self.server.directorio.terminar_sala(partes[0], datos)
                self._responder(HTTPStatus.OK, {"estado": "terminada"})
            else:
                self._responder(HTTPStatus.NOT_FOUND, {"error": "Ruta no encontrada."})
        except ErrorDirectorio as error:
            self._error(error)
        except (json.JSONDecodeError, UnicodeDecodeError):
            self._responder(HTTPStatus.BAD_REQUEST, {"error": "El cuerpo debe ser JSON válido."})

    def log_message(self, formato: str, *argumentos: Any) -> None:
        logging.info("%s - %s", self.address_string(), formato % argumentos)

    def _leer_json(self) -> dict[str, Any]:
        try:
            largo = int(self.headers.get("Content-Length", "0"))
        except ValueError as error:
            raise ErrorDirectorio("Content-Length debe ser un entero.") from error
        if largo < 0 or largo > MAXIMO_BODY_BYTES:
            raise ErrorDirectorio("El cuerpo de la solicitud es demasiado grande.")
        cuerpo = self.rfile.read(largo)
        datos = json.loads(cuerpo.decode("utf-8") if cuerpo else "{}")
        if not isinstance(datos, dict):
            raise ErrorDirectorio("El cuerpo JSON debe ser un objeto.")
        return datos

    @staticmethod
    def _partes_sala(ruta: str) -> list[str]:
        partes = [unquote(parte) for parte in ruta.split("/") if parte]
        if not partes or partes[0] != "salas":
            return []
        return partes[1:]

    def _error(self, error: ErrorDirectorio) -> None:
        self._responder(error.estado_http, {"error": str(error)})

    def _responder(self, estado: int, datos: dict[str, Any]) -> None:
        cuerpo = json.dumps(datos, ensure_ascii=False).encode("utf-8")
        self.send_response(estado)
        self._cabeceras_cors()
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(cuerpo)))
        self.end_headers()
        self.wfile.write(cuerpo)

    def _cabeceras_cors(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Cache-Control", "no-store")


def _argumentos() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Directorio de salas de Drone Guardian: Fire Ops.")
    parser.add_argument("--host", default="0.0.0.0", help="Interfaz HTTP donde escuchar.")
    parser.add_argument("--port", type=int, default=8080, help="Puerto del directorio HTTP.")
    parser.add_argument("--game-host", default="127.0.0.1", help="Host de partida anunciado a los clientes.")
    parser.add_argument("--game-port-start", type=int, default=9000)
    parser.add_argument("--game-port-end", type=int, default=9100)
    parser.add_argument("--max-rooms", type=int, default=12)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN") or shutil.which("godot") or "godot")
    parser.add_argument("--project", type=Path, default=RAIZ_PROYECTO)
    parser.add_argument("--transport", choices=("websocket", "enet"), default="websocket")
    parser.add_argument("--logs", type=Path, default=Path(os.getenv("TEMP", "/tmp")) / "drone-guardian-directorio")
    return parser.parse_args()


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    args = _argumentos()
    if not 1 <= args.port <= 65535:
        raise SystemExit("--port debe estar entre 1 y 65535.")
    if not 1 <= args.game_port_start <= args.game_port_end <= 65535:
        raise SystemExit("El rango de puertos de partida es inválido.")
    if args.max_rooms < 1:
        raise SystemExit("--max-rooms debe ser mayor que cero.")

    directorio = DirectorioSalas(
        godot=args.godot,
        proyecto=args.project,
        rango_puertos=(args.game_port_start, args.game_port_end),
        host_juego=args.game_host,
        url_interna=f"http://127.0.0.1:{args.port}",
        max_salas=args.max_rooms,
        transporte=args.transport,
        carpeta_logs=args.logs,
    )
    servidor = ServidorDirectorio((args.host, args.port), directorio)
    detener_limpieza = threading.Event()

    def limpiar_periodicamente() -> None:
        while not detener_limpieza.wait(2.0):
            directorio.limpiar_vencidas()

    hilo_limpieza = threading.Thread(target=limpiar_periodicamente, daemon=True)
    hilo_limpieza.start()
    logging.info(
        "Directorio escuchando en http://%s:%d; rango de partidas %d-%d; máximo %d salas.",
        args.host,
        args.port,
        args.game_port_start,
        args.game_port_end,
        args.max_rooms,
    )
    try:
        servidor.serve_forever()
    except KeyboardInterrupt:
        logging.info("Cerrando el directorio.")
    finally:
        detener_limpieza.set()
        servidor.server_close()
        directorio.cerrar()


if __name__ == "__main__":
    main()
