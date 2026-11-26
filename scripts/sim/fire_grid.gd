extends RefCounted
class_name FireGrid

signal celda_cambiada(indice: int, estado: int)
signal celdas_ardiendo_cambiado(cantidad: int)

const SCRIPT_PERFIL_COMBUSTIBLE: Script = preload("res://scripts/sim/perfil_combustible.gd")
const CELDA_METROS: float = 2.0
const INTERVALO_TICK: float = 0.3
const AGUA_POR_CELDA: float = 100.0
const TEMPERATURA_AMBIENTE: float = 20.0
const TASA_CALENTAMIENTO: float = 100.0
const TASA_ENFRIAMIENTO: float = 12.0
const DURACION_ETAPA_CALENTAMIENTO: float = 5.0
const DURACION_ENFRIAMIENTO_AGUA: float = 18.0
const DISTANCIA_MINIMA_CHISPA: float = 4.0
const FACTOR_VIENTO_MINIMO: float = 0.05
const FACTOR_VIENTO_MAXIMO: float = 2.0

const SANO: int = 0
const ARDIENDO: int = 1
const QUEMADO: int = 2
const MOJADO: int = 3

const BOSQUE_SECO: int = 0
const PASTIZAL: int = 1
const VIVIENDA: int = 2
const SIN_COMBUSTIBLE: int = 3

var origen: Vector2
var tamano_celdas: Vector2i
var semilla: int

var estado: PackedByteArray = PackedByteArray()
var combustible: PackedFloat32Array = PackedFloat32Array()
var humedad: PackedFloat32Array = PackedFloat32Array()
var altura: PackedFloat32Array = PackedFloat32Array()
var tipo_combustible: PackedByteArray = PackedByteArray()
var critico: PackedByteArray = PackedByteArray()
var tipo_objetivo_critico: PackedByteArray = PackedByteArray()
var temperatura: PackedFloat32Array = PackedFloat32Array()
var celdas_que_ardieron: PackedByteArray = PackedByteArray()
var _tiempo_ardiendo: PackedFloat32Array = PackedFloat32Array()
var velocidad_propagacion: float = 1.5

var _tiempo_mojado: PackedFloat32Array = PackedFloat32Array()
var _agua_recibida: PackedFloat32Array = PackedFloat32Array()
var _frente: PackedInt32Array = PackedInt32Array()
var _frente_mojado: PackedInt32Array = PackedInt32Array()
var _frente_calentado: PackedInt32Array = PackedInt32Array()
var _frente_siguiente: PackedInt32Array = PackedInt32Array()
var _conteo_estados: PackedInt32Array = PackedInt32Array()
var _conteo_combustible_por_tipo: PackedInt32Array = PackedInt32Array()
var _conteo_quemadas_por_tipo: PackedInt32Array = PackedInt32Array()
var _ultimas_celdas_con_agua: PackedInt32Array = PackedInt32Array()
var _ultimas_celdas_apagadas: PackedInt32Array = PackedInt32Array()
var _deltas: Array = []
var _perfiles: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _acumulador: float = 0.0
var _cantidad_ardiendo: int = 0
var _cantidad_combustible: int = 0
var _cantidad_quemadas: int = 0
var _igniciones_unicas: int = 0
var _centro_viento_erratico: Vector2 = Vector2.ZERO
var _radio_viento_erratico: float = 0.0
var _amplitud_viento_erratico: float = 0.0
var _tiempo_simulado: float = 0.0

func _init(origen_nuevo: Vector2, tamano_nuevo: Vector2i, semilla_nueva: int) -> void:
	origen = origen_nuevo
	if tamano_nuevo.x <= 0 or tamano_nuevo.y <= 0:
		push_error("FireGrid requiere dimensiones de celda mayores que cero.")
	tamano_celdas = Vector2i(maxi(tamano_nuevo.x, 1), maxi(tamano_nuevo.y, 1))
	semilla = semilla_nueva
	_rng.seed = semilla
	_crear_perfiles()
	_inicializar_celdas()

func encender(celda: Vector2i) -> void:
	if not _celda_valida(celda):
		return
	var indice := _indice(celda)
	if estado[indice] != SANO or combustible[indice] <= 0.0:
		return
	_agua_recibida[indice] = 0.0
	var perfil := _perfil(tipo_combustible[indice])
	if float(perfil.get("tasa_ignicion")) <= 0.0:
		return
	_temperatura_ignicion(indice, perfil)
	_cambiar_estado(indice, ARDIENDO)
	_frente.append(indice)

