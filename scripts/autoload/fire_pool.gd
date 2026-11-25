extends Node

const TAMANO_MAX := 250
const ESCENA_FUEGO: PackedScene = preload("res://scenes/actors/fire_source.tscn")

var tamano_max_actual: int = TAMANO_MAX
var max_particulas_por_fuego: int = 120
var _libres: Array[Node3D] = []
var _activos: Array[Node3D] = []
var _precalentado: bool = false

func _ready() -> void:
	GraphicsSettings.calidad_cambiada.connect(_aplicar_perfil_calidad)
	_aplicar_perfil_calidad(GraphicsSettings.calidad_actual)

func set_tamano_max(cantidad: int) -> void:
	tamano_max_actual = clampi(cantidad, 1, TAMANO_MAX)
	_recortar_pool()
	if _precalentado:
		precalentar()

func precalentar() -> void:
	_recortar_pool()
	while _libres.size() + _activos.size() < tamano_max_actual:
		var fuego := _crear_fuego_inactivo()
		if not fuego:
			return
		_libres.append(fuego)
	_precalentado = true

func _aplicar_perfil_calidad(calidad: int) -> void:
	var perfil := GraphicsSettings.obtener_perfil(calidad)
	if perfil.is_empty():
		return
	max_particulas_por_fuego = int(perfil["max_particles_per_fire"])
	set_tamano_max(int(perfil["max_fire_effects"]))
	for fuego in _libres:
		_actualizar_particulas_fuego(fuego)
	for fuego in _activos:
		_actualizar_particulas_fuego(fuego)

func _actualizar_particulas_fuego(fuego: Node3D) -> void:
	fuego.set("max_particulas_humo", max_particulas_por_fuego)
	if fuego.has_method("configurar_max_particulas_humo"):
		fuego.call("configurar_max_particulas_humo", max_particulas_por_fuego)

func adquirir(
	posicion: Vector3,
	viento: Vector3,
	objetivo_extinguible: bool = true,
	propietario: Node = null
) -> Node3D:
	if _libres.is_empty():
		if _activos.is_empty():
			push_error("FirePool no tiene efectos disponibles; llama a precalentar() al cargar el mapa.")
			return null
		var fuego_mas_lejano := _buscar_fuego_mas_lejano()
		push_warning("FirePool agotado; se reutiliza el efecto activo más lejano.")
		liberar(fuego_mas_lejano)
	if _libres.is_empty():
		push_error("FirePool no pudo recuperar un efecto disponible.")
		return null

	var fuego: Node3D = _libres.pop_back()
	_activos.append(fuego)
	fuego.set("objetivo_extinguible", objetivo_extinguible)
	fuego.set("propietario_pool", propietario)
	fuego.process_mode = Node.PROCESS_MODE_INHERIT
	fuego.visible = true
	if not fuego.has_method("reset"):
		push_error("El efecto del pool no implementa reset(posicion, viento).")
		liberar(fuego)
		return null
	fuego.call("reset", posicion, viento)
	fuego.add_to_group("fuego")
	print("FirePool: adquirido instance_id=", fuego.get_instance_id())
	return fuego

func liberar(fuego: Node3D) -> void:
	if not is_instance_valid(fuego):
		return
	var indice := _activos.find(fuego)
	if indice < 0:
		return
	_activos.remove_at(indice)

	var propietario: Variant = fuego.get("propietario_pool")
	if is_instance_valid(propietario) and propietario.has_method("olvidar_visual_fuego"):
		propietario.call("olvidar_visual_fuego", fuego)
	fuego.set("propietario_pool", null)
	if fuego.has_method("desactivar_para_pool"):
		fuego.call("desactivar_para_pool")
	else:
		fuego.visible = false
		fuego.process_mode = Node.PROCESS_MODE_DISABLED

	if _libres.size() + _activos.size() > tamano_max_actual:
		remove_child(fuego)
		fuego.queue_free()
		return
	_libres.append(fuego)

func _crear_fuego_inactivo() -> Node3D:
	var fuego := ESCENA_FUEGO.instantiate() as Node3D
	if not fuego:
		push_error("FirePool no pudo instanciar fire_source.tscn.")
		return null
	if not fuego.has_method("preparar_para_pool"):
		push_error("fire_source.tscn no implementa preparar_para_pool().")
		fuego.queue_free()
		return null
	fuego.set("max_particulas_humo", max_particulas_por_fuego)
	fuego.call("preparar_para_pool")
	fuego.visible = false
	fuego.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(fuego)
	return fuego

func _buscar_fuego_mas_lejano() -> Node3D:
	var camara := get_viewport().get_camera_3d()
	var mas_lejano: Node3D = _activos[0]
	if not camara:
		return mas_lejano
	var distancia_maxima := -1.0
	for fuego in _activos:
		if not is_instance_valid(fuego):
			continue
		var distancia := camara.global_position.distance_squared_to(fuego.global_position)
		if distancia > distancia_maxima:
			distancia_maxima = distancia
			mas_lejano = fuego
	return mas_lejano

func _recortar_pool() -> void:
	while _libres.size() + _activos.size() > tamano_max_actual and not _libres.is_empty():
		var fuego: Node3D = _libres.pop_back()
		remove_child(fuego)
		fuego.queue_free()
