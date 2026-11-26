extends SceneTree

const SCRIPT_FIRE_GRID: Script = preload("res://scripts/sim/fire_grid.gd")
const ESTADO_SANO: int = 0
const ESTADO_ARDIENDO: int = 1
const ESTADO_MOJADO: int = 3
const TIPO_BOSQUE_SECO: int = 0
const TIPO_PASTIZAL: int = 1
const TIPO_SIN_COMBUSTIBLE: int = 3

func _initialize() -> void:
	call_deferred("_ejecutar_pruebas")

func _ejecutar_pruebas() -> void:
	var exitosas := 0
	var total := 10
	if _probar_determinismo():
		exitosas += 1
	if _probar_viento():
		exitosas += 1
	if _probar_pendiente():
		exitosas += 1
	if _probar_agua_y_deltas():
		exitosas += 1
	if _probar_serializacion():
		exitosas += 1
	if _probar_duracion_combustion():
		exitosas += 1
	if _probar_calentamiento_gradual():
		exitosas += 1
	if _probar_barrera_etapa_calentamiento():
		exitosas += 1
	if _probar_velocidad_propagacion():
		exitosas += 1
	if _probar_propagar_por_chispa():
		exitosas += 1
	_benchmark()
	print("FireGrid: %d/%d pruebas aprobadas." % [exitosas, total])
	call_deferred("quit", 0 if exitosas == total else 1)

func _probar_determinismo() -> bool:
	var grilla_a: Variant = SCRIPT_FIRE_GRID.new(Vector2.ZERO, Vector2i(32, 32), 2468)
	var grilla_b: Variant = SCRIPT_FIRE_GRID.new(Vector2.ZERO, Vector2i(32, 32), 2468)
	grilla_a.encender(Vector2i(16, 16))
	grilla_b.encender(Vector2i(16, 16))
	for _paso in range(30):
		grilla_a.paso(0.3, Vector2(4.0, 1.0))
		grilla_b.paso(0.3, Vector2(4.0, 1.0))
	var correcto: bool = (
		grilla_a.estado == grilla_b.estado
		and grilla_a.combustible == grilla_b.combustible
	)
	_informar("determinismo", correcto)
	return correcto

func _probar_viento() -> bool:
	var grilla: Variant = SCRIPT_FIRE_GRID.new(Vector2.ZERO, Vector2i(3, 3), 91)
	var perfil: Resource = grilla.call("_perfil", TIPO_PASTIZAL)
	var origen := Vector2i(1, 1)
	var origen_indice := 4
	var destino_directo := Vector2i(2, 1)
	var destino_directo_indice := 5
	var destino_diagonal := Vector2i(2, 2)
	var destino_diagonal_indice := 8
	var a_favor: float = grilla.call(
		"_probabilidad_ignicion", origen, destino_directo, origen_indice,
		destino_directo_indice, perfil, Vector2.RIGHT, 4.0, 0.3
	)
	var calma: float = grilla.call(
		"_probabilidad_ignicion", origen, destino_directo, origen_indice,
		destino_directo_indice, perfil, Vector2.ZERO, 0.0, 0.3
	)
	var contra: float = grilla.call(
		"_probabilidad_ignicion", origen, destino_directo, origen_indice,
		destino_directo_indice, perfil, Vector2.LEFT, 4.0, 0.3
	)
	var diagonal: float = grilla.call(
		"_probabilidad_ignicion", origen, destino_diagonal, origen_indice,
		destino_diagonal_indice, perfil, Vector2.ZERO, 0.0, 0.3
	)
	var factor_viento_maximo: float = grilla.call(
		"_factor_viento", Vector2.RIGHT, Vector2.RIGHT, 30.0, 0.25
	)
	var factor_viento_contra: float = grilla.call(
		"_factor_viento", Vector2.RIGHT, Vector2.LEFT, 30.0, 0.25
	)
	var correcto: bool = (
		a_favor > calma
		and contra < calma * 0.1
		and is_equal_approx(diagonal / calma, 1.0 / sqrt(2.0))
		and is_equal_approx(factor_viento_maximo, 2.0)
		and is_equal_approx(factor_viento_contra, 0.05)
	)
	_informar("viento direccional y distancia", correcto)
	return correcto

