extends CanvasLayer

@onready var datos_rendimiento: Label = $Panel/Contenido/DatosRendimiento

var tiempo_actualizacion: float = 0.0
const INTERVALO_ACTUALIZACION: float = 0.25

func _ready() -> void:
	visible = false
	set_process(false)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		visible = not visible
		set_process(visible)
		if visible:
			tiempo_actualizacion = 0.0
			_actualizar_datos()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not visible:
		return
	tiempo_actualizacion += delta
	if tiempo_actualizacion >= INTERVALO_ACTUALIZACION:
		tiempo_actualizacion = 0.0
		_actualizar_datos()

func _actualizar_datos() -> void:
	var fps := Engine.get_frames_per_second()
	var tiempo_frame_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var llamadas_dibujo := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var objetos_en_pantalla := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	var memoria_video_mb := float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)) / (1024.0 * 1024.0)
	var cantidad_nodos := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var particulas_visibles := 0
	for nodo in get_tree().get_nodes_in_group("particulas_fuego"):
		if nodo is GPUParticles3D and nodo.is_visible_in_tree() and nodo.emitting:
			particulas_visibles += 1
	var fuegos_activos := get_tree().get_nodes_in_group("fuego").size()
	var bytes_por_jugador: Dictionary = NetworkManager.obtener_bytes_por_segundo()
	var ids_jugadores: Array = bytes_por_jugador.keys()
	ids_jugadores.sort()
	var lineas_red := PackedStringArray()
	for id_variant in ids_jugadores:
		var id := int(id_variant)
		var jugador: Dictionary = NetworkManager.jugadores.get(id, {})
		var nombre := str(jugador.get("nombre", "Jugador %d" % id))
		lineas_red.append("%s: %d B/s" % [nombre, int(bytes_por_jugador[id])])
	var texto_red := "\n".join(lineas_red) if not lineas_red.is_empty() else "Sin clientes conectados"
	datos_rendimiento.text = (
		"FPS: %d\n" % fps
		+ "Tiempo de frame: %.2f ms\n" % tiempo_frame_ms
		+ "Draw calls: %d\n" % llamadas_dibujo
		+ "Objetos en pantalla: %d\n" % objetos_en_pantalla
		+ "Memoria de video: %.1f MiB\n" % memoria_video_mb
		+ "Nodos: %d\n" % cantidad_nodos
		+ "Partículas de fuego visibles: %d\n" % particulas_visibles
		+ "Fuegos activos: %d\n" % fuegos_activos
		+ "Tráfico enviado estimado por jugador:\n%s" % texto_red
	)
