extends Node

const RUTA_CONFIG: String = "user://audio.cfg"
const MAXIMO_FUEGOS_AUDIBLES: int = 8
const INTERVALO_ACTUALIZACION: float = 0.15
const STREAM_ROTOR: AudioStreamWAV = preload("res://assets/audio/rotor.wav")
const STREAM_FUEGO: AudioStreamWAV = preload("res://assets/audio/fire_crackle.wav")
const STREAM_AGUA: AudioStreamWAV = preload("res://assets/audio/water_spray.wav")
const STREAM_ALERTA: AudioStreamWAV = preload("res://assets/audio/alert.wav")
const STREAM_CLIC: AudioStreamWAV = preload("res://assets/audio/ui_click.wav")
const BUSES: Array[String] = ["Maestro", "Efectos", "Musica", "UI"]

@export_group("Audio de recarga")
@export_range(-30.0, -4.0, 0.5) var volumen_recarga_db: float = -10.0
@export_range(0.05, 1.0, 0.05) var duracion_entrada_recarga: float = 0.3
@export_range(0.1, 2.0, 0.05) var duracion_salida_recarga: float = 0.55
@export_range(10.0, 100.0, 1.0) var distancia_maxima_audio_recarga: float = 40.0

var _volumenes: Dictionary = {
	"Maestro": 1.0,
	"Efectos": 1.0,
	"Musica": 1.0,
	"UI": 1.0,
}
var _reproductor_clic: AudioStreamPlayer
var _reproductor_alerta: AudioStreamPlayer
var _reproductores_fuego: Array[AudioStreamPlayer3D] = []
var _audio_drones: Dictionary = {}
var _stream_rotor: AudioStreamWAV
var _stream_fuego: AudioStreamWAV
var _stream_agua: AudioStreamWAV
var _acumulador: float = 0.0
var _sin_audio: bool = false


func _ready() -> void:
	_sin_audio = (OS.has_feature("dedicated_server") or DisplayServer.get_name() == "headless")
	if _sin_audio:
		set_process(false)
		return

	_stream_rotor = STREAM_ROTOR.duplicate() as AudioStreamWAV
	_stream_fuego = STREAM_FUEGO.duplicate() as AudioStreamWAV
	_stream_agua = STREAM_AGUA.duplicate() as AudioStreamWAV
	_stream_rotor.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_stream_fuego.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_stream_agua.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_configurar_buses()
	_cargar_volumenes()
	_crear_reproductores_globales()
	get_tree().node_added.connect(_al_agregar_nodo)
	FireGridServer.viento_proximo.connect(_al_anunciar_viento)
	FireGridServer.objetivo_critico_amenazado.connect(_al_amenazar_objetivo)
	NetworkManager.objetivo_critico_recibido.connect(_al_recibir_objetivo_por_red)
	_aplicar_volumenes()


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_al_agregar_nodo):
		get_tree().node_added.disconnect(_al_agregar_nodo)
	if FireGridServer.viento_proximo.is_connected(_al_anunciar_viento):
		FireGridServer.viento_proximo.disconnect(_al_anunciar_viento)
	if FireGridServer.objetivo_critico_amenazado.is_connected(_al_amenazar_objetivo):
		FireGridServer.objetivo_critico_amenazado.disconnect(_al_amenazar_objetivo)
	if NetworkManager.objetivo_critico_recibido.is_connected(_al_recibir_objetivo_por_red):
		NetworkManager.objetivo_critico_recibido.disconnect(_al_recibir_objetivo_por_red)
	for canales_variant in _audio_drones.values():
		if canales_variant is Dictionary:
			_liberar_canales_audio(canales_variant)
	_audio_drones.clear()


func _process(delta: float) -> void:
	_acumulador += delta
	if _acumulador < INTERVALO_ACTUALIZACION:
		return
	_acumulador = 0.0
	_actualizar_audio_drones()
	_actualizar_audio_fuegos()


func configurar_volumen_bus(nombre: String, volumen: float) -> void:
	if not BUSES.has(nombre):
		push_error("No existe el bus de audio solicitado: %s." % nombre)
		return
	var indice := AudioServer.get_bus_index(nombre)
	if indice < 0:
		push_error("No se encontró el bus de audio: %s." % nombre)
		return
	_volumenes[nombre] = clampf(volumen, 0.0, 1.0)
	AudioServer.set_bus_volume_db(indice, _volumen_a_db(float(_volumenes[nombre])))
	if nombre == "Maestro":
		GraphicsSettings.configurar_volumen_maestro(float(_volumenes[nombre]))
	var configuracion := ConfigFile.new()
	var error_carga := configuracion.load(RUTA_CONFIG)
	if error_carga != OK and error_carga != ERR_FILE_NOT_FOUND:
		push_error("No se pudieron leer los volúmenes guardados: %s." % error_carga)
		return
	configuracion.set_value("audio", nombre, _volumenes[nombre])
	var error_guardado := configuracion.save(RUTA_CONFIG)
	if error_guardado != OK:
		push_error(
			"No se pudo guardar el volumen del bus %s (error %d)." % [nombre, error_guardado]
		)


