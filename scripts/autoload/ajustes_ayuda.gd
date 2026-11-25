extends Node

signal ayuda_cambiada(nivel: int)

const AYUDA_ALTA: int = 0
const AYUDA_MEDIA: int = 1
const AYUDA_BAJA: int = 2
const AYUDA_NINGUNA: int = 3
const RUTA_AJUSTES: String = "user://ajustes.cfg"

var nivel_ayuda: int = AYUDA_ALTA
var primera_mision_completada: bool = false
var nivel_ayuda_personalizado: bool = false

func _ready() -> void:
	var ajustes := ConfigFile.new()
	var error_carga := ajustes.load(RUTA_AJUSTES)
	if error_carga != OK and error_carga != ERR_FILE_NOT_FOUND:
		push_error("No se pudieron cargar los ajustes de ayuda: %s" % error_carga)
		return
	if error_carga == OK:
		primera_mision_completada = bool(
			ajustes.get_value("progreso", "primera_mision_completada", false)
		)
		nivel_ayuda_personalizado = bool(
			ajustes.get_value("ayuda", "nivel_personalizado", false)
		)
		var nivel_guardado: Variant = ajustes.get_value("ayuda", "nivel", AYUDA_ALTA)
		if nivel_guardado is int and nivel_guardado >= AYUDA_ALTA and nivel_guardado <= AYUDA_NINGUNA:
			nivel_ayuda = nivel_guardado
		elif nivel_ayuda_personalizado:
			push_warning("El nivel de ayuda guardado no es válido; se usará el predeterminado.")
			nivel_ayuda_personalizado = false
	if not nivel_ayuda_personalizado:
		nivel_ayuda = AYUDA_MEDIA if primera_mision_completada else AYUDA_ALTA

func configurar_nivel_ayuda(nivel: int) -> void:
	if nivel < AYUDA_ALTA or nivel > AYUDA_NINGUNA:
		push_error("No se puede guardar un nivel de ayuda desconocido: %d" % nivel)
		return
	var cambio_nivel := nivel_ayuda != nivel
	nivel_ayuda = nivel
	nivel_ayuda_personalizado = true
	_guardar_ajustes()
	if cambio_nivel:
		ayuda_cambiada.emit(nivel_ayuda)

func completar_primera_mision() -> void:
	if primera_mision_completada:
		return
	primera_mision_completada = true
	var nivel_anterior := nivel_ayuda
	if not nivel_ayuda_personalizado:
		nivel_ayuda = AYUDA_MEDIA
	_guardar_ajustes()
	if nivel_anterior != nivel_ayuda:
		ayuda_cambiada.emit(nivel_ayuda)

func _guardar_ajustes() -> void:
	var ajustes := ConfigFile.new()
	var error_carga := ajustes.load(RUTA_AJUSTES)
	if error_carga != OK and error_carga != ERR_FILE_NOT_FOUND:
		push_error("No se pudieron leer los ajustes existentes: %s" % error_carga)
		return
	ajustes.set_value("progreso", "primera_mision_completada", primera_mision_completada)
	ajustes.set_value("ayuda", "nivel", nivel_ayuda)
	ajustes.set_value("ayuda", "nivel_personalizado", nivel_ayuda_personalizado)
	var error_guardado := ajustes.save(RUTA_AJUSTES)
	if error_guardado != OK:
		push_error("No se pudieron guardar los ajustes de ayuda: %s" % error_guardado)
