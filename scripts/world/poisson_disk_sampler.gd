extends RefCounted

func generar_muestras(
	bounds: Rect2,
	distancia_minima: float,
	distancia_maxima: float,
	intentos_por_punto: int,
	evaluar_candidato: Callable,
	rng: RandomNumberGenerator
) -> Array[Dictionary]:
	var muestras: Array[Dictionary] = []
	if (
		bounds.size.x <= 0.0
		or bounds.size.y <= 0.0
		or not evaluar_candidato.is_valid()
	):
		push_error("PoissonDiskSampler recibió límites o un evaluador inválidos.")
		return muestras

	var minimo := maxf(distancia_minima, 1.0)
	var maximo := maxf(distancia_maxima, minimo)
	var tamano_celda := minimo / sqrt(2.0)
	var radio_busqueda := ceili(maximo / tamano_celda)
	var puntos: Array[Vector2] = []
	var radios: Array[float] = []
	var datos: Array[Dictionary] = []
	var activos: Array[int] = []
	var celdas: Dictionary = {}

	for _intento in range(512):
		var punto := Vector2(
			rng.randf_range(bounds.position.x, bounds.end.x),
			rng.randf_range(bounds.position.y, bounds.end.y)
		)
		if not bounds.has_point(punto):
			continue
		var dato := _evaluar(evaluar_candidato, punto, minimo, maximo)
		if dato.is_empty():
			continue
		_registrar(punto, dato, tamano_celda, puntos, radios, datos, activos, celdas)
		break

	if puntos.is_empty():
		return muestras

	while not activos.is_empty():
		var posicion_activa := rng.randi_range(0, activos.size() - 1)
		var indice_activo := activos[posicion_activa]
		var encontrado := false
		for _intento in range(maxi(intentos_por_punto, 1)):
			var angulo := rng.randf_range(0.0, TAU)
			var radio_base := radios[indice_activo]
			var radio := sqrt(rng.randf_range(radio_base * radio_base, 4.0 * radio_base * radio_base))
			var punto := puntos[indice_activo] + Vector2(cos(angulo), sin(angulo)) * radio
			if not bounds.has_point(punto):
				continue
			var dato := _evaluar(evaluar_candidato, punto, minimo, maximo)
			if dato.is_empty():
				continue
			if not _separado(
				punto, float(dato["radio"]), puntos, radios, celdas,
				tamano_celda, radio_busqueda
			):
				continue
			_registrar(punto, dato, tamano_celda, puntos, radios, datos, activos, celdas)
			encontrado = true
			break
		if not encontrado:
			activos.remove_at(posicion_activa)

	for indice in range(puntos.size()):
		muestras.append({"posicion": puntos[indice], "datos": datos[indice]})
	return muestras

func _evaluar(
	evaluar_candidato: Callable,
	punto: Vector2,
	distancia_minima: float,
	distancia_maxima: float
) -> Dictionary:
	var valor: Variant = evaluar_candidato.call(punto, distancia_minima, distancia_maxima)
	if not valor is Dictionary:
		push_error("El evaluador de PoissonDiskSampler debe devolver un Dictionary.")
		return {}
	var datos: Dictionary = valor
	if datos.is_empty():
		return {}
	var radio: Variant = datos.get("radio")
	if (not radio is int and not radio is float) or not is_finite(float(radio)):
		push_error("El evaluador de PoissonDiskSampler devolvió un radio inválido.")
		return {}
	datos["radio"] = clampf(float(radio), distancia_minima, distancia_maxima)
	return datos

func _registrar(
	punto: Vector2,
	dato: Dictionary,
	tamano_celda: float,
	puntos: Array[Vector2],
	radios: Array[float],
	datos: Array[Dictionary],
	activos: Array[int],
	celdas: Dictionary
) -> void:
	var indice := puntos.size()
	puntos.append(punto)
	radios.append(float(dato["radio"]))
	datos.append(dato)
	activos.append(indice)
	var clave := _clave_celda(punto, tamano_celda)
	var vecinos: Array = celdas.get(clave, [])
	vecinos.append(indice)
	celdas[clave] = vecinos

func _separado(
	punto: Vector2,
	radio_punto: float,
	puntos: Array[Vector2],
	radios: Array[float],
	celdas: Dictionary,
	tamano_celda: float,
	radio_busqueda: int
) -> bool:
	var celda := _clave_celda(punto, tamano_celda)
	for z in range(celda.y - radio_busqueda, celda.y + radio_busqueda + 1):
		for x in range(celda.x - radio_busqueda, celda.x + radio_busqueda + 1):
			var vecinos: Array = celdas.get(Vector2i(x, z), [])
			for indice_variant in vecinos:
				var indice := int(indice_variant)
				var distancia_minima := maxf(radio_punto, radios[indice])
				if punto.distance_squared_to(puntos[indice]) < distancia_minima * distancia_minima:
					return false
	return true

func _clave_celda(punto: Vector2, tamano_celda: float) -> Vector2i:
	return Vector2i(floori(punto.x / tamano_celda), floori(punto.y / tamano_celda))