func obtener_volumen_bus(nombre: String) -> float:
	return float(_volumenes.get(nombre, 1.0))


func reproducir_alerta_viento() -> void:
	_reproducir_alerta(0.92)


func reproducir_alerta_objetivo() -> void:
	_reproducir_alerta(1.22)


func _configurar_buses() -> void:
	for nombre in BUSES:
		var indice := AudioServer.get_bus_index(nombre)
		if indice >= 0:
			continue
		AudioServer.add_bus()
		indice = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(indice, nombre)
		AudioServer.set_bus_send(indice, "Maestro" if nombre != "Maestro" else "Master")


func _cargar_volumenes() -> void:
	_volumenes["Maestro"] = GraphicsSettings.volumen_maestro
	var configuracion := ConfigFile.new()
	var error_carga := configuracion.load(RUTA_CONFIG)
	if error_carga != OK and error_carga != ERR_FILE_NOT_FOUND:
		push_error("No se pudieron cargar los volúmenes de audio: %s." % error_carga)
		return
	if error_carga != OK:
		return
	for nombre in BUSES:
		if not configuracion.has_section_key("audio", nombre):
			continue
		var valor: Variant = configuracion.get_value("audio", nombre)
		if valor is int or valor is float:
			_volumenes[nombre] = clampf(float(valor), 0.0, 1.0)
		else:
			push_warning("El volumen guardado del bus %s no es válido." % nombre)


func _aplicar_volumenes() -> void:
	for nombre in BUSES:
		var indice := AudioServer.get_bus_index(nombre)
		if indice >= 0:
			AudioServer.set_bus_volume_db(indice, _volumen_a_db(float(_volumenes[nombre])))


func _volumen_a_db(volumen: float) -> float:
	return linear_to_db(volumen) if volumen > 0.0 else -80.0


func _crear_reproductores_globales() -> void:
	_reproductor_clic = AudioStreamPlayer.new()
	_reproductor_clic.name = "ReproductorClicUI"
	_reproductor_clic.stream = STREAM_CLIC
	_reproductor_clic.bus = "UI"
	add_child(_reproductor_clic)

	_reproductor_alerta = AudioStreamPlayer.new()
	_reproductor_alerta.name = "ReproductorAlertas"
	_reproductor_alerta.stream = STREAM_ALERTA
	_reproductor_alerta.bus = "Efectos"
	add_child(_reproductor_alerta)

	for indice in range(MAXIMO_FUEGOS_AUDIBLES):
		var reproductor := AudioStreamPlayer3D.new()
		reproductor.name = "Fuego3D_%d" % indice
		reproductor.stream = _stream_fuego
		reproductor.bus = "Efectos"
		reproductor.max_distance = 100.0
		reproductor.unit_size = 18.0
		reproductor.top_level = true
		add_child(reproductor)
		_reproductores_fuego.append(reproductor)


func _al_agregar_nodo(nodo: Node) -> void:
	if not nodo is BaseButton or nodo.has_meta("audio_click_conectado"):
		return
	var boton := nodo as BaseButton
	boton.pressed.connect(_reproducir_clic)
	boton.set_meta("audio_click_conectado", true)


func _reproducir_clic() -> void:
	if is_instance_valid(_reproductor_clic):
		_reproductor_clic.play()


func _reproducir_alerta(tono: float) -> void:
	if not is_instance_valid(_reproductor_alerta):
		return
	_reproductor_alerta.pitch_scale = tono
	_reproductor_alerta.play()


func _al_anunciar_viento(_direccion: Vector2, _velocidad: float, _segundos: float) -> void:
	reproducir_alerta_viento()
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		rpc("_rpc_alerta_viento")


@rpc("authority", "call_remote", "reliable", 0)
func _rpc_alerta_viento() -> void:
	reproducir_alerta_viento()


func _al_amenazar_objetivo(_objetivo: Resource) -> void:
	reproducir_alerta_objetivo()


func _al_recibir_objetivo_por_red(datos: Dictionary) -> void:
	if str(datos.get("estado", "")) == "AMENAZADO":
		reproducir_alerta_objetivo()


func _actualizar_audio_drones() -> void:
	var vistos: Dictionary = {}
	for candidato in get_tree().get_nodes_in_group("jugador"):
		if not is_instance_valid(candidato) or not candidato is CharacterBody3D:
			continue
		var dron := candidato as CharacterBody3D
		if dron.is_queued_for_deletion():
			continue
		var id := dron.get_instance_id()
		vistos[id] = true
		var canales: Dictionary = _audio_drones.get(id, {})
		if canales.is_empty() or not _canales_audio_validos(canales):
			_liberar_canales_audio(canales)
			canales = _crear_audio_dron(dron)
			if canales.is_empty():
				continue
			_audio_drones[id] = canales
		var velocidad := dron.velocity.length()
		var rotor := canales["rotor"] as AudioStreamPlayer3D
		if not is_instance_valid(rotor):
			continue
		rotor.pitch_scale = clampf(0.78 + velocidad / 42.0, 0.78, 1.5)
		var rociador := canales["agua"] as AudioStreamPlayer3D
		if not is_instance_valid(rociador):
			continue
		var rociando := bool(dron.get("is_discharging"))
		if rociando and not rociador.playing:
			rociador.play()
		elif not rociando and rociador.playing:
			rociador.stop()
		var recargando := bool(dron.get("is_refilling"))
		if recargando != bool(canales.get("recargando", false)):
			_transicionar_audio_recarga(canales, recargando)
			canales["recargando"] = recargando
	for id_variant in _audio_drones.keys():
		var id := int(id_variant)
		if vistos.has(id):
			continue
		var canales_variant: Variant = _audio_drones[id]
		_audio_drones.erase(id)
		if canales_variant is Dictionary:
			_liberar_canales_audio(canales_variant)


