extends Node

signal celdas_modificadas(deltas: Array)
signal estado_inicial(datos: PackedByteArray)
signal incendio_descontrolado
signal viento_proximo(direccion: Vector2, velocidad: float, segundos: float)
signal viento_cambiado(direccion: Vector2, velocidad: float)
signal objetivo_critico_amenazado(objetivo: Resource)
signal objetivo_critico_perdido(objetivo: Resource)
signal objetivos_criticos_actualizados(resumen: Array, puntaje: int, bono: int)
signal explosion_deposito(posicion: Vector3, radio: float)
signal agua_aplicada_por_jugador(peer_id: int, celdas_con_agua: PackedInt32Array, celdas_apagadas: PackedInt32Array)

const SCRIPT_FIRE_GRID: Script = preload("res://scripts/sim/fire_grid.gd")
const SCRIPT_WIND_SYSTEM: Script = preload("res://scripts/sim/wind_system.gd")
const SCRIPT_OBJETIVO_CRITICO: Script = preload("res://scripts/world/objetivo_critico.gd")
const INTERVALO_SIMULACION: float = 0.3
const CELDA_METROS: float = 2.0
const INTERVALO_DEBUG_FRENTE: float = 10.0
const MAX_CELDAS_FOCO_INICIAL: int = 30
const RADIO_CONTAGIO_CHISPA: float = 7.0
const PROBABILIDAD_CONTAGIO_CHISPA: float = 0.3
const ESTADO_QUEMADO: int = 2
const ESTADO_ARDIENDO: int = 1
const TIPO_BOSQUE_SECO: int = 0
const TIPO_PASTIZAL: int = 1
const TIPO_VIVIENDA: int = 2
const TIPO_SIN_COMBUSTIBLE: int = 3
const TIPO_OBJETIVO_VIVIENDA: int = 0
const TIPO_OBJETIVO_TORRE: int = 1
const TIPO_OBJETIVO_DEPOSITO: int = 2
const TIPO_OBJETIVO_DUCTO: int = 3
const RADIO_EXPLOSION_DEPOSITO: float = 20.0

var grilla: RefCounted
var activa: bool = false
var porcentaje_derrota: float = 70.0
var tipo_objetivo_derrota: int = -1
var _viento: Vector2 = Vector2.ZERO
var _temporizador: Timer
var _tipos_temporales: PackedByteArray = PackedByteArray()
var _combustible_temporal: PackedFloat32Array = PackedFloat32Array()
var _altura_temporal: PackedFloat32Array = PackedFloat32Array()
var _mision_fallida: bool = false
var _indices_arboles_foco: Dictionary = {}
var _indices_vivienda: PackedInt32Array = PackedInt32Array()
var _objetivos_criticos: Array[Dictionary] = []
var _puntaje_objetivos: int = 0
var _bono_cero_perdidas: int = 0
var _bono_objetivos_otorgado: int = 0
var _objetivos_finalizados: bool = false
var _sistema_viento: Node
var _retardo_propagacion_restante: float = 0.0
var _centro_foco: Vector2 = Vector2.ZERO
var _ultima_medicion_frente_ms: int = 0
var _distancia_frente_anterior: float = 0.0

func _ready() -> void:
	_temporizador = Timer.new()
	_temporizador.name = "TemporizadorFireGrid"
	_temporizador.wait_time = INTERVALO_SIMULACION
	_temporizador.one_shot = false
	_temporizador.timeout.connect(_avanzar_simulacion)
	add_child(_temporizador)
	_sistema_viento = SCRIPT_WIND_SYSTEM.new() as Node
	_sistema_viento.name = "WindSystem"
	_sistema_viento.connect("viento_proximo", _al_anunciar_viento)
	_sistema_viento.connect("viento_cambiado", _al_cambiar_viento)
	add_child(_sistema_viento)

