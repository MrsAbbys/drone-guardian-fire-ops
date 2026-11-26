extends Node

signal jugador_conectado(id: int, datos: Dictionary)
signal jugador_desconectado(id: int)
signal conexion_fallida(motivo: String)
signal sala_actualizada(codigo: String, jugadores_sala: Dictionary)
signal rol_rechazado(motivo: String)
signal estado_fuego_recibido(deltas: Array, inicial: bool)
signal estado_dron_recibido(id: int, estado: Dictionary)
signal chat_recibido(nombre: String, texto: String)
signal metricas_red_actualizadas(bytes_por_jugador: Dictionary)
signal objetivo_critico_recibido(datos: Dictionary)
signal objetivos_criticos_finales_recibidos(resumen: Array, puntaje: int, bono: int)
signal ping_tactico_recibido(tipo: String, posicion: Vector3, emisor_id: int)
signal evento_tactico_recibido(texto: String)
signal marcador_final_recibido(resultados: Array)

const CANAL_CONTROL: int = 0
const CANAL_FUEGO: int = 1
const CANAL_DRONES: int = 2
const PUERTO_PREDETERMINADO: int = 8910
const ESCENAS: Dictionary = {
	"aguarague": "res://scenes/levels/escena_aguarague.tscn",
	"campo_pajoso": "res://scenes/levels/escena_campo_pajoso.tscn",
	"interfase_urbana": "res://scenes/levels/escena_interfase_urbana.tscn",
	"yacuiba": "res://scenes/gameplay/mission_01_yacuiba.tscn",
}
const ESCENA_DRON: String = "res://scenes/gameplay/drone_player.tscn"
const ROLES_DRON: Dictionary = {
	"cisterna": "res://data/roles/cisterna.tres",
	"explorador": "res://data/roles/explorador.tres",
	"tactico": "res://data/roles/tactico.tres",
}
const INTERVALO_SNAPSHOT_FUEGO: float = 3.0
const INTERVALO_METRICAS_RED: float = 1.0
const INTERVALO_METRICAS_DRON: float = 0.05

@export_enum("WebSocket", "ENet") var transporte: String = "WebSocket"

var nombre_local: String = "Piloto"
var rol_dron_local: String = "explorador"
var codigo_sala: String = ""
var jugadores: Dictionary = {}
var configuracion_sala: Dictionary = {}
var partida_iniciada: bool = false
var anfitrion_id: int = 0

var _servidor_dedicado: bool = false
var _codigo_esperado: String = ""
var _nombre_anfitrion: String = ""
var _puerto_sala: int = PUERTO_PREDETERMINADO
var _url_directorio: String = ""
var _token_directorio: String = ""
var _nombres_reservados: Dictionary = {}
var _marcas_ping: Dictionary = {}
var _marcas_chat: Dictionary = {}
var _clientes_listos: Dictionary = {}
var _drones_por_id: Dictionary = {}
var _spawner: MultiplayerSpawner
var _temporizador_ping: Timer
var _temporizador_conexion: Timer
var _temporizador_directorio: Timer
var _temporizador_snapshot_fuego: Timer
var _http_directorio: HTTPRequest
var _aviso_directorio_ms: int = 0
var _directorio_finalizado: bool = false
var _secuencia_fuego: int = 0
var _ultima_secuencia_fuego: int = 0
var _snapshot_solicitado: bool = false
var _bytes_en_ventana: Dictionary = {}
var _bytes_por_jugador: Dictionary = {}
var _ultimo_estado_sync_drones: Dictionary = {}
var _estadisticas_jugadores: Dictionary = {}
var _colaboradores_por_celda: Dictionary = {}
var _marcador_final_enviado: bool = false
var _acumulador_metricas: float = 0.0
var _acumulador_estimacion_drones: float = 0.0
var _acumulador_snapshot_drones: float = 0.0
var _acumulador_transform_sync: float = 0.0

func _ready() -> void:
	multiplayer.connected_to_server.connect(_al_conectar_servidor)
	multiplayer.connection_failed.connect(_al_fallar_conexion)
	multiplayer.server_disconnected.connect(_al_desconectar_servidor)
	multiplayer.peer_disconnected.connect(_al_desconectar_jugador)
	get_tree().scene_changed.connect(_al_cambiar_escena)
	conexion_fallida.connect(_registrar_fallo)
	FireGridServer.celdas_modificadas.connect(_al_modificarse_celdas_de_fuego)
	FireGridServer.estado_inicial.connect(_al_estado_inicial_de_fuego)
	FireGridServer.objetivo_critico_amenazado.connect(_al_objetivo_critico_amenazado)
	FireGridServer.objetivo_critico_perdido.connect(_al_objetivo_critico_perdido)
	FireGridServer.objetivos_criticos_actualizados.connect(_al_objetivos_criticos_actualizados)
	FireGridServer.agua_aplicada_por_jugador.connect(_al_aplicar_agua_atribuida)
	set_process(true)

	_temporizador_ping = Timer.new()
	_temporizador_ping.name = "TemporizadorPingRed"
	_temporizador_ping.wait_time = 2.0
	_temporizador_ping.timeout.connect(_medir_ping)
	add_child(_temporizador_ping)

	_temporizador_conexion = Timer.new()
	_temporizador_conexion.name = "TemporizadorConexionSala"
	_temporizador_conexion.wait_time = 12.0
	_temporizador_conexion.one_shot = true
	_temporizador_conexion.timeout.connect(_al_expirar_conexion)
	add_child(_temporizador_conexion)

	_temporizador_directorio = Timer.new()
	_temporizador_directorio.name = "TemporizadorDirectorio"
	_temporizador_directorio.wait_time = 5.0
	_temporizador_directorio.timeout.connect(_enviar_latido_directorio)
	add_child(_temporizador_directorio)

	_http_directorio = HTTPRequest.new()
	_http_directorio.name = "SolicitudDirectorio"
	_http_directorio.timeout = 4.0
	_http_directorio.request_completed.connect(_al_completar_latido_directorio)
	add_child(_http_directorio)

	_temporizador_snapshot_fuego = Timer.new()
	_temporizador_snapshot_fuego.name = "TemporizadorSnapshotFuego"
	_temporizador_snapshot_fuego.wait_time = INTERVALO_SNAPSHOT_FUEGO
	_temporizador_snapshot_fuego.timeout.connect(_enviar_snapshot_fuego_a_todos)
	add_child(_temporizador_snapshot_fuego)

	_procesar_argumentos_usuario(OS.get_cmdline_user_args())

func _process(delta: float) -> void:
	if not multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		return
	_acumulador_estimacion_drones += delta
	while _acumulador_estimacion_drones >= INTERVALO_METRICAS_DRON:
		_acumulador_estimacion_drones -= INTERVALO_METRICAS_DRON
		_estimar_bytes_sincronizacion_drones()
		_acumulador_snapshot_drones += INTERVALO_METRICAS_DRON
		if _acumulador_snapshot_drones >= INTERVALO_METRICAS_DRON:
			_acumulador_snapshot_drones = 0.0
			_enviar_snapshots_drones()
		_acumulador_transform_sync += INTERVALO_METRICAS_DRON
		if _acumulador_transform_sync >= 0.2:
			_acumulador_transform_sync = 0.0
			_estimar_bytes_transform_sync()
	_acumulador_metricas += delta
	if _acumulador_metricas < INTERVALO_METRICAS_RED:
		return
	var intervalo := _acumulador_metricas
	_acumulador_metricas = 0.0
	_actualizar_bytes_por_segundo(intervalo)

