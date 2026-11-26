extends Node

const CELDA_METROS: float = 2.0
const DISTANCIA_MAXIMA_VISUAL: float = 150.0
const INTERVALO_RECONCILIACION: float = 0.5
const ESTADO_SANO: int = 0
const ESTADO_ARDIENDO: int = 1
const ESTADO_QUEMADO: int = 2
const ESTADO_MOJADO: int = 3

var arboles_iniciales: Array[Node3D] = []
var _visuales_por_celda: Dictionary = {}
var _arboles_por_celda: Dictionary = {}
var _estados_por_celda: PackedByteArray = PackedByteArray()
var _temporizador: Timer
var _fuego_central: Node3D

func configurar(arboles: Array[Node3D]) -> void:
	arboles_iniciales = arboles

func _ready() -> void:
	FireGridServer.celdas_modificadas.connect(_al_modificarse_celdas)
	FireGridServer.estado_inicial.connect(_al_recibir_estado_inicial)
	_fuego_central = get_tree().root.find_child("WildfireZone", true, false) as Node3D
	_temporizador = Timer.new()
	_temporizador.name = "TemporizadorVisualFireGrid"
	_temporizador.wait_time = INTERVALO_RECONCILIACION
	_temporizador.timeout.connect(_reconciliar_visuales)
	add_child(_temporizador)
	_temporizador.start()
	if FireGridServer.activa:
		_reconstruir_mapa_arboles()
		_reconciliar_visuales()

func _exit_tree() -> void:
	if is_instance_valid(_temporizador):
		_temporizador.stop()
	if FireGridServer.celdas_modificadas.is_connected(_al_modificarse_celdas):
		FireGridServer.celdas_modificadas.disconnect(_al_modificarse_celdas)
	if FireGridServer.estado_inicial.is_connected(_al_recibir_estado_inicial):
		FireGridServer.estado_inicial.disconnect(_al_recibir_estado_inicial)
	for indice in _visuales_por_celda.keys().duplicate():
		_liberar_visual(int(indice))
	_visuales_por_celda.clear()
	_arboles_por_celda.clear()
	arboles_iniciales.clear()
	_fuego_central = null
	_temporizador = null

func olvidar_visual_fuego(visual: Node3D) -> void:
	var celdas_anteriores: Array = []
	for indice in _visuales_por_celda.keys().duplicate():
		var visual_guardado: Variant = _visuales_por_celda[indice]
		if not is_instance_valid(visual_guardado) or visual_guardado == visual:
			celdas_anteriores.append(indice)
	for indice in celdas_anteriores:
		_visuales_por_celda.erase(indice)

func _al_recibir_estado_inicial(_datos: PackedByteArray) -> void:
	_reconstruir_mapa_arboles()
	_actualizar_efecto_central()
	_reconciliar_visuales()

func _reconstruir_mapa_arboles() -> void:
	_arboles_por_celda.clear()
	_estados_por_celda = FireGridServer.obtener_estado_celdas()
	if not FireGridServer.activa:
		return
	var origen: Vector2 = FireGridServer.obtener_origen()
	var tamano: Vector2i = FireGridServer.obtener_tamano_celdas()
	for arbol in arboles_iniciales:
		if not is_instance_valid(arbol) or arbol.is_queued_for_deletion():
			continue
		var celda_x := floori((arbol.global_position.x - origen.x) / CELDA_METROS)
		var celda_y := floori((arbol.global_position.z - origen.y) / CELDA_METROS)
		if celda_x < 0 or celda_y < 0 or celda_x >= tamano.x or celda_y >= tamano.y:
			continue
		_arboles_por_celda[celda_y * tamano.x + celda_x] = arbol
	for indice in _arboles_por_celda:
		if indice >= 0 and indice < _estados_por_celda.size():
			_actualizar_estado_arbol(int(indice), int(_estados_por_celda[indice]))

func _al_modificarse_celdas(deltas: Array) -> void:
	for delta_estado in deltas:
		if not delta_estado is Array or delta_estado.size() != 2:
			continue
		var indice := int(delta_estado[0])
		var estado := int(delta_estado[1])
		if indice < 0 or indice >= _estados_por_celda.size():
			continue
		_estados_por_celda[indice] = estado
		_actualizar_estado_arbol(indice, estado)
		if estado == ESTADO_SANO or estado == ESTADO_QUEMADO or estado == ESTADO_MOJADO:
			_liberar_visual(indice)
	_actualizar_efecto_central()

