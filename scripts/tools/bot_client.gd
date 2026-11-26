extends Node

const RUTA_DIRECTORIO_CLIENT := "res://scripts/network/directorio_client.gd"
const ROLES_VALIDOS := ["cisterna", "explorador", "tactico"]
const ESTADO_ARDIENDO := 1
const DISTANCIA_CELDA_METROS := 2.0
const INTERVALO_SELECCION_OBJETIVO := 1.0

var _url_directorio: String = ""
var _codigo_sala: String = ""
var _nombre: String = ""
var _rol: String = "explorador"
var _bots_esperados: int = 0
var _duracion_segundos: float = 0.0
var _espera_reconexion: bool = false
var _ruta_estado: String = ""
var _dron: Node3D
var _fuente_agua: Node3D
var _indice_objetivo: int = -1
var _posicion_objetivo: Vector3 = Vector3.ZERO
var _tiempo_objetivo: float = 0.0
var _tiempo_total: float = 0.0
var _tiempo_en_partida: float = 0.0
var _listo: bool = false
var _inicio_solicitado: bool = false
var _recargar: bool = false


func configurar(argumentos: PackedStringArray) -> void:
	var valores: Dictionary = {}
	for argumento in argumentos:
		if argumento == "--expect-reconnect":
			_espera_reconexion = true
		elif argumento.begins_with("--") and argumento.contains("="):
			var partes := argumento.substr(2).split("=", false, 1)
			if partes.size() == 2:
				valores[partes[0]] = partes[1]

	_url_directorio = str(valores.get("directory", ""))
	_codigo_sala = str(valores.get("room-code", ""))
	_nombre = str(valores.get("name", ""))
	_rol = str(valores.get("role", "explorador")).to_lower()
	_bots_esperados = int(valores.get("bots-in-room", 0))
	_duracion_segundos = float(valores.get("duration", 0.0))
	_ruta_estado = str(valores.get("status-file", ""))
	if (
		_url_directorio.is_empty()
		or _codigo_sala.is_empty()
		or _nombre.strip_edges().is_empty()
		or not ROLES_VALIDOS.has(_rol)
		or _bots_esperados < 0
		or _bots_esperados > 6
	):
		_fallar("Parámetros de bot inválidos o incompletos.")
		return

	NetworkManager.nombre_local = _nombre
	NetworkManager.seleccionar_rol_dron(_rol)
	var transporte := str(valores.get("transport", "websocket")).to_lower()
	if transporte != "websocket" and transporte != "enet":
		_fallar("El transporte del bot debe ser websocket o enet.")
		return
	NetworkManager.transporte = "ENet" if transporte == "enet" else "WebSocket"
	NetworkManager.conexion_fallida.connect(_al_fallar_conexion)
	_escribir_estado("connecting")

	var script_directorio := load(RUTA_DIRECTORIO_CLIENT) as Script
	if not is_instance_valid(script_directorio):
		_fallar("No se pudo cargar DirectorioClient.")
		return
	var cliente_directorio := script_directorio.new() as Node
	if not is_instance_valid(cliente_directorio):
		_fallar("No se pudo crear DirectorioClient.")
		return
	cliente_directorio.name = "DirectorioBot"
	add_child(cliente_directorio)
	cliente_directorio.connect("sala_encontrada", _al_encontrar_sala)
	cliente_directorio.connect("error_directorio", _al_fallar_conexion)
	cliente_directorio.call("obtener_sala", _url_directorio, _codigo_sala)


func _process(delta: float) -> void:
	_tiempo_total += delta
	if _duracion_segundos > 0.0 and _tiempo_total >= _duracion_segundos:
		get_tree().quit()
		return
	if not NetworkManager.multiplayer.has_multiplayer_peer():
		return
	if not NetworkManager.partida_iniciada:
		if (
			not _inicio_solicitado
			and _bots_esperados > 0
			and NetworkManager.es_anfitrion_local()
			and NetworkManager.jugadores.size() >= _bots_esperados
		):
			_inicio_solicitado = NetworkManager.iniciar_partida()
		return

	_tiempo_en_partida += delta
	if not is_instance_valid(_dron):
		_dron = NetworkManager.obtener_dron(NetworkManager.multiplayer.get_unique_id())
		if not is_instance_valid(_dron):
			if _tiempo_en_partida > 60.0:
				_fallar("La partida inició, pero no se creó el dron del bot.")
			return
	if not FireGridServer.activa:
		if _tiempo_en_partida > 60.0:
			_fallar("El bot no recibió la grilla de fuego replicada.")
		return
	if not _validar_dron_y_rol():
		return
	if not _listo:
		_listo = true
		var estado := "recovered" if _espera_reconexion else "ready"
		_escribir_estado(
			estado,
			{
				"peer_id": NetworkManager.multiplayer.get_unique_id(),
				"drone_id": _dron.get_instance_id(),
				"role": _rol,
			}
		)
		print(
			(
				"BOT_%s name=%s role=%s drone=%d"
				% [
					"RECOVERY_OK" if _espera_reconexion else "READY",
					_nombre,
					_rol,
					_dron.get_instance_id(),
				]
			)
		)