func _probar_pendiente() -> bool:
	var grilla: Variant = SCRIPT_FIRE_GRID.new(Vector2.ZERO, Vector2i(3, 3), 92)
	var perfil: Resource = grilla.call("_perfil", TIPO_BOSQUE_SECO)
	var plano: float = grilla.call(
		"_probabilidad_ignicion", Vector2i(1, 1), Vector2i(2, 1),
		4, 5, perfil, Vector2.ZERO, 0.0, 0.3
	)
	grilla.altura[5] = 100.0
	var cuesta_arriba: float = grilla.call(
		"_probabilidad_ignicion", Vector2i(1, 1), Vector2i(2, 1),
		4, 5, perfil, Vector2.ZERO, 0.0, 0.3
	)
	var correcto: bool = cuesta_arriba > plano
	_informar("pendiente ascendente", correcto)
	return correcto

func _probar_calentamiento_gradual() -> bool:
	var grilla: Variant = SCRIPT_FIRE_GRID.new(Vector2.ZERO, Vector2i(3, 3), 93)
	var tipos: PackedByteArray = grilla.tipo_combustible
	tipos[5] = TIPO_PASTIZAL
	grilla.tipo_combustible = tipos
	grilla.encender(Vector2i(1, 1))
	grilla.paso(0.3, Vector2.ZERO)
	var correcto: bool = (
		grilla.estado[5] == ESTADO_SANO
		and grilla.temperatura[5] > 20.0
		and grilla.temperatura[5] < 150.0
	)
	_informar("calentamiento gradual previo a ignición", correcto)
	return correcto

func _probar_barrera_etapa_calentamiento() -> bool:
	var grilla: Variant = SCRIPT_FIRE_GRID.new(Vector2.ZERO, Vector2i(3, 3), 95)
	var tipos: PackedByteArray = grilla.tipo_combustible
	var combustibles: PackedFloat32Array = grilla.combustible
	tipos.fill(TIPO_SIN_COMBUSTIBLE)
	combustibles.fill(0.0)
	tipos[4] = TIPO_BOSQUE_SECO
	tipos[5] = TIPO_BOSQUE_SECO
	combustibles[4] = 100.0
	combustibles[5] = 100.0
	grilla.tipo_combustible = tipos
	grilla.combustible = combustibles
	grilla.velocidad_propagacion = 3.0
	grilla.reconstruir_contadores()
	var perfil: Resource = grilla.call("_perfil", TIPO_BOSQUE_SECO)
	perfil.set("tasa_ignicion", 1.0)
	perfil.set("calor_umbral", 100.0)
	grilla.encender(Vector2i(1, 1))
	for _tick in range(16):
		grilla.paso(0.3, Vector2.RIGHT)
	var no_ignitada_durante_calentamiento: bool = grilla.estado[5] == ESTADO_SANO
	for _tick in range(30):
		if grilla.estado[5] == ESTADO_ARDIENDO:
			break
		grilla.paso(0.3, Vector2.RIGHT)
	var correcto: bool = (
		no_ignitada_durante_calentamiento
		and grilla.estado[5] == ESTADO_ARDIENDO
	)
	_informar("propagación tras etapa de calentamiento", correcto)
	return correcto

func _probar_velocidad_propagacion() -> bool:
	var velocidad_pastizal := _medir_velocidad_media(
		TIPO_PASTIZAL, Vector2(4.0, 0.0), 20, 10, 360.0
	)
	var velocidad_bosque := _medir_velocidad_media(
		TIPO_BOSQUE_SECO, Vector2(4.0, 0.0), 20, 10, 360.0
	)
	var velocidad_contra_viento := _medir_velocidad_media(
		TIPO_PASTIZAL, Vector2(-4.0, 0.0), 32, 1, 35.0
	)
	print(("Velocidad de propagación: pastizal %.3f m/s, bosque %.3f m/s, "
		+ "pastizal contra viento %.3f m/s.") % [
			velocidad_pastizal, velocidad_bosque, velocidad_contra_viento
		])
	var correcto: bool = (
		velocidad_pastizal >= 0.1
		and velocidad_pastizal <= 0.35
		and velocidad_bosque >= 0.05
		and velocidad_bosque <= 0.2
		and velocidad_contra_viento < 0.05
	)
	_informar("velocidad de propagación (m/s)", correcto)
	return correcto