func _reconciliar_visuales() -> void:
	if not FireGridServer.activa:
		return
	_actualizar_efecto_central()
	var camara := get_viewport().get_camera_3d()
	if not is_instance_valid(camara):
		return
	var celdas_ardiendo := FireGridServer.obtener_celdas_ardiendo()
	var estados := FireGridServer.obtener_estado_celdas()
	var alturas := FireGridServer.obtener_alturas()
	var origen := FireGridServer.obtener_origen()
	var tamano := FireGridServer.obtener_tamano_celdas()
	var viento := FireGridServer.obtener_viento()
	var viento_visual := Vector3(viento.x, 0.0, viento.y)
	var candidatas: Array[Dictionary] = []
	for indice in _visuales_por_celda.keys().duplicate():
		var visual: Variant = _visuales_por_celda[indice]
		if not is_instance_valid(visual):
			_visuales_por_celda.erase(indice)
			continue
		if indice < 0 or indice >= estados.size() or estados[indice] != ESTADO_ARDIENDO:
			_liberar_visual(int(indice))
			continue
		if (
			camara.global_position.distance_squared_to(visual.global_position)
			> DISTANCIA_MAXIMA_VISUAL * DISTANCIA_MAXIMA_VISUAL
		) and not FireGridServer.es_celda_arbol_foco(int(indice)):
			_liberar_visual(int(indice))
			continue
		_actualizar_intensidad_fuego(int(indice))

	for indice in celdas_ardiendo:
		if indice < 0 or indice >= alturas.size():
			continue
		if indice >= estados.size() or estados[indice] != ESTADO_ARDIENDO:
			continue
		var celda := Vector2i(indice % tamano.x, floori(float(indice) / float(tamano.x)))
		var posicion := Vector3(
			origen.x + (float(celda.x) + 0.5) * CELDA_METROS,
			alturas[indice],
			origen.y + (float(celda.y) + 0.5) * CELDA_METROS
		)
		var distancia_cuadrada := camara.global_position.distance_squared_to(posicion)
		var es_foco := FireGridServer.es_celda_arbol_foco(indice)
		if (
			distancia_cuadrada <= DISTANCIA_MAXIMA_VISUAL * DISTANCIA_MAXIMA_VISUAL
			or es_foco
		):
			candidatas.append({
				"indice": indice,
				"posicion": posicion,
				"distancia": distancia_cuadrada,
				"foco": es_foco,
			})
	candidatas.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a["foco"]) != bool(b["foco"]):
			return bool(a["foco"])
		return float(a["distancia"]) < float(b["distancia"])
	)
	var limite := mini(FirePool.tamano_max_actual, FirePool.TAMANO_MAX)
	for candidato in candidatas:
		var indice: int = candidato["indice"]
		if _visuales_por_celda.has(indice):
			continue
		if _visuales_por_celda.size() >= limite:
			var distancia_mas_lejana := _distancia_visual_mas_lejana(camara)
			if float(candidato["distancia"]) >= distancia_mas_lejana:
				break
		var posicion: Vector3 = candidato["posicion"]
		var visual := FirePool.adquirir(posicion, viento_visual, false, self)
		if not is_instance_valid(visual):
			continue
		if _visuales_por_celda.has(indice):
			FirePool.liberar(visual)
			continue
		_visuales_por_celda[indice] = visual
		_actualizar_intensidad_fuego(indice)

func _distancia_visual_mas_lejana(camara: Camera3D) -> float:
	var distancia_maxima: float = -1.0
	for visual in _visuales_por_celda.values():
		if not is_instance_valid(visual):
			continue
		distancia_maxima = maxf(
			distancia_maxima,
			camara.global_position.distance_squared_to(visual.global_position)
		)
	return distancia_maxima

func _actualizar_efecto_central() -> void:
	if not is_instance_valid(_fuego_central) or not FireGridServer.activa:
		return
	var hay_fuego := FireGridServer.obtener_cantidad_ardiendo() > 0
	var extinguiendo := bool(_fuego_central.get("extinguishing"))
	if hay_fuego and extinguiendo:
		var viento := FireGridServer.obtener_viento()
		_fuego_central.call(
			"reset",
			_fuego_central.global_position,
			Vector3(viento.x, 0.0, viento.y)
		)
	elif not hay_fuego and not extinguiendo:
		_fuego_central.call("extinguish")

func _liberar_visual(indice: int) -> void:
	if not _visuales_por_celda.has(indice):
		return
	var visual: Variant = _visuales_por_celda[indice]
	_visuales_por_celda.erase(indice)
	if is_instance_valid(visual):
		FirePool.liberar(visual)

func _carbonizar_arbol(indice: int) -> void:
	_actualizar_estado_arbol(indice, ESTADO_QUEMADO)

func _actualizar_estado_arbol(indice: int, estado: int) -> void:
	var arbol_variant: Variant = _arboles_por_celda.get(indice)
	if (
		is_instance_valid(arbol_variant)
		and not arbol_variant.is_queued_for_deletion()
		and arbol_variant.has_method("actualizar_estado_fuego")
	):
		arbol_variant.call("actualizar_estado_fuego", estado)
	_actualizar_intensidad_fuego(indice)

func _actualizar_intensidad_fuego(indice: int) -> void:
	var intensidad: float = FireGridServer.obtener_intensidad_fuego(indice)
	var arbol_variant: Variant = _arboles_por_celda.get(indice)
	if (
		is_instance_valid(arbol_variant)
		and not arbol_variant.is_queued_for_deletion()
		and arbol_variant.has_method("actualizar_intensidad_fuego")
	):
		arbol_variant.call("actualizar_intensidad_fuego", intensidad)
	var visual_variant: Variant = _visuales_por_celda.get(indice)
	if (
		is_instance_valid(visual_variant)
		and not visual_variant.is_queued_for_deletion()
		and visual_variant.has_method("set_intensidad")
	):
		visual_variant.call("set_intensidad", intensidad / 100.0)