func _physics_process(delta: float) -> void:
	if not _listo or not is_instance_valid(_dron):
		return
	_tiempo_objetivo += delta
	var agua_actual := float(_dron.get("agua_actual"))
	var agua_maxima := maxf(float(_dron.get("agua_maxima")), 1.0)
	if agua_actual <= agua_maxima * 0.2:
		_recargar = true
	elif agua_actual >= agua_maxima * 0.9:
		_recargar = false

	if _recargar:
		_controlar_recarga()
	else:
		_controlar_incendio()


func _al_encontrar_sala(datos: Dictionary) -> void:
	var host := str(datos.get("host", ""))
	var puerto := int(datos.get("puerto", 0))
	if host.is_empty() or puerto < 1:
		_fallar("El directorio devolvió un host o puerto inválido.")
		return
	if not NetworkManager.unirse_a_sala(host, puerto, _codigo_sala):
		_fallar("No se pudo iniciar la conexión a la sala.")


func _al_fallar_conexion(mensaje: String) -> void:
	_fallar(mensaje)


func _validar_dron_y_rol() -> bool:
	var peer_id := NetworkManager.multiplayer.get_unique_id()
	var datos: Dictionary = NetworkManager.jugadores.get(peer_id, {})
	var rol_recibido := str(datos.get("rol_dron", ""))
	var rol_dron: Variant = _dron.get("rol_actual")
	var rol_instanciado := ""
	if rol_dron is DroneRole:
		rol_instanciado = str((rol_dron as DroneRole).identificador)
	var rol_meta := str(_dron.get_meta("rol_dron", ""))
	if rol_recibido != _rol or rol_instanciado != _rol or rol_meta != _rol:
		_fallar(
			(
				"El rol recuperado no coincide: sala=%s dron=%s meta=%s esperado=%s."
				% [rol_recibido, rol_instanciado, rol_meta, _rol]
			)
		)
		return false
	return true


func _controlar_incendio() -> void:
	if _tiempo_objetivo >= INTERVALO_SELECCION_OBJETIVO:
		_tiempo_objetivo = 0.0
		_seleccionar_foco_mas_cercano()
	if _indice_objetivo < 0:
		_liberar_acciones()
		return
	var indices_ardiendo := FireGridServer.obtener_celdas_ardiendo()
	if not indices_ardiendo.has(_indice_objetivo):
		_indice_objetivo = -1
		_set_accion(&"drone_spray", false)
		return

	var altura_dron := float(_posicion_objetivo.y) + 14.0
	var punto_vuelo := Vector3(_posicion_objetivo.x, altura_dron, _posicion_objetivo.z)
	var distancia_objetivo := Vector2(
		_dron.global_position.x - _posicion_objetivo.x,
		_dron.global_position.z - _posicion_objetivo.z
	)
	var distancia_horizontal := distancia_objetivo.length()
	var alcance := maxf(float(_dron.get("alcance_chorro")) - 3.0, 8.0)
	if distancia_horizontal > alcance:
		_dirigir_a(punto_vuelo, alcance, 2.0)
		_set_accion(&"drone_spray", false)
		return

	_set_accion(&"drone_forward", false)
	_controlar_altura(altura_dron)
	var apuntando := _apuntar_a(_posicion_objetivo)
	_set_accion(&"drone_spray", apuntando)


func _controlar_recarga() -> void:
	if not is_instance_valid(_fuente_agua):
		_fuente_agua = _buscar_fuente_agua_mas_cercana()
	if not is_instance_valid(_fuente_agua):
		_liberar_acciones()
		return
	var punto_agua := _fuente_agua.to_global(Vector3(0.0, 0.58, 0.0))
	var distancia_agua := Vector2(
		_dron.global_position.x - punto_agua.x, _dron.global_position.z - punto_agua.z
	)
	var distancia_horizontal := distancia_agua.length()
	var en_rango := bool(_dron.get("is_near_water_source"))
	if distancia_horizontal > 4.0 or absf(_dron.global_position.y - punto_agua.y) > 1.0:
		_dirigir_a(punto_agua, 4.0, 0.7)
		_set_accion(&"drone_refill", false)
	else:
		_set_accion(&"drone_forward", false)
		_controlar_altura(punto_agua.y)
		_set_accion(&"drone_refill", en_rango)
	_set_accion(&"drone_spray", false)


func _seleccionar_foco_mas_cercano() -> void:
	_indice_objetivo = -1
	var celdas := FireGridServer.obtener_celdas_ardiendo()
	var alturas := FireGridServer.obtener_alturas()
	var origen := FireGridServer.obtener_origen()
	var tamano := FireGridServer.obtener_tamano_celdas()
	if tamano.x <= 0:
		return
	var distancia_minima := INF
	for indice in celdas:
		if indice < 0 or indice >= alturas.size():
			continue
		var celda := Vector2i(indice % tamano.x, floori(float(indice) / float(tamano.x)))
		var posicion := Vector3(
			origen.x + (float(celda.x) + 0.5) * DISTANCIA_CELDA_METROS,
			alturas[indice],
			origen.y + (float(celda.y) + 0.5) * DISTANCIA_CELDA_METROS
		)
		var distancia := _dron.global_position.distance_squared_to(posicion)
		if distancia < distancia_minima:
			distancia_minima = distancia
			_indice_objetivo = indice
			_posicion_objetivo = posicion


