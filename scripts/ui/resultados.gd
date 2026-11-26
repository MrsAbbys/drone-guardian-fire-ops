extends Control

const RUTA_REGISTROS: String = "user://records.cfg"

@onready var etiqueta_estado: Label = $Panel/Contenido/Estado
@onready var etiqueta_estrellas: Label = $Panel/Contenido/Estrellas
@onready var etiqueta_tiempo: Label = $Panel/Contenido/Tiempo
@onready var etiqueta_superficie: Label = $Panel/Contenido/Superficie
@onready var etiqueta_objetivos: Label = $Panel/Contenido/Objetivos
@onready var etiqueta_agua: Label = $Panel/Contenido/AguaDesperdiciada
@onready var etiqueta_record: Label = $Panel/Contenido/Record
@onready var boton_reintentar: Button = $Panel/Contenido/Botones/Reintentar
@onready var boton_menu: Button = $Panel/Contenido/Botones/Menu


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	boton_reintentar.text = tr("RESULT_RETRY")
	boton_menu.text = tr("RESULT_MENU")
	boton_reintentar.disabled = (
		not NetworkManager.codigo_sala.is_empty() and not NetworkManager.es_anfitrion_local()
	)
	boton_reintentar.pressed.connect(MissionResults.reintentar)
	boton_menu.pressed.connect(MissionResults.volver_al_menu)
	_mostrar_resultado()


func _mostrar_resultado() -> void:
	var datos := MissionResults.resultado_actual
	if datos.is_empty():
		push_error("La pantalla de resultados se abrió sin datos de misión.")
		return
	var porcentaje := clampf(float(datos.get("superficie_salvada_pct", 0.0)), 0.0, 100.0)
	var objetivos_salvados := int(datos.get("objetivos_salvados", 0))
	var objetivos_totales := int(datos.get("objetivos_totales", 0))
	var victoria := bool(datos.get("victoria", false))
	var segundos := maxf(float(datos.get("tiempo_segundos", 0.0)), 0.0)
	var agua_desperdiciada := maxf(float(datos.get("wasted_water_time", 0.0)), 0.0)
	var estrellas := _calcular_estrellas(
		victoria, porcentaje, objetivos_salvados, objetivos_totales, agua_desperdiciada
	)
	etiqueta_estado.text = tr("RESULT_COMPLETED") if victoria else tr("RESULT_FAILED")
	etiqueta_estrellas.text = "★".repeat(estrellas) + "☆".repeat(3 - estrellas)
	etiqueta_tiempo.text = tr("RESULT_TIME") % _formatear_tiempo(segundos)
	etiqueta_superficie.text = tr("RESULT_SAVED_SURFACE") % porcentaje
	etiqueta_objetivos.text = (
		tr("RESULT_CRITICAL_OBJECTIVES") % [objetivos_salvados, objetivos_totales]
	)
	etiqueta_agua.text = tr("RESULT_WASTED_WATER") % agua_desperdiciada
	etiqueta_record.text = _guardar_y_leer_record(datos, estrellas)


func _calcular_estrellas(
	victoria: bool,
	porcentaje: float,
	objetivos_salvados: int,
	objetivos_totales: int,
	agua_desperdiciada: float
) -> int:
	if (
		victoria
		and porcentaje >= 90.0
		and objetivos_salvados == objetivos_totales
		and agua_desperdiciada <= 5.0
	):
		return 3
	if (
		porcentaje >= 65.0
		and (objetivos_totales == 0 or objetivos_salvados * 2 >= objetivos_totales)
	):
		return 2
	return 1


func _guardar_y_leer_record(datos: Dictionary, estrellas: int) -> String:
	var registros := ConfigFile.new()
	var error_carga := registros.load(RUTA_REGISTROS)
	if error_carga != OK and error_carga != ERR_FILE_NOT_FOUND:
		push_error("No se pudieron leer los mejores puntajes: %s." % error_carga)
		return tr("RESULT_RECORD_LOAD_FAILED")
	var escenario := str(datos.get("escenario", "sin_escenario"))
	var actual := {
		"estrellas": estrellas,
		"superficie_salvada_pct": float(datos.get("superficie_salvada_pct", 0.0)),
		"tiempo_segundos": float(datos.get("tiempo_segundos", 0.0)),
	}
	var anterior: Variant = registros.get_value("records", escenario, {})
	var guardar_nuevo := not anterior is Dictionary
	if anterior is Dictionary:
		guardar_nuevo = _es_mejor_record(actual, anterior)
	if guardar_nuevo:
		registros.set_value("records", escenario, actual)
		var error_guardado := registros.save(RUTA_REGISTROS)
		if error_guardado != OK:
			push_error("No se pudo guardar el mejor puntaje (error %d)." % error_guardado)
			return tr("RESULT_NEW_RECORD") % float(actual["superficie_salvada_pct"])
		anterior = actual
	return (
		tr("RESULT_BEST_SCORE")
		% [
			int(anterior.get("estrellas", 0)),
			float(anterior.get("superficie_salvada_pct", 0.0)),
		]
	)


func _es_mejor_record(actual: Dictionary, anterior: Dictionary) -> bool:
	var estrellas_anteriores := int(anterior.get("estrellas", 0))
	if int(actual["estrellas"]) != estrellas_anteriores:
		return int(actual["estrellas"]) > estrellas_anteriores
	var superficie_anterior := float(anterior.get("superficie_salvada_pct", 0.0))
	if not is_equal_approx(float(actual["superficie_salvada_pct"]), superficie_anterior):
		return float(actual["superficie_salvada_pct"]) > superficie_anterior
	var tiempo_anterior := float(anterior.get("tiempo_segundos", INF))
	return float(actual["tiempo_segundos"]) < tiempo_anterior


func _formatear_tiempo(segundos: float) -> String:
	var total := int(round(segundos))
	return "%02d:%02d" % [floori(float(total) / 60.0), total % 60]