func propagar_por_chispa(
	posicion: Vector2,
	direccion_viento: Vector2,
	radio: float,
	probabilidad_base: float
) -> int:
	if radio <= 0.0 or probabilidad_base <= 0.0:
		return 0
	var centro: Vector2i = mundo_a_celda(posicion)
	var radio_celdas: int = ceili(radio / CELDA_METROS)
	var viento_normalizado: Vector2 = direccion_viento.normalized()
	var probabilidad: float = clampf(probabilidad_base, 0.0, 1.0)
	var celda_vecina_mas_cercana: Vector2i = Vector2i(-1, -1)
	var indice_vecino_mas_cercano: int = -1
	var distancia_mas_cercana: float = INF
	for y in range(
		maxi(0, centro.y - radio_celdas),
		mini(tamano_celdas.y, centro.y + radio_celdas + 1)
	):
		for x in range(
			maxi(0, centro.x - radio_celdas),
			mini(tamano_celdas.x, centro.x + radio_celdas + 1)
		):
			var celda: Vector2i = Vector2i(x, y)
			var indice: int = _indice(celda)
			if (
				estado[indice] != SANO
				or combustible[indice] <= 0.0
				or tipo_combustible[indice] == SIN_COMBUSTIBLE
			):
				continue
			var desplazamiento: Vector2 = celda_a_mundo(celda) - posicion
			var distancia: float = desplazamiento.length()
			if (
				distancia < DISTANCIA_MINIMA_CHISPA
				or distancia > radio
				or distancia >= distancia_mas_cercana
			):
				continue
			celda_vecina_mas_cercana = celda
			indice_vecino_mas_cercano = indice
			distancia_mas_cercana = distancia
	if indice_vecino_mas_cercano < 0:
		return 0
	var posicion_vecina: Vector2 = celda_a_mundo(celda_vecina_mas_cercana)
	var direccion_vecina: Vector2 = (posicion_vecina - posicion).normalized()
	var factor_viento: float = 1.0
	if viento_normalizado.length_squared() > 0.0:
		factor_viento = clampf(
			1.0 + 0.65 * direccion_vecina.dot(viento_normalizado),
			0.2,
			1.65
		)
	var factor_humedad: float = 1.0 - clampf(
		humedad[indice_vecino_mas_cercano],
		0.0,
		1.0
	)
	var probabilidad_final: float = clampf(
		probabilidad * factor_viento * factor_humedad,
		0.0,
		1.0
	)
	if _rng.randf() >= probabilidad_final:
		return 0
	encender(celda_vecina_mas_cercana)
	return 1 if estado[indice_vecino_mas_cercano] == ARDIENDO else 0

func configurar_terreno_sin_combustible() -> void:
	estado.fill(SANO)
	combustible.fill(0.0)
	humedad.fill(0.0)
	altura.fill(0.0)
	tipo_combustible.fill(SIN_COMBUSTIBLE)
	critico.resize(estado.size())
	critico.fill(0)
	tipo_objetivo_critico.resize(estado.size())
	tipo_objetivo_critico.fill(0)
	temperatura.fill(TEMPERATURA_AMBIENTE)
	celdas_que_ardieron.resize(estado.size())
	celdas_que_ardieron.fill(0)
	_tiempo_mojado.fill(0.0)
	_agua_recibida.resize(estado.size())
	_agua_recibida.fill(0.0)
	_frente = PackedInt32Array()
	_frente_mojado = PackedInt32Array()
	_frente_calentado = PackedInt32Array()
	_frente_siguiente = PackedInt32Array()
	_deltas.clear()
	_acumulador = 0.0
	_cantidad_ardiendo = 0
	_cantidad_combustible = 0
	_cantidad_quemadas = 0
	_igniciones_unicas = 0
	_conteo_estados.resize(4)
	_conteo_estados.fill(0)
	_conteo_estados[SANO] = estado.size()
	_conteo_combustible_por_tipo.fill(0)
	_conteo_quemadas_por_tipo.fill(0)
	_tiempo_simulado = 0.0

func marcar_celda_critica(indice: int, tipo: int) -> bool:
	if indice < 0 or indice >= estado.size() or tipo < 0 or tipo > 3:
		push_error("FireGrid recibió un objetivo crítico fuera de rango.")
		return false
	critico[indice] = 1
	tipo_objetivo_critico[indice] = tipo
	return true

func configurar_viento_erratico(centro: Vector2, radio: float, amplitud: float) -> void:
	_centro_viento_erratico = centro
	_radio_viento_erratico = maxf(radio, 0.0)
	_amplitud_viento_erratico = clampf(amplitud, 0.0, PI)

func configurar_perfil_combustible(tipo: int, perfil: Resource) -> void:
	if not _perfiles.has(tipo) or not is_instance_valid(perfil):
		push_error("FireGrid recibió un perfil o tipo de combustible inválido.")
		return
	if perfil.get_script() != SCRIPT_PERFIL_COMBUSTIBLE:
		push_error("El perfil de combustible debe usar PerfilCombustible.")
		return
	for propiedad in [
		"tasa_ignicion",
		"tasa_consumo",
		"calor_umbral",
		"duracion_mojado",
		"k_viento",
		"k_pendiente",
	]:
		var valor: Variant = perfil.get(propiedad)
		if not valor is float and not valor is int:
			push_error("El perfil de combustible tiene un parámetro inválido: %s." % propiedad)
			return
	_perfiles[tipo] = perfil.duplicate(true)