func _probar_propagar_por_chispa() -> bool:
	var grilla: Variant = SCRIPT_FIRE_GRID.new(Vector2.ZERO, Vector2i(3, 3), 94)
	var tipos: PackedByteArray = grilla.tipo_combustible
	var combustibles: PackedFloat32Array = grilla.combustible
	tipos.fill(TIPO_SIN_COMBUSTIBLE)
	combustibles.fill(0.0)
	tipos[5] = TIPO_BOSQUE_SECO
	tipos[8] = TIPO_BOSQUE_SECO
	combustibles[5] = 100.0
	combustibles[8] = 100.0
	grilla.tipo_combustible = tipos
	grilla.combustible = combustibles
	grilla.reconstruir_contadores()
	var encendidas: int = grilla.propagar_por_chispa(
		Vector2(1.0, 3.0),
		Vector2.ZERO,
		7.0,
		1.0
	)
	var correcto: bool = (
		encendidas == 1
		and grilla.estado[5] == ESTADO_ARDIENDO
		and grilla.estado[8] == ESTADO_SANO
	)
	_informar("chispa enciende solo al vecino más cercano", correcto)
	return correcto

func _medir_velocidad_media(
	tipo: int,
	viento: Vector2,
	cantidad_pruebas: int,
	celdas_hasta_objetivo: int,
	tiempo_maximo: float
) -> float:
	var distancia := float(celdas_hasta_objetivo) * 2.0
	var distancia_total := 0.0
	var tiempo_total := 0.0
	for semilla_prueba in range(1, cantidad_pruebas + 1):
		var grilla: Variant = SCRIPT_FIRE_GRID.new(Vector2.ZERO, Vector2i(32, 3), semilla_prueba)
		var tipos: PackedByteArray = grilla.tipo_combustible
		var combustibles: PackedFloat32Array = grilla.combustible
		tipos.fill(TIPO_SIN_COMBUSTIBLE)
		combustibles.fill(0.0)
		var inicio_x := 4
		var objetivo_x := inicio_x + celdas_hasta_objetivo
		for x in range(inicio_x, objetivo_x + 1):
			var indice := 32 + x
			tipos[indice] = tipo
			combustibles[indice] = 45.0 if tipo == TIPO_PASTIZAL else 100.0
		grilla.tipo_combustible = tipos
		grilla.combustible = combustibles
		grilla.reconstruir_contadores()
		grilla.velocidad_propagacion = 1.5
		grilla.encender(Vector2i(inicio_x, 1))

		var tiempo_transcurrido := 0.0
		var objetivo_indice := 32 + objetivo_x
		while (
			grilla.estado[objetivo_indice] == ESTADO_SANO
			and tiempo_transcurrido < tiempo_maximo
		):
			grilla.paso(0.3, viento)
			tiempo_transcurrido += 0.3
		tiempo_total += tiempo_transcurrido
		if grilla.estado[objetivo_indice] != ESTADO_SANO:
			distancia_total += distancia
	if tiempo_total <= 0.0:
		return 0.0
	return distancia_total / tiempo_total

func _probar_agua_y_deltas() -> bool:
	var grilla: Variant = SCRIPT_FIRE_GRID.new(Vector2.ZERO, Vector2i(5, 5), 7)
	var celda := Vector2i(2, 2)
	var indice: int = celda.y * grilla.tamano_celdas.x + celda.x
	grilla.encender(celda)
	grilla.obtener_deltas()
	var centro: Vector2 = grilla.celda_a_mundo(celda)
	var primera_aplicacion: int = grilla.aplicar_agua(centro, 0.5, 40.0)
	var sin_cambios: Array = grilla.obtener_deltas()
	var apagadas: int = grilla.aplicar_agua(centro, 0.5, 60.0)
	var deltas: Array = grilla.obtener_deltas()
	var correcto: bool = (
		primera_aplicacion == 0
		and sin_cambios.is_empty()
		and apagadas == 1
		and grilla.estado[indice] == ESTADO_MOJADO
		and deltas.size() == 1
		and deltas[0] == [indice, ESTADO_MOJADO]
		and grilla.obtener_deltas().is_empty()
	)
	grilla.paso(13.0, Vector2.ZERO)
	correcto = correcto and grilla.estado[indice] == ESTADO_SANO
	_informar("agua y deltas", correcto)
	return correcto

