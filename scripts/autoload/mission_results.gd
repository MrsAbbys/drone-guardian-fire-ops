extends Node

const RUTA_RESULTADOS: String = "res://scenes/ui/resultados.tscn"
const RUTA_MENU: String = "res://scenes/menus/main_menu.tscn"

var resultado_actual: Dictionary = {}
var ruta_mision: String = ""
var escenario_id: String = ""
var _inicio_mision_ms: int = 0
var _resultado_publicado: bool = false


func _ready() -> void:
	get_tree().scene_changed.connect(_al_cambiar_escena)


func _al_cambiar_escena() -> void:
	var escena := get_tree().current_scene
	if not is_instance_valid(escena) or escena.scene_file_path == RUTA_RESULTADOS:
		return
	var gestor := escena.get_node_or_null("FireManager")
	if not is_instance_valid(gestor):
		return
	ruta_mision = escena.scene_file_path
	escenario_id = str(NetworkManager.configuracion_sala.get("escenario", escena.name))
	_inicio_mision_ms = Time.get_ticks_msec()
	_resultado_publicado = false
	var controlada := Callable(self, "_al_finalizar_mision").bind(true)
	var descontrolada := Callable(self, "_al_finalizar_mision").bind(false)
	if (
		gestor.has_signal("incendio_controlado")
		and not gestor.is_connected("incendio_controlado", controlada)
	):
		gestor.connect("incendio_controlado", controlada)
	if (
		gestor.has_signal("incendio_descontrolado")
		and not gestor.is_connected("incendio_descontrolado", descontrolada)
	):
		gestor.connect("incendio_descontrolado", descontrolada)


func _al_finalizar_mision(victoria: bool) -> void:
	if _resultado_publicado:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	_resultado_publicado = true
	resultado_actual = _crear_resultado(victoria)
	if multiplayer.has_multiplayer_peer():
		rpc("_rpc_mostrar_resultados", resultado_actual, ruta_mision)
	_mostrar_resultados(resultado_actual, ruta_mision)


func _crear_resultado(victoria: bool) -> Dictionary:
	var porcentaje_salvado := FireGridServer.obtener_porcentaje_superficie_salvada()
	var objetivos := FireGridServer.obtener_resumen_objetivos_criticos()
	var objetivos_salvados: int = 0
	for objetivo: Variant in objetivos:
		if objetivo is Dictionary and str(objetivo.get("estado", "")) == "SALVADO":
			objetivos_salvados += 1
	var agua_desperdiciada: float = 0.0
	for dron in get_tree().get_nodes_in_group("jugador"):
		if is_instance_valid(dron):
			agua_desperdiciada += float(dron.get("wasted_water_time"))
	return {
		"victoria": victoria,
		"escenario": escenario_id,
		"tiempo_segundos": maxf(float(Time.get_ticks_msec() - _inicio_mision_ms) / 1000.0, 0.0),
		"superficie_salvada_pct": porcentaje_salvado,
		"objetivos_salvados": objetivos_salvados,
		"objetivos_totales": objetivos.size(),
		"wasted_water_time": agua_desperdiciada,
	}


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_mostrar_resultados(datos: Dictionary, escena: String) -> void:
	resultado_actual = datos.duplicate(true)
	ruta_mision = escena
	_mostrar_resultados(resultado_actual, ruta_mision)


func _mostrar_resultados(datos: Dictionary, escena: String) -> void:
	resultado_actual = datos.duplicate(true)
	ruta_mision = escena
	if OS.has_feature("dedicated_server") or DisplayServer.get_name() == "headless":
		return
	var error_cambio := get_tree().change_scene_to_file(RUTA_RESULTADOS)
	if error_cambio != OK:
		push_error("No se pudo abrir la pantalla de resultados (error %d)." % error_cambio)


func reintentar() -> void:
	if not NetworkManager.codigo_sala.is_empty():
		if multiplayer.is_server():
			_recargar_mision_en_red(_obtener_ruta_reintento())
		else:
			rpc_id(1, "_rpc_solicitar_reintento")
		return
	if ruta_mision.is_empty() or not ResourceLoader.exists(ruta_mision):
		push_error("No se conoce una escena válida para reintentar la misión.")
		return
	_recargar_escena(ruta_mision)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_solicitar_reintento() -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != NetworkManager.anfitrion_id:
		return
	_recargar_mision_en_red(_obtener_ruta_reintento())


func _obtener_ruta_reintento() -> String:
	var escenario := str(NetworkManager.configuracion_sala.get("escenario", ""))
	var ruta: String = NetworkManager.ESCENAS.get(escenario, "")
	if ruta.is_empty():
		push_error("No se encontró la escena para reiniciar la sala.")
	return ruta


func _recargar_mision_en_red(escena: String) -> void:
	if escena.is_empty() or not NetworkManager.ESCENAS.values().has(escena):
		push_error("Se rechazó una escena inválida al reiniciar la sala.")
		return
	rpc("_rpc_recargar_mision", escena)
	_rpc_recargar_mision(escena)


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_recargar_mision(escena: String) -> void:
	if not NetworkManager.ESCENAS.values().has(escena):
		push_error("El servidor envió una escena inválida para el reinicio.")
		return
	NetworkManager.reiniciar_estadisticas_mision()
	_recargar_escena(escena)


func _recargar_escena(escena: String) -> void:
	var error_cambio := get_tree().change_scene_to_file(escena)
	if error_cambio != OK:
		push_error("No se pudo reiniciar la misión (error %d)." % error_cambio)


func volver_al_menu() -> void:
	if NetworkManager.multiplayer.has_multiplayer_peer():
		NetworkManager.salir()
	var error_cambio := get_tree().change_scene_to_file(RUTA_MENU)
	if error_cambio != OK:
		push_error("No se pudo volver al menú principal (error %d)." % error_cambio)
