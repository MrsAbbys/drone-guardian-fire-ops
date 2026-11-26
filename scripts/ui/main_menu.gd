extends Control

const MENU_THEME: Theme = preload("res://assets/ui/menu_theme.tres")
const SCRIPT_BENCHMARK_RUNNER: Script = preload("res://scripts/tools/fire_grid_benchmark_runner.gd")
const RUTA_MAIN_COLUMN := "FrontUILayer/MainPanel/ContentMargin/MainColumn"
const RUTA_WORKSPACE := RUTA_MAIN_COLUMN + "/MainArea/Workspace/WorkspaceContent"
const RUTA_SIDEBAR := RUTA_MAIN_COLUMN + "/MainArea/Sidebar/SidebarContent"
const RUTA_FOOTER := RUTA_MAIN_COLUMN + "/StatusFooter/StatusRow"
const ESCENARIOS := [
	{
		"key": "aguarague",
		"scene": "res://scenes/levels/escena_aguarague.tscn",
		"configuration": preload("res://resources/sim/configuracion_aguarague.tres"),
		"thumbnail": preload("res://assets/ui/scenarios/aguarague.png"),
		"name_key": "MENU_SCENARIO_AGUARAGUE",
		"description_key": "MENU_SCENARIO_AGUARAGUE_DESCRIPTION",
	},
	{
		"key": "campo",
		"scene": "res://scenes/levels/escena_campo_pajoso.tscn",
		"configuration": preload("res://resources/sim/configuracion_campo_pajoso.tres"),
		"thumbnail": preload("res://assets/ui/scenarios/campo_pajoso.png"),
		"name_key": "MENU_SCENARIO_CAMPO",
		"description_key": "MENU_SCENARIO_CAMPO_DESCRIPTION",
	},
	{
		"key": "urbano",
		"scene": "res://scenes/levels/escena_interfase_urbana.tscn",
		"configuration": preload("res://resources/sim/configuracion_interfase_urbana.tres"),
		"thumbnail": preload("res://assets/ui/scenarios/interfase_urbana.png"),
		"name_key": "MENU_SCENARIO_URBAN",
		"description_key": "MENU_SCENARIO_URBAN_DESCRIPTION",
	},
]
const ROLES := [
	{
		"path": "res://data/roles/cisterna.tres",
		"name_key": "HANGAR_ROLE_CISTERNA",
		"description_key": "HANGAR_ROLE_CISTERNA_DESCRIPTION",
	},
	{
		"path": "res://data/roles/explorador.tres",
		"name_key": "HANGAR_ROLE_EXPLORADOR",
		"description_key": "HANGAR_ROLE_EXPLORADOR_DESCRIPTION",
	},
	{
		"path": "res://data/roles/tactico.tres",
		"name_key": "HANGAR_ROLE_TACTICO",
		"description_key": "HANGAR_ROLE_TACTICO_DESCRIPTION",
	},
]
const GRAFICAS := [
	{
		"path": "res://drone-guardian-fire-ops-main/docs/graficas/speedup.png",
		"title_key": "LAB_GRAPH_SPEEDUP",
	},
	{
		"path": "res://drone-guardian-fire-ops-main/docs/graficas/eficiencia.png",
		"title_key": "LAB_GRAPH_EFFICIENCY",
	},
	{
		"path": "res://drone-guardian-fire-ops-main/docs/graficas/tiempo_vs_hilos.png",
		"title_key": "LAB_GRAPH_TIME_THREADS",
	},
	{
		"path": "res://drone-guardian-fire-ops-main/docs/graficas/fraccion_serial_amdahl.png",
		"title_key": "LAB_GRAPH_AMDAHL",
	},
]
const DIFICULTADES := ["easy", "normal", "hard"]
const MULTIPLICADORES_VIENTO := [0.6, 1.0, 1.4]

var panel_ajustes: PanelContainer
var selector_calidad: OptionButton
var selector_ayuda: OptionButton
var slider_sensibilidad: HSlider
var slider_volumen: HSlider
var etiqueta_sensibilidad: Label
var etiqueta_volumen: Label
var selector_escenario: OptionButton
var selector_dificultad: OptionButton
var selector_viento: OptionButton
var selector_idioma: OptionButton
var panel_reasignacion: PanelContainer
var panel_benchmark: PanelContainer
var boton_benchmark_ejecutar: Button
var etiqueta_resultados_benchmark: Label
var botones_reasignacion: Dictionary = {}
var _hover_tweens: Dictionary = {}
var _paginas: Dictionary = {}
var _botones_navegacion: Array[Button] = []
var _tiempo_actualizacion: float = 0.0
var _descripcion_escenario: Label
var _previsualizacion_escenario: TextureRect