func configurar_escenario(
	generador_vegetacion: Node,
	configuracion: Resource,
	posiciones_arboles: Array[Vector2],
	arboles_iniciales: Array[Node3D],
	semilla: int
) -> void:
	if not generador_vegetacion.has_method("get_exact_ground_y"):
		push_error("FireGridServer requiere get_exact_ground_y() en el spawner.")
		return
	if not is_instance_valid(configuracion) or not configuracion is ConfiguracionGrillaIncendio:
		push_error("FireGridServer requiere una ConfiguracionGrillaIncendio válida.")
		return
	var opciones_lanzamiento := get_node_or_null("/root/MissionLaunchOptions")
	if (
		not is_instance_valid(opciones_lanzamiento)
		or not opciones_lanzamiento.has_method("apply_to_configuration")
	):
		push_error("FireGridServer no encuentra el autoload MissionLaunchOptions.")
		return
	var configuracion_efectiva: Variant = opciones_lanzamiento.call(
		"apply_to_configuration",
		configuracion
	)
	if (
		not is_instance_valid(configuracion_efectiva)
		or not configuracion_efectiva is ConfiguracionGrillaIncendio
	):
		push_error("FireGridServer no pudo preparar la configuración de misión.")
		return
	var configuracion_tipada := configuracion_efectiva as ConfiguracionGrillaIncendio
	detener()
	var origen_nuevo: Variant = configuracion_efectiva.get("origen")
	var tamano_nuevo: Variant = configuracion_efectiva.get("tamano_celdas")
	if not origen_nuevo is Vector2 or not tamano_nuevo is Vector2i:
		push_error("La configuración de FireGrid tiene origen o dimensiones inválidas.")
		return
	var configuracion_viento: Variant = configuracion_efectiva.get("configuracion_viento")
	if not configuracion_viento is Resource:
		push_error("La configuración de FireGrid requiere un Resource de viento.")
		return
	if not bool(_sistema_viento.call("configurar", configuracion_viento, semilla)):
		return

	grilla = SCRIPT_FIRE_GRID.new(origen_nuevo, tamano_nuevo, semilla)
	grilla.call("configurar_terreno_sin_combustible")
	grilla.set("velocidad_propagacion", configuracion_tipada.velocidad_propagacion)
	porcentaje_derrota = clampf(float(configuracion_efectiva.get("porcentaje_derrota")), 1.0, 100.0)
	tipo_objetivo_derrota = int(configuracion_efectiva.get("tipo_objetivo_derrota"))
	_bono_cero_perdidas = maxi(configuracion_tipada.bono_cero_perdidas, 0)
	_retardo_propagacion_restante = 0.0
	_mision_fallida = false
	_aplicar_perfiles(configuracion_efectiva)
	var zona_viento_erratico: Vector3 = configuracion_tipada.zona_viento_erratico
	if zona_viento_erratico.z > 0.0:
		grilla.call(
			"configurar_viento_erratico",
			Vector2(zona_viento_erratico.x, zona_viento_erratico.y),
			zona_viento_erratico.z,
			deg_to_rad(configuracion_tipada.amplitud_viento_erratico_grados)
		)
	_rellenar_alturas(generador_vegetacion, origen_nuevo, tamano_nuevo)
	_inicializar_combustible(
		posiciones_arboles, origen_nuevo, tamano_nuevo, configuracion_efectiva
	)
	grilla.set("altura", _altura_temporal)
	grilla.set("tipo_combustible", _tipos_temporales)
	grilla.set("combustible", _combustible_temporal)
	_registrar_objetivos_criticos(
		configuracion_tipada.objetivos_criticos,
		origen_nuevo,
		tamano_nuevo,
		float(configuracion_efectiva.get("combustible_bosque")),
		float(configuracion_efectiva.get("combustible_vivienda"))
	)
	grilla.call("reconstruir_contadores")
	_encender_foco_inicial(arboles_iniciales, configuracion_efectiva)
	_actualizar_objetivos_criticos(0.0)
	grilla.call("obtener_deltas")
	_distancia_frente_anterior = _medir_distancia_frente()
	_ultima_medicion_frente_ms = Time.get_ticks_msec()
	activa = true
	_temporizador.start(INTERVALO_SIMULACION)
	estado_inicial.emit(grilla.call("serializar_completo"))

func detener() -> void:
	if _temporizador:
		_temporizador.stop()
	if is_instance_valid(_sistema_viento):
		_sistema_viento.call("detener")
	activa = false
	grilla = null
	_viento = Vector2.ZERO
	_tipos_temporales = PackedByteArray()
	_combustible_temporal = PackedFloat32Array()
	_altura_temporal = PackedFloat32Array()
	_indices_arboles_foco.clear()
	_indices_vivienda = PackedInt32Array()
	_objetivos_criticos.clear()
	_puntaje_objetivos = 0
	_bono_cero_perdidas = 0
	_bono_objetivos_otorgado = 0
	_objetivos_finalizados = false
	_retardo_propagacion_restante = 0.0
	tipo_objetivo_derrota = -1
	_ultima_medicion_frente_ms = 0
	_distancia_frente_anterior = 0.0
	_centro_foco = Vector2.ZERO

func aplicar_agua(pos_mundo: Vector3, radio: float, cantidad: float) -> int:
	if not activa or not is_instance_valid(grilla) or _es_cliente_multijugador():
		return 0
	var cantidad_apagada := int(grilla.call(
		"aplicar_agua",
		Vector2(pos_mundo.x, pos_mundo.z),
		radio,
		cantidad
	))
	_emitir_deltas_pendientes()
	_comprobar_derrota()
	return cantidad_apagada

func aplicar_agua_atribuida(
	peer_id: int,
	pos_mundo: Vector3,
	radio: float,
	cantidad: float
) -> int:
	if not activa or not is_instance_valid(grilla) or _es_cliente_multijugador():
		return 0
	var cantidad_apagada := int(grilla.call(
		"aplicar_agua",
		Vector2(pos_mundo.x, pos_mundo.z),
		radio,
		cantidad
	))
	var celdas_con_agua: PackedInt32Array = grilla.call("obtener_ultimas_celdas_con_agua")
	var celdas_apagadas: PackedInt32Array = grilla.call("obtener_ultimas_celdas_apagadas")
	agua_aplicada_por_jugador.emit(peer_id, celdas_con_agua, celdas_apagadas)
	_emitir_deltas_pendientes()
	_comprobar_derrota()
	return cantidad_apagada

