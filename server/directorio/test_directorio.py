from __future__ import annotations

import csv
import json
import socket
import tempfile
import threading
import unittest
from http.client import HTTPConnection
from pathlib import Path
from typing import Any
from directorio import DirectorioSalas, ServidorDirectorio


class ProcesoSimulado:
    def __init__(self) -> None:
        self.terminado = False

    def poll(self) -> int | None:
        return 0 if self.terminado else None

    def terminate(self) -> None:
        self.terminado = True

    def wait(self, timeout: float | None = None) -> int:
        self.terminado = True
        return 0

    def kill(self) -> None:
        self.terminado = True


def rango_puertos_disponibles(cantidad: int) -> tuple[int, int]:
    for inicio in range(30000, 60000 - cantidad):
        sockets: list[socket.socket] = []
        try:
            for puerto in range(inicio, inicio + cantidad):
                verificador = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                verificador.bind(("127.0.0.1", puerto))
                sockets.append(verificador)
            return inicio, inicio + cantidad - 1
        except OSError:
            continue
        finally:
            for verificador in sockets:
                verificador.close()
    raise RuntimeError("No se encontró un rango de puertos disponible para la prueba.")


class PruebasDirectorio(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.procesos: list[ProcesoSimulado] = []
        self.comandos: list[list[str]] = []

        def crear_proceso(comando: list[str], **_kwargs: Any) -> ProcesoSimulado:
            proceso = ProcesoSimulado()
            self.procesos.append(proceso)
            self.comandos.append(comando)
            return proceso

        self.reloj = [100.0]
        rango = rango_puertos_disponibles(3)
        self.directorio = DirectorioSalas(
            godot="godot",
            proyecto=Path(self.temp.name),
            rango_puertos=rango,
            host_juego="127.0.0.1",
            url_interna="http://127.0.0.1:8080",
            max_salas=2,
            carpeta_logs=Path(self.temp.name) / "logs",
            crear_proceso=crear_proceso,
            reloj=lambda: self.reloj[0],
        )
        self.servidor = ServidorDirectorio(("127.0.0.1", 0), self.directorio)
        self.hilo = threading.Thread(target=self.servidor.serve_forever, daemon=True)
        self.hilo.start()
        self.host, self.puerto_http = self.servidor.server_address

    def tearDown(self) -> None:
        self.servidor.shutdown()
        self.servidor.server_close()
        self.hilo.join(timeout=2)
        self.directorio.cerrar()
        self.temp.cleanup()

    def solicitar(self, metodo: str, ruta: str, datos: dict[str, Any] | None = None) -> tuple[int, dict[str, Any]]:
        conexion = HTTPConnection(self.host, self.puerto_http, timeout=2)
        cuerpo = json.dumps(datos).encode("utf-8") if datos is not None else None
        cabeceras = {"Content-Type": "application/json"} if cuerpo is not None else {}
        conexion.request(metodo, ruta, body=cuerpo, headers=cabeceras)
        respuesta = conexion.getresponse()
        contenido = respuesta.read()
        conexion.close()
        return respuesta.status, json.loads(contenido or b"{}")

    def crear_por_http(self) -> dict[str, Any]:
        estado, sala = self.solicitar(
            "POST",
            "/salas",
            {
                "nombre": "Operación Aguaragüe",
                "escenario": "aguarague",
                "dificultad": "media",
                "max_jugadores": 4,
            },
        )
        self.assertEqual(estado, 201)
        self.assertRegex(sala["codigo"], r"^\d{4}$")
        self.assertNotIn("token_anfitrion", sala)
        return sala

    def test_crea_y_resuelve_sala_sin_exponer_token(self) -> None:
        sala = self.crear_por_http()
        estado, resuelta = self.solicitar("GET", f"/salas/{sala['codigo']}")
        self.assertEqual(estado, 200)
        self.assertEqual(resuelta["host"], "127.0.0.1")
        self.assertEqual(resuelta["puerto"], sala["puerto"])
        self.assertEqual(resuelta["transporte"], "websocket")
        self.assertEqual(resuelta["nombre"], "Operación Aguaragüe")
        estado, lista = self.solicitar("GET", "/salas")
        self.assertEqual(estado, 200)
        self.assertEqual(lista["salas"][0]["codigo"], sala["codigo"])
        self.assertEqual(lista["salas"][0]["nombre"], "Operación Aguaragüe")

    def test_heartbeat_autenticado_y_expiracion_de_sala_vacia(self) -> None:
        sala = self.crear_por_http()
        token = self.directorio.salas[sala["codigo"]].token
        estado, _ = self.solicitar(
            "POST",
            f"/salas/{sala['codigo']}/heartbeat",
            {"token": token, "jugadores": 1},
        )
        self.assertEqual(estado, 200)
        estado, _ = self.solicitar(
            "POST",
            f"/salas/{sala['codigo']}/heartbeat",
            {"token": "token-incorrecto", "jugadores": 0},
        )
        self.assertEqual(estado, 403)
        estado, _ = self.solicitar(
            "POST",
            f"/salas/{sala['codigo']}/heartbeat",
            {"token": token, "jugadores": 0},
        )
        self.assertEqual(estado, 200)
        self.reloj[0] += 45
        estado, _ = self.solicitar(
            "POST",
            f"/salas/{sala['codigo']}/heartbeat",
            {"token": token, "jugadores": 0},
        )
        self.assertEqual(estado, 200)
        self.reloj[0] += 16
        estado, respuesta = self.solicitar("GET", f"/salas/{sala['codigo']}")
        self.assertEqual(estado, 404)
        self.assertIn("error", respuesta)
        self.assertTrue(self.procesos[0].terminado)

    def test_acepta_campo_pajoso_y_rechaza_escenario_no_disponible(self) -> None:
        estado, sala = self.solicitar(
            "POST",
            "/salas",
            {"escenario": "campo_pajoso", "dificultad": "media", "max_jugadores": 4},
        )
        self.assertEqual(estado, 201)
        self.assertEqual(sala["escenario"], "campo_pajoso")
        self.assertEqual(
            self.directorio.salas[sala["codigo"]].proceso.poll(),
            None,
        )

        estado, sala_urbana = self.solicitar(
            "POST",
            "/salas",
            {"escenario": "interfase_urbana", "dificultad": "media", "max_jugadores": 4},
        )
        self.assertEqual(estado, 201)
        self.assertEqual(sala_urbana["escenario"], "interfase_urbana")

        estado, respuesta = self.solicitar(
            "POST",
            "/salas",
            {"escenario": "escenario_inexistente", "dificultad": "media", "max_jugadores": 4},
        )
        self.assertEqual(estado, 400)
        self.assertIn("error", respuesta)

    def test_rechaza_directorio_lleno(self) -> None:
        self.crear_por_http()
        self.crear_por_http()
        estado, _ = self.solicitar("POST", "/salas", {"max_jugadores": 4})
        self.assertEqual(estado, 503)

    def test_lanza_binario_exportado_con_argumentos_de_usuario(self) -> None:
        self.directorio.crear_sala({"max_jugadores": 4})
        comando = self.comandos[0]
        self.assertEqual(
            comando[:4],
            ["godot", "--headless", "--path", str(Path(self.temp.name).resolve())],
        )
        self.assertIn("--server", comando)
        self.directorio.cerrar()

        comandos: list[list[str]] = []

        def crear_proceso(comando_exportado: list[str], **_kwargs: Any) -> ProcesoSimulado:
            comandos.append(comando_exportado)
            return ProcesoSimulado()

        directorio_exportado = DirectorioSalas(
            godot="godot",
            proyecto=Path(self.temp.name),
            rango_puertos=(self.directorio.puerto_inicio, self.directorio.puerto_fin),
            max_salas=1,
            carpeta_logs=Path(self.temp.name) / "logs-exportado",
            crear_proceso=crear_proceso,
            binario_juego="/opt/game/drone-server.x86_64",
        )
        directorio_exportado.crear_sala({"max_jugadores": 4})
        self.assertEqual(
            comandos[0][:4],
            ["/opt/game/drone-server.x86_64", "--headless", "--", "--server"],
        )
        self.assertTrue(any(argumento.startswith("--metrics-file=") for argumento in comandos[0]))
        directorio_exportado.cerrar()

    def test_registra_metricas_de_sala_en_csv_sin_duplicarlas(self) -> None:
        sala = self.directorio.crear_sala({"max_jugadores": 4})
        ruta_metricas = (
            self.directorio.carpeta_logs / f"metricas-sala-{sala['codigo']}.json"
        )
        ruta_metricas.write_text(
            json.dumps({
                "sample_id": 1,
                "sample_ms": 5000,
                "tick_ms_promedio": 16.7,
                "tick_ms_p95": 22.0,
                "tick_ms_max": 35.0,
                "jugadores": 4,
                "celdas_ardiendo": 12,
                "bytes_s_enviados": 4096,
                "bytes_s_por_jugador": 1024,
            }),
            encoding="utf-8",
        )
        self.directorio.registrar_metricas_csv()
        self.directorio.registrar_metricas_csv()

        with self.directorio.ruta_metricas_csv.open(newline="", encoding="utf-8") as archivo:
            filas = list(csv.DictReader(archivo))
        self.assertEqual(len(filas), 1)
        self.assertEqual(filas[0]["room_code"], sala["codigo"])
        self.assertEqual(filas[0]["tick_ms_p95"], "22.0")
        self.assertEqual(filas[0]["jugadores"], "4")
        self.assertEqual(filas[0]["sample_id"], "1")

    def test_maximo_de_salas_no_supera_el_rango_de_puertos(self) -> None:
        with self.assertRaisesRegex(ValueError, "cantidad de puertos"):
            DirectorioSalas(
                godot="godot",
                proyecto=Path(self.temp.name),
                rango_puertos=(9000, 9001),
                max_salas=3,
            )

    def test_contenido_malformado_se_rechaza_como_bad_request(self) -> None:
        conexion = HTTPConnection(self.host, self.puerto_http, timeout=2)
        conexion.request(
            "POST",
            "/salas",
            body=b"{",
            headers={"Content-Type": "application/json"},
        )
        respuesta = conexion.getresponse()
        contenido = json.loads(respuesta.read())
        conexion.close()
        self.assertEqual(respuesta.status, 400)
        self.assertIn("error", contenido)


if __name__ == "__main__":
    unittest.main()