@onready var bg_rect: TextureRect = $MenuArtBackground
@onready var capa_ui: CanvasLayer = $FrontUILayer
@onready var titulo_seccion: Label = get_node(RUTA_WORKSPACE + "/SectionTitle") as Label
@onready var contenido_seccion: VBoxContainer = get_node(
	RUTA_WORKSPACE + "/SectionBody"
) as VBoxContainer
@onready var dialogo_hartman: Label = get_node(
	RUTA_SIDEBAR
	+ "/HartmanCard/HartmanContent/HartmanText/"
	+ "HartmanAdvice"
) as Label
@onready var estado_zona: Label = get_node(RUTA_FOOTER + "/ZoneStatus/ZoneValue") as Label
@onready var estado_viento: Label = get_node(RUTA_FOOTER + "/WindStatus/WindValue") as Label
@onready var estado_amenaza: Label = get_node(RUTA_FOOTER + "/ThreatStatus/ThreatValue") as Label
@onready var estado_hora: Label = get_node(RUTA_FOOTER + "/TimeStatus/TimeValue") as Label


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if not is_instance_valid(bg_rect.texture):
		push_error("No se encontró la textura de fondo del menú.")
	_traducir_label(RUTA_MAIN_COLUMN + "/HeaderBox/BrandBlock/SystemLabel", "MENU_TITLE")
	_traducir_label(RUTA_MAIN_COLUMN + "/HeaderBox/BrandBlock/FireOpsLabel", "MENU_SUBTITLE")
	_traducir_label(RUTA_MAIN_COLUMN + "/HeaderBox/HeaderTag", "MENU_COMMAND_CENTER")
	_traducir_label(RUTA_SIDEBAR + "/HartmanCard/HartmanContent/HartmanText/HartmanName",
		"MENU_HARTMAN_NAME")
	_traducir_label(RUTA_FOOTER + "/ZoneStatus/ZoneTitle", "MENU_STATUS_ZONE")
	_traducir_label(RUTA_FOOTER + "/WindStatus/WindTitle", "MENU_STATUS_WIND")
	_traducir_label(RUTA_FOOTER + "/ThreatStatus/ThreatTitle", "MENU_STATUS_THREAT")
	_traducir_label(RUTA_FOOTER + "/TimeStatus/TimeTitle", "MENU_STATUS_TIME")
	_crear_pagina_desplegar()
	_crear_pagina_hangar()
	_crear_pagina_laboratorio()
	_crear_pagina_ajustes()
	_crear_panel_reasignacion()
	_configurar_filtros_mouse(self)
	_configurar_interaccion_menu()
	InputConfig.asignaciones_actualizadas.connect(_actualizar_etiquetas_reasignacion)
	InputConfig.reasignacion_iniciada.connect(_al_iniciar_reasignacion)
	InputConfig.reasignacion_finalizada.connect(_al_finalizar_reasignacion)
	_mostrar_seccion("deploy")
	_actualizar_estado_pie()


func _configurar_filtros_mouse(nodo: Node) -> void:
	if nodo is Control:
		var control := nodo as Control
		if (
			control is BaseButton
			or control is LineEdit
			or control is TextEdit
			or control is Slider
			or control is SpinBox
			or control is TabBar
			or control is TabContainer
		):
			control.mouse_filter = Control.MOUSE_FILTER_STOP
		elif control is ScrollContainer:
			control.mouse_filter = Control.MOUSE_FILTER_PASS
		else:
			control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not nodo.child_entered_tree.is_connected(_al_agregar_control_menu):
		nodo.child_entered_tree.connect(_al_agregar_control_menu)
	for hijo in nodo.get_children():
		_configurar_filtros_mouse(hijo)


func _al_agregar_control_menu(nodo: Node) -> void:
	_configurar_filtros_mouse(nodo)


func _process(delta: float) -> void:
	_tiempo_actualizacion += delta
	if _tiempo_actualizacion < 1.0:
		return
	_tiempo_actualizacion = 0.0
	_actualizar_estado_pie()