func crear_sala(config: Dictionary) -> bool:
	if not _validar_configuracion_sala(config):
		return false
	salir()

	var config_nueva := config.duplicate(true)
	_puerto_sala = int(config_nueva.get("puerto", _puerto_sala))
	var max_jugadores := int(config_nueva.get("max_jugadores", 6))
	var codigo := str(config_nueva.get("codigo", "")).strip_edges()
	if codigo.is_empty():
		codigo = _crear_codigo_sala()
	config_nueva["max_jugadores"] = max_jugadores
	config_nueva["codigo"] = codigo
	config_nueva["escenario"] = _normalizar_escenario(str(config_nueva.get("escenario", "aguarague")))
	config_nueva["dificultad"] = str(config_nueva.get("dificultad", "media")).to_lower()

	var peer_servidor: MultiplayerPeer
	if _usar_enet():
		var peer_enet := ENetMultiplayerPeer.new()
		var error_enet := peer_enet.create_server(_puerto_sala, max_jugadores, 3)
		if error_enet != OK:
			conexion_fallida.emit("No se pudo iniciar ENet (error %d)." % error_enet)
			return false
		peer_servidor = peer_enet
	else:
		var peer_websocket := WebSocketMultiplayerPeer.new()
		var error_websocket := peer_websocket.create_server(_puerto_sala)
		if error_websocket != OK:
			conexion_fallida.emit("No se pudo iniciar WebSocket (error %d)." % error_websocket)
			return false
		peer_servidor = peer_websocket

	configuracion_sala = config_nueva
	codigo_sala = codigo
	_codigo_esperado = codigo
	_servidor_dedicado = bool(config.get("servidor_dedicado", false))
	_url_directorio = str(config.get("url_directorio", "")).trim_suffix("/")
	_token_directorio = str(config.get("token_directorio", ""))
	_directorio_finalizado = false
	partida_iniciada = false
	anfitrion_id = 0
	_nombre_anfitrion = ""
	jugadores.clear()
	_nombres_reservados.clear()
	_clientes_listos.clear()
	multiplayer.multiplayer_peer = peer_servidor
	_temporizador_ping.start()
	_temporizador_snapshot_fuego.start()
	_estadisticas_jugadores.clear()
	_colaboradores_por_celda.clear()
	_marcador_final_enviado = false

	if not _servidor_dedicado:
		nombre_local = _normalizar_nombre(nombre_local)
		if nombre_local.is_empty():
			nombre_local = "Piloto"
		var datos_locales := _crear_datos_jugador(nombre_local, 1)
		datos_locales["rol"] = "anfitrion"
		jugadores[1] = datos_locales
		_asegurar_estadisticas_jugador(1)
		_nombres_reservados[nombre_local] = datos_locales.duplicate(true)
		anfitrion_id = 1
		_nombre_anfitrion = nombre_local
		jugador_conectado.emit(1, datos_locales.duplicate(true))
	if _servidor_dedicado and not _url_directorio.is_empty() and not _token_directorio.is_empty():
		_temporizador_directorio.start()
		_enviar_latido_directorio()
	_publicar_sala()
	print("NetworkManager: sala %s abierta en puerto %d (%s)." % [codigo_sala, _puerto_sala, transporte])
	return true

func unirse_a_sala(direccion: String, puerto: int, codigo: String) -> bool:
	var direccion_limpia := direccion.strip_edges()
	var codigo_limpio := codigo.strip_edges()
	if direccion_limpia.is_empty() or puerto < 1 or puerto > 65535 or codigo_limpio.is_empty():
		conexion_fallida.emit("Dirección, puerto o código de sala inválido.")
		return false
	salir()

	_codigo_esperado = codigo_limpio
	codigo_sala = ""
	_puerto_sala = puerto
	jugadores.clear()
	configuracion_sala.clear()
	partida_iniciada = false
	_servidor_dedicado = false

	var peer_cliente: MultiplayerPeer
	if _usar_enet():
		var peer_enet := ENetMultiplayerPeer.new()
		var error_enet := peer_enet.create_client(direccion_limpia, puerto, 3)
		if error_enet != OK:
			conexion_fallida.emit("No se pudo iniciar el cliente ENet (error %d)." % error_enet)
			return false
		peer_cliente = peer_enet
	else:
		var peer_websocket := WebSocketMultiplayerPeer.new()
		var protocolo := "wss" if direccion_limpia.begins_with("wss://") else "ws"
		var host := direccion_limpia.trim_prefix("wss://").trim_prefix("ws://").trim_suffix("/")
		if host.is_empty():
			conexion_fallida.emit("La dirección WebSocket no contiene un servidor.")
			return false
		var url := "%s://%s:%d" % [protocolo, host, puerto]
		var error_websocket := peer_websocket.create_client(url)
		if error_websocket != OK:
			conexion_fallida.emit("No se pudo iniciar el cliente WebSocket (error %d)." % error_websocket)
			return false
		peer_cliente = peer_websocket

	multiplayer.multiplayer_peer = peer_cliente
	_temporizador_conexion.start()
	print("NetworkManager: conectando a %s:%d (sala %s)." % [direccion_limpia, puerto, codigo_limpio])
	return true

func iniciar_partida() -> bool:
	if not multiplayer.has_multiplayer_peer() or codigo_sala.is_empty():
		conexion_fallida.emit("No hay una sala activa.")
		return false
	if not multiplayer.is_server():
		if not es_anfitrion_local():
			conexion_fallida.emit("Solo el anfitrión puede iniciar la partida.")
			return false
		rpc_id(1, "_rpc_solicitar_inicio")
		return true
	return _iniciar_partida_servidor()

func _iniciar_partida_servidor() -> bool:
	if partida_iniciada:
		return true
	var escenario := str(configuracion_sala.get("escenario", "aguarague"))
	if not ESCENAS.has(escenario):
		conexion_fallida.emit("El escenario solicitado no está disponible.")
		return false
	partida_iniciada = true
	_publicar_sala()
	rpc("_rpc_iniciar_escenario", escenario)
	var tamanio_rpc := var_to_bytes(escenario).size() + 8
	for peer_id in multiplayer.get_peers():
		_registrar_bytes_enviados(peer_id, tamanio_rpc)
	_cargar_escenario_local(escenario)
	return true

func es_anfitrion_local() -> bool:
	return (
		multiplayer.has_multiplayer_peer()
		and anfitrion_id > 0
		and multiplayer.get_unique_id() == anfitrion_id
	)

func establecer_listo(listo: bool) -> bool:
	if not multiplayer.has_multiplayer_peer() or codigo_sala.is_empty():
		return false
	if multiplayer.is_server():
		return _actualizar_estado_listo(multiplayer.get_unique_id(), listo)
	rpc_id(1, "_rpc_solicitar_listo", listo)
	return true

func seleccionar_rol_dron(rol_id: String) -> bool:
	var rol_normalizado := rol_id.strip_edges().to_lower()
	if not ROLES_DRON.has(rol_normalizado):
		rol_rechazado.emit("El rol de dron solicitado no existe.")
		return false
	rol_dron_local = rol_normalizado
	if not multiplayer.has_multiplayer_peer() or codigo_sala.is_empty():
		return true
	if multiplayer.is_server():
		return _actualizar_rol_dron(multiplayer.get_unique_id(), rol_normalizado)
	rpc_id(1, "_rpc_solicitar_rol_dron", rol_normalizado)
	return true