func aplicar_retardante(pos_mundo: Vector3, radio: float) -> bool:
	if not activa or not is_instance_valid(grilla) or _es_cliente_multijugador():
		return false
	var tamano: Vector2i = grilla.get("tamano_celdas")
	var celda: Vector2i = grilla.call("mundo_a_celda", Vector2(pos_mundo.x, pos_mundo.z))
	if celda.x < 0 or celda.y < 0 or celda.x >= tamano.x or celda.y >= tamano.y:
		return false
	grilla.call(
		"aplicar_retardante",
		Vector2(pos_mundo.x, pos_mundo.z),
		radio
	)
	_emitir_deltas_pendientes()
	return true

func propagar_chispa(posicion: Vector3, direccion_viento: Vector2) -> int:
	if not activa or not is_instance_valid(grilla) or _es_cliente_multijugador():
		return 0
	var cantidad: int = int(grilla.call(
		"propagar_por_chispa",
		Vector2(posicion.x, posicion.z),
		direccion_viento,
		RADIO_CONTAGIO_CHISPA,
		PROBABILIDAD_CONTAGIO_CHISPA
	))
	if cantidad > 0:
		_emitir_deltas_pendientes()
	return cantidad

func serializar_comprimido() -> PackedByteArray:
	if not activa or not is_instance_valid(grilla):
		return PackedByteArray()
	var datos: PackedByteArray = grilla.call("serializar_completo")
	return datos.compress(FileAccess.COMPRESSION_DEFLATE)

func aplicar_snapshot_comprimido(datos_comprimidos: PackedByteArray) -> bool:
	if not activa or not is_instance_valid(grilla):
		return false
	var datos: PackedByteArray = datos_comprimidos.decompress_dynamic(
		64 * 1024 * 1024,
		FileAccess.COMPRESSION_DEFLATE
	)
	if datos.is_empty():
		push_error("FireGridServer no pudo descomprimir el snapshot recibido.")
		return false
	if not bool(grilla.call("cargar_completo", datos)):
		return false
	estado_inicial.emit(datos)
	return true

func aplicar_deltas_remotos(deltas: PackedInt32Array) -> bool:
	if not activa or not is_instance_valid(grilla) or not bool(grilla.call("aplicar_deltas_remotos", deltas)):
		return false
	var cambios: Array = grilla.call("obtener_deltas")
	if not cambios.is_empty():
		celdas_modificadas.emit(cambios)
	return true

func obtener_celdas_ardiendo() -> PackedInt32Array:
	if not activa:
		return PackedInt32Array()
	return grilla.call("obtener_celdas_ardiendo")

func obtener_intensidad_fuego(indice: int) -> float:
	if not activa or not is_instance_valid(grilla):
		return 0.0
	return float(grilla.call("obtener_intensidad_fuego", indice))

func obtener_estado_celdas() -> PackedByteArray:
	if not activa:
		return PackedByteArray()
	return grilla.get("estado")

func obtener_porcentaje_superficie_salvada() -> float:
	if not activa or not is_instance_valid(grilla):
		return 0.0
	var estados: PackedByteArray = grilla.get("estado")
	var combustibles: PackedByteArray = grilla.get("tipo_combustible")
	var total_combustible: int = 0
	var superficie_salvada: int = 0
	for indice in range(mini(estados.size(), combustibles.size())):
		if combustibles[indice] == FireGrid.SIN_COMBUSTIBLE:
			continue
		total_combustible += 1
		if estados[indice] == FireGrid.SANO or estados[indice] == FireGrid.MOJADO:
			superficie_salvada += 1
	if total_combustible == 0:
		return 0.0
	return 100.0 * float(superficie_salvada) / float(total_combustible)

func obtener_alturas() -> PackedFloat32Array:
	if not activa:
		return PackedFloat32Array()
	return grilla.get("altura")

func obtener_tamano_celdas() -> Vector2i:
	if not activa:
		return Vector2i.ZERO
	return grilla.get("tamano_celdas")

func obtener_origen() -> Vector2:
	if not activa:
		return Vector2.ZERO
	return grilla.get("origen")

func obtener_viento() -> Vector2:
	return _viento

func obtener_direccion_viento() -> Vector2:
	if not is_instance_valid(_sistema_viento):
		return Vector2.RIGHT
	return _sistema_viento.get("direccion")

func obtener_velocidad_viento() -> float:
	if not is_instance_valid(_sistema_viento):
		return 0.0
	return float(_sistema_viento.get("velocidad"))

func obtener_datos_objetivo_critico(objetivo: Resource, estado_objetivo: String) -> Dictionary:
	var vida_restante: float = float(objetivo.get("vida"))
	for registro in _objetivos_criticos:
		if registro["recurso"] == objetivo:
			vida_restante = float(registro["vida_restante"])
			break
	return {
		"identificador": str(objetivo.get("identificador")),
		"nombre": str(objetivo.get("nombre")),
		"tipo": int(objetivo.get("tipo")),
		"posicion": objetivo.get("posicion"),
		"penalizacion": int(objetivo.get("penalizacion")),
		"vida_restante": vida_restante,
		"estado": estado_objetivo,
	}

func obtener_marcadores_objetivos_criticos() -> Array[Dictionary]:
	var marcadores: Array[Dictionary] = []
	for registro in _objetivos_criticos:
		var objetivo: Resource = registro["recurso"]
		marcadores.append({
			"identificador": str(objetivo.get("identificador")),
			"nombre": str(objetivo.get("nombre")),
			"tipo": int(objetivo.get("tipo")),
			"posicion": objetivo.get("posicion"),
		})
	return marcadores