func reconstruir_contadores() -> void:
	_conteo_estados.resize(4)
	_conteo_estados.fill(0)
	_cantidad_ardiendo = 0
	_cantidad_combustible = 0
	_cantidad_quemadas = 0
	_igniciones_unicas = 0
	_conteo_combustible_por_tipo.resize(4)
	_conteo_combustible_por_tipo.fill(0)
	_conteo_quemadas_por_tipo.resize(4)
	_conteo_quemadas_por_tipo.fill(0)
	for indice in range(estado.size()):
		var estado_celda := int(estado[indice])
		var tipo_celda := int(tipo_combustible[indice])
		_conteo_estados[estado_celda] += 1
		if estado_celda == ARDIENDO:
			_cantidad_ardiendo += 1
		elif estado_celda == QUEMADO:
			_cantidad_quemadas += 1
			_conteo_quemadas_por_tipo[tipo_celda] += 1
		if tipo_celda != SIN_COMBUSTIBLE:
			_cantidad_combustible += 1
			_conteo_combustible_por_tipo[tipo_celda] += 1
		if celdas_que_ardieron[indice] != 0:
			_igniciones_unicas += 1

func obtener_celdas_ardiendo() -> PackedInt32Array:
	var activas := PackedInt32Array()
	for indice in _frente:
		if estado[indice] == ARDIENDO:
			activas.append(indice)
	return activas

func obtener_intensidad_fuego(indice: int) -> float:
	if indice < 0 or indice >= estado.size() or estado[indice] != ARDIENDO:
		return 0.0
	return clampf(100.0 - _agua_recibida[indice], 0.0, 100.0)

func contar_celdas_que_ardieron() -> int:
	return _igniciones_unicas

func contar_celdas_ardiendo() -> int:
	return _cantidad_ardiendo

func porcentaje_celdas_quemadas() -> float:
	if _cantidad_combustible <= 0:
		return 0.0
	return 100.0 * float(_cantidad_quemadas) / float(_cantidad_combustible)

func porcentaje_celdas_quemadas_tipo(tipo: int) -> float:
	if tipo < BOSQUE_SECO or tipo > SIN_COMBUSTIBLE:
		push_error("FireGrid recibió un tipo de combustible inválido para el objetivo.")
		return 0.0
	var total := _conteo_combustible_por_tipo[tipo]
	if total <= 0:
		return 0.0
	return 100.0 * float(_conteo_quemadas_por_tipo[tipo]) / float(total)

func paso(delta_sim: float, viento: Vector2) -> void:
	if delta_sim <= 0.0:
		return
	_acumulador += delta_sim
	_tiempo_simulado += delta_sim
	while _acumulador + 0.000001 >= INTERVALO_TICK:
		_acumulador = maxf(_acumulador - INTERVALO_TICK, 0.0)
		_paso_tick(viento)

func aplicar_agua(pos_mundo: Vector2, radio: float, cantidad: float) -> int:
	_ultimas_celdas_con_agua.clear()
	_ultimas_celdas_apagadas.clear()
	if radio < 0.0 or cantidad <= 0.0:
		return 0
	var limites := _limites_area(pos_mundo, radio)
	var presupuesto := cantidad
	var apagadas := 0
	var incendios_procesados: Dictionary = {}
	for fase in range(2):
		for y in range(limites.position.y, limites.end.y):
			for x in range(limites.position.x, limites.end.x):
				var celda := Vector2i(x, y)
				var indice := _indice(celda)
				var era_ardiendo := estado[indice] == ARDIENDO
				if (
					estado[indice] == QUEMADO
					or tipo_combustible[indice] == SIN_COMBUSTIBLE
					or combustible[indice] <= 0.0
					or not _centro_dentro_radio(celda, pos_mundo, radio)
					or (fase == 0 and not era_ardiendo)
					or (fase == 1 and (era_ardiendo or incendios_procesados.has(indice)))
				):
					continue
				if era_ardiendo:
					incendios_procesados[indice] = true
				var requerido := maxf(AGUA_POR_CELDA - _agua_recibida[indice], 0.0)
				var aplicado := minf(presupuesto, requerido)
				var agua_anterior: float = _agua_recibida[indice]
				_agua_recibida[indice] += aplicado
				presupuesto -= aplicado
				if aplicado > 0.0:
					_ultimas_celdas_con_agua.append(indice)
					if era_ardiendo:
						var pasos_intensidad: int = (
							floori(_agua_recibida[indice]) - floori(agua_anterior)
						)
						for _paso in range(pasos_intensidad):
							_deltas.append([indice, ARDIENDO])
				if _agua_recibida[indice] >= AGUA_POR_CELDA:
					_agua_recibida[indice] = 0.0
					_mojar_indice(indice)
					if era_ardiendo:
						apagadas += 1
						_ultimas_celdas_apagadas.append(indice)
				if presupuesto <= 0.0:
					return apagadas
	return apagadas

func obtener_ultimas_celdas_con_agua() -> PackedInt32Array:
	return _ultimas_celdas_con_agua.duplicate()

func obtener_ultimas_celdas_apagadas() -> PackedInt32Array:
	return _ultimas_celdas_apagadas.duplicate()

func aplicar_retardante(pos_mundo: Vector2, radio: float) -> void:
	if radio < 0.0:
		return
	var limites := _limites_area(pos_mundo, radio)
	for y in range(limites.position.y, limites.end.y):
		for x in range(limites.position.x, limites.end.x):
			var celda := Vector2i(x, y)
			if not _centro_dentro_radio(celda, pos_mundo, radio):
				continue
			_mojar_indice(_indice(celda))