func _crear_pagina(clave: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "Page_%s" % clave
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.visible = false
	contenido_seccion.add_child(scroll)
	var cuerpo := VBoxContainer.new()
	cuerpo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cuerpo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cuerpo.add_theme_constant_override("separation", 14)
	scroll.add_child(cuerpo)
	_paginas[clave] = scroll
	return cuerpo


func _crear_pagina_desplegar() -> void:
	var pagina := _crear_pagina("deploy")
	var introduccion := _nueva_etiqueta("MENU_DEPLOY_DESCRIPTION")
	introduccion.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pagina.add_child(introduccion)
	var fila := HBoxContainer.new()
	fila.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila.add_theme_constant_override("separation", 18)
	pagina.add_child(fila)
	_previsualizacion_escenario = TextureRect.new()
	_previsualizacion_escenario.custom_minimum_size = Vector2(280, 190)
	_previsualizacion_escenario.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_previsualizacion_escenario.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_previsualizacion_escenario.texture = ESCENARIOS[0]["thumbnail"]
	_previsualizacion_escenario.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_previsualizacion_escenario.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_previsualizacion_escenario.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fila.add_child(_previsualizacion_escenario)
	var formulario := VBoxContainer.new()
	formulario.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	formulario.add_theme_constant_override("separation", 10)
	fila.add_child(formulario)
	selector_escenario = OptionButton.new()
	for indice in range(ESCENARIOS.size()):
		selector_escenario.add_item(tr(str(ESCENARIOS[indice]["name_key"])), indice)
	selector_escenario.select(0)
	selector_escenario.item_selected.connect(_actualizar_resumen_mision)
	_agregar_campo_formulario(formulario, "MENU_SCENARIO_LABEL", selector_escenario)
	selector_dificultad = OptionButton.new()
	selector_dificultad.add_item(tr("MENU_DIFFICULTY_EASY"), 0)
	selector_dificultad.add_item(tr("MENU_DIFFICULTY_NORMAL"), 1)
	selector_dificultad.add_item(tr("MENU_DIFFICULTY_HARD"), 2)
	selector_dificultad.select(1)
	selector_dificultad.item_selected.connect(_actualizar_estado_pie)
	_agregar_campo_formulario(formulario, "MENU_DIFFICULTY_LABEL", selector_dificultad)
	selector_viento = OptionButton.new()
	selector_viento.add_item(tr("MENU_WIND_CALM"), 0)
	selector_viento.add_item(tr("MENU_WIND_STANDARD"), 1)
	selector_viento.add_item(tr("MENU_WIND_STRONG"), 2)
	selector_viento.select(1)
	selector_viento.item_selected.connect(_actualizar_estado_pie)
	_agregar_campo_formulario(formulario, "MENU_WIND_LABEL", selector_viento)
	_descripcion_escenario = _nueva_etiqueta("MENU_SCENARIO_AGUARAGUE_DESCRIPTION")
	_descripcion_escenario.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pagina.add_child(_descripcion_escenario)
	var despegar := Button.new()
	despegar.name = "BtnTakeoff"
	despegar.custom_minimum_size = Vector2(0, 58)
	despegar.theme_type_variation = &"PrimaryButton"
	despegar.text = tr("MENU_TAKEOFF")
	despegar.pressed.connect(_iniciar_mision_seleccionada)
	pagina.add_child(despegar)
	_actualizar_resumen_mision(0)


func _crear_pagina_hangar() -> void:
	var pagina := _crear_pagina("hangar")
	var introduccion := _nueva_etiqueta("HANGAR_DESCRIPTION")
	introduccion.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pagina.add_child(introduccion)
	var tarjetas := HBoxContainer.new()
	tarjetas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tarjetas.add_theme_constant_override("separation", 12)
	pagina.add_child(tarjetas)
	for definicion in ROLES:
		var recurso := load(str(definicion["path"])) as Resource
		if not is_instance_valid(recurso):
			push_error("No se pudo cargar un rol del hangar: %s." % definicion["path"])
			continue
		var tarjeta := PanelContainer.new()
		tarjeta.custom_minimum_size = Vector2(210, 290)
		tarjeta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tarjeta.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tarjetas.add_child(tarjeta)
		var contenido := VBoxContainer.new()
		contenido.add_theme_constant_override("separation", 10)
		tarjeta.add_child(contenido)
		var nombre := _nueva_etiqueta(str(definicion["name_key"]))
		nombre.add_theme_font_size_override("font_size", 22)
		nombre.add_theme_color_override("font_color", Color(1.0, 0.48, 0.14, 1.0))
		contenido.add_child(nombre)
		var descripcion := _nueva_etiqueta(str(definicion["description_key"]))
		descripcion.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		descripcion.size_flags_vertical = Control.SIZE_EXPAND_FILL
		contenido.add_child(descripcion)
		_agregar_separador(contenido)
		contenido.add_child(_nueva_etiqueta(
			"MENU_ROLE_WATER", [int(round(float(recurso.get("agua_maxima"))))]
		))
		contenido.add_child(_nueva_etiqueta(
			"MENU_ROLE_SPEED", [float(recurso.get("velocidad_maxima"))]
		))
		contenido.add_child(_nueva_etiqueta(
			"MENU_ROLE_RANGE", [float(recurso.get("alcance_chorro"))]
		))


func _crear_pagina_laboratorio() -> void:
	var pagina := _crear_pagina("laboratory")
	var introduccion := _nueva_etiqueta("LAB_DESCRIPTION")
	introduccion.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pagina.add_child(introduccion)
	_crear_panel_benchmark(pagina)
	var graficas := GridContainer.new()
	graficas.columns = 2
	graficas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graficas.add_theme_constant_override("h_separation", 12)
	graficas.add_theme_constant_override("v_separation", 12)
	pagina.add_child(graficas)
	for grafica in GRAFICAS:
		_agregar_grafica(graficas, str(grafica["path"]), str(grafica["title_key"]))


func _crear_pagina_ajustes() -> void:
	var pagina := _crear_pagina("settings")
	var introduccion := _nueva_etiqueta("MENU_SETTINGS_DESCRIPTION")
	introduccion.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pagina.add_child(introduccion)
	_crear_panel_ajustes(pagina)


func _agregar_grafica(contenedor: GridContainer, ruta: String, titulo_clave: String) -> void:
	var textura := load(ruta) as Texture2D
	if not is_instance_valid(textura):
		push_error("No se pudo cargar una gráfica del laboratorio: %s." % ruta)
		return
	var tarjeta := PanelContainer.new()
	tarjeta.custom_minimum_size = Vector2(340, 250)
	tarjeta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contenedor.add_child(tarjeta)
	var contenido := VBoxContainer.new()
	contenido.add_theme_constant_override("separation", 8)
	tarjeta.add_child(contenido)
	contenido.add_child(_nueva_etiqueta(titulo_clave))
	var imagen := TextureRect.new()
	imagen.custom_minimum_size = Vector2(310, 205)
	imagen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	imagen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	imagen.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	imagen.texture = textura
	imagen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	contenido.add_child(imagen)


func _crear_panel_benchmark(contenedor: VBoxContainer) -> void:
	panel_benchmark = PanelContainer.new()
	panel_benchmark.name = "PanelBenchmarkFireGrid"
	panel_benchmark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contenedor.add_child(panel_benchmark)
	var contenido := VBoxContainer.new()
	contenido.add_theme_constant_override("separation", 8)
	panel_benchmark.add_child(contenido)
	var titulo := _nueva_etiqueta("BENCHMARK_TITLE")
	titulo.add_theme_font_size_override("font_size", 22)
	contenido.add_child(titulo)
	var descripcion := _nueva_etiqueta("BENCHMARK_DESCRIPTION")
	descripcion.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	contenido.add_child(descripcion)
	boton_benchmark_ejecutar = Button.new()
	boton_benchmark_ejecutar.text = tr("BENCHMARK_RUN")
	boton_benchmark_ejecutar.custom_minimum_size.y = 48
	boton_benchmark_ejecutar.pressed.connect(_ejecutar_benchmark)
	contenido.add_child(boton_benchmark_ejecutar)
	etiqueta_resultados_benchmark = Label.new()
	etiqueta_resultados_benchmark.custom_minimum_size.y = 48
	etiqueta_resultados_benchmark.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	etiqueta_resultados_benchmark.text = tr("BENCHMARK_NO_RESULTS")
	contenido.add_child(etiqueta_resultados_benchmark)


func _ejecutar_benchmark() -> void:
	if boton_benchmark_ejecutar.disabled:
		return
	boton_benchmark_ejecutar.disabled = true
	var runner: RefCounted = SCRIPT_BENCHMARK_RUNNER.new()
	var resultados := tr("BENCHMARK_RUNNING")
	etiqueta_resultados_benchmark.text = resultados
	for tamano in SCRIPT_BENCHMARK_RUNNER.TAMANOS:
		await get_tree().process_frame
		if (
			not is_instance_valid(self)
			or not is_inside_tree()
			or not is_instance_valid(boton_benchmark_ejecutar)
			or not is_instance_valid(etiqueta_resultados_benchmark)
		):
			return
		var medicion: Dictionary = runner.call(
			"medir_tamano",
			tamano,
			SCRIPT_BENCHMARK_RUNNER.PASOS,
			SCRIPT_BENCHMARK_RUNNER.SEMILLA,
			SCRIPT_BENCHMARK_RUNNER.VIENTO
		)
		if medicion.is_empty():
			etiqueta_resultados_benchmark.text = tr("BENCHMARK_FAILED")
			boton_benchmark_ejecutar.disabled = false
			return
		resultados += "\n" + (tr("BENCHMARK_RESULT") % [
			tamano,
			float(medicion["ms_tick"]),
			int(medicion["celdas_que_ardieron"]),
		])
		etiqueta_resultados_benchmark.text = resultados
		await get_tree().process_frame
		if (
			not is_instance_valid(self)
			or not is_inside_tree()
			or not is_instance_valid(boton_benchmark_ejecutar)
			or not is_instance_valid(etiqueta_resultados_benchmark)
		):
			return
	boton_benchmark_ejecutar.disabled = false


func _crear_panel_ajustes(contenedor: VBoxContainer) -> void:
	panel_ajustes = PanelContainer.new()
	panel_ajustes.name = "PanelConfiguracion"
	panel_ajustes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_ajustes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_ajustes.theme = MENU_THEME
	contenedor.add_child(panel_ajustes)
	var contenido := VBoxContainer.new()
	contenido.add_theme_constant_override("separation", 10)
	panel_ajustes.add_child(contenido)
	var pestanas := TabContainer.new()
	pestanas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pestanas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contenido.add_child(pestanas)

	var graficos := _crear_pestana_ajustes(pestanas, tr("MENU_TAB_GRAPHICS"))
	var etiqueta_calidad := _nueva_etiqueta("MENU_GRAPHICS_QUALITY")
	graficos.add_child(etiqueta_calidad)
	selector_calidad = OptionButton.new()
	selector_calidad.add_item(tr("BAJA"), GraphicsSettings.Calidad.BAJO)
	selector_calidad.add_item(tr("MEDIA"), GraphicsSettings.Calidad.MEDIO)
	selector_calidad.add_item(tr("ALTA"), GraphicsSettings.Calidad.ALTO)
	selector_calidad.select(GraphicsSettings.calidad_actual)
	selector_calidad.item_selected.connect(_al_cambiar_calidad)
	graficos.add_child(selector_calidad)

	var controles := _crear_pestana_ajustes(pestanas, tr("MENU_TAB_CONTROL"))
	etiqueta_sensibilidad = Label.new()
	controles.add_child(etiqueta_sensibilidad)
	slider_sensibilidad = HSlider.new()
	slider_sensibilidad.min_value = 0.0005
	slider_sensibilidad.max_value = 0.01
	slider_sensibilidad.step = 0.0001
	slider_sensibilidad.value = GraphicsSettings.sensibilidad_mouse
	slider_sensibilidad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider_sensibilidad.value_changed.connect(_al_cambiar_sensibilidad_mouse)
	controles.add_child(slider_sensibilidad)
	_actualizar_etiqueta_sensibilidad(GraphicsSettings.sensibilidad_mouse)
	var boton_controles := Button.new()
	boton_controles.text = tr("REASIGNAR TECLAS Y GAMEPAD")
	boton_controles.custom_minimum_size.y = 48
	boton_controles.pressed.connect(_alternar_panel_reasignacion)
	controles.add_child(boton_controles)

	var audio := _crear_pestana_ajustes(pestanas, tr("MENU_TAB_AUDIO"))
	etiqueta_volumen = Label.new()
	audio.add_child(etiqueta_volumen)
	slider_volumen = HSlider.new()
	slider_volumen.min_value = 0.0
	slider_volumen.max_value = 1.0
	slider_volumen.step = 0.01
	slider_volumen.value = AudioManager.obtener_volumen_bus("Maestro")
	slider_volumen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider_volumen.value_changed.connect(_al_cambiar_volumen_maestro)
	audio.add_child(slider_volumen)
	_actualizar_etiqueta_volumen(AudioManager.obtener_volumen_bus("Maestro"))
	_crear_slider_audio(audio, "Efectos", "Volumen de efectos")
	_crear_slider_audio(audio, "Musica", "Volumen de música")
	_crear_slider_audio(audio, "UI", "Volumen de interfaz")

	var idioma := _crear_pestana_ajustes(pestanas, tr("MENU_TAB_LANGUAGE"))
	idioma.add_child(_nueva_etiqueta("Idioma"))
	selector_idioma = OptionButton.new()
	selector_idioma.add_item(tr("Español"), 0)
	selector_idioma.add_item(tr("English"), 1)
	selector_idioma.select(0 if LocalizationManager.idioma_actual() == "es" else 1)
	selector_idioma.item_selected.connect(_al_cambiar_idioma)
	idioma.add_child(selector_idioma)

	var ayuda := _crear_pestana_ajustes(pestanas, tr("MENU_TAB_HELP"))
	ayuda.add_child(_nueva_etiqueta("Ayuda de puntería"))
	selector_ayuda = OptionButton.new()
	selector_ayuda.add_item(tr("ALTA — voz, retícula y flecha"), AjustesAyuda.AYUDA_ALTA)
	selector_ayuda.add_item(tr("MEDIA — retícula y flecha"), AjustesAyuda.AYUDA_MEDIA)
	selector_ayuda.add_item(tr("BAJA — solo retícula"), AjustesAyuda.AYUDA_BAJA)
	selector_ayuda.add_item(tr("NINGUNA"), AjustesAyuda.AYUDA_NINGUNA)
	selector_ayuda.item_selected.connect(_al_cambiar_nivel_ayuda)
	ayuda.add_child(selector_ayuda)
	_seleccionar_nivel_ayuda_guardado()


func _crear_pestana_ajustes(pestanas: TabContainer, nombre: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = nombre
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pestanas.add_child(scroll)
	var contenido := VBoxContainer.new()
	contenido.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contenido.add_theme_constant_override("separation", 12)
	scroll.add_child(contenido)
	return contenido


func _crear_panel_reasignacion() -> void:
	panel_reasignacion = PanelContainer.new()
	panel_reasignacion.name = "PanelReasignacion"
	panel_reasignacion.anchor_left = 0.20
	panel_reasignacion.anchor_top = 0.08
	panel_reasignacion.anchor_right = 0.80
	panel_reasignacion.anchor_bottom = 0.92
	panel_reasignacion.visible = false
	panel_reasignacion.theme = MENU_THEME
	capa_ui.add_child(panel_reasignacion)
	var contenido := VBoxContainer.new()
	contenido.add_theme_constant_override("separation", 8)
	panel_reasignacion.add_child(contenido)
	var titulo := _nueva_etiqueta("CONTROLES")
	titulo.add_theme_font_size_override("font_size", 24)
	contenido.add_child(titulo)
	var instruccion := _nueva_etiqueta(
		"Selecciona una asignación y pulsa una tecla, botón o dirección del mando. ESC cancela."
	)
	instruccion.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	contenido.add_child(instruccion)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contenido.add_child(scroll)
	var lista := VBoxContainer.new()
	lista.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lista.add_theme_constant_override("separation", 4)
	scroll.add_child(lista)
	for accion in InputConfig.obtener_acciones():
		var fila := HBoxContainer.new()
		fila.add_theme_constant_override("separation", 6)
		lista.add_child(fila)
		var etiqueta := _nueva_etiqueta(InputConfig.obtener_etiqueta(accion))
		etiqueta.custom_minimum_size = Vector2(158, 48)
		etiqueta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		etiqueta.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fila.add_child(etiqueta)
		var boton := Button.new()
		boton.custom_minimum_size = Vector2(205, 48)
		boton.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		boton.pressed.connect(InputConfig.iniciar_reasignacion.bind(accion))
		fila.add_child(boton)
		botones_reasignacion[accion] = boton
	_actualizar_etiquetas_reasignacion()
	var cerrar := Button.new()
	cerrar.text = tr("CERRAR")
	cerrar.custom_minimum_size.y = 48
	cerrar.pressed.connect(func() -> void: panel_reasignacion.visible = false)
	contenido.add_child(cerrar)


func _configurar_interaccion_menu() -> void:
	var orden := [
		"BtnDeploy",
		"BtnMultiplayer",
		"BtnHangar",
		"BtnTraining",
		"BtnLaboratory",
		"BtnSettings",
		"BtnExit",
	]
	var acciones := {
		"BtnDeploy": Callable(self, "_mostrar_desplegar"),
		"BtnMultiplayer": Callable(self, "_abrir_lobby_multijugador"),
		"BtnHangar": Callable(self, "_mostrar_hangar"),
		"BtnTraining": Callable(self, "_iniciar_tutorial"),
		"BtnLaboratory": Callable(self, "_mostrar_laboratorio"),
		"BtnSettings": Callable(self, "_mostrar_ajustes"),
		"BtnExit": Callable(self, "_salir"),
	}
	var tips := {
		"BtnDeploy": "MENU_TIP_DEPLOY",
		"BtnMultiplayer": "MENU_TIP_MULTIPLAYER",
		"BtnHangar": "MENU_TIP_HANGAR",
		"BtnTraining": "MENU_TIP_TRAINING",
		"BtnLaboratory": "MENU_TIP_LABORATORY",
		"BtnSettings": "MENU_TIP_SETTINGS",
		"BtnExit": "MENU_TIP_EXIT",
	}
	for nombre in orden:
		var boton := get_node(
			RUTA_SIDEBAR + "/" + nombre
		) as Button
		boton.text = tr("MENU_NAV_%s" % nombre.replace("Btn", "").to_upper())
		boton.focus_mode = Control.FOCUS_ALL
		boton.pivot_offset = boton.custom_minimum_size * 0.5
		boton.pressed.connect(acciones[nombre])
		boton.mouse_entered.connect(_al_resaltar_boton.bind(boton, str(tips[nombre])))
		boton.focus_entered.connect(_al_resaltar_boton.bind(boton, str(tips[nombre])))
		boton.mouse_exited.connect(_al_desresaltar_boton.bind(boton))
		boton.focus_exited.connect(_al_desresaltar_boton.bind(boton))
		_botones_navegacion.append(boton)
		if nombre == "BtnMultiplayer" and not ResourceLoader.exists(
			"res://scenes/menus/lobby.tscn"
		):
			boton.disabled = true
	for indice in range(_botones_navegacion.size()):
		var boton := _botones_navegacion[indice]
		boton.focus_neighbor_top = boton.get_path_to(
			_botones_navegacion[posmod(indice - 1, _botones_navegacion.size())]
		)
		boton.focus_neighbor_bottom = boton.get_path_to(
			_botones_navegacion[(indice + 1) % _botones_navegacion.size()]
		)
	var primer_boton := _botones_navegacion[0] as Button
	primer_boton.grab_focus()
	_asignar_foco_lateral("deploy", "BtnDeploy")
	_asignar_foco_lateral("hangar", "BtnHangar")
	_asignar_foco_lateral("laboratory", "BtnLaboratory")
	_asignar_foco_lateral("settings", "BtnSettings")


func _mostrar_desplegar() -> void:
	_mostrar_seccion("deploy")


func _mostrar_hangar() -> void:
	_mostrar_seccion("hangar")


func _mostrar_laboratorio() -> void:
	_mostrar_seccion("laboratory")


func _mostrar_ajustes() -> void:
	_mostrar_seccion("settings")


func _mostrar_seccion(clave: String) -> void:
	if not _paginas.has(clave):
		push_error("No existe la sección del menú: %s." % clave)
		return
	for clave_pagina in _paginas:
		var pagina := _paginas[clave_pagina] as Control
		pagina.visible = str(clave_pagina) == clave
	var titulos := {
		"deploy": "MENU_SECTION_DEPLOY",
		"hangar": "MENU_SECTION_HANGAR",
		"laboratory": "MENU_SECTION_LABORATORY",
		"settings": "MENU_SECTION_SETTINGS",
	}
	var consejos := {
		"deploy": "MENU_TIP_DEPLOY",
		"hangar": "MENU_TIP_HANGAR",
		"laboratory": "MENU_TIP_LABORATORY",
		"settings": "MENU_TIP_SETTINGS",
	}
	titulo_seccion.text = tr(str(titulos[clave]))
	dialogo_hartman.text = tr(str(consejos[clave]))
	if selector_escenario:
		_actualizar_estado_pie()
	var botones_pagina := {
		"deploy": "BtnDeploy",
		"hangar": "BtnHangar",
		"laboratory": "BtnLaboratory",
		"settings": "BtnSettings",
	}
	var boton := get_node(RUTA_SIDEBAR + "/" + str(botones_pagina[clave])) as Button
	var primer_control := _primer_control_interactivo(_paginas[clave])
	if is_instance_valid(primer_control):
		primer_control.grab_focus()
		boton.focus_neighbor_right = boton.get_path_to(primer_control)
		primer_control.focus_neighbor_left = primer_control.get_path_to(boton)


func _asignar_foco_lateral(clave_pagina: String, nombre_boton: String) -> void:
	var boton := get_node(RUTA_SIDEBAR + "/" + nombre_boton) as Button
	var primer_control := _primer_control_interactivo(_paginas[clave_pagina])
	if is_instance_valid(primer_control):
		boton.focus_neighbor_right = boton.get_path_to(primer_control)
		primer_control.focus_neighbor_left = primer_control.get_path_to(boton)


func _primer_control_interactivo(nodo: Node) -> Control:
	for hijo in nodo.get_children():
		var control := hijo as Control
		if is_instance_valid(control) and control.focus_mode != Control.FOCUS_NONE:
			if not control is BaseButton or not (control as BaseButton).disabled:
				return control
		var descendiente := _primer_control_interactivo(hijo)
		if is_instance_valid(descendiente):
			return descendiente
	return null


func _iniciar_mision_seleccionada() -> void:
	var escenario := _obtener_escenario_seleccionado()
	var opciones_lanzamiento := _obtener_opciones_lanzamiento()
	if not is_instance_valid(opciones_lanzamiento):
		return
	opciones_lanzamiento.call(
		"prepare_launch",
		_dificultad_seleccionada(),
		_viento_seleccionado()
	)
	var error_cambio := get_tree().change_scene_to_file(str(escenario["scene"]))
	if error_cambio != OK:
		opciones_lanzamiento.call("cancel")
		push_error("No se pudo iniciar el escenario (error %d)." % error_cambio)


func _iniciar_tutorial() -> void:
	var escenario := _obtener_escenario_seleccionado()
	var opciones_lanzamiento := _obtener_opciones_lanzamiento()
	if not is_instance_valid(opciones_lanzamiento):
		return
	opciones_lanzamiento.call(
		"prepare_launch",
		_dificultad_seleccionada(),
		_viento_seleccionado()
	)
	if not TutorialManager.iniciar_tutorial(str(escenario["scene"])):
		opciones_lanzamiento.call("cancel")


func _obtener_opciones_lanzamiento() -> Node:
	var opciones := get_node_or_null("/root/MissionLaunchOptions")
	if not is_instance_valid(opciones):
		push_error("No está disponible el autoload MissionLaunchOptions.")
	return opciones


func _abrir_lobby_multijugador() -> void:
	var error_cambio := get_tree().change_scene_to_file("res://scenes/menus/lobby.tscn")
	if error_cambio != OK:
		push_error("No se pudo abrir el lobby multijugador (error %d)." % error_cambio)


func _salir() -> void:
	get_tree().quit()


func _actualizar_resumen_mision(_indice: int) -> void:
	var escenario := _obtener_escenario_seleccionado()
	_previsualizacion_escenario.texture = escenario["thumbnail"]
	_descripcion_escenario.text = tr(str(escenario["description_key"]))
	_actualizar_estado_pie()


func _actualizar_estado_pie(_indice: int = -1) -> void:
	if not is_instance_valid(estado_hora):
		return
	if selector_escenario:
		var escenario := _obtener_escenario_seleccionado()
		estado_zona.text = tr(str(escenario["name_key"]))
		var viento_actual := FireGridServer.activa
		var velocidad := (
			FireGridServer.obtener_velocidad_viento()
			if viento_actual
			else _velocidad_viento_prevision()
		)
		var clave_viento := "MENU_WIND_CURRENT" if viento_actual else "MENU_WIND_VALUE"
		estado_viento.text = tr(clave_viento) % velocidad
	if FireGridServer.activa:
		var objetivos := FireGridServer.obtener_resumen_objetivos_criticos()
		var perdidos := 0
		for objetivo in objetivos:
			if str(objetivo.get("estado", "")) == "PERDIDO":
				perdidos += 1
		estado_amenaza.text = tr("MENU_THREAT_ACTIVE") % [perdidos, objetivos.size()]
	else:
		estado_amenaza.text = tr("MENU_THREAT_READY")
	estado_hora.text = Time.get_time_string_from_system()


func _velocidad_viento_prevision() -> float:
	var escenario := _obtener_escenario_seleccionado()
	var configuracion: Resource = escenario["configuration"]
	var viento: Resource = configuracion.get("configuracion_viento")
	if not is_instance_valid(viento):
		push_error("El escenario seleccionado no tiene configuración de viento.")
		return 0.0
	var indice := selector_viento.get_selected_id() if selector_viento else 1
	var factor: float = float(
		MULTIPLICADORES_VIENTO[clampi(indice, 0, MULTIPLICADORES_VIENTO.size() - 1)]
	)
	return float(viento.get("velocidad_base")) * factor


func _obtener_escenario_seleccionado() -> Dictionary:
	var indice := selector_escenario.get_selected_id() if selector_escenario else 0
	return ESCENARIOS[clampi(indice, 0, ESCENARIOS.size() - 1)]


func _dificultad_seleccionada() -> String:
	var indice := selector_dificultad.get_selected_id() if selector_dificultad else 1
	return DIFICULTADES[clampi(indice, 0, DIFICULTADES.size() - 1)]


func _viento_seleccionado() -> String:
	var indice := selector_viento.get_selected_id() if selector_viento else 1
	match indice:
		0:
			return "calm"
		2:
			return "strong"
	return "standard"


func _agregar_campo_formulario(
	contenedor: VBoxContainer,
	clave_etiqueta: String,
	campo: Control
) -> void:
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 8)
	contenedor.add_child(fila)
	var etiqueta := _nueva_etiqueta(clave_etiqueta)
	etiqueta.custom_minimum_size.x = 130
	etiqueta.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fila.add_child(etiqueta)
	campo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	campo.custom_minimum_size.y = maxf(campo.custom_minimum_size.y, 44)
	fila.add_child(campo)


func _nueva_etiqueta(clave: String, valores: Array = []) -> Label:
	var etiqueta := Label.new()
	etiqueta.text = tr(clave)
	if not valores.is_empty():
		etiqueta.text = etiqueta.text % valores
	return etiqueta


func _traducir_label(ruta: String, clave: String) -> void:
	var etiqueta := get_node_or_null(ruta) as Label
	if not is_instance_valid(etiqueta):
		push_error("No se encontró el texto del menú en la ruta %s." % ruta)
		return
	etiqueta.text = tr(clave)


func _agregar_separador(contenedor: Control) -> void:
	var separador := ColorRect.new()
	separador.custom_minimum_size = Vector2(0, 2)
	separador.color = Color(1.0, 0.36, 0.08, 0.75)
	separador.mouse_filter = Control.MOUSE_FILTER_IGNORE
	contenedor.add_child(separador)


func _al_resaltar_boton(boton: Button, consejo: String) -> void:
	dialogo_hartman.text = tr(consejo)
	_animar_boton(boton, true)


func _al_desresaltar_boton(boton: Button) -> void:
	if boton.is_hovered() or boton.has_focus():
		return
	_animar_boton(boton, false)


func _animar_boton(boton: Button, resaltado: bool) -> void:
	var anterior := _hover_tweens.get(boton) as Tween
	if is_instance_valid(anterior):
		anterior.kill()
	var escala := Vector2(1.015, 1.015) if resaltado else Vector2.ONE
	var tinte := Color(1.08, 1.04, 0.98, 1.0) if resaltado else Color.WHITE
	var animacion := create_tween().set_parallel(true)
	animacion.tween_property(boton, "scale", escala, 0.12)
	animacion.tween_property(boton, "modulate", tinte, 0.12)
	_hover_tweens[boton] = animacion


func _crear_slider_audio(contenido: VBoxContainer, bus: String, titulo: String) -> void:
	var etiqueta := _nueva_etiqueta(titulo)
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


func _al_cambiar_calidad(indice: int) -> void:
	GraphicsSettings.configurar_calidad(selector_calidad.get_item_id(indice))


func _al_cambiar_idioma(indice: int) -> void:
	LocalizationManager.configurar_idioma("es" if indice == 0 else "en")
	var error_recarga := get_tree().reload_current_scene()
	if error_recarga != OK:
		push_error("No se pudo actualizar el idioma del menú (error %d)." % error_recarga)


func _al_cambiar_sensibilidad_mouse(valor: float) -> void:
	GraphicsSettings.configurar_sensibilidad_mouse(valor)
	_actualizar_etiqueta_sensibilidad(valor)


func _al_cambiar_volumen_maestro(valor: float) -> void:
	AudioManager.configurar_volumen_bus("Maestro", valor)
	_actualizar_etiqueta_volumen(valor)


func _actualizar_etiqueta_sensibilidad(valor: float) -> void:
	etiqueta_sensibilidad.text = tr("Sensibilidad del ratón: %.4f") % valor


func _actualizar_etiqueta_volumen(valor: float) -> void:
	etiqueta_volumen.text = tr("Volumen maestro: %d%%") % int(round(valor * 100.0))


func _seleccionar_nivel_ayuda_guardado() -> void:
	for indice in range(selector_ayuda.get_item_count()):
		if selector_ayuda.get_item_id(indice) == AjustesAyuda.nivel_ayuda:
			selector_ayuda.select(indice)
			return


func _al_cambiar_nivel_ayuda(indice: int) -> void:
	AjustesAyuda.configurar_nivel_ayuda(selector_ayuda.get_item_id(indice))


func _alternar_panel_reasignacion() -> void:
	panel_reasignacion.visible = not panel_reasignacion.visible
	if panel_reasignacion.visible:
		_actualizar_etiquetas_reasignacion()
		if not InputConfig.obtener_acciones().is_empty():
			var primera_accion: StringName = InputConfig.obtener_acciones()[0]
			var primer_boton := botones_reasignacion.get(primera_accion) as Button
			if is_instance_valid(primer_boton):
				primer_boton.grab_focus()


func _actualizar_etiquetas_reasignacion() -> void:
	for accion in botones_reasignacion:
		var boton := botones_reasignacion[accion] as Button
		if is_instance_valid(boton):
			boton.text = InputConfig.obtener_resumen(accion)


func _al_iniciar_reasignacion(accion: StringName) -> void:
	var boton := botones_reasignacion.get(accion) as Button
	if is_instance_valid(boton):
		boton.text = tr("Pulsa una entrada...")


func _al_finalizar_reasignacion(accion: StringName, cancelada: bool) -> void:
	if not cancelada:
		_actualizar_etiquetas_reasignacion()
	else:
		var boton := botones_reasignacion.get(accion) as Button
		if is_instance_valid(boton):
			boton.text = InputConfig.obtener_resumen(accion)