func _probar_serializacion() -> bool:
	var original: Variant = SCRIPT_FIRE_GRID.new(Vector2(10.0, -4.0), Vector2i(8, 8), 991)
	original.velocidad_propagacion = 1.75
	original.encender(Vector2i(3, 4))
	original.paso(0.45, Vector2(2.0, -1.0))
	var copia: Variant = SCRIPT_FIRE_GRID.new(Vector2.ZERO, Vector2i(1, 1), 1)
	var correcto: bool = (
		copia.cargar_completo(original.serializar_completo())
		and copia.estado == original.estado
		and copia.tamano_celdas == original.tamano_celdas
		and copia.origen == original.origen
		and copia.velocidad_propagacion == original.velocidad_propagacion
		and copia.temperatura == original.temperatura
		and copia._tiempo_ardiendo == original._tiempo_ardiendo
	)
	original.paso(0.15, Vector2(2.0, -1.0))
	copia.paso(0.15, Vector2(2.0, -1.0))
	correcto = (
		correcto
		and copia.estado == original.estado
		and copia.combustible == original.combustible
		and copia.temperatura == original.temperatura
		and copia._tiempo_ardiendo == original._tiempo_ardiendo
	)
	_informar("serialización", correcto)
	return correcto

func _probar_duracion_combustion() -> bool:
	var bosque: Variant = SCRIPT_FIRE_GRID.new(Vector2.ZERO, Vector2i(1, 1), 81)
	bosque.encender(Vector2i.ZERO)
	for _paso in range(222):
		bosque.paso(0.3, Vector2.ZERO)
	var bosque_aun_ardiendo: bool = bosque.estado[0] == ESTADO_ARDIENDO
	bosque.paso(0.3, Vector2.ZERO)
	var bosque_quemado: bool = bosque.estado[0] == 2

	var pastizal: Variant = SCRIPT_FIRE_GRID.new(Vector2.ZERO, Vector2i(1, 1), 82)
	var tipos: PackedByteArray = pastizal.tipo_combustible
	tipos[0] = 1
	pastizal.tipo_combustible = tipos
	var combustible: PackedFloat32Array = pastizal.combustible
	combustible[0] = 40.0
	pastizal.combustible = combustible
	pastizal.encender(Vector2i.ZERO)
	for _paso in range(66):
		pastizal.paso(0.3, Vector2.ZERO)
	var pastizal_aun_ardiendo: bool = pastizal.estado[0] == ESTADO_ARDIENDO
	pastizal.paso(0.3, Vector2.ZERO)
	var pastizal_quemado: bool = pastizal.estado[0] == 2
	var correcto: bool = (
		bosque_aun_ardiendo
		and bosque_quemado
		and pastizal_aun_ardiendo
		and pastizal_quemado
	)
	_informar("duración de combustión por perfil", correcto)
	return correcto

func _benchmark() -> void:
	var grilla: Variant = SCRIPT_FIRE_GRID.new(Vector2.ZERO, Vector2i(200, 200), 321)
	var tipos: PackedByteArray = grilla.tipo_combustible
	var combustibles: PackedFloat32Array = grilla.combustible
	tipos.fill(TIPO_SIN_COMBUSTIBLE)
	combustibles.fill(0.0)
	for y in range(96, 104):
		for x in range(96, 104):
			var indice: int = y * 200 + x
			tipos[indice] = TIPO_BOSQUE_SECO
			combustibles[indice] = 100.0
	grilla.tipo_combustible = tipos
	grilla.combustible = combustibles
	grilla.encender(Vector2i(100, 100))
	var inicio := Time.get_ticks_usec()
	for _paso in range(150):
		grilla.paso(0.3, Vector2(5.0, 2.0))
		grilla.obtener_deltas()
	var milisegundos_por_tick := float(Time.get_ticks_usec() - inicio) / 150000.0
	print("Benchmark FireGrid 200x200, 150 pasos: %.3f ms/tick" % milisegundos_por_tick)

func _informar(nombre: String, correcto: bool) -> void:
	print("%s: %s" % [nombre, "OK" if correcto else "FALLO"])