func obtener_deltas() -> Array:
	var resultado: Array = _deltas.duplicate(true)
	_deltas.clear()
	return resultado

func aplicar_deltas_remotos(deltas: PackedInt32Array) -> bool:
	if deltas.size() % 2 != 0:
		push_error("FireGrid recibió un paquete de deltas incompleto.")
		return false
	for indice_par in range(0, deltas.size(), 2):
		var indice := deltas[indice_par]
		var nuevo_estado := deltas[indice_par + 1]
		if indice < 0 or indice >= estado.size() or nuevo_estado < SANO or nuevo_estado > MOJADO:
			push_error("FireGrid recibió un delta fuera de rango.")
			return false
	for indice_par in range(0, deltas.size(), 2):
		var indice := deltas[indice_par]
		var nuevo_estado := deltas[indice_par + 1]
		if nuevo_estado == ARDIENDO and estado[indice] == ARDIENDO:
			# Repeated burning-state pairs carry integer water-progress steps to clients.
			_agua_recibida[indice] = minf(_agua_recibida[indice] + 1.0, AGUA_POR_CELDA)
			_deltas.append([indice, ARDIENDO])
		else:
			_cambiar_estado(indice, nuevo_estado)
	_reconstruir_frentes()
	return true

func serializar_completo() -> PackedByteArray:
	var datos: Dictionary = {
		"version": 4,
		"origen": origen,
		"tamano_celdas": tamano_celdas,
		"semilla": semilla,
		"estado": estado,
		"combustible": combustible,
		"humedad": humedad,
		"altura": altura,
		"tipo_combustible": tipo_combustible,
		"critico": critico,
		"tipo_objetivo_critico": tipo_objetivo_critico,
		"temperatura": temperatura,
		"tiempo_ardiendo": _tiempo_ardiendo,
		"velocidad_propagacion": velocidad_propagacion,
		"celdas_que_ardieron": celdas_que_ardieron,
		"tiempo_mojado": _tiempo_mojado,
		"agua_recibida": _agua_recibida,
		"frente": _frente,
		"frente_mojado": _frente_mojado,
		"rng_state": _rng.state,
		"acumulador": _acumulador,
		"deltas": _deltas,
	}
	return var_to_bytes(datos)

