extends Node

const ESCENA_AGUARAGUE: PackedScene = preload("res://scenes/levels/escena_aguarague.tscn")

func _ready() -> void:
	call_deferred("_probar_integracion")

func _probar_integracion() -> void:
	var escena := ESCENA_AGUARAGUE.instantiate()
	get_tree().root.add_child(escena)
	await get_tree().process_frame
	var dron := escena.find_child("DronePlayer", true, false) as Node3D
	if not is_instance_valid(dron):
		push_error("La escena Aguaragüe no contiene DronePlayer.")
		get_tree().quit(1)
		return
	dron.global_position = Vector3(500.0, 100.0, 500.0)
	for _marco in range(40):
		await get_tree().process_frame

	var vista := escena.find_child("FireGridView", true, false)
	var visuales_por_celda: Dictionary = vista.get("_visuales_por_celda")
	var visuales := get_tree().get_nodes_in_group("fuego")
	var arboles_calentando: int = 0
	var arboles_intensos: int = 0
	for arbol in get_tree().get_nodes_in_group("arbol_simulado"):
		if is_instance_valid(arbol):
			var fase_fuego: int = int(arbol.get("_fase_fuego"))
			if fase_fuego >= 1 and fase_fuego <= 2:
				arboles_calentando += 1
			if fase_fuego == 2:
				arboles_intensos += 1
	var estados_iniciales := FireGridServer.obtener_estado_celdas()
	var estados_no_iniciales: int = 0
	for estado in estados_iniciales:
		if estado != 0 and estado != 1:
			estados_no_iniciales += 1
	var correcto := (
		FireGridServer.activa
		and FireGridServer.obtener_cantidad_ardiendo() == 3
		and float(FireGridServer.get("_retardo_propagacion_restante")) == 0.0
		and estados_no_iniciales == 0
		and arboles_calentando >= 3
		and arboles_intensos == 0
		and visuales_por_celda.size() == 3
		and visuales.size() <= FirePool.TAMANO_MAX
	)
	var temporizador_grilla := FireGridServer.get_node("TemporizadorFireGrid") as Timer
	while float(FireGridServer.get("_retardo_propagacion_restante")) > 0.0:
		await temporizador_grilla.timeout
	correcto = correcto and FireGridServer.obtener_cantidad_ardiendo() == 3
	FireGridServer.set("_ultima_medicion_frente_ms", Time.get_ticks_msec() - 10000)
	FireGridServer.debug_velocidad_frente()
	var camara := get_viewport().get_camera_3d()
	vista.call("_reconciliar_visuales")
	correcto = correcto and visuales_por_celda.size() >= 3
	camara.global_position = Vector3(55.0, 20.0, -90.0)
	vista.call("_reconciliar_visuales")
	correcto = correcto and visuales_por_celda.size() >= 3
	for _etapa in range(18):
		await temporizador_grilla.timeout
	var arboles_intensos_despues_calentamiento: int = 0
	for arbol in get_tree().get_nodes_in_group("arbol_simulado"):
		if is_instance_valid(arbol) and int(arbol.get("_fase_fuego")) == 2:
			arboles_intensos_despues_calentamiento += 1
	correcto = correcto and arboles_intensos_despues_calentamiento >= 3
	if correcto:
		var visual := visuales_por_celda.values()[0] as Node3D
		var identificador := visual.get_instance_id()
		FirePool.liberar(visual)
		FirePool.liberar(visual)
		var reutilizado := FirePool.adquirir(Vector3.ZERO, Vector3.ZERO, false)
		correcto = is_instance_valid(reutilizado) and reutilizado.get_instance_id() == identificador
		if is_instance_valid(reutilizado):
			FirePool.liberar(reutilizado)
	print("Integración FireGrid/FirePool: %s (%d visuales)" % ["OK" if correcto else "FALLO", visuales.size()])
	escena.queue_free()
	get_tree().quit(0 if correcto else 1)
