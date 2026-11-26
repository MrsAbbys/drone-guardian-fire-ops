extends Node

signal idioma_cambiado(locale: String)

const RUTA_CONFIGURACION: String = "user://idioma.cfg"
const IDIOMAS_ADMITIDOS: Array[String] = ["es", "en"]

var _configuracion := ConfigFile.new()
var _idioma_actual: String = "es"

func _ready() -> void:
	var error_carga := _configuracion.load(RUTA_CONFIGURACION)
	if error_carga != OK and error_carga != ERR_FILE_NOT_FOUND:
		push_error("No se pudo leer el idioma guardado (error %d)." % error_carga)
	var idioma_guardado := str(_configuracion.get_value("idioma", "locale", "es"))
	if not IDIOMAS_ADMITIDOS.has(idioma_guardado):
		push_error("El idioma guardado no es compatible: %s." % idioma_guardado)
		idioma_guardado = "es"
	_aplicar_idioma(idioma_guardado)

func idioma_actual() -> String:
	return _idioma_actual

func configurar_idioma(locale: String) -> void:
	if not IDIOMAS_ADMITIDOS.has(locale):
		push_error("Idioma no compatible: %s." % locale)
		return
	_aplicar_idioma(locale)
	_configuracion.set_value("idioma", "locale", locale)
	var error_guardado := _configuracion.save(RUTA_CONFIGURACION)
	if error_guardado != OK:
		push_error("No se pudo guardar el idioma (error %d)." % error_guardado)

func _aplicar_idioma(locale: String) -> void:
	_idioma_actual = locale
	TranslationServer.set_locale(locale)
	idioma_cambiado.emit(locale)