func cargar_completo(datos: PackedByteArray) -> bool:
	var valor_contenido: Variant = bytes_to_var(datos)
	if not valor_contenido is Dictionary:
		push_error("FireGrid no pudo cargar el estado serializado: formato inválido.")
		return false
	var contenido: Dictionary = valor_contenido
	var version: int = int(contenido.get("version", -1))
	if version < 2 or version > 4:
		push_error("FireGrid no reconoce la versión del estado serializado.")
		return false
	if not contenido.get("origen") is Vector2 or not contenido.get("tamano_celdas") is Vector2i:
		push_error("FireGrid no pudo cargar origen o dimensiones inválidas.")
		return false

	var nuevo_origen: Vector2 = contenido["origen"]
	var nuevo_tamano: Vector2i = contenido["tamano_celdas"]
	if nuevo_tamano.x <= 0 or nuevo_tamano.y <= 0:
		push_error("FireGrid no pudo cargar dimensiones de celda inválidas.")
		return false
	var cantidad_celdas := nuevo_tamano.x * nuevo_tamano.y
	var estado_nuevo: Variant = contenido.get("estado")
	var combustible_nuevo: Variant = contenido.get("combustible")
	var humedad_nueva: Variant = contenido.get("humedad")
	var altura_nueva: Variant = contenido.get("altura")
	var tipos_nuevos: Variant = contenido.get("tipo_combustible")
	var criticos_nuevos: Variant = contenido.get("critico", PackedByteArray())
	var tipos_criticos_nuevos: Variant = contenido.get("tipo_objetivo_critico", PackedByteArray())
	var temperatura_nueva: Variant = contenido.get("temperatura")
	var tiempo_ardiendo_nuevo: Variant = contenido.get("tiempo_ardiendo")
	var historial_nuevo: Variant = contenido.get("celdas_que_ardieron")
	var mojado_nuevo: Variant = contenido.get("tiempo_mojado")
	var agua_nueva: Variant = contenido.get("agua_recibida")
	var frente_nuevo: Variant = contenido.get("frente")
	var frente_mojado_nuevo: Variant = contenido.get("frente_mojado")
	var deltas_nuevos: Variant = contenido.get("deltas", [])
	if (
		not estado_nuevo is PackedByteArray
		or not combustible_nuevo is PackedFloat32Array
		or not humedad_nueva is PackedFloat32Array
		or not altura_nueva is PackedFloat32Array
		or not tipos_nuevos is PackedByteArray
		or (version >= 3 and not criticos_nuevos is PackedByteArray)
		or (version >= 3 and not tipos_criticos_nuevos is PackedByteArray)
		or not temperatura_nueva is PackedFloat32Array
		or (version >= 4 and not tiempo_ardiendo_nuevo is PackedFloat32Array)
		or not historial_nuevo is PackedByteArray
		or not mojado_nuevo is PackedFloat32Array
		or not agua_nueva is PackedFloat32Array
		or not frente_nuevo is PackedInt32Array
		or not frente_mojado_nuevo is PackedInt32Array
		or not deltas_nuevos is Array
	):
		push_error("FireGrid no pudo cargar arrays incompatibles.")
		return false
	if (
		estado_nuevo.size() != cantidad_celdas
		or combustible_nuevo.size() != cantidad_celdas
		or humedad_nueva.size() != cantidad_celdas
		or altura_nueva.size() != cantidad_celdas
		or tipos_nuevos.size() != cantidad_celdas
		or temperatura_nueva.size() != cantidad_celdas
		or (version >= 4 and tiempo_ardiendo_nuevo.size() != cantidad_celdas)
		or historial_nuevo.size() != cantidad_celdas
		or mojado_nuevo.size() != cantidad_celdas
		or agua_nueva.size() != cantidad_celdas
		or (version >= 3 and criticos_nuevos.size() != cantidad_celdas)
		or (version >= 3 and tipos_criticos_nuevos.size() != cantidad_celdas)
	):
		push_error("FireGrid no pudo cargar arrays con dimensiones incompatibles.")
		return false
	if not _indices_validos(frente_nuevo, cantidad_celdas) or not _indices_validos(frente_mojado_nuevo, cantidad_celdas):
		push_error("FireGrid no pudo cargar frentes con índices inválidos.")
		return false
	for indice in range(cantidad_celdas):
		if (
			estado_nuevo[indice] > MOJADO
			or tipos_nuevos[indice] > SIN_COMBUSTIBLE
			or (version >= 3 and criticos_nuevos[indice] > 1)
			or (version >= 3 and tipos_criticos_nuevos[indice] > 3)
		):
			push_error("FireGrid no pudo cargar estados o combustibles desconocidos.")
			return false
	for par: Variant in deltas_nuevos:
		if (
			not par is Array
			or par.size() != 2
			or not par[0] is int
			or not par[1] is int
			or int(par[0]) < 0
			or int(par[0]) >= cantidad_celdas
			or int(par[1]) < SANO
			or int(par[1]) > MOJADO
		):
			push_error("FireGrid no pudo cargar deltas inválidos.")
			return false
	var acumulador_nuevo: Variant = contenido.get("acumulador", 0.0)
	var estado_rng: Variant = contenido.get("rng_state")
	var velocidad_propagacion_nueva: Variant = contenido.get("velocidad_propagacion", 1.5)
	if (
		(not acumulador_nuevo is int and not acumulador_nuevo is float)
		or float(acumulador_nuevo) < 0.0
		or float(acumulador_nuevo) >= INTERVALO_TICK
		or not estado_rng is int
	):
		push_error("FireGrid no pudo cargar el temporizador o estado aleatorio.")
		return false
	if (
		(not velocidad_propagacion_nueva is int and not velocidad_propagacion_nueva is float)
		or not is_finite(float(velocidad_propagacion_nueva))
		or float(velocidad_propagacion_nueva) < 0.1
		or float(velocidad_propagacion_nueva) > 3.0
	):
		push_error("FireGrid no pudo cargar una velocidad de propagación inválida.")
		return false

	var cantidad_ardiendo_anterior := _cantidad_ardiendo
	origen = nuevo_origen
	tamano_celdas = nuevo_tamano
	semilla = int(contenido.get("semilla", 0))
	estado = estado_nuevo
	combustible = combustible_nuevo
	humedad = humedad_nueva
	altura = altura_nueva
	tipo_combustible = tipos_nuevos
	velocidad_propagacion = float(velocidad_propagacion_nueva)
	if version >= 3:
		critico = criticos_nuevos
		tipo_objetivo_critico = tipos_criticos_nuevos
	else:
		critico.resize(cantidad_celdas)
		critico.fill(0)
		tipo_objetivo_critico.resize(cantidad_celdas)
		tipo_objetivo_critico.fill(0)
	temperatura = temperatura_nueva
	if version >= 4:
		_tiempo_ardiendo = tiempo_ardiendo_nuevo
	else:
		_tiempo_ardiendo.resize(cantidad_celdas)
		_tiempo_ardiendo.fill(0.0)
	celdas_que_ardieron = historial_nuevo
	_tiempo_mojado = mojado_nuevo
	_agua_recibida = agua_nueva
	_frente = frente_nuevo
	_frente_mojado = frente_mojado_nuevo
	_acumulador = float(acumulador_nuevo)
	_deltas = deltas_nuevos.duplicate(true)
	_rng.seed = semilla
	_rng.state = int(estado_rng)
	reconstruir_contadores()
	if cantidad_ardiendo_anterior != _cantidad_ardiendo:
		celdas_ardiendo_cambiado.emit(_cantidad_ardiendo)
	return true

func mundo_a_celda(pos_mundo: Vector2) -> Vector2i:
	return Vector2i(
		floori((pos_mundo.x - origen.x) / CELDA_METROS),
		floori((pos_mundo.y - origen.y) / CELDA_METROS)
	)