func _buscar_fuente_agua_mas_cercana() -> Node3D:
	var mas_cercana: Node3D
	var distancia_minima := INF
	for nodo in get_tree().get_nodes_in_group("fuente_agua"):
		if not nodo is Node3D:
			continue
		var fuente := nodo as Node3D
		var distancia := _dron.global_position.distance_squared_to(fuente.global_position)
		if distancia < distancia_minima:
			distancia_minima = distancia
			mas_cercana = fuente
	return mas_cercana


func _dirigir_a(destino: Vector3, distancia_parada: float, tolerancia_altura: float) -> void:
	var diferencia := Vector2(
		destino.x - _dron.global_position.x, destino.z - _dron.global_position.z
	)
	var distancia := diferencia.length()
	_orientar_hacia(destino)
	_set_accion(&"drone_forward", distancia > distancia_parada)
	_controlar_altura(destino.y, tolerancia_altura)


func _orientar_hacia(destino: Vector3) -> void:
	var direccion := destino - _dron.global_position
	var yaw_deseado := atan2(-direccion.x, -direccion.z)
	var error_yaw := wrapf(yaw_deseado - _dron.global_rotation.y, -PI, PI)
	var sensibilidad := maxf(float(_dron.get("mouse_sensitivity")), 0.0005)
	var entrada_x := clampf(-error_yaw / sensibilidad, -120.0, 120.0)
	_dron.set("mouse_input", Vector2(entrada_x, 0.0))


func _apuntar_a(destino: Vector3) -> bool:
	var nozzle := _dron.get("nozzle") as Node3D
	if not is_instance_valid(nozzle):
		return false
	var direccion: Vector3 = destino - nozzle.global_position
	var distancia_horizontal := Vector2(direccion.x, direccion.z).length()
	var error_yaw := 0.0
	if distancia_horizontal > 0.1:
		var yaw_deseado := atan2(-direccion.x, -direccion.z)
		error_yaw = wrapf(yaw_deseado - _dron.global_rotation.y, -PI, PI)
	var pitch_deseado := clampf(
		atan2(direccion.y, distancia_horizontal), deg_to_rad(-45.0), deg_to_rad(30.0)
	)
	var pivot := _dron.get("pivot") as Node3D
	var error_pitch := wrapf(pitch_deseado - pivot.rotation.x, -PI, PI)
	var sensibilidad := maxf(float(_dron.get("mouse_sensitivity")), 0.0005)
	_dron.set(
		"mouse_input",
		Vector2(
			clampf(-error_yaw / sensibilidad, -120.0, 120.0),
			clampf(-error_pitch / sensibilidad, -120.0, 120.0)
		)
	)
	return absf(error_yaw) < deg_to_rad(3.0) and absf(error_pitch) < deg_to_rad(3.0)


func _controlar_altura(altura: float, tolerancia: float = 1.5) -> void:
	var diferencia := altura - _dron.global_position.y
	_set_accion(&"drone_ascend", diferencia > tolerancia)
	_set_accion(&"drone_descend", diferencia < -tolerancia)


func _set_accion(accion: StringName, presionada: bool) -> void:
	if presionada:
		Input.action_press(accion)
	else:
		Input.action_release(accion)


func _liberar_acciones() -> void:
	for accion in [
		&"drone_forward",
		&"drone_backward",
		&"drone_left",
		&"drone_right",
		&"drone_ascend",
		&"drone_descend",
		&"drone_refill",
		&"drone_spray",
	]:
		Input.action_release(accion)


func _escribir_estado(estado: String, extra: Dictionary = {}) -> void:
	if _ruta_estado.is_empty():
		return
	var ruta_absoluta := ProjectSettings.globalize_path(_ruta_estado)
	var error_directorio := DirAccess.make_dir_recursive_absolute(ruta_absoluta.get_base_dir())
	if error_directorio != OK:
		push_error("El bot no pudo crear el directorio de estado (error %d)." % error_directorio)
		return
	var archivo := FileAccess.open(ruta_absoluta, FileAccess.WRITE)
	if not is_instance_valid(archivo):
		push_error("El bot no pudo escribir su estado.")
		return
	var datos := {
		"status": estado,
		"name": _nombre,
		"role": _rol,
		"message": "",
	}
	datos.merge(extra, true)
	archivo.store_string(JSON.stringify(datos))
	archivo.close()


func _fallar(mensaje: String) -> void:
	_escribir_estado("failed", {"message": mensaje})
	push_error("Bot %s: %s" % [_nombre, mensaje])
	get_tree().quit(1)
