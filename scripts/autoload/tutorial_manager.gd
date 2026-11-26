extends Node

const RUTA_CONFIGURACION: String = "user://tutorial.cfg"
const DURACION_TUTORIAL: float = 120.0
const DURACION_PASO: float = 24.0
const PASOS: Array[Dictionary] = [
	{
		"accion": "mover",
		"titulo": "TUTORIAL_MOVE_TITLE",
		"texto": "TUTORIAL_MOVE_TEXT",
	},
	{
		"accion": "altura",
		"titulo": "TUTORIAL_ALTITUDE_TITLE",
		"texto": "TUTORIAL_ALTITUDE_TEXT",
	},
	{
		"accion": "recargar",
		"titulo": "TUTORIAL_REFILL_TITLE",
		"texto": "TUTORIAL_REFILL_TEXT",
	},
	{
		"accion": "rociar",
		"titulo": "TUTORIAL_SPRAY_TITLE",
		"texto": "TUTORIAL_SPRAY_TEXT",
	},
	{
		"accion": "viento",
		"titulo": "TUTORIAL_WIND_TITLE",
		"texto": "TUTORIAL_WIND_TEXT",
	},
]

var _configuracion := ConfigFile.new()
var _panel: PanelContainer
var _titulo: Label
var _texto: Label
var _progreso: Label
var _boton: Button
var _tiempo_transcurrido: float = 0.0
var _indice_paso: int = 0
var _tutorial_activo: bool = false
var _tutorial_visto: bool = false


func _ready() -> void:
	get_tree().scene_changed.connect(_al_cambiar_escena)


func _process(delta: float) -> void:
	if not _tutorial_activo or not is_instance_valid(_panel):
		return
	_tiempo_transcurrido += delta
	_actualizar_paso_por_tiempo()
	if _indice_paso < PASOS.size() and _accion_actual_completada():
		_indice_paso += 1
		_actualizar_contenido()
	_actualizar_progreso()
	if _tiempo_transcurrido >= DURACION_TUTORIAL:
		_boton.text = tr("TUTORIAL_FINISH")
		_boton.disabled = false


func _al_cambiar_escena() -> void:
	if is_instance_valid(_panel):
		_panel.get_parent().get_parent().queue_free()
	_panel = null
	_tutorial_activo = false
	_tutorial_visto = false
	call_deferred("_iniciar_si_corresponde")


func _iniciar_si_corresponde() -> void:
	if not is_instance_valid(get_tree().current_scene) or not FireGridServer.activa:
		return
	var error_carga := _configuracion.load(RUTA_CONFIGURACION)
	if error_carga != OK and error_carga != ERR_FILE_NOT_FOUND:
		push_error("No se pudo leer el estado del tutorial (error %d)." % error_carga)
	if bool(_configuracion.get_value("tutorial", "tutorial_visto", false)):
		return
	_tiempo_transcurrido = 0.0
	_indice_paso = 0
	_tutorial_activo = true
	_crear_interfaz()
	_actualizar_contenido()
	_actualizar_progreso()


func _crear_interfaz() -> void:
	var capa := CanvasLayer.new()
	capa.name = "TutorialPrimerVuelo"
	capa.layer = 90
	get_tree().root.add_child(capa)
	var raiz := Control.new()
	raiz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	capa.add_child(raiz)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(560.0, 205.0)
	_panel.position = Vector2((get_viewport().get_visible_rect().size.x - 560.0) * 0.5, 72.0)
	raiz.add_child(_panel)
	var contenido := VBoxContainer.new()
	contenido.add_theme_constant_override("separation", 10)
	_panel.add_child(contenido)
	_titulo = Label.new()
	_titulo.add_theme_font_size_override("font_size", 22)
	contenido.add_child(_titulo)
	_texto = Label.new()
	_texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	contenido.add_child(_texto)
	_progreso = Label.new()
	contenido.add_child(_progreso)
	_boton = Button.new()
	_boton.text = tr("TUTORIAL_NEXT")
	_boton.pressed.connect(_avanzar_paso)
	contenido.add_child(_boton)


func _actualizar_paso_por_tiempo() -> void:
	var paso_temporal := mini(int(floor(_tiempo_transcurrido / DURACION_PASO)), PASOS.size() - 1)
	if paso_temporal > _indice_paso:
		_indice_paso = paso_temporal
		_actualizar_contenido()


func _accion_actual_completada() -> bool:
	var accion := str(PASOS[_indice_paso]["accion"])
	match accion:
		"mover":
			return (
				Input.is_action_pressed("drone_forward")
				or Input.is_action_pressed("drone_backward")
				or Input.is_action_pressed("drone_left")
				or Input.is_action_pressed("drone_right")
			)
		"altura":
			return (
				Input.is_action_pressed("drone_ascend") or Input.is_action_pressed("drone_descend")
			)
		"recargar":
			return Input.is_action_just_pressed("drone_refill")
		"rociar":
			return Input.is_action_pressed("drone_spray")
	return false


func _avanzar_paso() -> void:
	if _tiempo_transcurrido >= DURACION_TUTORIAL:
		_finalizar_tutorial()
		return
	_indice_paso = mini(_indice_paso + 1, PASOS.size())
	_actualizar_contenido()
	_actualizar_progreso()


func _actualizar_contenido() -> void:
	if _indice_paso >= PASOS.size():
		_titulo.text = tr("TUTORIAL_PRACTICE_TITLE")
		_texto.text = tr("TUTORIAL_PRACTICE_TEXT")
		_boton.disabled = _tiempo_transcurrido < DURACION_TUTORIAL
		return
	var paso: Dictionary = PASOS[_indice_paso]
	_titulo.text = tr(str(paso["titulo"]))
	_texto.text = tr(str(paso["texto"]))
	_boton.disabled = false


func _actualizar_progreso() -> void:
	var restante := maxi(0, ceili(DURACION_TUTORIAL - _tiempo_transcurrido))
	_progreso.text = (
		tr("TUTORIAL_PROGRESS")
		% [
			mini(_indice_paso + 1, PASOS.size()),
			PASOS.size(),
			restante / 60,
			restante % 60,
		]
	)
	if _indice_paso >= PASOS.size():
		_boton.disabled = _tiempo_transcurrido < DURACION_TUTORIAL


func _finalizar_tutorial() -> void:
	if _tutorial_visto:
		return
	_tutorial_visto = true
	_tutorial_activo = false
	_configuracion.set_value("tutorial", "tutorial_visto", true)
	var error_guardado := _configuracion.save(RUTA_CONFIGURACION)
	if error_guardado != OK:
		push_error("No se pudo guardar el tutorial completado (error %d)." % error_guardado)
	if is_instance_valid(_panel):
		_panel.get_parent().get_parent().queue_free()
	_panel = null