func celda_a_mundo(celda: Vector2i) -> Vector2:
	return origen + Vector2(
		(float(celda.x) + 0.5) * CELDA_METROS,
		(float(celda.y) + 0.5) * CELDA_METROS
	)

func contar_estados() -> Dictionary:
	return {
		SANO: _conteo_estados[SANO],
		ARDIENDO: _conteo_estados[ARDIENDO],
		QUEMADO: _conteo_estados[QUEMADO],
		MOJADO: _conteo_estados[MOJADO],
	}

func _crear_perfiles() -> void:
	_perfiles[BOSQUE_SECO] = _nuevo_perfil(0.03, 1.5, 300.0, 12.0, 0.25, 0.1)
	_perfiles[PASTIZAL] = _nuevo_perfil(0.08, 2.0, 150.0, 7.0, 0.25, 0.1)
	_perfiles[VIVIENDA] = _nuevo_perfil(0.04, 1.8, 500.0, 20.0, 0.25, 0.1)
	_perfiles[SIN_COMBUSTIBLE] = _nuevo_perfil(0.0, 0.0, 2000.0, 0.0, 0.25, 0.1)

func _nuevo_perfil(
	ignicion: float,
	consumo: float,
	umbral: float,
	mojado: float,
	viento: float,
	pendiente: float
) -> Resource:
	var perfil: Resource = SCRIPT_PERFIL_COMBUSTIBLE.new()
	perfil.set("tasa_ignicion", ignicion)
	perfil.set("tasa_consumo", consumo)
	perfil.set("calor_umbral", umbral)
	perfil.set("duracion_mojado", mojado)
	perfil.set("k_viento", viento)
	perfil.set("k_pendiente", pendiente)
	return perfil

func _inicializar_celdas() -> void:
	var cantidad := tamano_celdas.x * tamano_celdas.y
	estado.resize(cantidad)
	estado.fill(SANO)
	combustible.resize(cantidad)
	humedad.resize(cantidad)
	humedad.fill(0.0)
	altura.resize(cantidad)
	altura.fill(0.0)
	tipo_combustible.resize(cantidad)
	tipo_combustible.fill(BOSQUE_SECO)
	critico.resize(cantidad)
	critico.fill(0)
	tipo_objetivo_critico.resize(cantidad)
	tipo_objetivo_critico.fill(0)
	temperatura.resize(cantidad)
	temperatura.fill(TEMPERATURA_AMBIENTE)
	_tiempo_ardiendo.resize(cantidad)
	_tiempo_ardiendo.fill(0.0)
	_tiempo_mojado.resize(cantidad)
	_tiempo_mojado.fill(0.0)
	_agua_recibida.resize(cantidad)
	_agua_recibida.fill(0.0)
	celdas_que_ardieron.resize(cantidad)
	celdas_que_ardieron.fill(0)
	_conteo_estados.resize(4)
	_conteo_estados.fill(0)
	_conteo_estados[SANO] = cantidad
	_conteo_combustible_por_tipo.resize(4)
	_conteo_combustible_por_tipo.fill(0)
	_conteo_combustible_por_tipo[BOSQUE_SECO] = cantidad
	_conteo_quemadas_por_tipo.resize(4)
	_conteo_quemadas_por_tipo.fill(0)
	_frente_calentado = PackedInt32Array()
	_cantidad_combustible = cantidad
	for indice in range(cantidad):
		combustible[indice] = _combustible_inicial(BOSQUE_SECO)

