extends Control

const COLOR_SANO: Color = Color(0.16, 0.39, 0.18, 1.0)
const COLOR_ARDIENDO: Color = Color(0.94, 0.16, 0.06, 1.0)
const COLOR_QUEMADO: Color = Color(0.34, 0.35, 0.36, 1.0)
const COLOR_MOJADO: Color = Color(0.08, 0.48, 0.9, 1.0)
const INTERVALO_REDIBUJO: float = 0.25

var _imagen: Image
var _textura: ImageTexture
var _vista_textura: TextureRect
var _temporizador: Timer
var _origen: Vector2 = Vector2.ZERO
var _tamano_celdas: Vector2i = Vector2i.ZERO
var _textura_sucia: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vista_textura = TextureRect.new()
	_vista_textura.name = "TexturaGrilla"
	_vista_textura.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vista_textura.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vista_textura.stretch_mode = TextureRect.STRETCH_SCALE
	_vista_textura.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vista_textura)

	FireGridServer.celdas_modificadas.connect(_al_modificarse_celdas)
	FireGridServer.estado_inicial.connect(_al_estado_inicial)
	_temporizador = Timer.new()
	_temporizador.name = "TemporizadorMinimapa"
	_temporizador.wait_time = INTERVALO_REDIBUJO
	_temporizador.timeout.connect(_actualizar_minimapa)
	add_child(_temporizador)
	_temporizador.start()
	if FireGridServer.activa:
		_inicializar_imagen()

func _exit_tree() -> void:
	if FireGridServer.celdas_modificadas.is_connected(_al_modificarse_celdas):
		FireGridServer.celdas_modificadas.disconnect(_al_modificarse_celdas)
	if FireGridServer.estado_inicial.is_connected(_al_estado_inicial):
		FireGridServer.estado_inicial.disconnect(_al_estado_inicial)

func _al_estado_inicial(_datos: PackedByteArray) -> void:
	_inicializar_imagen()

func _inicializar_imagen() -> void:
	if not FireGridServer.activa:
		return
	_origen = FireGridServer.obtener_origen()
	_tamano_celdas = FireGridServer.obtener_tamano_celdas()
	if _tamano_celdas.x <= 0 or _tamano_celdas.y <= 0:
		return
	_imagen = Image.create(
		_tamano_celdas.x,
		_tamano_celdas.y,
		false,
		Image.FORMAT_RGBA8
	)
	var estados := FireGridServer.obtener_estado_celdas()
	for indice in range(estados.size()):
		_imagen.set_pixel(
			indice % _tamano_celdas.x,
			floori(float(indice) / float(_tamano_celdas.x)),
			_color_estado(int(estados[indice]))
		)
	_textura = ImageTexture.create_from_image(_imagen)
	_vista_textura.texture = _textura
	_textura_sucia = false
	queue_redraw()

func _al_modificarse_celdas(deltas: Array) -> void:
	if _imagen == null:
		_inicializar_imagen()
	if _imagen == null:
		return
	for cambio in deltas:
		if not cambio is Array or cambio.size() != 2:
			continue
		var indice := int(cambio[0])
		if indice < 0 or indice >= _tamano_celdas.x * _tamano_celdas.y:
			continue
		_imagen.set_pixel(
			indice % _tamano_celdas.x,
			floori(float(indice) / float(_tamano_celdas.x)),
			_color_estado(int(cambio[1]))
		)
		_textura_sucia = true

func _actualizar_minimapa() -> void:
	if _imagen == null and FireGridServer.activa:
		_inicializar_imagen()
	if _textura_sucia and is_instance_valid(_textura):
		_textura.update(_imagen)
		_textura_sucia = false
	queue_redraw()

func _draw() -> void:
	if _tamano_celdas.x <= 0 or _tamano_celdas.y <= 0:
		return
	for fuente in get_tree().get_nodes_in_group("fuente_agua"):
		if fuente is Node3D:
			_dibujar_marcador(fuente.global_position, Color("#35cfff"), 3.0)
	for marcador in FireGridServer.obtener_marcadores_objetivos_criticos():
		var posicion: Variant = marcador.get("posicion", Vector3.ZERO)
		if posicion is Vector3:
			_dibujar_marcador(posicion, Color("#ffe45b"), 2.5)

	var drones := NetworkManager.obtener_drones_por_id()
	for id_variant in drones.keys():
		var dron: Variant = drones[id_variant]
		if not is_instance_valid(dron) or not dron is Node3D:
			continue
		var color := Color("#54e6ff")
		var datos: Dictionary = NetworkManager.jugadores.get(int(id_variant), {})
		if datos.has("equipo"):
			color = _color_equipo(str(datos["equipo"]))
		_dibujar_marcador((dron as Node3D).global_position, color, 3.2)
	if drones.is_empty() and not multiplayer.has_multiplayer_peer():
		for dron in get_tree().get_nodes_in_group("jugador"):
			if dron is Node3D:
				_dibujar_marcador((dron as Node3D).global_position, Color("#54e6ff"), 3.2)

func _dibujar_marcador(posicion: Vector3, color: Color, radio: float) -> void:
	var punto := Vector2(
		(posicion.x - _origen.x) / (float(_tamano_celdas.x) * 2.0) * size.x,
		(posicion.z - _origen.y) / (float(_tamano_celdas.y) * 2.0) * size.y
	)
	if Rect2(Vector2.ZERO, size).has_point(punto):
		draw_circle(punto, radio, color)

func _color_estado(estado: int) -> Color:
	match estado:
		1:
			return COLOR_ARDIENDO
		2:
			return COLOR_QUEMADO
		3:
			return COLOR_MOJADO
		_:
			return COLOR_SANO

func _color_equipo(equipo: String) -> Color:
	var indice := absi(equipo.hash()) % 6
	var colores: Array[Color] = [
		Color("#54e6ff"),
		Color("#ffa943"),
		Color("#d47bff"),
		Color("#83e36a"),
		Color("#ff7190"),
		Color("#f2e85b"),
	]
	return colores[indice]
