extends Control

const DISTANCIA_CELDA: float = 2.0
const MAX_MARCADORES: int = 600

var activo: bool = false
var alcance: float = 0.0
var _duracion_restante: float = 0.0
var _acumulador_dibujo: float = 0.0

func activar(nuevo_alcance: float, duracion: float) -> void:
	alcance = maxf(nuevo_alcance, 0.0)
	_duracion_restante = maxf(duracion, 0.0)
	activo = _duracion_restante > 0.0 and alcance > 0.0
	visible = activo
	queue_redraw()

func _process(delta: float) -> void:
	if not activo:
		return
	_duracion_restante = maxf(_duracion_restante - delta, 0.0)
	if _duracion_restante <= 0.0:
		activo = false
		visible = false
		return
	_acumulador_dibujo += delta
	if _acumulador_dibujo >= 0.2:
		_acumulador_dibujo = 0.0
		queue_redraw()

func _draw() -> void:
	if not activo or not FireGridServer.activa:
		return
	var camara := get_viewport().get_camera_3d()
	if not is_instance_valid(camara):
		return
	var celdas := FireGridServer.obtener_celdas_ardiendo()
	var alturas := FireGridServer.obtener_alturas()
	var origen := FireGridServer.obtener_origen()
	var tamano := FireGridServer.obtener_tamano_celdas()
	if tamano.x <= 0:
		return
	var centro := camara.global_position
	var dibujados: int = 0
	for indice in celdas:
		if indice < 0 or indice >= alturas.size():
			continue
		var celda_x := indice % tamano.x
		var celda_y := floori(float(indice) / float(tamano.x))
		var posicion := Vector3(
			origen.x + (float(celda_x) + 0.5) * DISTANCIA_CELDA,
			alturas[indice] + 1.0,
			origen.y + (float(celda_y) + 0.5) * DISTANCIA_CELDA
		)
		if Vector2(posicion.x - centro.x, posicion.z - centro.z).length() > alcance:
			continue
		if camara.is_position_behind(posicion):
			continue
		var pantalla := camara.unproject_position(posicion)
		draw_circle(pantalla, 8.0, Color(1.0, 0.25, 0.04, 0.16))
		draw_arc(pantalla, 10.0, 0.0, TAU, 16, Color(1.0, 0.72, 0.14, 0.9), 2.0)
		dibujados += 1
		if dibujados >= MAX_MARCADORES:
			break
