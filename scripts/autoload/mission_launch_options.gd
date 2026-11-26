extends Node

const SCRIPT_CONFIGURACION_VIENTO: Script = preload("res://scripts/sim/configuracion_viento.gd")

var _pending: bool = false
var _difficulty_multiplier: float = 1.0
var _wind_multiplier: float = 1.0


func prepare_launch(difficulty: String, wind: String) -> void:
	match difficulty:
		"easy":
			_difficulty_multiplier = 0.75
		"hard":
			_difficulty_multiplier = 1.3
		_:
			_difficulty_multiplier = 1.0
	match wind:
		"calm":
			_wind_multiplier = 0.6
		"strong":
			_wind_multiplier = 1.4
		_:
			_wind_multiplier = 1.0
	_pending = true


func cancel() -> void:
	_pending = false


func apply_to_configuration(configuration: Resource) -> Resource:
	if not _pending:
		return configuration
	if not is_instance_valid(configuration) or not configuration is ConfiguracionGrillaIncendio:
		push_error("MissionLaunchOptions requiere una ConfiguracionGrillaIncendio válida.")
		_pending = false
		return null

	var adjusted := configuration.duplicate(true) as ConfiguracionGrillaIncendio
	if not is_instance_valid(adjusted):
		push_error("No se pudo duplicar la configuración de misión.")
		_pending = false
		return null

	var wind_configuration := adjusted.configuracion_viento
	if (
		not is_instance_valid(wind_configuration)
		or wind_configuration.get_script() != SCRIPT_CONFIGURACION_VIENTO
	):
		push_error("La configuración de misión no contiene un perfil de viento válido.")
		_pending = false
		return null
	wind_configuration = wind_configuration.duplicate(true) as Resource
	if not is_instance_valid(wind_configuration):
		push_error("No se pudo duplicar el perfil de viento.")
		_pending = false
		return null

	adjusted.velocidad_propagacion = clampf(
		adjusted.velocidad_propagacion * _difficulty_multiplier,
		0.1,
		3.0
	)
	wind_configuration.set(
		"velocidad_base",
		maxf(float(wind_configuration.get("velocidad_base")) * _wind_multiplier, 0.0)
	)
	wind_configuration.set(
		"amplitud_velocidad",
		maxf(float(wind_configuration.get("amplitud_velocidad")) * _wind_multiplier, 0.0)
	)
	adjusted.configuracion_viento = wind_configuration
	_pending = false
	return adjusted
