extends Node

signal asignaciones_actualizadas
signal reasignacion_iniciada(accion: StringName)
signal reasignacion_finalizada(accion: StringName, cancelada: bool)

const RUTA_CONFIGURACION: String = "user://controles.cfg"
const ACCIONES: Array[StringName] = [
	&"drone_forward",
	&"drone_backward",
	&"drone_left",
	&"drone_right",
	&"drone_ascend",
	&"drone_descend",
	&"drone_refill",
	&"drone_special",
	&"drone_spray",
	&"drone_retardant",
]
const ETIQUETAS: Dictionary = {
	"drone_forward": "Avanzar",
	"drone_backward": "Retroceder",
	"drone_left": "Desplazarse a la izquierda",
	"drone_right": "Desplazarse a la derecha",
	"drone_ascend": "Subir",
	"drone_descend": "Bajar",
	"drone_refill": "Recargar agua",
	"drone_special": "Habilidad especial",
	"drone_spray": "Rociar agua",
	"drone_retardant": "Lanzar retardante",
}

var _configuracion := ConfigFile.new()
var _accion_pendiente: StringName = &""


func _ready() -> void:
	_configurar_acciones_predeterminadas()
	_cargar_configuracion()


func _input(evento: InputEvent) -> void:
	if _accion_pendiente.is_empty():
		return
	if evento is InputEventKey and evento.pressed and evento.keycode == KEY_ESCAPE:
		var accion_cancelada := _accion_pendiente
		_accion_pendiente = &""
		reasignacion_finalizada.emit(accion_cancelada, true)
		get_viewport().set_input_as_handled()
		return
	if not _es_evento_reasignable(evento):
		return
	_guardar_evento(_accion_pendiente, evento)
	var accion_completada := _accion_pendiente
	_accion_pendiente = &""
	reasignacion_finalizada.emit(accion_completada, false)
	asignaciones_actualizadas.emit()
	get_viewport().set_input_as_handled()


func obtener_acciones() -> Array[StringName]:
	return ACCIONES.duplicate()


func obtener_etiqueta(accion: StringName) -> String:
	return str(ETIQUETAS.get(str(accion), accion))


func obtener_resumen(accion: StringName) -> String:
	if not InputMap.has_action(accion):
		return "Sin asignar"
	var resumen: Array[String] = []
	for evento in InputMap.action_get_events(accion):
		resumen.append(evento.as_text())
	return " / ".join(resumen) if not resumen.is_empty() else "Sin asignar"


func iniciar_reasignacion(accion: StringName) -> void:
	if not ACCIONES.has(accion):
		push_error("No se puede reasignar una acción desconocida: %s." % accion)
		return
	_accion_pendiente = accion
	reasignacion_iniciada.emit(accion)


func _configurar_acciones_predeterminadas() -> void:
	for accion in ACCIONES:
		if not InputMap.has_action(accion):
			InputMap.add_action(accion, 0.2)
		if InputMap.action_get_events(accion).is_empty():
			for evento in _eventos_predeterminados(accion):
				InputMap.action_add_event(accion, evento)


func _eventos_predeterminados(accion: StringName) -> Array[InputEvent]:
	var eventos: Array[InputEvent] = []
	match accion:
		&"drone_forward":
			eventos.append(_crear_tecla(KEY_W))
			eventos.append(_crear_eje(JOY_AXIS_LEFT_Y, -1.0))
		&"drone_backward":
			eventos.append(_crear_tecla(KEY_S))
			eventos.append(_crear_eje(JOY_AXIS_LEFT_Y, 1.0))
		&"drone_left":
			eventos.append(_crear_tecla(KEY_A))
			eventos.append(_crear_eje(JOY_AXIS_LEFT_X, -1.0))
		&"drone_right":
			eventos.append(_crear_tecla(KEY_D))
			eventos.append(_crear_eje(JOY_AXIS_LEFT_X, 1.0))
		&"drone_ascend":
			eventos.append(_crear_tecla(KEY_SPACE))
			eventos.append(_crear_boton(JOY_BUTTON_Y))
		&"drone_descend":
			eventos.append(_crear_tecla(KEY_C))
			eventos.append(_crear_boton(JOY_BUTTON_A))
		&"drone_refill":
			eventos.append(_crear_tecla(KEY_E))
			eventos.append(_crear_boton(JOY_BUTTON_X))
		&"drone_special":
			eventos.append(_crear_tecla(KEY_Q))
			eventos.append(_crear_boton(JOY_BUTTON_B))
		&"drone_spray":
			eventos.append(_crear_boton_raton(MOUSE_BUTTON_LEFT))
			eventos.append(_crear_boton(JOY_BUTTON_RIGHT_SHOULDER))
		&"drone_retardant":
			eventos.append(_crear_boton_raton(MOUSE_BUTTON_RIGHT))
			eventos.append(_crear_boton(JOY_BUTTON_LEFT_SHOULDER))
	return eventos


func _crear_tecla(tecla: Key) -> InputEventKey:
	var evento := InputEventKey.new()
	evento.physical_keycode = tecla
	return evento


func _crear_boton_raton(boton: MouseButton) -> InputEventMouseButton:
	var evento := InputEventMouseButton.new()
	evento.button_index = boton
	return evento


func _crear_boton(boton: JoyButton) -> InputEventJoypadButton:
	var evento := InputEventJoypadButton.new()
	evento.button_index = boton
	return evento


func _crear_eje(eje: JoyAxis, valor: float) -> InputEventJoypadMotion:
	var evento := InputEventJoypadMotion.new()
	evento.axis = eje
	evento.axis_value = valor
	return evento


