# Directorio de salas

El directorio usa `http.server` de la biblioteca estándar de Python para no añadir dependencias de terceros ni requerir un entorno virtual. El servicio reserva un puerto y lanza una instancia dedicada de Godot por sala; el código de cuatro dígitos se resuelve mediante HTTP antes de que el cliente conecte al transporte de juego.

## Requisitos y ejecución

- Python 3.10 o posterior.
- Godot 4.x disponible como `godot` en `PATH`, o una ruta configurada en `GODOT_BIN`.
- Para lanzar binarios empaquetados, exporta el preset Linux Server y pasa su ruta a `--game-binary` o `GAME_SERVER_BIN`.

Desde la raíz del proyecto:

```powershell
python server\directorio\directorio.py --host 0.0.0.0 --port 8080 --game-host 127.0.0.1 --game-port-start 9000 --game-port-end 9100
```

En una red local o en un servidor público, cambia `--game-host` por una dirección que los clientes puedan alcanzar. Abre el puerto HTTP del directorio y el rango de puertos de juego en el firewall. WebSocket es el transporte predeterminado; se puede seleccionar ENet con `--transport enet` si los clientes también están configurados para ENet. ENet requiere permitir tráfico UDP en el rango de puertos.

Con `--game-binary`, el directorio inicia una sala como proceso headless exportado, pasando `--server` y el resto de argumentos de juego después del separador `--` de Godot. `--max-rooms` no puede ser mayor que la cantidad de puertos disponibles.

El directorio agrega cada cinco segundos las métricas de los procesos de sala en `servidor_metricas.csv` dentro de `--logs` (por defecto `logs/`). Cada proceso publica una instantánea JSON privada para que el directorio mida también su CPU y RAM sin que varios servidores escriban concurrentemente el CSV.

Argumentos configurables:

- `--host`, `--port`: interfaz y puerto HTTP del directorio.
- `--game-host`, `--game-port-start`, `--game-port-end`: dirección anunciada y rango de puertos de partidas.
- `--max-rooms`: máximo de partidas simultáneas.
- `--game-binary`: ejecutable Linux exportado por sala; si se omite, se usa Godot con el proyecto.
- `--godot`, `--project`, `--logs`: ejecutable, proyecto Godot y ubicación de logs.
- `--transport websocket|enet`: transporte de las partidas lanzadas.

## API

- `POST /salas` con `{"nombre":"Operación","escenario":"interfase_urbana","dificultad":"media","max_jugadores":4}` crea una sala y responde con nombre, código, host, puerto y transporte. El nombre es opcional y admite hasta 40 caracteres. Los escenarios disponibles son `aguarague`, `campo_pajoso` e `interfase_urbana`.
- `GET /salas` lista las salas abiertas.
- `GET /salas/{codigo}` resuelve el código a host y puerto.
- `GET /health` comprueba que el servicio está activo.

Los procesos dedicados usan `POST /salas/{codigo}/heartbeat` cada cinco segundos y `POST /salas/{codigo}/terminar` al concluir la misión. Ambos endpoints internos requieren el token aleatorio entregado únicamente al proceso de juego. Una sala vacía se elimina tras 60 segundos; los procesos terminados se limpian automáticamente.

## Seguridad de despliegue

Este servicio mínimo no implementa autenticación para crear salas, límites por IP ni TLS. No lo expongas directamente a Internet sin ponerlo detrás de un proxy con HTTPS y controles de acceso/rate limiting. El token de heartbeat no se devuelve a los clientes.

## Pruebas

```powershell
python -m unittest discover -s server\directorio -p "test_*.py" -v
```