func obtener_resumen_objetivos_criticos() -> Array:
	var resumen: Array = []
	for registro in _objetivos_criticos:
		var objetivo: Resource = registro["recurso"]
		var estado_objetivo: String = "PERDIDO" if bool(registro["perdido"]) else "SALVADO"
		resumen.append({
			"identificador": str(objetivo.get("identificador")),
			"nombre": str(objetivo.get("nombre")),
			"tipo": int(objetivo.get("tipo")),
			"estado": estado_objetivo,
			"penalizacion": int(objetivo.get("penalizacion")) if bool(registro["perdido"]) else 0,
		})
	return resumen

func obtener_puntaje_objetivos() -> int:
	return _puntaje_objetivos

func obtener_bono_objetivos() -> int:
	return _bono_objetivos_otorgado

func finalizar_objetivos_criticos() -> void:
	if _objetivos_finalizados or _es_cliente_multijugador():
		return
	_objetivos_finalizados = true
	var perdidos := 0
	for registro in _objetivos_criticos:
		if bool(registro["perdido"]):
			perdidos += 1
	if perdidos == 0 and not _objetivos_criticos.is_empty():
		_bono_objetivos_otorgado = _bono_cero_perdidas
		_puntaje_objetivos += _bono_objetivos_otorgado
	objetivos_criticos_actualizados.emit(
		obtener_resumen_objetivos_criticos(),
		_puntaje_objetivos,
		_bono_objetivos_otorgado
	)

func obtener_total_ignitado() -> int:
	if not activa:
		return 0
	return int(grilla.call("contar_celdas_que_ardieron"))

func obtener_cantidad_ardiendo() -> int:
	if not activa:
		return 0
	return int(grilla.call("contar_celdas_ardiendo"))

func es_celda_arbol_foco(indice: int) -> bool:
	return _indices_arboles_foco.has(indice)

func debug_velocidad_frente() -> void:
	if not activa or not is_instance_valid(grilla):
		return
	var ahora_ms := Time.get_ticks_msec()
	var tiempo_transcurrido := float(ahora_ms - _ultima_medicion_frente_ms) / 1000.0
	if tiempo_transcurrido < INTERVALO_DEBUG_FRENTE:
		return
	var distancia_actual := _medir_distancia_frente()
	var velocidad_frente := maxf(
		(distancia_actual - _distancia_frente_anterior) / tiempo_transcurrido,
		0.0
	)
	var estados: Dictionary = grilla.call("contar_estados")
	print(
		"FireGrid | ardiendo=%d quemadas=%d sanas=%d avance_frente=%.2f m/s"
		% [int(estados.get(1, 0)), int(estados.get(2, 0)), int(estados.get(0, 0)), velocidad_frente]
	)
	_distancia_frente_anterior = distancia_actual
	_ultima_medicion_frente_ms = ahora_ms

func _al_anunciar_viento(direccion: Vector2, velocidad: float, segundos: float) -> void:
	viento_proximo.emit(direccion, velocidad, segundos)

func _al_cambiar_viento(direccion: Vector2, velocidad: float) -> void:
	_viento = direccion.normalized() * velocidad
	viento_cambiado.emit(direccion.normalized(), velocidad)

func _aplicar_perfiles(configuracion: Resource) -> void:
	var nombres: Array[String] = [
		"perfil_bosque_seco",
		"perfil_pastizal",
		"perfil_vivienda",
		"perfil_sin_combustible",
	]
	for tipo in range(nombres.size()):
		var perfil: Variant = configuracion.get(nombres[tipo])
		if perfil is Resource:
			grilla.call("configurar_perfil_combustible", tipo, perfil)

func _rellenar_alturas(generador_vegetacion: Node, origen: Vector2, tamano: Vector2i) -> void:
	_altura_temporal = grilla.get("altura")
	for y in range(tamano.y):
		for x in range(tamano.x):
			var indice: int = y * tamano.x + x
			var mundo_x := origen.x + (float(x) + 0.5) * CELDA_METROS
			var mundo_z := origen.y + (float(y) + 0.5) * CELDA_METROS
			_altura_temporal[indice] = float(generador_vegetacion.call("get_exact_ground_y", mundo_x, mundo_z))