@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_solicitar_rol_dron(rol_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	_actualizar_rol_dron(peer_id, rol_id.strip_edges().to_lower())

func _actualizar_rol_dron(peer_id: int, rol_id: String) -> bool:
	if not multiplayer.is_server() or not jugadores.has(peer_id):
		return false
	if partida_iniciada:
		_rechazar_rol(peer_id, "Los roles no se pueden cambiar después de iniciar la misión.")
		return false
	if not ROLES_DRON.has(rol_id):
		_rechazar_rol(peer_id, "El rol de dron solicitado no existe.")
		return false
	if rol_id == "tactico" and _tactico_ocupado(peer_id):
		_rechazar_rol(peer_id, "El rol Táctico ya está ocupado.")
		return false
	var datos: Dictionary = jugadores[peer_id]
	datos["rol_dron"] = rol_id
	jugadores[peer_id] = datos
	_nombres_reservados[str(datos.get("nombre", ""))] = datos.duplicate(true)
	if peer_id == multiplayer.get_unique_id():
		rol_dron_local = rol_id
	_publicar_sala()
	return true

func _tactico_ocupado(excluir_peer_id: int = -1) -> bool:
	for id_variant in jugadores.keys():
		var id := int(id_variant)
		if id == excluir_peer_id:
			continue
		var datos: Dictionary = jugadores[id]
		if str(datos.get("rol_dron", "")) == "tactico":
			return true
	return false

func _rechazar_rol(peer_id: int, motivo: String) -> void:
	if peer_id == multiplayer.get_unique_id():
		var jugador_local: Dictionary = jugadores.get(peer_id, {})
		if not jugador_local.is_empty():
			rol_dron_local = str(jugador_local.get("rol_dron", "explorador"))
		rol_rechazado.emit(motivo)
	elif peer_id > 1:
		rpc_id(peer_id, "_rpc_rol_rechazado", motivo)

@rpc("authority", "call_remote", "reliable", 0)
func _rpc_rol_rechazado(motivo: String) -> void:
	var jugador_local: Dictionary = jugadores.get(multiplayer.get_unique_id(), {})
	if not jugador_local.is_empty():
		rol_dron_local = str(jugador_local.get("rol_dron", "explorador"))
	rol_rechazado.emit(motivo)

func enviar_chat(texto: String) -> bool:
	var mensaje := texto.strip_edges()
	if mensaje.is_empty() or mensaje.length() > 160 or codigo_sala.is_empty():
		return false
	if multiplayer.is_server():
		var id_local := multiplayer.get_unique_id()
		if not jugadores.has(id_local):
			return false
		_publicar_chat(str(jugadores[id_local].get("nombre", nombre_local)), mensaje)
		return true
	rpc_id(1, "_rpc_solicitar_chat", mensaje)
	return true

func _registrar_fallo(motivo: String) -> void:
	push_warning("NetworkManager: %s" % motivo)

func _al_expirar_conexion() -> void:
	if not multiplayer.is_server() and codigo_sala.is_empty():
		conexion_fallida.emit("Tiempo de espera agotado al conectar con la sala.")
		salir()

func salir() -> void:
	_temporizador_ping.stop()
	_temporizador_conexion.stop()
	_temporizador_directorio.stop()
	_temporizador_snapshot_fuego.stop()
	var ids: Array = jugadores.keys()
	for id in ids:
		if int(id) != 1:
			jugador_desconectado.emit(int(id))
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	codigo_sala = ""
	_codigo_esperado = ""
	jugadores.clear()
	configuracion_sala.clear()
	_nombres_reservados.clear()
	_marcas_ping.clear()
	_marcas_chat.clear()
	_clientes_listos.clear()
	_drones_por_id.clear()
	_bytes_en_ventana.clear()
	_bytes_por_jugador.clear()
	_ultimo_estado_sync_drones.clear()
	_estadisticas_jugadores.clear()
	_colaboradores_por_celda.clear()
	_marcador_final_enviado = false
	_secuencia_fuego = 0
	_ultima_secuencia_fuego = 0
	_snapshot_solicitado = false
	anfitrion_id = 0
	_nombre_anfitrion = ""
	_url_directorio = ""
	_token_directorio = ""
	partida_iniciada = false
	_servidor_dedicado = false
	sala_actualizada.emit(codigo_sala, jugadores)
	metricas_red_actualizadas.emit(_bytes_por_jugador)

func reiniciar_estadisticas_mision() -> void:
	_estadisticas_jugadores.clear()
	_colaboradores_por_celda.clear()
	_marcador_final_enviado = false

func publicar_estado_fuego(deltas: Array, inicial: bool = false) -> void:
	if not multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		return
	rpc("_rpc_estado_fuego", deltas, inicial)

func publicar_estado_dron(id: int, estado: Dictionary) -> void:
	if not multiplayer.is_server() or not jugadores.has(id):
		return
	rpc("_rpc_estado_dron", id, estado)

func notificar_pulso_termico(peer_id: int, alcance: float, duracion: float) -> void:
	if not multiplayer.is_server() or not jugadores.has(peer_id):
		return
	if peer_id == multiplayer.get_unique_id():
		_aplicar_pulso_termico_local(alcance, duracion)
	else:
		rpc_id(peer_id, "_rpc_activar_vision_termica", alcance, duracion)

@rpc("authority", "call_remote", "reliable", 0)
func _rpc_activar_vision_termica(alcance: float, duracion: float) -> void:
	_aplicar_pulso_termico_local(alcance, duracion)

func _aplicar_pulso_termico_local(alcance: float, duracion: float) -> void:
	var dron := _obtener_dron_local()
	if is_instance_valid(dron) and dron.has_method("activar_vision_termica_local"):
		dron.call("activar_vision_termica_local", alcance, duracion)

func difundir_marca_objetivo(posicion: Vector3, nombre_piloto: String, duracion: float) -> void:
	if not multiplayer.is_server():
		return
	_mostrar_marca_objetivo_local(posicion, nombre_piloto, duracion)
	rpc("_rpc_mostrar_marca_objetivo", posicion, nombre_piloto, duracion)
	var tamanio := var_to_bytes([posicion, nombre_piloto, duracion]).size() + 8
	for peer_id in multiplayer.get_peers():
		_registrar_bytes_enviados(peer_id, tamanio)

@rpc("authority", "call_remote", "reliable", 0)
func _rpc_mostrar_marca_objetivo(posicion: Vector3, nombre_piloto: String, duracion: float) -> void:
	_mostrar_marca_objetivo_local(posicion, nombre_piloto, duracion)

func _mostrar_marca_objetivo_local(
	posicion: Vector3,
	nombre_piloto: String,
	duracion: float
) -> void:
	var dron := _obtener_dron_local()
	if is_instance_valid(dron) and dron.has_method("mostrar_marca_objetivo_local"):
		dron.call("mostrar_marca_objetivo_local", posicion, nombre_piloto, duracion)

func _obtener_dron_local() -> Node:
	var dron: Variant = _drones_por_id.get(multiplayer.get_unique_id())
	if is_instance_valid(dron):
		return dron as Node
	for candidato in get_tree().get_nodes_in_group("jugador"):
		if candidato is Node and candidato.is_multiplayer_authority():
			return candidato
	return null

func _validar_configuracion_sala(config: Dictionary) -> bool:
	var max_jugadores := int(config.get("max_jugadores", 6))
	if max_jugadores < 2 or max_jugadores > 6:
		conexion_fallida.emit("La sala debe admitir entre 2 y 6 jugadores.")
		return false
	if _normalizar_escenario(str(config.get("escenario", "aguarague"))).is_empty():
		conexion_fallida.emit("El escenario solicitado no está disponible.")
		return false
	var puerto := int(config.get("puerto", _puerto_sala))
	if puerto < 1 or puerto > 65535:
		conexion_fallida.emit("El puerto debe estar entre 1 y 65535.")
		return false
	var codigo := str(config.get("codigo", "")).strip_edges()
	if not codigo.is_empty() and not _codigo_valido(codigo):
		conexion_fallida.emit("El código de sala solo puede contener letras y números (3 a 12 caracteres).")
		return false
	return true

func _al_conectar_servidor() -> void:
	_temporizador_conexion.start()
	var nombre := _normalizar_nombre(nombre_local)
	if nombre.is_empty():
		nombre = "Piloto"
	nombre_local = nombre
	print("NetworkManager: solicitando ingreso a la sala %s." % _codigo_esperado)
	rpc_id(1, "_rpc_solicitar_ingreso", _codigo_esperado, nombre, rol_dron_local)

func _al_fallar_conexion() -> void:
	_temporizador_conexion.stop()
	conexion_fallida.emit("No se pudo establecer conexión con la sala.")
	salir()

func _al_desconectar_servidor() -> void:
	_temporizador_conexion.stop()
	conexion_fallida.emit("Se perdió la conexión con el servidor.")
	salir()

func _al_desconectar_jugador(id: int) -> void:
	_marcas_ping.erase(id)
	_marcas_chat.erase(id)
	_clientes_listos.erase(id)
	_bytes_en_ventana.erase(id)
	_bytes_por_jugador.erase(id)
	if not jugadores.has(id):
		return
	var datos: Dictionary = jugadores[id]
	var nombre := str(datos.get("nombre", ""))
	if not nombre.is_empty():
		_nombres_reservados[nombre] = datos.duplicate(true)
	jugadores.erase(id)
	_despawnear_dron(id)
	if id == anfitrion_id:
		anfitrion_id = 0
		if not partida_iniciada and not jugadores.is_empty():
			var nuevo_anfitrion_id := int(jugadores.keys()[0])
			var nuevo_anfitrion: Dictionary = jugadores[nuevo_anfitrion_id]
			nuevo_anfitrion["rol"] = "anfitrion"
			jugadores[nuevo_anfitrion_id] = nuevo_anfitrion
			anfitrion_id = nuevo_anfitrion_id
			_nombre_anfitrion = str(nuevo_anfitrion.get("nombre", ""))
	jugador_desconectado.emit(id)
	if multiplayer.is_server():
		_publicar_sala()

func _medir_ping() -> void:
	if not multiplayer.is_server():
		return
	for id_variant in jugadores.keys():
		var id := int(id_variant)
		if id == 1:
			continue
		var marca := Time.get_ticks_msec()
		_marcas_ping[id] = marca
		rpc_id(id, "_rpc_solicitar_ping", marca)
		_registrar_bytes_enviados(id, var_to_bytes(marca).size() + 8)

@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_solicitar_ingreso(
	codigo: String,
	nombre_recibido: String,
	rol_dron_recibido: String
) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var nombre := _normalizar_nombre(nombre_recibido)
	var codigo_coincide := not codigo_sala.is_empty() and codigo == codigo_sala
	var reconexion := _nombres_reservados.has(nombre) and not _nombre_en_linea(nombre)
	var razon := ""
	if nombre.is_empty():
		razon = "El nombre de jugador no es válido."
	elif not codigo_coincide:
		razon = "El código de sala no coincide."
	elif _nombre_en_linea(nombre):
		razon = "Ese nombre ya está conectado."
	elif partida_iniciada and not reconexion:
		razon = "La partida ya empezó; solo se permite reconectar con el mismo nombre."
	elif _contar_jugadores_conectados() >= int(configuracion_sala.get("max_jugadores", 6)):
		razon = "La sala está llena."
	if not razon.is_empty():
		push_warning("NetworkManager rechazó al jugador %s: %s" % [nombre, razon])
		_rechazar_cliente(peer_id, razon)
		return

	var datos: Dictionary
	if reconexion:
		datos = _nombres_reservados[nombre].duplicate(true)
		datos["ping"] = 0
	else:
		datos = _crear_datos_jugador(nombre, jugadores.size() + 1)
		var rol_solicitado := rol_dron_recibido.strip_edges().to_lower()
		if not ROLES_DRON.has(rol_solicitado) or (rol_solicitado == "tactico" and _tactico_ocupado()):
			rol_solicitado = "explorador"
		datos["rol_dron"] = rol_solicitado
	if str(datos.get("rol_dron", "")) == "tactico" and _tactico_ocupado():
		datos["rol_dron"] = "explorador"
	datos["rol"] = "piloto"
	if _nombre_anfitrion.is_empty() and not partida_iniciada:
		_nombre_anfitrion = nombre
		anfitrion_id = peer_id
		datos["rol"] = "anfitrion"
	elif nombre == _nombre_anfitrion:
		anfitrion_id = peer_id
		datos["rol"] = "anfitrion"
	jugadores[peer_id] = datos
	_asegurar_estadisticas_jugador(peer_id)
	_nombres_reservados[nombre] = datos.duplicate(true)
	print("NetworkManager: jugador conectado id=%d nombre=%s." % [peer_id, nombre])
	jugador_conectado.emit(peer_id, datos.duplicate(true))
	_publicar_sala()
	if partida_iniciada:
		rpc_id(peer_id, "_rpc_iniciar_escenario", str(configuracion_sala.get("escenario", "aguarague")))

@rpc("authority", "call_remote", "reliable", 0)
func _rpc_ingreso_rechazado(motivo: String) -> void:
	conexion_fallida.emit(motivo)
	salir()

@rpc("authority", "call_remote", "reliable", 0)
func _rpc_actualizar_sala(
	codigo: String,
	jugadores_recibidos: Dictionary,
	configuracion_recibida: Dictionary,
	partida_activa: bool,
	anfitrion_recibido: int
) -> void:
	var anteriores: Dictionary = jugadores
	jugadores = jugadores_recibidos.duplicate(true)
	codigo_sala = codigo
	configuracion_sala = configuracion_recibida.duplicate(true)
	partida_iniciada = partida_activa
	anfitrion_id = anfitrion_recibido
	if not multiplayer.is_server():
		_temporizador_conexion.stop()
	for id_variant in jugadores.keys():
		var id := int(id_variant)
		var datos: Dictionary = jugadores[id]
		if id == anfitrion_id:
			datos["rol"] = "anfitrion"
		elif str(datos.get("rol", "")) == "anfitrion":
			datos["rol"] = "piloto"
		jugadores[id] = datos
	var jugador_local: Dictionary = jugadores.get(multiplayer.get_unique_id(), {})
	if not jugador_local.is_empty():
		rol_dron_local = str(jugador_local.get("rol_dron", "explorador"))
	var ids_anteriores: Array = anteriores.keys()
	var ids_actuales: Array = jugadores.keys()
	ids_anteriores.sort()
	ids_actuales.sort()
	if ids_anteriores != ids_actuales:
		var nombres: PackedStringArray = PackedStringArray()
		for datos_variant in jugadores.values():
			var datos: Dictionary = datos_variant
			nombres.append(str(datos.get("nombre", "Piloto")))
		print("NetworkManager: sala %s; pilotos: %s." % [codigo_sala, ", ".join(nombres)])
	for id_variant in jugadores.keys():
		var id := int(id_variant)
		if not anteriores.has(id):
			jugador_conectado.emit(id, jugadores[id].duplicate(true))
	for id_variant in anteriores.keys():
		var id := int(id_variant)
		if not jugadores.has(id):
			jugador_desconectado.emit(id)
	sala_actualizada.emit(codigo_sala, jugadores.duplicate(true))

@rpc("authority", "call_remote", "reliable", 0)
func _rpc_iniciar_escenario(escenario: String) -> void:
	partida_iniciada = true
	_cargar_escenario_local(escenario)

@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_cliente_listo() -> void:
	if not multiplayer.is_server() or not partida_iniciada:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if jugadores.has(peer_id):
		_clientes_listos[peer_id] = true
		if is_instance_valid(_spawner):
			_instanciar_dron_jugador(peer_id)
		_enviar_snapshot_fuego(peer_id)

@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_solicitar_inicio() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id != anfitrion_id:
		push_warning("NetworkManager ignoró una solicitud de inicio de un jugador que no es el anfitrión.")
		return
	_iniciar_partida_servidor()

@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_solicitar_listo(listo: bool) -> void:
	if not multiplayer.is_server():
		return
	_actualizar_estado_listo(multiplayer.get_remote_sender_id(), listo)

@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_solicitar_chat(texto: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var mensaje := texto.strip_edges()
	if not jugadores.has(peer_id) or mensaje.is_empty() or mensaje.length() > 160:
		return
	var ahora := Time.get_ticks_msec()
	if _marcas_chat.has(peer_id) and ahora - int(_marcas_chat[peer_id]) < 700:
		return
	_marcas_chat[peer_id] = ahora
	var datos: Dictionary = jugadores[peer_id]
	_publicar_chat(str(datos.get("nombre", "Piloto")), mensaje)

@rpc("authority", "call_remote", "reliable", 0)
func _rpc_recibir_chat(nombre: String, texto: String) -> void:
	chat_recibido.emit(nombre, texto)

@rpc("authority", "call_remote", "reliable", 0)
func _rpc_solicitar_ping(marca_servidor_ms: int) -> void:
	rpc_id(1, "_rpc_responder_ping", marca_servidor_ms)

@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_responder_ping(marca_servidor_ms: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not jugadores.has(peer_id) or not _marcas_ping.has(peer_id):
		return
	if int(_marcas_ping[peer_id]) != marca_servidor_ms:
		return
	var datos: Dictionary = jugadores[peer_id]
	datos["ping"] = maxi(Time.get_ticks_msec() - marca_servidor_ms, 0)
	jugadores[peer_id] = datos
	_publicar_sala()

@rpc("authority", "call_remote", "reliable", 1)
func _rpc_estado_fuego(deltas: Array, inicial: bool) -> void:
	estado_fuego_recibido.emit(deltas, inicial)

@rpc("authority", "call_remote", "reliable", 1)
func sincronizar_deltas(secuencia: int, deltas: PackedInt32Array) -> void:
	if multiplayer.is_server():
		return
	if secuencia != _ultima_secuencia_fuego + 1:
		if not _snapshot_solicitado:
			_snapshot_solicitado = true
			rpc_id(1, "_rpc_solicitar_snapshot_fuego", _ultima_secuencia_fuego)
		return
	if not FireGridServer.aplicar_deltas_remotos(deltas):
		if not _snapshot_solicitado:
			_snapshot_solicitado = true
			rpc_id(1, "_rpc_solicitar_snapshot_fuego", _ultima_secuencia_fuego)
		return
	_ultima_secuencia_fuego = secuencia

@rpc("any_peer", "call_remote", "reliable", 1)
func _rpc_solicitar_snapshot_fuego(_secuencia_recibida: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not jugadores.has(peer_id):
		return
	_enviar_snapshot_fuego(peer_id)

@rpc("authority", "call_remote", "reliable", 1)
func _rpc_snapshot_fuego(secuencia: int, datos_comprimidos: PackedByteArray) -> void:
	if multiplayer.is_server():
		return
	if not FireGridServer.aplicar_snapshot_comprimido(datos_comprimidos):
		return
	_ultima_secuencia_fuego = secuencia
	_snapshot_solicitado = false

@rpc("authority", "call_remote", "reliable", 0)
func _rpc_actualizar_metricas_red(bytes_por_jugador: Dictionary) -> void:
	_bytes_por_jugador = bytes_por_jugador.duplicate(true)
	metricas_red_actualizadas.emit(_bytes_por_jugador.duplicate(true))

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _rpc_estado_dron(id: int, estado: Dictionary) -> void:
	estado_dron_recibido.emit(id, estado.duplicate(true))

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _rpc_snapshot_dron(
	id: int,
	posicion: Vector3,
	rotacion: Vector3,
	velocidad: Vector3,
	apuntamiento: float,
	_tiempo_servidor_ms: int
) -> void:
	if multiplayer.is_server():
		return
	var dron: Variant = _drones_por_id.get(id)
	if is_instance_valid(dron) and dron.has_method("recibir_snapshot_autoritativo"):
		dron.set("apuntamiento_vertical", apuntamiento)
		dron.call(
			"recibir_snapshot_autoritativo",
			posicion,
			rotacion,
			velocidad,
			Time.get_ticks_msec()
		)

func obtener_bytes_por_segundo() -> Dictionary:
	return _bytes_por_jugador.duplicate(true)

func obtener_dron(peer_id: int) -> Node3D:
	var dron: Variant = _drones_por_id.get(peer_id)
	if is_instance_valid(dron) and dron is Node3D:
		return dron as Node3D
	return null

func obtener_drones_por_id() -> Dictionary:
	return _drones_por_id.duplicate()

func registrar_agua_usada(peer_id: int, cantidad: float) -> void:
	if (
		peer_id < 1
		or cantidad <= 0.0
		or (multiplayer.has_multiplayer_peer() and not multiplayer.is_server())
	):
		return
	var estadisticas := _asegurar_estadisticas_jugador(peer_id)
	estadisticas["agua_usada"] = float(estadisticas.get("agua_usada", 0.0)) + cantidad
	_estadisticas_jugadores[peer_id] = estadisticas

func _asegurar_estadisticas_jugador(peer_id: int) -> Dictionary:
	var estadisticas: Dictionary = _estadisticas_jugadores.get(peer_id, {})
	if estadisticas.is_empty():
		estadisticas = {
			"celdas_apagadas": 0,
			"agua_usada": 0.0,
			"asistencias": 0,
		}
	var datos: Dictionary = jugadores.get(peer_id, {})
	var dron := obtener_dron(peer_id)
	estadisticas["nombre"] = str(
		datos.get("nombre", dron.get_meta("nombre_jugador", nombre_local) if dron else nombre_local)
	)
	estadisticas["rol_dron"] = str(
		datos.get("rol_dron", dron.get_meta("rol_dron", rol_dron_local) if dron else rol_dron_local)
	)
	_estadisticas_jugadores[peer_id] = estadisticas
	return estadisticas

func _al_aplicar_agua_atribuida(
	peer_id: int,
	celdas_con_agua: PackedInt32Array,
	celdas_apagadas: PackedInt32Array
) -> void:
	var estadisticas := _asegurar_estadisticas_jugador(peer_id)
	for indice in celdas_con_agua:
		var colaboradores: Dictionary = _colaboradores_por_celda.get(indice, {})
		colaboradores[peer_id] = true
		_colaboradores_por_celda[indice] = colaboradores
	for indice_apagado in celdas_apagadas:
		var colaboradores_apagado: Dictionary = _colaboradores_por_celda.get(indice_apagado, {})
		for id_variant in colaboradores_apagado.keys():
			if int(id_variant) != peer_id:
				var ayudante := _asegurar_estadisticas_jugador(int(id_variant))
				ayudante["asistencias"] = int(ayudante.get("asistencias", 0)) + 1
				_estadisticas_jugadores[int(id_variant)] = ayudante
		estadisticas["celdas_apagadas"] = int(estadisticas.get("celdas_apagadas", 0)) + 1
		_colaboradores_por_celda.erase(indice_apagado)
	_estadisticas_jugadores[peer_id] = estadisticas
	if not celdas_apagadas.is_empty():
		var nombre := str(estadisticas.get("nombre", "Piloto"))
		publicar_evento_tactico("%s apagó %d celdas" % [nombre, celdas_apagadas.size()])

func enviar_ping_tactico(tipo: String, posicion: Vector3) -> void:
	var tipo_normalizado := tipo.strip_edges().to_lower()
	if not ["fuego", "agua", "peligro"].has(tipo_normalizado):
		return
	if not multiplayer.has_multiplayer_peer():
		ping_tactico_recibido.emit(tipo_normalizado, posicion, multiplayer.get_unique_id())
		return
	if multiplayer.is_server():
		_publicar_ping_tactico(tipo_normalizado, posicion, multiplayer.get_unique_id())
	else:
		rpc_id(1, "_rpc_solicitar_ping_tactico", tipo_normalizado, posicion)

@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_solicitar_ping_tactico(tipo: String, posicion: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not jugadores.has(peer_id) or not _ping_dentro_de_grilla(posicion):
		return
	var tipo_normalizado := tipo.strip_edges().to_lower()
	if not ["fuego", "agua", "peligro"].has(tipo_normalizado):
		return
	_publicar_ping_tactico(tipo_normalizado, posicion, peer_id)

func _ping_dentro_de_grilla(posicion: Vector3) -> bool:
	if not FireGridServer.activa:
		return true
	var origen := FireGridServer.obtener_origen()
	var tamano := FireGridServer.obtener_tamano_celdas()
	return (
		posicion.x >= origen.x
		and posicion.y >= -100.0
		and posicion.x < origen.x + float(tamano.x) * 2.0
		and posicion.z >= origen.y
		and posicion.z < origen.y + float(tamano.y) * 2.0
		and posicion.y <= 1000.0
	)

func _publicar_ping_tactico(tipo: String, posicion: Vector3, emisor_id: int) -> void:
	ping_tactico_recibido.emit(tipo, posicion, emisor_id)
	var datos: Dictionary = jugadores.get(emisor_id, {})
	var nombre := str(datos.get("nombre", nombre_local))
	var etiqueta := {
		"fuego": "Fuego aquí",
		"agua": "Necesito agua",
		"peligro": "Peligro",
	}
	publicar_evento_tactico("%s: %s" % [nombre, str(etiqueta[tipo])])
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		for peer_id in multiplayer.get_peers():
			rpc_id(peer_id, "_rpc_ping_tactico", tipo, posicion, emisor_id)

@rpc("authority", "call_remote", "reliable", 0)
func _rpc_ping_tactico(tipo: String, posicion: Vector3, emisor_id: int) -> void:
	ping_tactico_recibido.emit(tipo, posicion, emisor_id)

func publicar_evento_tactico(texto: String) -> void:
	var mensaje := texto.strip_edges()
	if mensaje.is_empty():
		return
	evento_tactico_recibido.emit(mensaje)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		for peer_id in multiplayer.get_peers():
			rpc_id(peer_id, "_rpc_evento_tactico", mensaje)

@rpc("authority", "call_remote", "reliable", 0)
func _rpc_evento_tactico(texto: String) -> void:
	evento_tactico_recibido.emit(texto)

func _publicar_marcador_final() -> void:
	if _marcador_final_enviado:
		return
	_marcador_final_enviado = true
	var ids: Array = jugadores.keys()
	if ids.is_empty():
		ids = _estadisticas_jugadores.keys()
	ids.sort()
	var resultados: Array = []
	for id_variant in ids:
		var peer_id := int(id_variant)
		var estadisticas := _asegurar_estadisticas_jugador(peer_id)
		resultados.append({
			"id": peer_id,
			"nombre": str(estadisticas.get("nombre", "Piloto")),
			"rol_dron": str(estadisticas.get("rol_dron", "explorador")),
			"celdas_apagadas": int(estadisticas.get("celdas_apagadas", 0)),
			"agua_usada": int(round(float(estadisticas.get("agua_usada", 0.0)))),
			"asistencias": int(estadisticas.get("asistencias", 0)),
		})
	marcador_final_recibido.emit(resultados)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		rpc("_rpc_marcador_final", resultados)

@rpc("authority", "call_remote", "reliable", 0)
func _rpc_marcador_final(resultados: Array) -> void:
	marcador_final_recibido.emit(resultados.duplicate(true))

func _al_modificarse_celdas_de_fuego(deltas: Array) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	var deltas_planos := PackedInt32Array()
	for cambio in deltas:
		if not cambio is Array or cambio.size() != 2:
			continue
		deltas_planos.append(int(cambio[0]))
		deltas_planos.append(int(cambio[1]))
	if deltas_planos.is_empty():
		return
	_secuencia_fuego += 1
	var tamano_paquete := var_to_bytes([_secuencia_fuego, deltas_planos]).size() + 12
	for peer_id in multiplayer.get_peers():
		rpc_id(peer_id, "sincronizar_deltas", _secuencia_fuego, deltas_planos)
		_registrar_bytes_enviados(peer_id, tamano_paquete)

func _al_estado_inicial_de_fuego(_datos: PackedByteArray) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_secuencia_fuego = 0

func _enviar_snapshot_fuego_a_todos() -> void:
	if not multiplayer.is_server() or not FireGridServer.activa:
		return
	for peer_id in multiplayer.get_peers():
		if jugadores.has(peer_id):
			_enviar_snapshot_fuego(peer_id)

func _al_objetivo_critico_amenazado(objetivo: Resource) -> void:
	_replicar_objetivo_critico(objetivo, "AMENAZADO")

func _al_objetivo_critico_perdido(objetivo: Resource) -> void:
	_replicar_objetivo_critico(objetivo, "PERDIDO")

func _replicar_objetivo_critico(objetivo: Resource, estado_objetivo: String) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	var datos: Dictionary = FireGridServer.obtener_datos_objetivo_critico(objetivo, estado_objetivo)
	rpc("_rpc_objetivo_critico", datos)

@rpc("authority", "call_remote", "reliable", CANAL_CONTROL)
func _rpc_objetivo_critico(datos: Dictionary) -> void:
	objetivo_critico_recibido.emit(datos)

func _al_objetivos_criticos_actualizados(resumen: Array, puntaje: int, bono: int) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	rpc("_rpc_objetivos_criticos_finales", resumen, puntaje, bono)

@rpc("authority", "call_remote", "reliable", CANAL_CONTROL)
func _rpc_objetivos_criticos_finales(resumen: Array, puntaje: int, bono: int) -> void:
	objetivos_criticos_finales_recibidos.emit(resumen, puntaje, bono)

func _enviar_snapshot_fuego(peer_id: int) -> void:
	if (
		not multiplayer.is_server()
		or not jugadores.has(peer_id)
		or not FireGridServer.activa
	):
		return
	var comprimido := FireGridServer.serializar_comprimido()
	if comprimido.is_empty():
		return
	rpc_id(peer_id, "_rpc_snapshot_fuego", _secuencia_fuego, comprimido)
	_registrar_bytes_enviados(peer_id, comprimido.size() + 20)

func _estimar_bytes_sincronizacion_drones() -> void:
	var peers := multiplayer.get_peers()
	if peers.is_empty():
		return
	for id_variant in _drones_por_id.keys():
		var id := int(id_variant)
		var dron_variant: Variant = _drones_por_id[id]
		if not is_instance_valid(dron_variant):
			continue
		var dron := dron_variant as Node3D
		var estado := [
			dron.get("agua_actual"),
			dron.get("current_health"),
			dron.get("is_discharging"),
		]
		if _ultimo_estado_sync_drones.get(id, []) == estado:
			continue
		_ultimo_estado_sync_drones[id] = estado.duplicate(true)
		var bytes_estado := var_to_bytes(estado).size() + 12
		for peer_id in peers:
			_registrar_bytes_enviados(peer_id, bytes_estado)

func _estimar_bytes_transform_sync() -> void:
	var peers := multiplayer.get_peers()
	for dron_variant in _drones_por_id.values():
		if not is_instance_valid(dron_variant):
			continue
		var dron := dron_variant as Node3D
		var estado := [
			dron.position,
			dron.rotation,
			dron.get("velocity"),
			dron.get("apuntamiento_vertical"),
		]
		var bytes_estado := var_to_bytes(estado).size() + 12
		for peer_id in peers:
			_registrar_bytes_enviados(peer_id, bytes_estado)

func _enviar_snapshots_drones() -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	var tiempo_ms := Time.get_ticks_msec()
	for id_variant in _drones_por_id.keys():
		var id := int(id_variant)
		var dron: Variant = _drones_por_id[id]
		if not is_instance_valid(dron):
			continue
		var posicion: Vector3 = dron.global_position
		var rotacion: Vector3 = dron.global_rotation
		var velocidad: Vector3 = dron.get("velocity")
		var apuntamiento := float(dron.get("apuntamiento_vertical"))
		var tamanio := var_to_bytes([
			id,
			posicion,
			rotacion,
			velocidad,
			apuntamiento,
			tiempo_ms,
		]).size() + 12
		for peer_id in multiplayer.get_peers():
			rpc_id(
				peer_id,
				"_rpc_snapshot_dron",
				id,
				posicion,
				rotacion,
				velocidad,
				apuntamiento,
				tiempo_ms
			)
			_registrar_bytes_enviados(peer_id, tamanio)

func _registrar_bytes_enviados(peer_id: int, cantidad: int) -> void:
	var peer := int(peer_id)
	_bytes_en_ventana[peer] = int(_bytes_en_ventana.get(peer, 0)) + maxi(cantidad, 0)

func _actualizar_bytes_por_segundo(intervalo: float) -> void:
	var metricas: Dictionary = {}
	for peer_id in jugadores.keys():
		var peer := int(peer_id)
		if peer == multiplayer.get_unique_id():
			continue
		metricas[peer] = int(round(float(_bytes_en_ventana.get(peer, 0)) / maxf(intervalo, 0.001)))
	_bytes_en_ventana.clear()
	_bytes_por_jugador = metricas
	metricas_red_actualizadas.emit(_bytes_por_jugador.duplicate(true))
	var tamanio_metricas := var_to_bytes(metricas).size() + 12
	for peer_id in multiplayer.get_peers():
		rpc_id(peer_id, "_rpc_actualizar_metricas_red", metricas)
		_registrar_bytes_enviados(peer_id, tamanio_metricas)

func _rechazar_cliente(peer_id: int, motivo: String) -> void:
	if peer_id <= 1:
		return
	rpc_id(peer_id, "_rpc_ingreso_rechazado", motivo)
	_desconectar_rechazado_despues(peer_id)

func _desconectar_rechazado_despues(peer_id: int) -> void:
	await get_tree().create_timer(0.25).timeout
	if multiplayer.is_server() and multiplayer.get_peers().has(peer_id):
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)

func _publicar_sala() -> void:
	sala_actualizada.emit(codigo_sala, jugadores.duplicate(true))
	if multiplayer.is_server():
		var paquete := [
			codigo_sala,
			jugadores.duplicate(true),
			configuracion_sala.duplicate(true),
			partida_iniciada,
			anfitrion_id,
		]
		var tamanio_rpc := var_to_bytes(paquete).size() + 12
		rpc(
			"_rpc_actualizar_sala",
			codigo_sala,
			jugadores.duplicate(true),
			configuracion_sala.duplicate(true),
			partida_iniciada,
			anfitrion_id
		)
		for peer_id in multiplayer.get_peers():
			_registrar_bytes_enviados(peer_id, tamanio_rpc)

func _actualizar_estado_listo(id: int, listo: bool) -> bool:
	if not multiplayer.is_server() or not jugadores.has(id):
		return false
	var datos: Dictionary = jugadores[id]
	datos["listo"] = listo
	jugadores[id] = datos
	_nombres_reservados[str(datos.get("nombre", ""))] = datos.duplicate(true)
	_publicar_sala()
	return true

func _publicar_chat(nombre: String, texto: String) -> void:
	chat_recibido.emit(nombre, texto)
	if multiplayer.is_server():
		rpc("_rpc_recibir_chat", nombre, texto)
		var tamanio_rpc := var_to_bytes([nombre, texto]).size() + 8
		for peer_id in multiplayer.get_peers():
			_registrar_bytes_enviados(peer_id, tamanio_rpc)

func _enviar_latido_directorio() -> void:
	if not _servidor_dedicado or _url_directorio.is_empty() or _token_directorio.is_empty():
		return
	if _http_directorio.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	var cuerpo := JSON.stringify({
		"token": _token_directorio,
		"jugadores": jugadores.size(),
	})
	var resultado := _http_directorio.request(
		"%s/salas/%s/heartbeat" % [_url_directorio, codigo_sala.uri_encode()],
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		cuerpo
	)
	if resultado != OK:
		_registrar_error_directorio("No se pudo enviar el latido de sala (error %d)." % resultado)

func _al_completar_latido_directorio(
	resultado: int,
	codigo_http: int,
	_cabeceras: PackedStringArray,
	_cuerpo: PackedByteArray
) -> void:
	if resultado != HTTPRequest.RESULT_SUCCESS or codigo_http < 200 or codigo_http >= 300:
		var ahora := Time.get_ticks_msec()
		if ahora - _aviso_directorio_ms >= 10000:
			_aviso_directorio_ms = ahora
			_registrar_error_directorio("El directorio no confirmó el estado de la sala (HTTP %d, resultado %d)." % [codigo_http, resultado])

func _registrar_error_directorio(mensaje: String) -> void:
	push_warning("NetworkManager: %s" % mensaje)

func _terminar_sala_en_directorio() -> void:
	if _url_directorio.is_empty() or _token_directorio.is_empty() or codigo_sala.is_empty():
		return
	var solicitud := HTTPRequest.new()
	solicitud.timeout = 4.0
	add_child(solicitud)
	solicitud.request_completed.connect(func(_r: int, _c: int, _h: PackedStringArray, _b: PackedByteArray) -> void: solicitud.queue_free())
	var resultado := solicitud.request(
		"%s/salas/%s/terminar" % [_url_directorio, codigo_sala.uri_encode()],
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		JSON.stringify({"token": _token_directorio})
	)
	if resultado != OK:
		solicitud.queue_free()
		_registrar_error_directorio("No se pudo notificar el cierre de sala al directorio.")

func _al_finalizar_mision() -> void:
	if multiplayer.is_server():
		_publicar_marcador_final()

func _conectar_fin_mision() -> void:
	if not multiplayer.is_server():
		return
	var escena := get_tree().current_scene
	if escena == null:
		return
	var gestor := escena.get_node_or_null("FireManager")
	if gestor == null:
		return
	for nombre_senal in ["incendio_controlado", "incendio_descontrolado"]:
		if gestor.has_signal(nombre_senal):
			var callable := Callable(self, "_al_finalizar_mision")
			if not gestor.is_connected(nombre_senal, callable):
				gestor.connect(nombre_senal, callable)

func _contar_jugadores_conectados() -> int:
	return jugadores.size()

func _nombre_en_linea(nombre: String) -> bool:
	for datos_variant in jugadores.values():
		var datos: Dictionary = datos_variant
		if str(datos.get("nombre", "")).to_lower() == nombre.to_lower():
			return true
	return false

func _crear_datos_jugador(nombre: String, posicion: int) -> Dictionary:
	return {
		"nombre": nombre,
		"rol": "piloto",
		"rol_dron": rol_dron_local,
		"listo": false,
		"equipo": "Equipo %d" % posicion,
		"ping": 0,
	}

func _normalizar_nombre(nombre: String) -> String:
	var limpio := nombre.strip_edges()
	if limpio.length() > 24:
		limpio = limpio.substr(0, 24)
	return limpio

func _codigo_valido(codigo: String) -> bool:
	if codigo.length() < 3 or codigo.length() > 12:
		return false
	for caracter in codigo:
		var caracter_ascii := caracter.unicode_at(0)
		var es_digito := caracter_ascii >= 48 and caracter_ascii <= 57
		var es_letra := (
			(caracter_ascii >= 65 and caracter_ascii <= 90)
			or (caracter_ascii >= 97 and caracter_ascii <= 122)
		)
		if not es_digito and not es_letra:
			return false
	return true

func _crear_codigo_sala() -> String:
	var generador := RandomNumberGenerator.new()
	generador.randomize()
	return str(generador.randi_range(1000, 9999))

func _normalizar_escenario(escenario: String) -> String:
	var normalizado := escenario.strip_edges().to_lower()
	return normalizado if ESCENAS.has(normalizado) else ""

func _usar_enet() -> bool:
	return transporte.strip_edges().to_lower() == "enet"

func _cargar_escenario_local(escenario_recibido: String) -> void:
	var escenario := _normalizar_escenario(escenario_recibido)
	if escenario.is_empty():
		push_error("NetworkManager rechazó un identificador de escenario desconocido.")
		return
	var error_cambio := get_tree().change_scene_to_file(str(ESCENAS[escenario]))
	if error_cambio != OK:
		conexion_fallida.emit("No se pudo cargar el escenario solicitado (error %d)." % error_cambio)

func _al_cambiar_escena() -> void:
	_conectar_fin_mision()
	if not partida_iniciada or not multiplayer.has_multiplayer_peer():
		return
	var escena_actual := get_tree().current_scene
	if not is_instance_valid(escena_actual):
		return
	var escenario_esperado := _normalizar_escenario(str(configuracion_sala.get("escenario", "aguarague")))
	if str(ESCENAS.get(escenario_esperado, "")) != escena_actual.scene_file_path:
		return
	_configurar_spawner(escena_actual)
	if multiplayer.is_server():
		if not _servidor_dedicado:
			_instanciar_dron_jugador(1)
		for peer_id_variant in _clientes_listos.keys():
			_instanciar_dron_jugador(int(peer_id_variant))
	else:
		rpc_id(1, "_rpc_cliente_listo")

func _configurar_spawner(escena: Node) -> void:
	if is_instance_valid(_spawner):
		_spawner.queue_free()
	_spawner = MultiplayerSpawner.new()
	_spawner.name = "SpawnerDronesRed"
	_spawner.set_multiplayer_authority(1)
	_spawner.spawn_path = NodePath("..")
	_spawner.spawn_function = Callable(self, "_crear_dron_multijugador")
	_spawner.add_spawnable_scene(ESCENA_DRON)
	escena.add_child(_spawner)

	var dron_predefinido := escena.get_node_or_null("DronePlayer")
	if is_instance_valid(dron_predefinido):
		dron_predefinido.queue_free()

func _crear_dron_multijugador(datos: Variant) -> Node:
	if not datos is Dictionary:
		push_error("MultiplayerSpawner recibió datos de dron inválidos.")
		return null
	var peer_id := int(datos.get("id", 0))
	if peer_id < 1 or not jugadores.has(peer_id):
		push_error("MultiplayerSpawner recibió un identificador de jugador no validado.")
		return null
	var escena := ResourceLoader.load(ESCENA_DRON) as PackedScene
	if not is_instance_valid(escena):
		push_error("No se pudo cargar la escena de dron multijugador.")
		return null
	var dron := escena.instantiate() as CharacterBody3D
	if not is_instance_valid(dron):
		push_error("La escena de dron no contiene un CharacterBody3D.")
		return null
	dron.name = "DronePlayer_%d" % peer_id
	dron.set_multiplayer_authority(peer_id)
	var escena_actual := get_tree().current_scene
	var pista := escena_actual.find_child("PistaAterrizaje", true, false) as Node3D
	if is_instance_valid(pista):
		var indice := peer_id - 1
		var fila := floori(float(indice) / 3.0)
		var columna := indice % 3
		dron.position = pista.position + Vector3(
			-42.0 + float(fila) * 24.0,
			3.5,
			(float(columna) - 1.0) * 7.0
		)
	else:
		dron.position = Vector3(
			-120.0 + float((peer_id - 1) % 3) * 5.0,
			3.5,
			40.0 + float((peer_id - 1) / 3) * 5.0
		)
	dron.set_meta("nombre_jugador", str(datos.get("nombre", "Piloto")))
	dron.set_meta("rol_dron", str(datos.get("rol_dron", "explorador")))
	_agregar_sincronizador_dron(dron, peer_id)
	_drones_por_id[peer_id] = dron
	return dron

func _agregar_sincronizador_dron(dron: CharacterBody3D, peer_id: int) -> void:
	if is_instance_valid(dron.get_node_or_null("SincronizadorDron")):
		return
	var sincronizador := MultiplayerSynchronizer.new()
	sincronizador.name = "SincronizadorDron"
	sincronizador.set_multiplayer_authority(1)
	sincronizador.replication_interval = 0.2
	sincronizador.delta_interval = 0.05
	var configuracion := SceneReplicationConfig.new()
	var propiedades_no_confiables: Array[NodePath] = [
		NodePath(".:position"),
		NodePath(".:rotation"),
		NodePath(".:velocity"),
		NodePath(".:apuntamiento_vertical"),
	]
	for propiedad in propiedades_no_confiables:
		configuracion.add_property(propiedad)
		configuracion.property_set_replication_mode(
			propiedad,
			SceneReplicationConfig.REPLICATION_MODE_ALWAYS
		)
	var propiedades_confiables: Array[NodePath] = [
		NodePath(".:agua_actual"),
		NodePath(".:current_health"),
		NodePath(".:is_discharging"),
	]
	for propiedad in propiedades_confiables:
		configuracion.add_property(propiedad)
		configuracion.property_set_replication_mode(
			propiedad,
			SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE
		)
	sincronizador.replication_config = configuracion
	sincronizador.synchronized.connect(Callable(dron, "_al_sincronizar_dron"))
	dron.add_child(sincronizador)

func _instanciar_dron_jugador(peer_id: int) -> void:
	if not multiplayer.is_server() or not is_instance_valid(_spawner):
		return
	if _drones_por_id.has(peer_id) and is_instance_valid(_drones_por_id[peer_id]):
		return
	var datos: Dictionary = jugadores.get(peer_id, {})
	if datos.is_empty():
		return
	_spawner.spawn({
		"id": peer_id,
		"nombre": str(datos.get("nombre", "Piloto")),
		"rol": str(datos.get("rol", "piloto")),
		"rol_dron": str(datos.get("rol_dron", "explorador")),
	})

func _despawnear_dron(peer_id: int) -> void:
	if not _drones_por_id.has(peer_id):
		return
	var dron: Variant = _drones_por_id[peer_id]
	_drones_por_id.erase(peer_id)
	_ultimo_estado_sync_drones.erase(peer_id)
	if multiplayer.is_server() and is_instance_valid(dron) and peer_id != 1:
		dron.queue_free()

func _procesar_argumentos_usuario(argumentos: PackedStringArray) -> void:
	var valores: Dictionary = {}
	var es_servidor := false
	for argumento in argumentos:
		if argumento == "--server":
			es_servidor = true
		elif argumento.begins_with("--") and argumento.contains("="):
			var partes := argumento.substr(2).split("=", false, 1)
			if partes.size() == 2:
				valores[partes[0]] = partes[1]
	if valores.has("transport"):
		var transporte_recibido := str(valores["transport"]).to_lower()
		if transporte_recibido != "enet" and transporte_recibido != "websocket":
			conexion_fallida.emit("Transporte inválido; use websocket o enet.")
			return
		transporte = "ENet" if transporte_recibido == "enet" else "WebSocket"
	_puerto_sala = int(valores.get("port", PUERTO_PREDETERMINADO))
	if es_servidor:
		var config := {
			"escenario": str(valores.get("scenario", "aguarague")),
			"dificultad": str(valores.get("difficulty", "media")),
			"max_jugadores": int(valores.get("max-players", 6)),
			"codigo": str(valores.get("room", "")),
			"servidor_dedicado": true,
			"url_directorio": str(valores.get("directory", "")),
			"token_directorio": str(valores.get("directory-token", "")),
		}
		if crear_sala(config):
			print("NetworkManager: servidor dedicado listo; sala %s." % codigo_sala)
		return
	if valores.has("connect") and valores.has("room"):
		nombre_local = str(valores.get("name", "Piloto"))
		unirse_a_sala(
			str(valores["connect"]),
			_puerto_sala,
			str(valores["room"])
		)

