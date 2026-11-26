extends SceneTree

const SCRIPT_LAUNCH_OPTIONS: Script = preload(
	"res://scripts/autoload/mission_launch_options.gd"
)
const CONFIGURACION_AGUARAGUE: Resource = preload(
	"res://resources/sim/configuracion_aguarague.tres"
)


func _initialize() -> void:
	call_deferred("_probar_opciones_de_mision")


func _probar_opciones_de_mision() -> void:
	var opciones: Node = SCRIPT_LAUNCH_OPTIONS.new()
	root.add_child(opciones)
	var velocidad_original := float(CONFIGURACION_AGUARAGUE.get("velocidad_propagacion"))
	var viento_original: Resource = CONFIGURACION_AGUARAGUE.get("configuracion_viento")
	var velocidad_viento_original := float(viento_original.get("velocidad_base"))

	opciones.call("prepare_launch", "hard", "strong")
	var ajustada: Resource = opciones.call(
		"apply_to_configuration", CONFIGURACION_AGUARAGUE
	)
	if not is_instance_valid(ajustada):
		push_error("MissionLaunchOptions no devolvió una configuración ajustada.")
		opciones.queue_free()
		call_deferred("quit", 1)
		return
	var viento_ajustado: Resource = ajustada.get("configuracion_viento")
	if not is_instance_valid(viento_ajustado):
		push_error("MissionLaunchOptions no devolvió una configuración de viento.")
		opciones.queue_free()
		call_deferred("quit", 1)
		return
	var correcta := (
		is_equal_approx(
			float(ajustada.get("velocidad_propagacion")),
			minf(velocidad_original * 1.3, 3.0)
		)
		and is_equal_approx(
			float(viento_ajustado.get("velocidad_base")),
			velocidad_viento_original * 1.4
		)
		and is_equal_approx(
			float(CONFIGURACION_AGUARAGUE.get("velocidad_propagacion")),
			velocidad_original
		)
		and is_equal_approx(
			float(viento_original.get("velocidad_base")),
			velocidad_viento_original
		)
		and opciones.call("apply_to_configuration", CONFIGURACION_AGUARAGUE)
		== CONFIGURACION_AGUARAGUE
	)
	if correcta:
		print("MissionLaunchOptions: presets apply once without mutating resources.")
	else:
		push_error("MissionLaunchOptions: preset application or resource isolation failed.")
	opciones.queue_free()
	call_deferred("quit", 0 if correcta else 1)