func _inicializar_combustible(
	posiciones_arboles: Array[Vector2],
	origen: Vector2,
	tamano: Vector2i,
	configuracion: Resource
) -> void:
	_tipos_temporales = grilla.get("tipo_combustible")
	_combustible_temporal = grilla.get("combustible")
	var radio_nucleo := float(configuracion.get("radio_nucleo_arbol"))
	var radio_combustible := float(configuracion.get("radio_combustible_arbol"))
	var tipo_base := int(configuracion.get("tipo_combustible_base"))
	var combustible_base := float(configuracion.get("combustible_base"))
	if tipo_base < TIPO_BOSQUE_SECO or tipo_base > TIPO_SIN_COMBUSTIBLE:
		push_error("La configuración de combustible base contiene un tipo inválido.")
		return
	_tipos_temporales.fill(tipo_base)
	_combustible_temporal.fill(
		0.0 if tipo_base == TIPO_SIN_COMBUSTIBLE else maxf(combustible_base, 0.0)
	)
	var combustible_bosque := float(configuracion.get("combustible_bosque"))
	var combustible_pastizal := float(configuracion.get("combustible_pastizal"))
	for posicion_arbol in posiciones_arboles:
		_marcar_combustible_arbol(
			posicion_arbol,
			origen,
			tamano,
			radio_nucleo,
			radio_combustible,
			combustible_bosque,
			combustible_pastizal
		)
	_marcar_lineas_sin_combustible(
		configuracion.get("lineas_sin_combustible"),
		origen,
		tamano,
		float(configuracion.get("ancho_lineas_sin_combustible"))
	)
	_marcar_zonas_circulares(
		configuracion.get("zonas_sin_combustible"),
		origen,
		tamano,
		TIPO_SIN_COMBUSTIBLE,
		0.0
	)
	_marcar_zonas_vivienda(
		configuracion.get("zonas_vivienda"),
		origen,
		tamano,
		float(configuracion.get("combustible_vivienda"))
	)

func _registrar_objetivos_criticos(
	objetivos: Variant,
	origen: Vector2,
	tamano: Vector2i,
	combustible_bosque: float,
	combustible_vivienda: float
) -> void:
	if not objetivos is Array:
		push_error("La configuración de objetivos críticos debe ser un Array.")
		return
	var tipos_combustible: PackedByteArray = grilla.get("tipo_combustible")
	var combustibles: PackedFloat32Array = grilla.get("combustible")
	var celdas_criticas: PackedByteArray = grilla.get("critico")
	var tipos_criticos: PackedByteArray = grilla.get("tipo_objetivo_critico")
	for recurso: Variant in objetivos:
		if not recurso is Resource or recurso.get_script() != SCRIPT_OBJETIVO_CRITICO:
			push_error("FireGridServer recibió un Resource de objetivo crítico inválido.")
			continue
		var objetivo: Resource = recurso
		var identificador := str(objetivo.get("identificador"))
		var nombre := str(objetivo.get("nombre"))
		var tipo := int(objetivo.get("tipo"))
		var posicion: Variant = objetivo.get("posicion")
		var vida := float(objetivo.get("vida"))
		var penalizacion := int(objetivo.get("penalizacion"))
		var area := float(objetivo.get("area"))
		var longitud := float(objetivo.get("longitud"))
		var direccion: Variant = objetivo.get("direccion_ducto")
		if (
			identificador.is_empty()
			or nombre.is_empty()
			or tipo < TIPO_OBJETIVO_VIVIENDA
			or tipo > TIPO_OBJETIVO_DUCTO
			or not posicion is Vector3
			or vida <= 0.0
			or penalizacion < 0
			or area <= 0.0
			or (longitud > 0.0 and (not direccion is Vector2 or direccion.length_squared() <= 0.0))
		):
			push_error("FireGridServer encontró un objetivo crítico sin datos válidos: %s." % nombre)
			continue
		var centro := Vector2(posicion.x, posicion.z)
		var direccion_normalizada: Vector2 = direccion.normalized() if direccion is Vector2 else Vector2.RIGHT
		var radio_busqueda := area + longitud * 0.5
		var minimo_x := maxi(0, floori((centro.x - radio_busqueda - origen.x) / CELDA_METROS))
		var maximo_x := mini(tamano.x - 1, floori((centro.x + radio_busqueda - origen.x) / CELDA_METROS))
		var minimo_y := maxi(0, floori((centro.y - radio_busqueda - origen.y) / CELDA_METROS))
		var maximo_y := mini(tamano.y - 1, floori((centro.y + radio_busqueda - origen.y) / CELDA_METROS))
		var celdas_objetivo := PackedInt32Array()
		for y in range(minimo_y, maximo_y + 1):
			for x in range(minimo_x, maximo_x + 1):
				var centro_celda := origen + Vector2(
					(float(x) + 0.5) * CELDA_METROS,
					(float(y) + 0.5) * CELDA_METROS
				)
				if not _celda_dentro_objetivo(centro_celda, centro, direccion_normalizada, longitud, area):
					continue
				var indice: int = y * tamano.x + x
				celdas_criticas[indice] = 1
				tipos_criticos[indice] = tipo
				celdas_objetivo.append(indice)
				if tipo == TIPO_OBJETIVO_VIVIENDA or tipo == TIPO_OBJETIVO_DEPOSITO:
					tipos_combustible[indice] = TIPO_VIVIENDA
					combustibles[indice] = maxf(combustibles[indice], combustible_vivienda)
				elif tipos_combustible[indice] == TIPO_SIN_COMBUSTIBLE:
					tipos_combustible[indice] = TIPO_BOSQUE_SECO
					combustibles[indice] = maxf(combustibles[indice], combustible_bosque)
		if celdas_objetivo.is_empty():
			push_error("El objetivo crítico no cubre celdas de la grilla: %s." % nombre)
			continue
		_objetivos_criticos.append({
			"recurso": objetivo,
			"celdas": celdas_objetivo,
			"vida_restante": vida,
			"amenazado": false,
			"perdido": false,
		})
	grilla.set("tipo_combustible", tipos_combustible)
	grilla.set("combustible", combustibles)
	grilla.set("critico", celdas_criticas)
	grilla.set("tipo_objetivo_critico", tipos_criticos)

