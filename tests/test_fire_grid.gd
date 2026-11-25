extends SceneTree

const SCRIPT_FIRE_GRID: Script = preload("res://scripts/sim/fire_grid.gd")
const ESTADO_SANO: int = 0
const ESTADO_ARDIENDO: int = 1
const ESTADO_MOJADO: int = 3
const TIPO_BOSQUE_SECO: int = 0
const TIPO_SIN_COMBUSTIBLE: int = 3

func _initialize() -> void:
	call_deferred("_ejecutar_pruebas")

func _ejecutar_pruebas() -> void:
	var exitosas := 0
	var total := 6
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
	var correcto: bool = grilla_a.estado == grilla_b.estado and grilla_a.combustible == grilla_b.combustible
	_informar("determinismo", correcto)
	return correcto

func _probar_viento() -> bool:
	var semilla_prueba := _buscar_semilla_entre(0.02, 0.04)
	var calma: Variant = SCRIPT_FIRE_GRID.new(Vector2.ZERO, Vector2i(3, 3), semilla_prueba)
	var a_favor: Variant = SCRIPT_FIRE_GRID.new(Vector2.ZERO, Vector2i(3, 3), semilla_prueba)
	calma.encender(Vector2i(1, 1))
	a_favor.encender(Vector2i(1, 1))
	var viento_direccionado := Vector2(-1.0, -1.0).normalized() * 30.0
	calma.paso(0.3, Vector2.ZERO)
	a_favor.paso(0.3, viento_direccionado)
	var indice_objetivo := 0
	var correcto: bool = calma.estado[indice_objetivo] == ESTADO_SANO and a_favor.estado[indice_objetivo] == ESTADO_ARDIENDO
	_informar("viento a favor", correcto)
	return correcto

func _probar_pendiente() -> bool:
	var semilla_prueba := _buscar_semilla_entre(0.02, 0.04)
	var plano: Variant = SCRIPT_FIRE_GRID.new(Vector2.ZERO, Vector2i(3, 3), semilla_prueba)
	var cuesta_arriba: Variant = SCRIPT_FIRE_GRID.new(Vector2.ZERO, Vector2i(3, 3), semilla_prueba)
	cuesta_arriba.altura[0] = 100.0
	plano.encender(Vector2i(1, 1))
	cuesta_arriba.encender(Vector2i(1, 1))
	plano.paso(0.3, Vector2.ZERO)
	cuesta_arriba.paso(0.3, Vector2.ZERO)
	var correcto: bool = plano.estado[0] == ESTADO_SANO and cuesta_arriba.estado[0] == ESTADO_ARDIENDO
	_informar("pendiente ascendente", correcto)
	return correcto

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
	original.encender(Vector2i(3, 4))
	original.paso(0.45, Vector2(2.0, -1.0))
	var copia: Variant = SCRIPT_FIRE_GRID.new(Vector2.ZERO, Vector2i(1, 1), 1)
	var correcto: bool = (
		copia.cargar_completo(original.serializar_completo())
		and copia.estado == original.estado
		and copia.tamano_celdas == original.tamano_celdas
		and copia.origen == original.origen
	)
	original.paso(0.15, Vector2(2.0, -1.0))
	copia.paso(0.15, Vector2(2.0, -1.0))
	correcto = correcto and copia.estado == original.estado and copia.combustible == original.combustible
	_informar("serialización", correcto)
	return correcto

func _probar_duracion_combustion() -> bool:
	var bosque: Variant = SCRIPT_FIRE_GRID.new(Vector2.ZERO, Vector2i(1, 1), 81)
	bosque.encender(Vector2i.ZERO)
	for _paso in range(133):
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
	for _paso in range(33):
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

func _buscar_semilla_entre(minimo: float, maximo: float) -> int:
	var comprobador := RandomNumberGenerator.new()
	for semilla_prueba in range(1, 10000):
		comprobador.seed = semilla_prueba
		var tirada := comprobador.randf()
		if tirada > minimo and tirada < maximo:
			return semilla_prueba
	push_error("No se encontró una semilla adecuada para las pruebas de ignición.")
	return 1

func _informar(nombre: String, correcto: bool) -> void:
	print("%s: %s" % [nombre, "OK" if correcto else "FALLO"])