func _canales_audio_validos(canales: Dictionary) -> bool:
	for nombre in ["rotor", "agua", "recarga"]:
		if not is_instance_valid(canales.get(nombre)):
			return false
	return true


func _liberar_canales_audio(canales: Dictionary) -> void:
	var tween: Variant = canales.get("tween_recarga")
	if tween is Tween and is_instance_valid(tween) and tween.is_running():
		tween.kill()
	for nombre in ["rotor", "agua", "recarga"]:
		var reproductor: Variant = canales.get(nombre)
		if not is_instance_valid(reproductor):
			continue
		reproductor.stop()
		reproductor.queue_free()


func _transicionar_audio_recarga(canales: Dictionary, activo: bool) -> void:
	var reproductor := canales.get("recarga") as AudioStreamPlayer3D
	if not is_instance_valid(reproductor):
		return
	var tween_anterior: Variant = canales.get("tween_recarga")
	if (
		tween_anterior is Tween
		and is_instance_valid(tween_anterior)
		and tween_anterior.is_running()
	):
		tween_anterior.kill()
	if activo and not reproductor.playing:
		reproductor.volume_db = -42.0
		reproductor.play()
	var tween := reproductor.create_tween()
	canales["tween_recarga"] = tween
	if activo:
		tween.tween_property(
			reproductor, "volume_db", volumen_recarga_db, duracion_entrada_recarga
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		tween.tween_property(
			reproductor, "volume_db", -60.0, duracion_salida_recarga
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.tween_callback(Callable(reproductor, "stop"))


func _crear_audio_dron(dron: CharacterBody3D) -> Dictionary:
	if not is_instance_valid(dron) or dron.is_queued_for_deletion():
		return {}
	var rotor := AudioStreamPlayer3D.new()
	rotor.name = "AudioRotor"
	rotor.stream = _stream_rotor
	rotor.bus = "Efectos"
	rotor.volume_db = -13.0
	rotor.max_distance = 45.0
	rotor.unit_size = 8.0
	dron.add_child(rotor)
	rotor.play()

	var agua := AudioStreamPlayer3D.new()
	agua.name = "AudioRociado"
	agua.stream = _stream_agua
	agua.bus = "Efectos"
	agua.volume_db = -5.0
	agua.max_distance = 35.0
	agua.unit_size = 7.0
	dron.add_child(agua)

	var recarga := AudioStreamPlayer3D.new()
	recarga.name = "AudioRecarga"
	recarga.stream = _stream_agua
	recarga.bus = "Efectos"
	recarga.volume_db = -42.0
	recarga.max_distance = distancia_maxima_audio_recarga
	recarga.unit_size = 8.0
	dron.add_child(recarga)
	return {
		"rotor": rotor,
		"agua": agua,
		"recarga": recarga,
		"recargando": false,
	}


func _actualizar_audio_fuegos() -> void:
	var camara := get_viewport().get_camera_3d()
	if not is_instance_valid(camara):
		for reproductor in _reproductores_fuego:
			if is_instance_valid(reproductor):
				reproductor.stop()
		return
	var candidatos: Array[Dictionary] = []
	for elemento in get_tree().get_nodes_in_group("fuego"):
		if (
			not is_instance_valid(elemento)
			or not elemento is Node3D
			or not elemento.is_visible_in_tree()
		):
			continue
		var fuego := elemento as Node3D
		var distancia := camara.global_position.distance_squared_to(fuego.global_position)
		if distancia > 10000.0:
			continue
		candidatos.append({"nodo": fuego, "distancia": distancia})
	candidatos.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["distancia"]) < float(b["distancia"])
	)

	for indice in range(_reproductores_fuego.size()):
		var reproductor := _reproductores_fuego[indice]
		if not is_instance_valid(reproductor):
			continue
		if indice >= candidatos.size():
			reproductor.stop()
			continue
		var fuego: Variant = candidatos[indice]["nodo"]
		if not is_instance_valid(fuego):
			reproductor.stop()
			continue
		fuego = fuego as Node3D
		var distancia := sqrt(float(candidatos[indice]["distancia"]))
		reproductor.global_position = fuego.global_position
		reproductor.volume_db = _volumen_a_db(clampf(1.0 - distancia / 120.0, 0.01, 0.65))
		if not reproductor.playing:
			reproductor.play()