func _celda_dentro_objetivo(
	posicion: Vector2,
	centro: Vector2,
	direccion: Vector2,
	longitud: float,
	radio: float
) -> bool:
	if longitud <= 0.0:
		return posicion.distance_to(centro) <= radio
	var inicio := centro - direccion * longitud * 0.5
	var fin := centro + direccion * longitud * 0.5
	return _distancia_a_segmento(posicion, inicio, fin) <= radio

func _marcar_lineas_sin_combustible(
	lineas: Array[Vector4],
	origen: Vector2,
	tamano: Vector2i,
	ancho: float
) -> void:
	var radio := maxf(ancho, 0.0) * 0.5
	for linea in lineas:
		var inicio := Vector2(linea.x, linea.y)
		var fin := Vector2(linea.z, linea.w)
		var minimo_x := maxi(0, floori((minf(inicio.x, fin.x) - radio - origen.x) / CELDA_METROS))
		var maximo_x := mini(
			tamano.x - 1,
			floori((maxf(inicio.x, fin.x) + radio - origen.x) / CELDA_METROS)
		)
		var minimo_y := maxi(0, floori((minf(inicio.y, fin.y) - radio - origen.y) / CELDA_METROS))
		var maximo_y := mini(
			tamano.y - 1,
			floori((maxf(inicio.y, fin.y) + radio - origen.y) / CELDA_METROS)
		)
		for y in range(minimo_y, maximo_y + 1):
			for x in range(minimo_x, maximo_x + 1):
				var centro := origen + Vector2(
					(float(x) + 0.5) * CELDA_METROS,
					(float(y) + 0.5) * CELDA_METROS
				)
				if _distancia_a_segmento(centro, inicio, fin) <= radio:
					var indice: int = y * tamano.x + x
					_tipos_temporales[indice] = TIPO_SIN_COMBUSTIBLE
					_combustible_temporal[indice] = 0.0

func _marcar_zonas_circulares(
	zonas: Array[Vector3],
	origen: Vector2,
	tamano: Vector2i,
	tipo: int,
	combustible: float
) -> void:
	for zona in zonas:
		var centro := Vector2(zona.x, zona.y)
		var radio := maxf(zona.z, 0.0)
		var minimo_x := maxi(0, floori((centro.x - radio - origen.x) / CELDA_METROS))
		var maximo_x := mini(tamano.x - 1, floori((centro.x + radio - origen.x) / CELDA_METROS))
		var minimo_y := maxi(0, floori((centro.y - radio - origen.y) / CELDA_METROS))
		var maximo_y := mini(tamano.y - 1, floori((centro.y + radio - origen.y) / CELDA_METROS))
		for y in range(minimo_y, maximo_y + 1):
			for x in range(minimo_x, maximo_x + 1):
				var posicion := origen + Vector2(
					(float(x) + 0.5) * CELDA_METROS,
					(float(y) + 0.5) * CELDA_METROS
				)
				if posicion.distance_to(centro) > radio:
					continue
				var indice: int = y * tamano.x + x
				_tipos_temporales[indice] = tipo
				_combustible_temporal[indice] = combustible

func _marcar_zonas_vivienda(
	zonas: Array[Vector3],
	origen: Vector2,
	tamano: Vector2i,
	combustible: float
) -> void:
	_indices_vivienda = PackedInt32Array()
	var vistos: Dictionary = {}
	for zona in zonas:
		var centro := Vector2(zona.x, zona.y)
		var radio := maxf(zona.z, 0.0)
		var minimo_x := maxi(0, floori((centro.x - radio - origen.x) / CELDA_METROS))
		var maximo_x := mini(tamano.x - 1, floori((centro.x + radio - origen.x) / CELDA_METROS))
		var minimo_y := maxi(0, floori((centro.y - radio - origen.y) / CELDA_METROS))
		var maximo_y := mini(tamano.y - 1, floori((centro.y + radio - origen.y) / CELDA_METROS))
		for y in range(minimo_y, maximo_y + 1):
			for x in range(minimo_x, maximo_x + 1):
				var posicion := origen + Vector2(
					(float(x) + 0.5) * CELDA_METROS,
					(float(y) + 0.5) * CELDA_METROS
				)
				if posicion.distance_to(centro) > radio:
					continue
				var indice: int = y * tamano.x + x
				_tipos_temporales[indice] = TIPO_VIVIENDA
				_combustible_temporal[indice] = maxf(combustible, 0.0)
				if not vistos.has(indice):
					vistos[indice] = true
					_indices_vivienda.append(indice)

func _distancia_a_segmento(punto: Vector2, inicio: Vector2, fin: Vector2) -> float:
	var segmento := fin - inicio
	if segmento.length_squared() <= 0.000001:
		return punto.distance_to(inicio)
	var avance := clampf((punto - inicio).dot(segmento) / segmento.length_squared(), 0.0, 1.0)
	return punto.distance_to(inicio + segmento * avance)

