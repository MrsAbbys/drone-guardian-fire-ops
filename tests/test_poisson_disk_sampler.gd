extends SceneTree

const SCRIPT_POISSON_SAMPLER: Script = preload("res://scripts/world/poisson_disk_sampler.gd")
const AREA_PRUEBA := Rect2(Vector2(-40.0, -40.0), Vector2(80.0, 80.0))

func _initialize() -> void:
	var sampler: RefCounted = SCRIPT_POISSON_SAMPLER.new()
	var rng_a := RandomNumberGenerator.new()
	var rng_b := RandomNumberGenerator.new()
	rng_a.seed = 24680
	rng_b.seed = 24680
	var evaluar := Callable(self, "_evaluar_punto")
	var muestras_a: Array = sampler.call(
		"generar_muestras", AREA_PRUEBA, 4.0, 8.0, 24, evaluar, rng_a
	)
	var muestras_b: Array = sampler.call(
		"generar_muestras", AREA_PRUEBA, 4.0, 8.0, 24, evaluar, rng_b
	)
	assert(not muestras_a.is_empty(), "El muestreo Poisson debe generar puntos.")
	assert(muestras_a == muestras_b, "La semilla debe producir una distribución determinista.")

	for indice in range(muestras_a.size()):
		var muestra: Dictionary = muestras_a[indice]
		var punto: Vector2 = muestra["posicion"]
		var radio: float = float(muestra["datos"]["radio"])
		assert(AREA_PRUEBA.has_point(punto), "Los puntos deben quedar dentro del área.")
		for indice_anterior in range(indice):
			var anterior: Dictionary = muestras_a[indice_anterior]
			var distancia_requerida := maxf(radio, float(anterior["datos"]["radio"]))
			var anterior_posicion: Vector2 = anterior["posicion"]
			assert(
				punto.distance_to(anterior_posicion) + 0.0001 >= distancia_requerida,
				"Los puntos deben respetar la distancia mínima variable."
			)
	print("PoissonDiskSampler: OK (%d puntos)" % muestras_a.size())
	quit()

func _evaluar_punto(
	punto: Vector2,
	_distancia_minima: float,
	_distancia_maxima: float
) -> Dictionary:
	if absf(punto.x) < 4.0 and absf(punto.y) < 10.0:
		return {}
	return {"radio": 4.0 if punto.x < 0.0 else 8.0}
