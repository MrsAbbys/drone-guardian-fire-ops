extends Control

const RETRATO_NORMAL := preload("res://imagenes_sargento/bien.jpg")
const TextosHartman := preload("res://scripts/ui/textos_hartman.gd")
const ESCENA_AGUARAGUE: String = "res://scenes/levels/escena_aguarague.tscn"
const ESCENA_CAMPO_PAJOSO: String = "res://scenes/levels/escena_campo_pajoso.tscn"
const ESCENA_INTERFASE_URBANA: String = "res://scenes/levels/escena_interfase_urbana.tscn"

var textos_hartman = TextosHartman.new()
@onready var bg_rect: TextureRect = $MenuArtBackground
@onready var capa_ui: CanvasLayer = $FrontUILayer
@onready var lbl_hartman_dialogue: Label = $FrontUILayer/LeftTacticalPanel/HartmanCard/DialogueText
@onready var hartman_portrait: TextureRect = $FrontUILayer/LeftTacticalPanel/HartmanCard/PortraitBox

var panel_ajustes: PanelContainer
var selector_calidad: OptionButton
var selector_ayuda: OptionButton
var slider_sensibilidad: HSlider
var slider_volumen: HSlider
var etiqueta_sensibilidad: Label
var etiqueta_volumen: Label
var selector_escenario: OptionButton
var panel_reasignacion: PanelContainer
var botones_reasignacion: Dictionary = {}

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	hartman_portrait.texture = RETRATO_NORMAL
	load_art()
	_crear_selector_escenario()
	_crear_panel_ajustes()
	_crear_panel_reasignacion()
	_crear_panel_multijugador()
	InputConfig.asignaciones_actualizadas.connect(_actualizar_etiquetas_reasignacion)
	InputConfig.reasignacion_iniciada.connect(_al_iniciar_reasignacion)
	InputConfig.reasignacion_finalizada.connect(_al_finalizar_reasignacion)

func load_art() -> void:
	var background_texture = ResourceLoader.load("res://assets/ui/menu_background.png")
	if background_texture is Texture2D:
		bg_rect.texture = background_texture
	else:
		push_error("No se pudo cargar el fondo del menú: res://assets/ui/menu_background.png")

func _on_btn_1_iniciar_pressed() -> void:
	var target: String = ESCENA_AGUARAGUE
	match selector_escenario.get_selected_id():
		1:
			target = ESCENA_CAMPO_PAJOSO
		2:
			target = ESCENA_INTERFASE_URBANA
	if ResourceLoader.exists(target):
		get_tree().change_scene_to_file(target)
	else:
		get_tree().change_scene_to_file("res://scenes/gameplay/mission_01_yacuiba.tscn")

func _crear_selector_escenario() -> void:
	var lista := get_node_or_null("FrontUILayer/LeftTacticalPanel/ButtonList") as VBoxContainer
	if not is_instance_valid(lista):
		push_error("No se encontró la lista de botones para agregar el selector de escenario.")
		return
	var fila := HBoxContainer.new()
	fila.name = "SelectorEscenario"
	fila.add_theme_constant_override("separation", 8)
	var etiqueta := Label.new()
	etiqueta.text = "ESCENARIO"
	etiqueta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila.add_child(etiqueta)
	selector_escenario = OptionButton.new()
	selector_escenario.add_item("Aguaragüe", 0)
	selector_escenario.add_item("Campo Pajoso", 1)
	selector_escenario.add_item("Interfase Urbana", 2)
	selector_escenario.select(0)
	fila.add_child(selector_escenario)
	lista.add_child(fila)
	lista.move_child(fila, 1)

func _on_btn_2_drones_pressed() -> void:
	if lbl_hartman_dialogue:
		lbl_hartman_dialogue.text = textos_hartman.obtener("menu_flota")

func _on_btn_3_ruleta_pressed() -> void:
	if lbl_hartman_dialogue:
		lbl_hartman_dialogue.text = textos_hartman.obtener("menu_ruleta")

func _on_btn_4_misiones_pressed() -> void:
	if lbl_hartman_dialogue:
		lbl_hartman_dialogue.text = textos_hartman.obtener("menu_misiones")

func _on_btn_5_config_pressed() -> void:
	if lbl_hartman_dialogue:
		lbl_hartman_dialogue.text = textos_hartman.obtener("menu_ajustes")
	panel_ajustes.visible = not panel_ajustes.visible

func _on_btn_6_salir_pressed() -> void:
	get_tree().quit()