func _marcar_combustible_arbol(
	posicion: Vector2,
	origen: Vector2,
	tamano: Vector2i,
	radio_nucleo: float,
	radio_combustible: float,
	combustible_bosque: float,
	combustible_pastizal: float
) -> void:
	var celda_central := Vector2i(
		floori((posicion.x - origen.x) / CELDA_METROS),
		floori((posicion.y - origen.y) / CELDA_METROS)
	)
	var margen := ceili(radio_combustible / CELDA_METROS)
	for y in range(maxi(0, celda_central.y - margen), mini(tamano.y, celda_central.y + margen + 1)):
		for x in range(maxi(0, celda_central.x - margen), mini(tamano.x, celda_central.x + margen + 1)):
			var centro_celda := origen + Vector2(
				(float(x) + 0.5) * CELDA_METROS,
				(float(y) + 0.5) * CELDA_METROS
			)
			var distancia := centro_celda.distance_to(posicion)
			if distancia > radio_combustible:
				continue
			var indice: int = y * tamano.x + x
			if distancia <= radio_nucleo:
				_tipos_temporales[indice] = TIPO_BOSQUE_SECO
				_combustible_temporal[indice] = maxf(_combustible_temporal[indice], combustible_bosque)
			elif _tipos_temporales[indice] != TIPO_BOSQUE_SECO:
				_tipos_temporales[indice] = TIPO_PASTIZAL
				_combustible_temporal[indice] = maxf(_combustible_temporal[indice], combustible_pastizal)

func _encender_foco_inicial(arboles_iniciales: Array[Node3D], configuracion: Resource) -> void:
	var centro_configurado: Variant = configuracion.get("centro_foco")
	if not centro_configurado is Vector2:
		push_error("La configuración de FireGrid tiene un centro de foco inválido.")
		return
	var centro: Vector2 = centro_configurado
	_centro_foco = centro
	var radio := float(configuracion.get("radio_foco"))
	var origen: Vector2 = grilla.get("origen")
	var tamano: Vector2i = grilla.get("tamano_celdas")
	_indices_arboles_foco.clear()
	var candidatas: Array[Dictionary] = []
	var celdas_vistas: Dictionary = {}
	var cantidad_inicial := clampi(
		maxi(int(configuracion.get("cantidad_celdas_foco_inicial")), 3),
		3,
		MAX_CELDAS_FOCO_INICIAL
	)
	for arbol in arboles_iniciales:
		if not is_instance_valid(arbol):
			continue
		var posicion := Vector2(arbol.global_position.x, arbol.global_position.z)
		if posicion.distance_to(centro) > radio:
			continue
		var celda: Vector2i = grilla.call("mundo_a_celda", posicion)
		if (
			celda.x >= 0
			and celda.y >= 0
			and celda.x < tamano.x
			and celda.y < tamano.y
		):
			var indice: int = celda.y * tamano.x + celda.x
			if _combustible_temporal[indice] <= 0.0 or celdas_vistas.has(indice):
				continue
			celdas_vistas[indice] = true
			candidatas.append({
				"celda": celda,
				"indice": indice,
				"distancia": posicion.distance_to(centro),
			})
	if candidatas.size() < cantidad_inicial:
		var celda_centro: Vector2i = grilla.call("mundo_a_celda", centro)
		for radio_busqueda in range(maxi(tamano.x, tamano.y)):
			for y in range(maxi(0, celda_centro.y - radio_busqueda), mini(
				tamano.y, celda_centro.y + radio_busqueda + 1
			)):
				for x in range(maxi(0, celda_centro.x - radio_busqueda), mini(
					tamano.x, celda_centro.x + radio_busqueda + 1
				)):
					if maxi(absi(x - celda_centro.x), absi(y - celda_centro.y)) != radio_busqueda:
						continue
					var indice: int = y * tamano.x + x
					if _combustible_temporal[indice] <= 0.0 or celdas_vistas.has(indice):
						continue
					var posicion := origen + Vector2(
						(float(x) + 0.5) * CELDA_METROS,
						(float(y) + 0.5) * CELDA_METROS
					)
					celdas_vistas[indice] = true
					candidatas.append({
						"celda": Vector2i(x, y),
						"indice": indice,
						"distancia": posicion.distance_to(centro),
					})
			if candidatas.size() >= cantidad_inicial:
				break
	candidatas.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["distancia"]) < float(b["distancia"])
	)
	if candidatas.size() < cantidad_inicial:
		push_error("FireGridServer no encontró tres celdas combustibles para iniciar el fuego.")
		return
	var estados_grilla: PackedByteArray = grilla.get("estado")
	for indice_candidata in range(mini(cantidad_inicial, candidatas.size())):
		var candidata: Dictionary = candidatas[indice_candidata]
		var celda: Vector2i = candidata["celda"]
		var indice: int = candidata["indice"]
		grilla.call("encender", celda)
		if estados_grilla[indice] == ESTADO_ARDIENDO:
			_indices_arboles_foco[indice] = true

func _avanzar_simulacion() -> void:
	if not activa or not is_instance_valid(grilla):
		return
	if _es_cliente_multijugador():
		return
	grilla.call("paso", INTERVALO_SIMULACION, _viento)
	_actualizar_objetivos_criticos(INTERVALO_SIMULACION)
	_comprobar_derrota()
	_emitir_deltas_pendientes()
	debug_velocidad_frente()

