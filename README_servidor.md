# Servidor dedicado

El despliegue separa el endpoint HTTP público (`directorio`) del gestor de salas
(`servidor-partidas`). El segundo servicio ejecuta un proceso Linux headless por
sala y admite hasta ocho salas de forma predeterminada. El cliente usa WebSocket
por defecto, por lo que también se conserva el preset Web.

## Exportar y desplegar

Instala Godot 4.7 y sus plantillas de exportación. Desde la raíz del repositorio:

```powershell
pwsh -File scripts/tools/exportar.ps1 -Godot "C:\Godot\Godot_v4.7-stable_win64.exe"
```

En Linux:

```sh
GODOT_BIN=godot bash scripts/tools/exportar.sh
```

La imagen necesita `exports/linux-server/drone-server.x86_64`. Luego configura
`PUBLIC_GAME_HOST` con la IP o el nombre DNS que alcanzarán los clientes y
levanta los servicios:

```sh
docker compose -f infrastructure/game/docker-compose.yml up --build -d
```

Para un despliegue público, configura las variables en un archivo `.env` junto
al `docker-compose.yml`:

| Variable | Predeterminado | Uso |
| --- | --- | --- |
| `PUBLIC_GAME_HOST` | `127.0.0.1` | Host anunciado a los clientes en la respuesta del directorio. |
| `GAME_PORT_START` | `9000` | Primer puerto de partida. |
| `GAME_PORT_END` | `9007` | Último puerto de partida; el rango predeterminado admite ocho salas. |
| `MAX_ROOMS` | `8` | Máximo de procesos/salas simultáneos; no puede superar el rango de puertos. |
| `GAME_TRANSPORT` | `websocket` | Transporte de juego: `websocket` o `enet`. |
| `SERVER_CPU_LIMIT` | `2.0` | Límite de CPU del gestor de partidas. |
| `SERVER_MEMORY_LIMIT` | `2g` | Límite de memoria del gestor de partidas. |

El endpoint del directorio queda en `http://<host>:8080`. En la pestaña
multijugador, el cliente crea una sala en ese URL y se conecta al host/puerto
que devuelve el servicio.

## Puertos y transporte

- Publica TCP `8080` para el directorio HTTP.
- Para WebSocket, permite TCP en todo el rango `GAME_PORT_START`–`GAME_PORT_END`.
- Para ENet, permite UDP en el mismo rango. Compose publica TCP y UDP para que
  cualquiera de los dos transportes pueda seleccionarse.
- En un despliegue con firewall o NAT, configura `PUBLIC_GAME_HOST` con la
  dirección externa y reenvía los rangos correspondientes al host Docker.
- `ws://` no cifra tráfico. Para producción, termina TLS en un proxy HTTPS/WSS
  y configura el cliente para usar `wss://`.

El Dockerfile ejecuta el binario con usuario no root. La imagen incluye Python
únicamente para que el gestor del servicio `servidor-partidas` pueda lanzar y
supervisar los procesos por sala. Sus logs se conservan en el volumen Docker
`game-logs`.

## Logs y apagado

```sh
docker compose -f infrastructure/game/docker-compose.yml logs -f directorio servidor-partidas
docker compose -f infrastructure/game/docker-compose.yml exec servidor-partidas \
  sh -c 'tail -f /var/log/drone-game/sala-*.log'
docker compose -f infrastructure/game/docker-compose.yml down
```

El gestor elimina las salas vacías vencidas y termina los procesos hijos al
cerrarse el contenedor. Los límites de salas y recursos se pueden ajustar con
las variables de entorno anteriores.