func _crear_panel_ajustes() -> void:
	panel_ajustes = PanelContainer.new()
	panel_ajustes.name = "PanelConfiguracion"
	panel_ajustes.position = Vector2(420.0, 70.0)
	panel_ajustes.size = Vector2(480.0, 630.0)
	panel_ajustes.custom_minimum_size = Vector2(480.0, 630.0)
	panel_ajustes.visible = false
	capa_ui.add_child(panel_ajustes)

	var contenido := VBoxContainer.new()
	contenido.add_theme_constant_override("separation", 8)
	panel_ajustes.add_child(contenido)

	var titulo := Label.new()
	titulo.text = "CONFIGURACIÓN"
	titulo.add_theme_font_size_override("font_size", 18)
	contenido.add_child(titulo)

	var etiqueta_calidad := Label.new()
	etiqueta_calidad.text = "Calidad gráfica"
	contenido.add_child(etiqueta_calidad)

	selector_calidad = OptionButton.new()
	selector_calidad.add_item("BAJA", GraphicsSettings.Calidad.BAJO)
	selector_calidad.add_item("MEDIA", GraphicsSettings.Calidad.MEDIO)
	selector_calidad.add_item("ALTA", GraphicsSettings.Calidad.ALTO)
	selector_calidad.select(GraphicsSettings.calidad_actual)
	selector_calidad.item_selected.connect(_al_cambiar_calidad)
	contenido.add_child(selector_calidad)

	etiqueta_sensibilidad = Label.new()
	contenido.add_child(etiqueta_sensibilidad)
	slider_sensibilidad = HSlider.new()
	slider_sensibilidad.min_value = 0.0005
	slider_sensibilidad.max_value = 0.01
	slider_sensibilidad.step = 0.0001
	slider_sensibilidad.value = GraphicsSettings.sensibilidad_mouse
	slider_sensibilidad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider_sensibilidad.value_changed.connect(_al_cambiar_sensibilidad_mouse)
	contenido.add_child(slider_sensibilidad)
	_actualizar_etiqueta_sensibilidad(GraphicsSettings.sensibilidad_mouse)

	etiqueta_volumen = Label.new()
	contenido.add_child(etiqueta_volumen)
	slider_volumen = HSlider.new()
	slider_volumen.min_value = 0.0
	slider_volumen.max_value = 1.0
	slider_volumen.step = 0.01
	slider_volumen.value = AudioManager.obtener_volumen_bus("Maestro")
	slider_volumen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider_volumen.value_changed.connect(_al_cambiar_volumen_maestro)
	contenido.add_child(slider_volumen)
	_actualizar_etiqueta_volumen(AudioManager.obtener_volumen_bus("Maestro"))
	_crear_slider_audio(contenido, "Efectos", "Volumen de efectos")
	_crear_slider_audio(contenido, "Musica", "Volumen de música")
	_crear_slider_audio(contenido, "UI", "Volumen de interfaz")

	var etiqueta_ayuda := Label.new()
	etiqueta_ayuda.text = "Ayuda de puntería"
	contenido.add_child(etiqueta_ayuda)
	selector_ayuda = OptionButton.new()
	selector_ayuda.add_item("ALTA — voz, retícula y flecha", AjustesAyuda.AYUDA_ALTA)
	selector_ayuda.add_item("MEDIA — retícula y flecha", AjustesAyuda.AYUDA_MEDIA)
	selector_ayuda.add_item("BAJA — solo retícula", AjustesAyuda.AYUDA_BAJA)
	selector_ayuda.add_item("NINGUNA", AjustesAyuda.AYUDA_NINGUNA)
	selector_ayuda.item_selected.connect(_al_cambiar_nivel_ayuda)
	contenido.add_child(selector_ayuda)

	var boton_controles := Button.new()
	boton_controles.text = "REASIGNAR TECLAS Y GAMEPAD"
	boton_controles.pressed.connect(_alternar_panel_reasignacion)
	contenido.add_child(boton_controles)

	var volver := Button.new()
	volver.text = "VOLVER"
	volver.pressed.connect(_cerrar_panel_ajustes)
	contenido.add_child(volver)
	_seleccionar_nivel_ayuda_guardado()