func _actualizar_objetivos_criticos(delta: float) -> void:
	if not is_instance_valid(grilla):
		return
	var estados: PackedByteArray = grilla.get("estado")
	for indice_objetivo in range(_objetivos_criticos.size()):
		var registro: Dictionary = _objetivos_criticos[indice_objetivo]
		if bool(registro["perdido"]):
			continue
		var celdas: PackedInt32Array = registro["celdas"]
		var en_llamas := false
		for indice in celdas:
			if indice >= 0 and indice < estados.size() and estados[indice] == ESTADO_ARDIENDO:
				en_llamas = true
				break
		if not en_llamas:
			continue
		var objetivo: Resource = registro["recurso"]
		if not bool(registro["amenazado"]):
			registro["amenazado"] = true
			_objetivos_criticos[indice_objetivo] = registro
			objetivo_critico_amenazado.emit(objetivo)
		if delta <= 0.0:
			continue
		var vida_restante := maxf(float(registro["vida_restante"]) - delta, 0.0)
		registro["vida_restante"] = vida_restante
		if vida_restante > 0.0:
			_objetivos_criticos[indice_objetivo] = registro
			continue
		registro["perdido"] = true
		_objetivos_criticos[indice_objetivo] = registro
		var penalizacion := int(objetivo.get("penalizacion"))
		_puntaje_objetivos -= penalizacion
		objetivo_critico_perdido.emit(objetivo)
		if int(objetivo.get("tipo")) == TIPO_OBJETIVO_DEPOSITO:
			_detonar_deposito(objetivo)

func _detonar_deposito(objetivo: Resource) -> void:
	if not activa or not is_instance_valid(grilla):
		return
	var posicion: Vector3 = objetivo.get("posicion")
	var centro := Vector2(posicion.x, posicion.z)
	var origen: Vector2 = grilla.get("origen")
	var tamano: Vector2i = grilla.get("tamano_celdas")
	var minimo_x := maxi(0, floori((centro.x - RADIO_EXPLOSION_DEPOSITO - origen.x) / CELDA_METROS))
	var maximo_x := mini(tamano.x - 1, floori((centro.x + RADIO_EXPLOSION_DEPOSITO - origen.x) / CELDA_METROS))
	var minimo_y := maxi(0, floori((centro.y - RADIO_EXPLOSION_DEPOSITO - origen.y) / CELDA_METROS))
	var maximo_y := mini(tamano.y - 1, floori((centro.y + RADIO_EXPLOSION_DEPOSITO - origen.y) / CELDA_METROS))
	for y in range(minimo_y, maximo_y + 1):
		for x in range(minimo_x, maximo_x + 1):
			var celda_mundo := origen + Vector2(
				(float(x) + 0.5) * CELDA_METROS,
				(float(y) + 0.5) * CELDA_METROS
			)
			if celda_mundo.distance_to(centro) > RADIO_EXPLOSION_DEPOSITO:
				continue
			grilla.call("encender", Vector2i(x, y))
	explosion_deposito.emit(posicion, RADIO_EXPLOSION_DEPOSITO)

func _medir_distancia_frente() -> float:
	if not is_instance_valid(grilla):
		return 0.0
	var celdas_que_ardieron: PackedByteArray = grilla.get("celdas_que_ardieron")
	var origen: Vector2 = grilla.get("origen")
	var tamano: Vector2i = grilla.get("tamano_celdas")
	var distancia_maxima: float = 0.0
	for indice in range(celdas_que_ardieron.size()):
		if celdas_que_ardieron[indice] == 0:
			continue
		var celda := Vector2i(indice % tamano.x, floori(float(indice) / float(tamano.x)))
		var posicion := origen + Vector2(
			(float(celda.x) + 0.5) * CELDA_METROS,
			(float(celda.y) + 0.5) * CELDA_METROS
		)
		distancia_maxima = maxf(distancia_maxima, posicion.distance_to(_centro_foco))
	return distancia_maxima

func _emitir_deltas_pendientes() -> void:
	var deltas: Array = grilla.call("obtener_deltas")
	if not deltas.is_empty():
		celdas_modificadas.emit(deltas)

func _es_cliente_multijugador() -> bool:
	return multiplayer.has_multiplayer_peer() and not multiplayer.is_server()

func _comprobar_derrota() -> void:
	if _mision_fallida:
		return
	var porcentaje_quemado := (
		float(grilla.call("porcentaje_celdas_quemadas_tipo", tipo_objetivo_derrota))
		if tipo_objetivo_derrota >= TIPO_BOSQUE_SECO and tipo_objetivo_derrota < TIPO_SIN_COMBUSTIBLE
		else float(grilla.call("porcentaje_celdas_quemadas"))
	)
	if porcentaje_quemado > porcentaje_derrota or _hay_fuego_en_viviendas():
		_mision_fallida = true
		incendio_descontrolado.emit()

func _hay_fuego_en_viviendas() -> bool:
	var estados: PackedByteArray = grilla.get("estado")
	for indice in _indices_vivienda:
		if indice < 0 or indice >= estados.size():
			continue
		if estados[indice] == ESTADO_ARDIENDO or estados[indice] == ESTADO_QUEMADO:
			return true
	return false