func _cargar_configuracion() -> void:
	var error_carga := _configuracion.load(RUTA_CONFIGURACION)
	if error_carga == ERR_FILE_NOT_FOUND:
		return
	if error_carga != OK:
		push_error("No se pudieron leer los controles guardados (error %d)." % error_carga)
		return
	for accion in ACCIONES:
		var guardados: Variant = _configuracion.get_value("bindings", str(accion), null)
		if guardados == null:
			continue
		if not guardados is Array:
			push_error("La configuración de la acción %s no es una lista." % accion)
			continue
		var eventos: Array[InputEvent] = []
		for datos in guardados:
			if not datos is Dictionary:
				push_error("Se encontró una asignación de control inválida para %s." % accion)
				continue
			var evento := _deserializar_evento(datos)
			if is_instance_valid(evento):
				eventos.append(evento)
		if eventos.is_empty():
			push_error(
				(
					"La acción %s no tiene asignaciones válidas; se conservarán sus valores predeterminados."
					% accion
				)
			)
			continue
		InputMap.action_erase_events(accion)
		for evento in eventos:
			InputMap.action_add_event(accion, evento)


func _guardar_evento(accion: StringName, evento_nuevo: InputEvent) -> void:
	var categoria := _categoria_evento(evento_nuevo)
	var eventos: Array[InputEvent] = []
	for evento in InputMap.action_get_events(accion):
		if _categoria_evento(evento) != categoria:
			eventos.append(evento)
	eventos.append(_normalizar_evento(evento_nuevo))
	InputMap.action_erase_events(accion)
	for evento in eventos:
		InputMap.action_add_event(accion, evento)
	var datos_eventos: Array[Dictionary] = []
	for evento in eventos:
		datos_eventos.append(_serializar_evento(evento))
	_configuracion.set_value("bindings", str(accion), datos_eventos)
	var error_guardado := _configuracion.save(RUTA_CONFIGURACION)
	if error_guardado != OK:
		push_error("No se pudieron guardar los controles (error %d)." % error_guardado)


func _es_evento_reasignable(evento: InputEvent) -> bool:
	if evento is InputEventKey:
		return evento.pressed and not evento.echo
	if evento is InputEventMouseButton:
		return evento.pressed
	if evento is InputEventJoypadButton:
		return evento.pressed
	if evento is InputEventJoypadMotion:
		return absf(evento.axis_value) >= 0.7
	return false


func _categoria_evento(evento: InputEvent) -> String:
	if evento is InputEventKey:
		return "teclado"
	if evento is InputEventMouseButton:
		return "raton"
	return "mando"


func _normalizar_evento(evento: InputEvent) -> InputEvent:
	var copia := evento.duplicate() as InputEvent
	if copia is InputEventKey or copia is InputEventMouseButton or copia is InputEventJoypadButton:
		copia.set("pressed", false)
	if copia is InputEventKey:
		copia.set("echo", false)
	return copia


func _serializar_evento(evento: InputEvent) -> Dictionary:
	if evento is InputEventKey:
		return {
			"tipo": "tecla",
			"codigo_fisico": evento.physical_keycode,
			"codigo": evento.keycode,
			"unicode": evento.unicode,
			"shift": evento.shift_pressed,
			"ctrl": evento.ctrl_pressed,
			"alt": evento.alt_pressed,
			"meta": evento.meta_pressed,
			"device": evento.device,
		}
	if evento is InputEventMouseButton:
		return {
			"tipo": "raton",
			"boton": evento.button_index,
			"shift": evento.shift_pressed,
			"ctrl": evento.ctrl_pressed,
			"alt": evento.alt_pressed,
			"meta": evento.meta_pressed,
			"device": evento.device,
		}
	if evento is InputEventJoypadButton:
		return {
			"tipo": "boton_mando",
			"boton": evento.button_index,
			"device": evento.device,
		}
	if evento is InputEventJoypadMotion:
		return {
			"tipo": "eje_mando",
			"eje": evento.axis,
			"valor": evento.axis_value,
			"device": evento.device,
		}
	return {}


func _deserializar_evento(datos: Dictionary) -> InputEvent:
	match str(datos.get("tipo", "")):
		"tecla":
			var evento := InputEventKey.new()
			evento.physical_keycode = int(datos.get("codigo_fisico", 0))
			evento.keycode = int(datos.get("codigo", 0))
			evento.unicode = int(datos.get("unicode", 0))
			evento.shift_pressed = bool(datos.get("shift", false))
			evento.ctrl_pressed = bool(datos.get("ctrl", false))
			evento.alt_pressed = bool(datos.get("alt", false))
			evento.meta_pressed = bool(datos.get("meta", false))
			evento.device = int(datos.get("device", -1))
			return evento
		"raton":
			var evento := InputEventMouseButton.new()
			evento.button_index = int(datos.get("boton", 0))
			evento.shift_pressed = bool(datos.get("shift", false))
			evento.ctrl_pressed = bool(datos.get("ctrl", false))
			evento.alt_pressed = bool(datos.get("alt", false))
			evento.meta_pressed = bool(datos.get("meta", false))
			evento.device = int(datos.get("device", -1))
			return evento
		"boton_mando":
			var evento := InputEventJoypadButton.new()
			evento.button_index = int(datos.get("boton", 0))
			evento.device = int(datos.get("device", -1))
			return evento
		"eje_mando":
			var evento := InputEventJoypadMotion.new()
			evento.axis = int(datos.get("eje", 0))
			evento.axis_value = float(datos.get("valor", 0.0))
			evento.device = int(datos.get("device", -1))
			return evento
	return null