func _paso_tick(viento: Vector2) -> void:
	_frente_siguiente = PackedInt32Array()
	var mojadas_siguientes := PackedInt32Array()
	for indice in _frente_mojado:
		if estado[indice] != MOJADO:
			continue
		_tiempo_mojado[indice] = maxf(_tiempo_mojado[indice] - INTERVALO_TICK, 0.0)
		if _tiempo_mojado[indice] <= 0.000001:
			_agua_recibida[indice] = 0.0
			_cambiar_estado(indice, SANO)
		else:
			mojadas_siguientes.append(indice)
	_frente_mojado = mojadas_siguientes

	var calentadas_siguientes := PackedInt32Array()
	for indice in _frente_calentado:
		if estado[indice] != SANO:
			continue
		temperatura[indice] = maxf(
			temperatura[indice] - TASA_ENFRIAMIENTO * INTERVALO_TICK,
			TEMPERATURA_AMBIENTE
		)
		if temperatura[indice] > TEMPERATURA_AMBIENTE:
			calentadas_siguientes.append(indice)
	_frente_calentado = calentadas_siguientes

	for indice_origen in _frente:
		if estado[indice_origen] != ARDIENDO:
			continue
		_tiempo_ardiendo[indice_origen] += INTERVALO_TICK
		var celda_origen := _celda_desde_indice(indice_origen)
		var viento_local := _viento_en_celda(celda_origen, viento)
		var direccion_viento := viento_local.normalized() if viento_local.length_squared() > 0.0 else Vector2.ZERO
		var velocidad_viento := viento_local.length()
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var celda_vecina := celda_origen + Vector2i(dx, dy)
				if not _celda_valida(celda_vecina):
					continue
				var indice_vecino := _indice(celda_vecina)
				if estado[indice_vecino] != SANO or combustible[indice_vecino] <= 0.0:
					continue
				var perfil_vecino := _perfil(tipo_combustible[indice_vecino])
				var umbral := float(perfil_vecino.get("calor_umbral"))
				if temperatura[indice_origen] < umbral:
					continue
				var desplazamiento := Vector2(celda_vecina - celda_origen)
				var distancia := desplazamiento.length() * CELDA_METROS
				_calentar_celda(
					indice_vecino,
					umbral,
					desplazamiento.normalized(),
					distancia,
					direccion_viento,
					velocidad_viento
				)
				if temperatura[indice_vecino] < umbral:
					continue
				if _tiempo_ardiendo[indice_origen] < DURACION_ETAPA_CALENTAMIENTO:
					continue
				var probabilidad := _probabilidad_ignicion(
					celda_origen,
					celda_vecina,
					indice_origen,
					indice_vecino,
					perfil_vecino,
					direccion_viento,
					velocidad_viento,
					INTERVALO_TICK
				)
				if _rng.randf() < probabilidad:
					_temperatura_ignicion(indice_vecino, perfil_vecino)
					_cambiar_estado(indice_vecino, ARDIENDO)
					_frente_siguiente.append(indice_vecino)

		var perfil_origen := _perfil(tipo_combustible[indice_origen])
		var consumo := float(perfil_origen.get("tasa_consumo")) * INTERVALO_TICK
		combustible[indice_origen] = maxf(combustible[indice_origen] - consumo, 0.0)
		if combustible[indice_origen] <= 0.0:
			temperatura[indice_origen] = 80.0
			_cambiar_estado(indice_origen, QUEMADO)
		else:
			_frente_siguiente.append(indice_origen)
	_frente = _frente_siguiente

func _probabilidad_ignicion(
	celda_origen: Vector2i,
	celda_vecina: Vector2i,
	indice_origen: int,
	indice_vecino: int,
	perfil_vecino: Resource,
	direccion_viento: Vector2,
	velocidad_viento: float,
	delta_tick: float
) -> float:
	var desplazamiento := Vector2(celda_vecina - celda_origen)
	var distancia := desplazamiento.length() * CELDA_METROS
	var direccion_vecino := desplazamiento.normalized()
	var k_viento := float(perfil_vecino.get("k_viento"))
	var k_pendiente := float(perfil_vecino.get("k_pendiente"))
	var factor_viento := _factor_viento(direccion_vecino, direccion_viento, velocidad_viento, k_viento)
	var factor_pendiente := clampf(
		exp(k_pendiente * (altura[indice_vecino] - altura[indice_origen]) / distancia),
		0.0,
		3.0
	)
	var factor_humedad := 1.0 - clampf(humedad[indice_vecino], 0.0, 1.0)
	var tasa := (
		float(perfil_vecino.get("tasa_ignicion"))
		* velocidad_propagacion
		* factor_viento
		* factor_pendiente
		* factor_humedad
	)
	var factor_distancia := CELDA_METROS / distancia
	return clampf((1.0 - exp(-tasa * delta_tick)) * factor_distancia, 0.0, 1.0)

func _calentar_celda(
	indice: int,
	umbral: float,
	direccion_vecino: Vector2,
	distancia: float,
	direccion_viento: Vector2,
	velocidad_viento: float
) -> void:
	if temperatura[indice] <= TEMPERATURA_AMBIENTE:
		_frente_calentado.append(indice)
	var perfil := _perfil(tipo_combustible[indice])
	var factor_viento := _factor_viento(
		direccion_vecino,
		direccion_viento,
		velocidad_viento,
		float(perfil.get("k_viento"))
	)
	var factor_distancia := CELDA_METROS / distancia
	var incremento := (
		TASA_CALENTAMIENTO
		* velocidad_propagacion
		* factor_viento
		* factor_distancia
		* INTERVALO_TICK
	)
	temperatura[indice] = minf(temperatura[indice] + incremento, umbral)

func _factor_viento(
	direccion_vecino: Vector2,
	direccion_viento: Vector2,
	velocidad_viento: float,
	k_viento: float
) -> float:
	return clampf(
		1.0 + k_viento * direccion_vecino.dot(direccion_viento) * velocidad_viento,
		FACTOR_VIENTO_MINIMO,
		FACTOR_VIENTO_MAXIMO
	)

func _viento_en_celda(celda: Vector2i, viento: Vector2) -> Vector2:
	if _radio_viento_erratico <= 0.0 or viento.length_squared() <= 0.0:
		return viento
	var distancia := celda_a_mundo(celda).distance_to(_centro_viento_erratico)
	if distancia >= _radio_viento_erratico:
		return viento
	var influencia := 1.0 - distancia / _radio_viento_erratico
	var fase := _tiempo_simulado * 0.7 + float(celda.x * 31 + celda.y * 17) * 0.13
	var angulo := sin(fase) * _amplitud_viento_erratico * influencia
	var factor_velocidad := maxf(1.0 + cos(fase * 1.7) * 0.35 * influencia, 0.2)
	return viento.rotated(angulo) * factor_velocidad