func _crear_panel_reasignacion() -> void:
	panel_reasignacion = PanelContainer.new()
	panel_reasignacion.name = "PanelReasignacion"
	panel_reasignacion.position = Vector2(830.0, 70.0)
	panel_reasignacion.custom_minimum_size = Vector2(420.0, 580.0)
	panel_reasignacion.visible = false
	capa_ui.add_child(panel_reasignacion)
	var contenido := VBoxContainer.new()
	contenido.add_theme_constant_override("separation", 8)
	panel_reasignacion.add_child(contenido)
	var titulo := Label.new()
	titulo.text = "CONTROLES"
	titulo.add_theme_font_size_override("font_size", 18)
	contenido.add_child(titulo)
	var instruccion := Label.new()
	instruccion.text = (
		"Selecciona una asignación y pulsa una tecla, botón o dirección del mando. ESC cancela."
	)
	instruccion.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	contenido.add_child(instruccion)
	var lista := VBoxContainer.new()
	lista.add_theme_constant_override("separation", 4)
	contenido.add_child(lista)
	for accion in InputConfig.obtener_acciones():
		var fila := HBoxContainer.new()
		fila.add_theme_constant_override("separation", 6)
		lista.add_child(fila)
		var etiqueta := Label.new()
		etiqueta.text = InputConfig.obtener_etiqueta(accion)
		etiqueta.custom_minimum_size = Vector2(158.0, 34.0)
		etiqueta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fila.add_child(etiqueta)
		var boton := Button.new()
		boton.custom_minimum_size = Vector2(205.0, 34.0)
		boton.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		boton.pressed.connect(InputConfig.iniciar_reasignacion.bind(accion))
		fila.add_child(boton)
		botones_reasignacion[accion] = boton
	_actualizar_etiquetas_reasignacion()
	var cerrar := Button.new()
	cerrar.text = "CERRAR"
	cerrar.pressed.connect(func() -> void: panel_reasignacion.visible = false)
	contenido.add_child(cerrar)

func _alternar_panel_reasignacion() -> void:
	panel_reasignacion.visible = not panel_reasignacion.visible
	if panel_reasignacion.visible:
		_actualizar_etiquetas_reasignacion()

func _actualizar_etiquetas_reasignacion() -> void:
	for accion in botones_reasignacion:
		var boton := botones_reasignacion[accion] as Button
		if is_instance_valid(boton):
			boton.text = InputConfig.obtener_resumen(accion)

func _al_iniciar_reasignacion(accion: StringName) -> void:
	var boton := botones_reasignacion.get(accion) as Button
	if is_instance_valid(boton):
		boton.text = "Pulsa una entrada..."

func _al_finalizar_reasignacion(accion: StringName, cancelada: bool) -> void:
	if not cancelada:
		_actualizar_etiquetas_reasignacion()
	else:
		var boton := botones_reasignacion.get(accion) as Button
		if is_instance_valid(boton):
			boton.text = InputConfig.obtener_resumen(accion)

func _crear_panel_multijugador() -> void:
	var lista_botones := $FrontUILayer/LeftTacticalPanel/ButtonList as VBoxContainer
	var boton_multijugador := Button.new()
	boton_multijugador.name = "BtnMultijugador"
	boton_multijugador.text = "🌐  MULTIJUGADOR"
	boton_multijugador.custom_minimum_size = Vector2(0, 44)
	boton_multijugador.pressed.connect(_abrir_lobby_multijugador)
	lista_botones.add_child(boton_multijugador)

func _abrir_lobby_multijugador() -> void:
	var error_cambio := get_tree().change_scene_to_file("res://scenes/menus/lobby.tscn")
	if error_cambio != OK:
		push_error("No se pudo abrir el lobby multijugador (error %d)." % error_cambio)

func _al_cambiar_calidad(indice: int) -> void:
	GraphicsSettings.configurar_calidad(selector_calidad.get_item_id(indice))

func _al_cambiar_sensibilidad_mouse(valor: float) -> void:
	GraphicsSettings.configurar_sensibilidad_mouse(valor)
	_actualizar_etiqueta_sensibilidad(valor)

func _al_cambiar_volumen_maestro(valor: float) -> void:
	AudioManager.configurar_volumen_bus("Maestro", valor)
	_actualizar_etiqueta_volumen(valor)

func _crear_slider_audio(contenido: VBoxContainer, bus: String, titulo: String) -> void:
	var etiqueta := Label.new()
	etiqueta.text = titulo
	contenido.add_child(etiqueta)
	var slider := HSlider.new()
	slider.name = "Volumen%s" % bus
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = AudioManager.obtener_volumen_bus(bus)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(
		func(valor: float) -> void:
			AudioManager.configurar_volumen_bus(bus, valor)
	)
	contenido.add_child(slider)

func _actualizar_etiqueta_sensibilidad(valor: float) -> void:
	etiqueta_sensibilidad.text = "Sensibilidad del ratón: %.4f" % valor

func _actualizar_etiqueta_volumen(valor: float) -> void:
	etiqueta_volumen.text = "Volumen maestro: %d%%" % int(round(valor * 100.0))

func _seleccionar_nivel_ayuda_guardado() -> void:
	for indice in range(selector_ayuda.get_item_count()):
		if selector_ayuda.get_item_id(indice) == AjustesAyuda.nivel_ayuda:
			selector_ayuda.select(indice)
			return

func _al_cambiar_nivel_ayuda(indice: int) -> void:
	AjustesAyuda.configurar_nivel_ayuda(selector_ayuda.get_item_id(indice))

func _cerrar_panel_ajustes() -> void:
	panel_ajustes.visible = false
