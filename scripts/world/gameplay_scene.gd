extends Node

@export var fuego_central_position: Vector3 = Vector3.ZERO

func _enter_tree() -> void:
	if NetworkManager.es_servidor_headless():
		return
	_instanciar_escena_visual("res://scenes/actors/fire_source.tscn", "WildfireZone")
	_instanciar_escena_visual("res://scenes/ui/tactical_hud.tscn", "TacticalHUD")
	_instanciar_escena_visual("res://scenes/ui/perf_overlay.tscn", "PerfOverlay")

func _instanciar_escena_visual(ruta: String, nombre: String) -> void:
	var escena := load(ruta) as PackedScene
	if not is_instance_valid(escena):
		push_error("No se pudo cargar la escena visual: %s." % ruta)
		return
	var instancia := escena.instantiate()
	if not is_instance_valid(instancia):
		push_error("No se pudo instanciar la escena visual: %s." % ruta)
		return
	instancia.name = nombre
	if nombre == "WildfireZone" and instancia is Node3D:
		(instancia as Node3D).position = fuego_central_position
		instancia.set("objetivo_extinguible", false)
	add_child(instancia)