func _mojar_indice(indice: int) -> void:
	if estado[indice] == QUEMADO or tipo_combustible[indice] == SIN_COMBUSTIBLE:
		return
	var duracion: float = maxf(
		float(_perfil(tipo_combustible[indice]).get("duracion_mojado")),
		DURACION_ENFRIAMIENTO_AGUA
	)
	if duracion <= 0.0:
		if estado[indice] == ARDIENDO:
			_cambiar_estado(indice, SANO)
		return
	if estado[indice] != MOJADO:
		_cambiar_estado(indice, MOJADO)
		_frente_mojado.append(indice)
	temperatura[indice] = TEMPERATURA_AMBIENTE
	_tiempo_mojado[indice] = maxf(_tiempo_mojado[indice], duracion)

func _temperatura_ignicion(indice: int, perfil: Resource) -> void:
	temperatura[indice] = maxf(550.0, float(perfil.get("calor_umbral")))

func _reconstruir_frentes() -> void:
	_frente = PackedInt32Array()
	_frente_mojado = PackedInt32Array()
	_frente_calentado = PackedInt32Array()
	for indice in range(estado.size()):
		if estado[indice] == ARDIENDO:
			_frente.append(indice)
		elif estado[indice] == MOJADO:
			_frente_mojado.append(indice)
		elif estado[indice] == SANO and temperatura[indice] > TEMPERATURA_AMBIENTE:
			_frente_calentado.append(indice)

func _cambiar_estado(indice: int, nuevo_estado: int) -> void:
	var anterior := int(estado[indice])
	if anterior == nuevo_estado:
		return
	_conteo_estados[anterior] -= 1
	_conteo_estados[nuevo_estado] += 1
	if anterior == ARDIENDO:
		_cantidad_ardiendo -= 1
		_tiempo_ardiendo[indice] = 0.0
	if nuevo_estado == ARDIENDO:
		_cantidad_ardiendo += 1
		_tiempo_ardiendo[indice] = 0.0
		_agua_recibida[indice] = 0.0
		if celdas_que_ardieron[indice] == 0:
			celdas_que_ardieron[indice] = 1
			_igniciones_unicas += 1
	if anterior == QUEMADO:
		_cantidad_quemadas -= 1
		_conteo_quemadas_por_tipo[tipo_combustible[indice]] -= 1
	if nuevo_estado == QUEMADO:
		_cantidad_quemadas += 1
		_conteo_quemadas_por_tipo[tipo_combustible[indice]] += 1
	if nuevo_estado == MOJADO:
		_agua_recibida[indice] = 0.0
	estado[indice] = nuevo_estado
	_deltas.append([indice, nuevo_estado])
	celda_cambiada.emit(indice, nuevo_estado)
	if anterior == ARDIENDO or nuevo_estado == ARDIENDO:
		celdas_ardiendo_cambiado.emit(_cantidad_ardiendo)

func _perfil(tipo: int) -> Resource:
	if _perfiles.has(tipo):
		return _perfiles[tipo]
	push_error("FireGrid recibió un tipo de combustible desconocido.")
	return _perfiles[BOSQUE_SECO]

func _combustible_inicial(tipo: int) -> float:
	match tipo:
		PASTIZAL:
			return 40.0
		VIVIENDA:
			return 200.0
		SIN_COMBUSTIBLE:
			return 0.0
		_:
			return 100.0

func _limites_area(pos_mundo: Vector2, radio: float) -> Rect2i:
	var celda_minima := mundo_a_celda(pos_mundo - Vector2.ONE * radio)
	var celda_maxima := mundo_a_celda(pos_mundo + Vector2.ONE * radio)
	var minimo_x := clampi(celda_minima.x, 0, tamano_celdas.x)
	var minimo_y := clampi(celda_minima.y, 0, tamano_celdas.y)
	var maximo_x := clampi(celda_maxima.x + 1, 0, tamano_celdas.x)
	var maximo_y := clampi(celda_maxima.y + 1, 0, tamano_celdas.y)
	return Rect2i(
		Vector2i(minimo_x, minimo_y),
		Vector2i(maxi(0, maximo_x - minimo_x), maxi(0, maximo_y - minimo_y))
	)

func _centro_dentro_radio(celda: Vector2i, pos_mundo: Vector2, radio: float) -> bool:
	return celda_a_mundo(celda).distance_squared_to(pos_mundo) <= radio * radio

func _celda_valida(celda: Vector2i) -> bool:
	return (
		celda.x >= 0
		and celda.y >= 0
		and celda.x < tamano_celdas.x
		and celda.y < tamano_celdas.y
	)

func _indice(celda: Vector2i) -> int:
	return celda.y * tamano_celdas.x + celda.x

func _celda_desde_indice(indice: int) -> Vector2i:
	return Vector2i(indice % tamano_celdas.x, floori(float(indice) / float(tamano_celdas.x)))

func _indices_validos(indices: PackedInt32Array, cantidad: int) -> bool:
	for indice in indices:
		if indice < 0 or indice >= cantidad:
			return false
	return true

