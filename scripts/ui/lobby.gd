extends Control

const CLIENTE_DIRECTORIO: Script = preload("res://scripts/network/directorio_client.gd")
const ESCENA_MENU_PRINCIPAL: String = "res://scenes/menus/main_menu.tscn"
const ARCHIVO_CONFIGURACION: String = "user://lobby.cfg"
const URL_DIRECTORIO_PREDETERMINADA: String = "http://127.0.0.1:8080"
const MAX_JUGADORES_SALA: int = 4
const COLOR_VERDE := Color("#73d99a")
const COLOR_AMARILLO := Color("#f0c45a")
const COLOR_ROJO := Color("#ff7168")
const COLOR_TEXTO := Color("#e8edf2")
const RECURSOS_ROL: Dictionary = {
	"cisterna": preload("res://data/roles/cisterna.tres"),
	"explorador": preload("res://data/roles/explorador.tres"),
	"tactico": preload("res://data/roles/tactico.tres"),
}
const ORDEN_ROLES: Array[String] = ["cisterna", "explorador", "tactico"]

var _cliente_directorio: Node
var _temporizador_lista: Timer
var _url_directorio_actual: String = URL_DIRECTORIO_PREDETERMINADA
var _pantalla_actual: String = "inicio"
var _pantallas: Dictionary = {}
var _nombre: LineEdit
var _nombre_sala: LineEdit
var _nombre_sala_directa: LineEdit
var _url_directorio: LineEdit
var _escenario: OptionButton
var _dificultad: OptionButton
var _escenario_directo: OptionButton
var _dificultad_directa: OptionButton
var _direccion_directa: LineEdit
var _puerto_directo: SpinBox
var _codigo_directo: LineEdit
var _transporte_directo: OptionButton
var _codigo_directorio: LineEdit
var _lista_salas: ItemList
var _estado: Label
var _codigo_actual: Label
var _lista_pilotos: VBoxContainer
var _botones_rol: Dictionary = {}
var _grupo_roles: ButtonGroup
var _boton_listo: Button
var _boton_iniciar: Button
var _chat_historial: RichTextLabel
var _chat_entrada: LineEdit
var _boton_ajustes: Button
var _salas_recibidas: Array[Dictionary] = []
var _mensajes_chat: PackedStringArray = PackedStringArray()
var _configuracion_sala_pendiente: Dictionary = {}
var _creacion_directorio_pendiente: bool = false

func _ready() -> void:
	_cargar_url_directorio()
	_crear_interfaz()
	_cliente_directorio = CLIENTE_DIRECTORIO.new() as Node
	if _cliente_directorio == null:
		push_error("No se pudo crear el cliente HTTP del directorio.")
		_mostrar_estado(tr("LOBBY_ERROR_DIRECTORY_CLIENT"), COLOR_ROJO)
		return
	add_child(_cliente_directorio)
	_cliente_directorio.sala_creada.connect(_al_crear_sala_directorio)
	_cliente_directorio.salas_recibidas.connect(_al_recibir_lista_salas)
	_cliente_directorio.sala_encontrada.connect(_al_encontrar_sala)
	_cliente_directorio.error_directorio.connect(_al_error_directorio)
	_cliente_directorio.error_creacion_sala.connect(_al_fallar_creacion_directorio)
	NetworkManager.sala_actualizada.connect(_al_actualizar_sala)
	NetworkManager.jugador_conectado.connect(_al_actualizar_jugador)
	NetworkManager.jugador_desconectado.connect(_al_desconectar_jugador)
	NetworkManager.conexion_fallida.connect(_al_error_conexion)
	NetworkManager.rol_rechazado.connect(_al_rol_rechazado)
	NetworkManager.chat_recibido.connect(_al_recibir_chat)

	_temporizador_lista = Timer.new()
	_temporizador_lista.wait_time = 5.0
	_temporizador_lista.timeout.connect(_solicitar_lista_salas)
	add_child(_temporizador_lista)
	_temporizador_lista.start()
	_mostrar_pantalla("inicio")
	_actualizar_sala(NetworkManager.codigo_sala, NetworkManager.jugadores)
	_solicitar_lista_salas()

func _crear_interfaz() -> void:
	var fondo := ColorRect.new()
	fondo.color = Color("#07111b")
	fondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fondo)

	var margen := MarginContainer.new()
	margen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margen.add_theme_constant_override("margin_left", 32)
	margen.add_theme_constant_override("margin_top", 22)
	margen.add_theme_constant_override("margin_right", 32)
	margen.add_theme_constant_override("margin_bottom", 22)
	add_child(margen)

	var columna := VBoxContainer.new()
	columna.add_theme_constant_override("separation", 12)
	margen.add_child(columna)

	var encabezado := HBoxContainer.new()
	encabezado.add_theme_constant_override("separation", 14)
	columna.add_child(encabezado)
	var titulo := Label.new()
	titulo.text = tr("LOBBY_TITLE")
	titulo.add_theme_font_size_override("font_size", 30)
	titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	encabezado.add_child(titulo)
	encabezado.add_child(_nueva_etiqueta("LOBBY_PILOT_NAME"))
	_nombre = _nuevo_campo(tr("LOBBY_PILOT_DEFAULT"))
	_nombre.placeholder_text = tr("LOBBY_PILOT_NAME")
	_nombre.custom_minimum_size.x = 230.0
	encabezado.add_child(_nombre)
	_boton_ajustes = _nuevo_boton("LOBBY_SETTINGS", _abrir_ajustes)
	encabezado.add_child(_boton_ajustes)

	_estado = Label.new()
	_estado.text = tr("LOBBY_STATUS_READY")
	_estado.add_theme_font_size_override("font_size", 18)
	_estado.modulate = COLOR_TEXTO
	columna.add_child(_estado)

	var area_pantallas := Control.new()
	area_pantallas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area_pantallas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columna.add_child(area_pantallas)
	set_meta("area_pantallas", area_pantallas)

	var inicio := _crear_pantalla("inicio", false)
	_crear_pantalla_inicio(inicio)
	var unirse := _crear_pantalla("unirse")
	_crear_pantalla_unirse(unirse)
	var crear := _crear_pantalla("crear")
	_crear_pantalla_crear(crear)
	var directa := _crear_pantalla("directa")
	_crear_pantalla_directa(directa)
	var ajustes := _crear_pantalla("ajustes")
	_crear_pantalla_ajustes(ajustes)
	var sala := _crear_pantalla("sala")
	_crear_pantalla_sala(sala)

func _crear_pantalla(nombre: String, desplazable: bool = true) -> VBoxContainer:
	var area := get_meta("area_pantallas") as Control
	var raiz: Control
	var contenido := VBoxContainer.new()
	contenido.add_theme_constant_override("separation", 14)
	contenido.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contenido.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if desplazable:
		var scroll := ScrollContainer.new()
		scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.add_child(contenido)
		raiz = scroll
	else:
		contenido.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		raiz = contenido
	area.add_child(raiz)
	_pantallas[nombre] = raiz
	return contenido

func _crear_pantalla_inicio(contenido: VBoxContainer) -> void:
	_agregar_titulo_pantalla(contenido, "LOBBY_HOME_TITLE", "LOBBY_HOME_SUBTITLE")
	var tarjetas := GridContainer.new()
	tarjetas.columns = 3
	tarjetas.add_theme_constant_override("h_separation", 16)
	tarjetas.add_theme_constant_override("v_separation", 16)
	tarjetas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contenido.add_child(tarjetas)
	tarjetas.add_child(
		_nueva_tarjeta(
			"LOBBY_CREATE_CARD",
			"LOBBY_CREATE_CARD_DESCRIPTION",
			Callable(self, "_mostrar_pantalla").bind("crear")
		)
	)
	tarjetas.add_child(
		_nueva_tarjeta(
			"LOBBY_JOIN_CARD",
			"LOBBY_JOIN_CARD_DESCRIPTION",
			Callable(self, "_abrir_busqueda_salas")
		)
	)
	tarjetas.add_child(
		_nueva_tarjeta(
			"LOBBY_DIRECT_CARD",
			"LOBBY_DIRECT_CARD_DESCRIPTION",
			Callable(self, "_mostrar_pantalla").bind("directa")
		)
	)
	var pie := HBoxContainer.new()
	pie.alignment = BoxContainer.ALIGNMENT_END
	contenido.add_child(pie)
	pie.add_child(_nuevo_boton("LOBBY_BACK_TO_MENU", _volver_al_menu))

func _crear_pantalla_unirse(contenido: VBoxContainer) -> void:
	_agregar_titulo_pantalla(contenido, "LOBBY_JOIN_TITLE", "LOBBY_JOIN_SUBTITLE")
	var acciones_lista := HBoxContainer.new()
	contenido.add_child(acciones_lista)
	acciones_lista.add_child(_nueva_etiqueta("LOBBY_ROOM_LIST_TITLE"))
	var boton_actualizar := _nuevo_boton("LOBBY_REFRESH", _actualizar_lista_manual)
	acciones_lista.add_child(boton_actualizar)
	_lista_salas = ItemList.new()
	_lista_salas.custom_minimum_size = Vector2(0.0, 250.0)
	_lista_salas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lista_salas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lista_salas.select_mode = ItemList.SELECT_SINGLE
	_lista_salas.item_activated.connect(_conectar_item_sala)
	contenido.add_child(_lista_salas)
	contenido.add_child(_nuevo_boton("LOBBY_JOIN_SELECTED", _unirse_a_sala_seleccionada))

	var fila_codigo := HBoxContainer.new()
	fila_codigo.add_child(_nueva_etiqueta("LOBBY_CODE_ALTERNATIVE"))
	_codigo_directorio = _nuevo_campo("")
	_codigo_directorio.placeholder_text = tr("LOBBY_CODE_PLACEHOLDER")
	_codigo_directorio.max_length = 4
	_codigo_directorio.text_changed.connect(_filtrar_codigo_directorio)
	fila_codigo.add_child(_codigo_directorio)
	fila_codigo.add_child(_nuevo_boton("LOBBY_JOIN_WITH_CODE", _unirse_con_codigo))
	contenido.add_child(fila_codigo)
	contenido.add_child(_nuevo_boton("LOBBY_BACK", _volver_a_inicio))

func _crear_pantalla_crear(contenido: VBoxContainer) -> void:
	_agregar_titulo_pantalla(contenido, "LOBBY_CREATE_TITLE", "LOBBY_CREATE_SUBTITLE")
	_nombre_sala = _nuevo_campo(tr("LOBBY_ROOM_DEFAULT"))
	_nombre_sala.max_length = 40
	_agregar_campo_formulario(contenido, "LOBBY_ROOM_NAME", _nombre_sala)
	_escenario = _nuevo_selector_escenario()
	_agregar_campo_formulario(contenido, "LOBBY_SCENARIO", _escenario)
	_dificultad = _nuevo_selector_dificultad()
	_agregar_campo_formulario(contenido, "LOBBY_DIFFICULTY", _dificultad)
	contenido.add_child(_nueva_etiqueta("LOBBY_CAPACITY_NOTE"))
	var acciones := HBoxContainer.new()
	contenido.add_child(acciones)
	acciones.add_child(_nuevo_boton("LOBBY_CREATE_BUTTON", _crear_sala_directorio))
	acciones.add_child(_nuevo_boton("LOBBY_BACK", _volver_a_inicio))
	acciones.add_child(_nuevo_boton("LOBBY_BACK_TO_MENU", _volver_al_menu))

func _crear_pantalla_directa(contenido: VBoxContainer) -> void:
	_agregar_titulo_pantalla(contenido, "LOBBY_DIRECT_TITLE", "LOBBY_DIRECT_SUBTITLE")
	_nombre_sala_directa = _nuevo_campo(tr("LOBBY_ROOM_DEFAULT"))
	_nombre_sala_directa.max_length = 40
	_agregar_campo_formulario(contenido, "LOBBY_ROOM_NAME", _nombre_sala_directa)
	_direccion_directa = _nuevo_campo("127.0.0.1")
	_direccion_directa.placeholder_text = tr("LOBBY_HOST_PLACEHOLDER")
	_agregar_campo_formulario(contenido, "LOBBY_HOST", _direccion_directa)
	_puerto_directo = SpinBox.new()
	_puerto_directo.min_value = 1
	_puerto_directo.max_value = 65535
	_puerto_directo.value = NetworkManager.PUERTO_PREDETERMINADO
	_puerto_directo.step = 1
	_agregar_campo_formulario(contenido, "LOBBY_PORT", _puerto_directo)
	_transporte_directo = _nuevo_selector_transporte()
	_agregar_campo_formulario(contenido, "LOBBY_TRANSPORT", _transporte_directo)
	_codigo_directo = _nuevo_campo("")
	_codigo_directo.placeholder_text = tr("LOBBY_DIRECT_CODE_PLACEHOLDER")
	_codigo_directo.max_length = 12
	_agregar_campo_formulario(contenido, "LOBBY_DIRECT_CODE", _codigo_directo)
	_escenario_directo = _nuevo_selector_escenario()
	_agregar_campo_formulario(contenido, "LOBBY_SCENARIO", _escenario_directo)
	_dificultad_directa = _nuevo_selector_dificultad()
	_agregar_campo_formulario(contenido, "LOBBY_DIFFICULTY", _dificultad_directa)
	var acciones := HBoxContainer.new()
	contenido.add_child(acciones)
	acciones.add_child(_nuevo_boton("LOBBY_DIRECT_CREATE", _crear_sala_directa))
	acciones.add_child(_nuevo_boton("LOBBY_DIRECT_JOIN", _unirse_directamente))
	acciones.add_child(_nuevo_boton("LOBBY_BACK", _volver_a_inicio))

func _crear_pantalla_ajustes(contenido: VBoxContainer) -> void:
	_agregar_titulo_pantalla(contenido, "LOBBY_SETTINGS_TITLE", "LOBBY_SETTINGS_SUBTITLE")
	_url_directorio = _nuevo_campo(_url_directorio_actual)
	_url_directorio.placeholder_text = URL_DIRECTORIO_PREDETERMINADA
	_agregar_campo_formulario(contenido, "LOBBY_DIRECTORY_URL", _url_directorio)
	var acciones := HBoxContainer.new()
	contenido.add_child(acciones)
	acciones.add_child(_nuevo_boton("LOBBY_SAVE_SETTINGS", _guardar_ajustes))
	acciones.add_child(_nuevo_boton("LOBBY_BACK", _volver_a_inicio))

func _crear_pantalla_sala(contenido: VBoxContainer) -> void:
	_agregar_titulo_pantalla(contenido, "LOBBY_ROOM_TITLE", "LOBBY_ROOM_SUBTITLE")
	var fila_codigo := HBoxContainer.new()
	fila_codigo.add_child(_nueva_etiqueta("LOBBY_ROOM_CODE"))
	_codigo_actual = Label.new()
	_codigo_actual.text = "----"
	_codigo_actual.add_theme_font_size_override("font_size", 32)
	_codigo_actual.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila_codigo.add_child(_codigo_actual)
	fila_codigo.add_child(_nuevo_boton("LOBBY_COPY_CODE", _copiar_codigo_sala))
	contenido.add_child(fila_codigo)

	contenido.add_child(_nueva_etiqueta("LOBBY_ROLE_TITLE"))
	var tarjetas_rol := HBoxContainer.new()
	tarjetas_rol.add_theme_constant_override("separation", 12)
	contenido.add_child(tarjetas_rol)
	_grupo_roles = ButtonGroup.new()
	_grupo_roles.allow_unpress = false
	for rol_id in ORDEN_ROLES:
		var boton := Button.new()
		boton.custom_minimum_size = Vector2(220.0, 118.0)
		boton.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		boton.toggle_mode = true
		boton.button_group = _grupo_roles
		boton.add_theme_font_size_override("font_size", 19)
		boton.pressed.connect(_seleccionar_rol.bind(rol_id))
		_botones_rol[rol_id] = boton
		tarjetas_rol.add_child(boton)

	var panel_pilotos := PanelContainer.new()
	panel_pilotos.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contenido.add_child(panel_pilotos)
	var lista_contenido := VBoxContainer.new()
	lista_contenido.add_theme_constant_override("separation", 6)
	panel_pilotos.add_child(lista_contenido)
	lista_contenido.add_child(_nueva_etiqueta("LOBBY_PILOTS_TITLE"))
	_lista_pilotos = VBoxContainer.new()
	_lista_pilotos.add_theme_constant_override("separation", 4)
	lista_contenido.add_child(_lista_pilotos)

	var acciones := HBoxContainer.new()
	contenido.add_child(acciones)
	_boton_listo = _nuevo_boton("LOBBY_READY", _alternar_listo)
	_boton_listo.toggle_mode = true
	acciones.add_child(_boton_listo)
	_boton_iniciar = _nuevo_boton("LOBBY_START", _iniciar_partida)
	_boton_iniciar.visible = false
	acciones.add_child(_boton_iniciar)
	acciones.add_child(_nuevo_boton("LOBBY_LEAVE_ROOM", _salir_de_sala))
	acciones.add_child(_nuevo_boton("LOBBY_BACK_TO_MENU", _volver_al_menu))

	var panel_chat := PanelContainer.new()
	contenido.add_child(panel_chat)
	var columna_chat := VBoxContainer.new()
	columna_chat.add_theme_constant_override("separation", 6)
	panel_chat.add_child(columna_chat)
	columna_chat.add_child(_nueva_etiqueta("LOBBY_CHAT_TITLE"))
	_chat_historial = RichTextLabel.new()
	_chat_historial.custom_minimum_size = Vector2(0.0, 76.0)
	_chat_historial.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_historial.scroll_following = true
	columna_chat.add_child(_chat_historial)
	var fila_chat := HBoxContainer.new()
	columna_chat.add_child(fila_chat)
	_chat_entrada = _nuevo_campo("")
	_chat_entrada.placeholder_text = tr("LOBBY_CHAT_PLACEHOLDER")
	_chat_entrada.max_length = 160
	_chat_entrada.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_entrada.text_submitted.connect(_enviar_mensaje_chat)
	fila_chat.add_child(_chat_entrada)
	fila_chat.add_child(_nuevo_boton("LOBBY_CHAT_SEND", _enviar_chat_desde_boton))

func _agregar_titulo_pantalla(
	contenido: VBoxContainer,
	titulo_clave: String,
	subtitulo_clave: String
) -> void:
	var titulo := Label.new()
	titulo.text = tr(titulo_clave)
	titulo.add_theme_font_size_override("font_size", 26)
	contenido.add_child(titulo)
	var subtitulo := Label.new()
	subtitulo.text = tr(subtitulo_clave)
	subtitulo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitulo.modulate = Color("#b5c3d0")
	contenido.add_child(subtitulo)

func _nueva_tarjeta(titulo_clave: String, descripcion_clave: String, accion: Callable) -> Button:
	var boton := Button.new()
	boton.text = "%s\n\n%s" % [tr(titulo_clave), tr(descripcion_clave)]
	boton.custom_minimum_size = Vector2(260.0, 190.0)
	boton.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	boton.size_flags_vertical = Control.SIZE_EXPAND_FILL
	boton.add_theme_font_size_override("font_size", 22)
	boton.pressed.connect(accion)
	return boton

func _agregar_campo_formulario(
	contenido: VBoxContainer,
	etiqueta_clave: String,
	campo: Control
) -> void:
	var fila := VBoxContainer.new()
	fila.add_theme_constant_override("separation", 5)
	fila.add_child(_nueva_etiqueta(etiqueta_clave))
	campo.custom_minimum_size.y = maxf(campo.custom_minimum_size.y, 42.0)
	fila.add_child(campo)
	contenido.add_child(fila)

func _nuevo_selector_escenario() -> OptionButton:
	var selector := OptionButton.new()
	selector.add_item(tr("LOBBY_SCENARIO_AGUARAGUE"), 0)
	selector.add_item(tr("LOBBY_SCENARIO_CAMPO"), 1)
	selector.add_item(tr("LOBBY_SCENARIO_URBANO"), 2)
	selector.select(0)
	return selector

func _nuevo_selector_dificultad() -> OptionButton:
	var selector := OptionButton.new()
	selector.add_item(tr("LOBBY_DIFFICULTY_LOW"), 0)
	selector.add_item(tr("LOBBY_DIFFICULTY_MEDIUM"), 1)
	selector.add_item(tr("LOBBY_DIFFICULTY_HIGH"), 2)
	selector.select(1)
	return selector

func _nuevo_selector_transporte() -> OptionButton:
	var selector := OptionButton.new()
	selector.add_item("WebSocket", 0)
	selector.add_item("ENet", 1)
	selector.select(0)
	return selector

func _nueva_etiqueta(clave: String) -> Label:
	var etiqueta := Label.new()
	etiqueta.text = tr(clave)
	etiqueta.add_theme_font_size_override("font_size", 17)
	return etiqueta

func _nuevo_campo(texto: String) -> LineEdit:
	var campo := LineEdit.new()
	campo.text = texto
	campo.add_theme_font_size_override("font_size", 18)
	return campo

func _nuevo_boton(clave: String, accion: Callable) -> Button:
	var boton := Button.new()
	boton.text = tr(clave)
	boton.custom_minimum_size.y = 48.0
	boton.add_theme_font_size_override("font_size", 18)
	boton.pressed.connect(accion)
	return boton

func _mostrar_pantalla(nombre: String) -> void:
	if not _pantallas.has(nombre):
		push_error("No existe la pantalla de lobby solicitada: %s." % nombre)
		return
	_pantalla_actual = nombre
	for clave in _pantallas:
		var pantalla := _pantallas[clave] as Control
		pantalla.visible = str(clave) == nombre
	_nombre.visible = nombre not in ["sala", "ajustes"]
	_boton_ajustes.visible = nombre not in ["sala", "ajustes"]

func _abrir_ajustes() -> void:
	_url_directorio.text = _url_directorio_actual
	_mostrar_pantalla("ajustes")

func _abrir_busqueda_salas() -> void:
	_mostrar_pantalla("unirse")
	_actualizar_lista_manual()

func _volver_a_inicio() -> void:
	_mostrar_pantalla("inicio")

func _cargar_url_directorio() -> void:
	var configuracion := ConfigFile.new()
	var error_carga := configuracion.load(ARCHIVO_CONFIGURACION)
	if error_carga == ERR_FILE_NOT_FOUND:
		return
	if error_carga != OK:
		push_error("No se pudo cargar la URL del directorio (error %d)." % error_carga)
		return
	var valor: Variant = configuracion.get_value(
		"red", "url_directorio", URL_DIRECTORIO_PREDETERMINADA
	)
	if valor is String and not str(valor).strip_edges().is_empty():
		_url_directorio_actual = str(valor).strip_edges().trim_suffix("/")
	else:
		push_warning("La URL del directorio guardada no es válida; se usará la predeterminada.")

func _guardar_ajustes() -> void:
	var url := _url_directorio.text.strip_edges().trim_suffix("/")
	if not url.begins_with("http://") and not url.begins_with("https://"):
		_mostrar_estado(tr("LOBBY_ERROR_DIRECTORY_URL"), COLOR_ROJO)
		_url_directorio.grab_focus()
		return
	var configuracion := ConfigFile.new()
	configuracion.set_value("red", "url_directorio", url)
	var error_guardado := configuracion.save(ARCHIVO_CONFIGURACION)
	if error_guardado != OK:
		push_error("No se pudo guardar la URL del directorio (error %d)." % error_guardado)
		_mostrar_estado(tr("LOBBY_ERROR_SETTINGS_SAVE"), COLOR_ROJO)
		return
	_url_directorio_actual = url
	_mostrar_estado(tr("LOBBY_STATUS_SETTINGS_SAVED"), COLOR_VERDE)
	_mostrar_pantalla("inicio")
	_solicitar_lista_salas()

func _crear_sala_directorio() -> void:
	if _nombre_sala.text.strip_edges().is_empty():
		_mostrar_estado(tr("LOBBY_ERROR_ROOM_NAME"), COLOR_ROJO)
		_nombre_sala.grab_focus()
		return
	NetworkManager.nombre_local = _nombre_piloto()
	_configuracion_sala_pendiente = {
		"nombre": _nombre_sala.text.strip_edges(),
		"escenario": _escenario_seleccionado(_escenario),
		"dificultad": _dificultad_seleccionada(_dificultad),
		"max_jugadores": MAX_JUGADORES_SALA,
		"puerto": NetworkManager.PUERTO_PREDETERMINADO,
	}
	_creacion_directorio_pendiente = true
	_mostrar_estado(tr("LOBBY_STATUS_CREATING"), COLOR_AMARILLO)
	if not is_instance_valid(_cliente_directorio):
		_crear_sala_lan_respaldo()
		return
	_cliente_directorio.crear_sala(
		_url_directorio_actual,
		str(_configuracion_sala_pendiente["nombre"]),
		str(_configuracion_sala_pendiente["escenario"]),
		str(_configuracion_sala_pendiente["dificultad"]),
		int(_configuracion_sala_pendiente["max_jugadores"])
	)

func _crear_sala_directa() -> void:
	if _nombre_sala_directa.text.strip_edges().is_empty():
		_mostrar_estado(tr("LOBBY_ERROR_ROOM_NAME"), COLOR_ROJO)
		_nombre_sala_directa.grab_focus()
		return
	NetworkManager.nombre_local = _nombre_piloto()
	NetworkManager.transporte = "ENet" if _transporte_directo.get_selected_id() == 1 else "WebSocket"
	var codigo := _codigo_directo.text.strip_edges()
	var configuracion := {
		"nombre": _nombre_sala_directa.text.strip_edges(),
		"escenario": _escenario_seleccionado(_escenario_directo),
		"dificultad": _dificultad_seleccionada(_dificultad_directa),
		"max_jugadores": MAX_JUGADORES_SALA,
		"puerto": int(_puerto_directo.value),
		"codigo": codigo,
	}
	if NetworkManager.crear_sala(configuracion):
		_mostrar_estado(tr("LOBBY_STATUS_DIRECT_CREATED"), COLOR_VERDE)

func _unirse_directamente() -> void:
	var codigo := _codigo_directo.text.strip_edges()
	if codigo.is_empty():
		_mostrar_estado(tr("LOBBY_ERROR_DIRECT_CODE"), COLOR_ROJO)
		_codigo_directo.grab_focus()
		return
	NetworkManager.nombre_local = _nombre_piloto()
	NetworkManager.transporte = "ENet" if _transporte_directo.get_selected_id() == 1 else "WebSocket"
	_mostrar_estado(tr("LOBBY_STATUS_CONNECTING"), COLOR_AMARILLO)
	if not NetworkManager.unirse_a_sala(
		_direccion_directa.text.strip_edges(),
		int(_puerto_directo.value),
		codigo
	):
		_mostrar_estado(tr("LOBBY_ERROR_CONNECT"), COLOR_ROJO)

func _unirse_con_codigo() -> void:
	var codigo := _codigo_directorio.text.strip_edges()
	if not _codigo_tiene_cuatro_digitos(codigo):
		_mostrar_estado(tr("LOBBY_ERROR_ROOM_CODE"), COLOR_ROJO)
		_codigo_directorio.grab_focus()
		return
	NetworkManager.nombre_local = _nombre_piloto()
	_mostrar_estado(tr("LOBBY_STATUS_LOOKING_UP"), COLOR_AMARILLO)
	_cliente_directorio.obtener_sala(_url_directorio_actual, codigo)

func _solicitar_lista_salas() -> void:
	if is_instance_valid(_cliente_directorio):
		_cliente_directorio.listar_salas(_url_directorio_actual)

func _actualizar_lista_manual() -> void:
	_mostrar_estado(tr("LOBBY_STATUS_REFRESHING"), COLOR_AMARILLO)
	_solicitar_lista_salas()

func _al_recibir_lista_salas(salas: Array) -> void:
	if not is_instance_valid(_lista_salas):
		return
	_salas_recibidas.clear()
	_lista_salas.clear()
	for elemento in salas:
		if not elemento is Dictionary:
			continue
		var sala: Dictionary = elemento
		_salas_recibidas.append(sala)
		var codigo := str(sala.get("codigo", "----"))
		var nombre := str(sala.get("nombre", ""))
		if nombre.is_empty():
			nombre = tr("LOBBY_ROOM_FALLBACK") % codigo
		var jugadores := int(sala.get("jugadores", 0))
		var max_jugadores := int(sala.get("max_jugadores", MAX_JUGADORES_SALA))
		var completa := jugadores >= max_jugadores
		var estado := str(sala.get("estado", ""))
		if estado.is_empty():
			estado = tr("LOBBY_ROOM_FULL") if completa else tr("LOBBY_ROOM_AVAILABLE")
		var ping := tr("LOBBY_PING_UNKNOWN")
		if sala.has("ping"):
			ping = tr("LOBBY_PING_VALUE") % int(sala.get("ping", 0))
		var fila := tr("LOBBY_ROOM_ROW") % [
			nombre,
			tr(_nombre_escenario(str(sala.get("escenario", "")))),
			jugadores,
			max_jugadores,
			estado,
			ping,
		]
		_lista_salas.add_item(fila)
		_lista_salas.set_item_custom_fg_color(
			_lista_salas.item_count - 1,
			COLOR_ROJO if completa else COLOR_VERDE
		)
	if salas.is_empty() and _pantalla_actual == "unirse":
		_mostrar_estado(tr("LOBBY_STATUS_NO_ROOMS"), COLOR_AMARILLO)
	elif _pantalla_actual == "unirse":
		_mostrar_estado(tr("LOBBY_STATUS_ROOMS_UPDATED"), COLOR_VERDE)

func _al_crear_sala_directorio(datos: Dictionary) -> void:
	if not _datos_sala_directorio_validos(datos):
		_al_fallar_creacion_directorio(tr("LOBBY_ERROR_DIRECTORY_RESPONSE"))
		return
	_creacion_directorio_pendiente = false
	_configuracion_sala_pendiente.clear()
	_mostrar_estado(
		tr("LOBBY_STATUS_ROOM_CREATED") % str(datos.get("codigo", "")),
		COLOR_VERDE
	)
	_conectar_a_sala_directorio(datos)

func _al_fallar_creacion_directorio(mensaje: String) -> void:
	if not _creacion_directorio_pendiente:
		return
	push_warning("No se pudo crear la sala en el directorio; se intentará en LAN: %s" % mensaje)
	_crear_sala_lan_respaldo()

func _crear_sala_lan_respaldo() -> void:
	if _configuracion_sala_pendiente.is_empty():
		_creacion_directorio_pendiente = false
		_mostrar_estado(tr("LOBBY_ERROR_DIRECTORY_RESPONSE"), COLOR_ROJO)
		return
	var configuracion := _configuracion_sala_pendiente.duplicate(true)
	configuracion["puerto"] = NetworkManager.PUERTO_PREDETERMINADO
	configuracion.erase("codigo")
	NetworkManager.transporte = "WebSocket"
	_creacion_directorio_pendiente = false
	_configuracion_sala_pendiente.clear()
	if not NetworkManager.crear_sala(configuracion):
		_mostrar_estado(tr("LOBBY_ERROR_LAN_CREATE"), COLOR_ROJO)
		return
	var codigo := NetworkManager.codigo_sala
	var direccion := _obtener_direccion_lan()
	_mostrar_estado(
		tr("LOBBY_STATUS_LAN_FALLBACK") % [
			direccion,
			NetworkManager.PUERTO_PREDETERMINADO,
			codigo,
		],
		COLOR_AMARILLO
	)

func _obtener_direccion_lan() -> String:
	for direccion in IP.get_local_addresses():
		var partes := str(direccion).split(".")
		if (
			partes.size() != 4
			or str(direccion).begins_with("127.")
			or str(direccion).begins_with("169.254.")
		):
			continue
		var es_ipv4 := true
		for parte in partes:
			if not str(parte).is_valid_int() or int(parte) < 0 or int(parte) > 255:
				es_ipv4 = false
				break
		if es_ipv4:
			return str(direccion)
	return "127.0.0.1"

func _al_encontrar_sala(datos: Dictionary) -> void:
	_mostrar_estado(tr("LOBBY_STATUS_ROOM_FOUND"), COLOR_AMARILLO)
	_conectar_a_sala_directorio(datos)

func _conectar_a_sala_directorio(datos: Dictionary) -> void:
	var codigo := str(datos.get("codigo", ""))
	var host := str(datos.get("host", "")).strip_edges()
	var puerto := int(datos.get("puerto", 0))
	if not _datos_sala_directorio_validos(datos):
		_mostrar_estado(tr("LOBBY_ERROR_DIRECTORY_RESPONSE"), COLOR_ROJO)
		return
	var transporte := str(datos.get("transporte", "websocket"))
	NetworkManager.transporte = "ENet" if transporte == "enet" else "WebSocket"
	if not NetworkManager.unirse_a_sala(host, puerto, codigo):
		_mostrar_estado(tr("LOBBY_ERROR_CONNECT"), COLOR_ROJO)

func _datos_sala_directorio_validos(datos: Dictionary) -> bool:
	var codigo := str(datos.get("codigo", ""))
	var host := str(datos.get("host", "")).strip_edges()
	var puerto := int(datos.get("puerto", 0))
	return (
		_codigo_tiene_cuatro_digitos(codigo)
		and not host.is_empty()
		and puerto >= 1
		and puerto <= 65535
	)

func _conectar_item_sala(indice: int) -> void:
	if indice < 0 or indice >= _salas_recibidas.size():
		return
	_lista_salas.select(indice)
	_unirse_a_sala_seleccionada()

func _unirse_a_sala_seleccionada() -> void:
	var seleccion := _lista_salas.get_selected_items()
	if seleccion.is_empty():
		_mostrar_estado(tr("LOBBY_ERROR_SELECT_ROOM"), COLOR_AMARILLO)
		return
	var indice := seleccion[0]
	if indice < 0 or indice >= _salas_recibidas.size():
		_mostrar_estado(tr("LOBBY_ERROR_STALE_ROOM"), COLOR_ROJO)
		return
	var sala: Dictionary = _salas_recibidas[indice]
	var codigo := str(sala.get("codigo", ""))
	if not _codigo_tiene_cuatro_digitos(codigo):
		_mostrar_estado(tr("LOBBY_ERROR_DIRECTORY_CODE"), COLOR_ROJO)
		return
	NetworkManager.nombre_local = _nombre_piloto()
	_mostrar_estado(tr("LOBBY_STATUS_LOOKING_UP"), COLOR_AMARILLO)
	_cliente_directorio.obtener_sala(_url_directorio_actual, codigo)

func _al_error_directorio(mensaje: String) -> void:
	_mostrar_estado(tr(mensaje), COLOR_ROJO)

func _actualizar_sala(codigo: String, jugadores_sala: Dictionary) -> void:
	if not is_instance_valid(_codigo_actual):
		return
	if codigo.is_empty():
		_codigo_actual.text = "----"
		if _pantalla_actual == "sala" and not multiplayer.has_multiplayer_peer():
			_mostrar_pantalla("inicio")
			_mostrar_estado(tr("LOBBY_STATUS_DISCONNECTED"), COLOR_AMARILLO)
		return

	_codigo_actual.text = codigo
	_mostrar_pantalla("sala")
	var total := jugadores_sala.size()
	var max_jugadores := int(NetworkManager.configuracion_sala.get(
		"max_jugadores", MAX_JUGADORES_SALA
	))
	_mostrar_estado(
		tr("LOBBY_STATUS_CONNECTED") % [total, max_jugadores],
		COLOR_VERDE
	)
	_actualizar_lista_pilotos(jugadores_sala)
	_actualizar_tarjetas_rol(jugadores_sala)
	_boton_listo.disabled = not jugadores_sala.has(multiplayer.get_unique_id())
	var jugador_local: Dictionary = jugadores_sala.get(multiplayer.get_unique_id(), {})
	var listo := bool(jugador_local.get("listo", false))
	_boton_listo.button_pressed = listo
	_boton_listo.text = tr("LOBBY_READY") if not listo else tr("LOBBY_READY_SET")
	_boton_iniciar.visible = NetworkManager.es_anfitrion_local()
	_boton_iniciar.disabled = NetworkManager.partida_iniciada

func _actualizar_lista_pilotos(jugadores_sala: Dictionary) -> void:
	for hijo in _lista_pilotos.get_children():
		hijo.queue_free()
	var ids: Array = jugadores_sala.keys()
	ids.sort()
	for id_variant in ids:
		var datos: Dictionary = jugadores_sala[id_variant]
		var fila := HBoxContainer.new()
		var nombre := Label.new()
		nombre.text = str(datos.get("nombre", tr("LOBBY_PILOT_DEFAULT")))
		nombre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fila.add_child(nombre)
		var rol_id := str(datos.get("rol_dron", "explorador"))
		var etiqueta_rol := Label.new()
		etiqueta_rol.text = tr(_nombre_rol(rol_id))
		fila.add_child(etiqueta_rol)
		if str(datos.get("rol", "")) == "anfitrion":
			var anfitrion := Label.new()
			anfitrion.text = tr("LOBBY_HOST_BADGE")
			anfitrion.modulate = COLOR_AMARILLO
			fila.add_child(anfitrion)
		var esta_listo := bool(datos.get("listo", false))
		var estado := Label.new()
		estado.text = tr("LOBBY_READY_STATUS") if esta_listo else tr("LOBBY_WAITING_STATUS")
		estado.modulate = COLOR_VERDE if esta_listo else COLOR_AMARILLO
		fila.add_child(estado)
		var ping := Label.new()
		ping.text = tr("LOBBY_PING_VALUE") % int(datos.get("ping", 0))
		ping.modulate = Color("#b5c3d0")
		fila.add_child(ping)
		_lista_pilotos.add_child(fila)

func _actualizar_tarjetas_rol(jugadores_sala: Dictionary) -> void:
	var id_local := multiplayer.get_unique_id()
	var jugador_local: Dictionary = jugadores_sala.get(id_local, {})
	var rol_local := str(jugador_local.get("rol_dron", NetworkManager.rol_dron_local))
	for rol_id in ORDEN_ROLES:
		var boton := _botones_rol[rol_id] as Button
		var recurso := RECURSOS_ROL[rol_id] as DroneRole
		var ocupado_por := ""
		for id_variant in jugadores_sala:
			if int(id_variant) == id_local:
				continue
			var datos: Dictionary = jugadores_sala[id_variant]
			if str(datos.get("rol_dron", "")) == rol_id:
				ocupado_por = str(datos.get("nombre", tr("LOBBY_PILOT_DEFAULT")))
				break
		var titulo := tr(recurso.nombre)
		var estadisticas := tr("LOBBY_ROLE_STATS") % [
			int(recurso.agua_maxima),
			int(recurso.velocidad_maxima),
		]
		var disponibilidad := (
			tr("LOBBY_ROLE_TAKEN") % ocupado_por
			if not ocupado_por.is_empty()
			else tr("LOBBY_ROLE_AVAILABLE")
		)
		boton.text = "%s\n%s\n%s" % [titulo, estadisticas, disponibilidad]
		boton.disabled = not ocupado_por.is_empty()
		boton.button_pressed = rol_id == rol_local

func _seleccionar_rol(rol_id: String) -> void:
	if not NetworkManager.seleccionar_rol_dron(rol_id):
		_mostrar_estado(tr("LOBBY_ERROR_ROLE"), COLOR_ROJO)
		return
	_mostrar_estado(tr("LOBBY_STATUS_ROLE_PENDING"), COLOR_AMARILLO)

func _alternar_listo() -> void:
	if not NetworkManager.establecer_listo(not _jugador_local_listo()):
		_mostrar_estado(tr("LOBBY_ERROR_READY"), COLOR_ROJO)

func _jugador_local_listo() -> bool:
	var jugador: Dictionary = NetworkManager.jugadores.get(multiplayer.get_unique_id(), {})
	return bool(jugador.get("listo", false))

func _iniciar_partida() -> void:
	if not NetworkManager.iniciar_partida():
		_mostrar_estado(tr("LOBBY_ERROR_START"), COLOR_ROJO)

func _copiar_codigo_sala() -> void:
	if NetworkManager.codigo_sala.is_empty():
		_mostrar_estado(tr("LOBBY_ERROR_NO_CODE"), COLOR_ROJO)
		return
	DisplayServer.clipboard_set(NetworkManager.codigo_sala)
	_mostrar_estado(tr("LOBBY_STATUS_CODE_COPIED"), COLOR_VERDE)

func _salir_de_sala() -> void:
	NetworkManager.salir()
	_mostrar_pantalla("inicio")
	_mostrar_estado(tr("LOBBY_STATUS_LEFT_ROOM"), COLOR_AMARILLO)

func _enviar_chat_desde_boton() -> void:
	_enviar_mensaje_chat(_chat_entrada.text)

func _enviar_mensaje_chat(texto: String) -> void:
	if not NetworkManager.enviar_chat(texto):
		_mostrar_estado(tr("LOBBY_ERROR_CHAT"), COLOR_ROJO)
		return
	_chat_entrada.clear()

func _al_recibir_chat(nombre: String, texto: String) -> void:
	_mensajes_chat.append("%s: %s" % [nombre, texto])
	if _mensajes_chat.size() > 30:
		_mensajes_chat.remove_at(0)
	_chat_historial.text = "\n".join(_mensajes_chat)
	_chat_historial.scroll_to_line(_chat_historial.get_line_count())

func _al_actualizar_sala(codigo: String, jugadores_sala: Dictionary) -> void:
	_actualizar_sala(codigo, jugadores_sala)

func _al_actualizar_jugador(_id: int, _datos: Dictionary) -> void:
	_actualizar_sala(NetworkManager.codigo_sala, NetworkManager.jugadores)

func _al_desconectar_jugador(_id: int) -> void:
	_actualizar_sala(NetworkManager.codigo_sala, NetworkManager.jugadores)

func _al_error_conexion(mensaje: String) -> void:
	_mostrar_estado(tr(mensaje), COLOR_ROJO)

func _al_rol_rechazado(motivo: String) -> void:
	_mostrar_estado(tr(motivo), COLOR_ROJO)
	_actualizar_sala(NetworkManager.codigo_sala, NetworkManager.jugadores)

func _volver_al_menu() -> void:
	if is_instance_valid(_temporizador_lista):
		_temporizador_lista.stop()
	_creacion_directorio_pendiente = false
	_configuracion_sala_pendiente.clear()
	if is_instance_valid(_cliente_directorio):
		_cliente_directorio.cancelar_solicitudes()
	NetworkManager.salir()
	var error_cambio := get_tree().change_scene_to_file(ESCENA_MENU_PRINCIPAL)
	if error_cambio != OK:
		push_error("No se pudo volver al menú principal (error %d)." % error_cambio)

func _exit_tree() -> void:
	_creacion_directorio_pendiente = false
	_configuracion_sala_pendiente.clear()
	if is_instance_valid(_temporizador_lista):
		_temporizador_lista.stop()
		if _temporizador_lista.timeout.is_connected(_solicitar_lista_salas):
			_temporizador_lista.timeout.disconnect(_solicitar_lista_salas)
	if is_instance_valid(_cliente_directorio):
		if _cliente_directorio.sala_creada.is_connected(_al_crear_sala_directorio):
			_cliente_directorio.sala_creada.disconnect(_al_crear_sala_directorio)
		if _cliente_directorio.salas_recibidas.is_connected(_al_recibir_lista_salas):
			_cliente_directorio.salas_recibidas.disconnect(_al_recibir_lista_salas)
		if _cliente_directorio.sala_encontrada.is_connected(_al_encontrar_sala):
			_cliente_directorio.sala_encontrada.disconnect(_al_encontrar_sala)
		if _cliente_directorio.error_directorio.is_connected(_al_error_directorio):
			_cliente_directorio.error_directorio.disconnect(_al_error_directorio)
		if _cliente_directorio.error_creacion_sala.is_connected(_al_fallar_creacion_directorio):
			_cliente_directorio.error_creacion_sala.disconnect(_al_fallar_creacion_directorio)
		_cliente_directorio.cancelar_solicitudes()
	if NetworkManager.sala_actualizada.is_connected(_al_actualizar_sala):
		NetworkManager.sala_actualizada.disconnect(_al_actualizar_sala)
	if NetworkManager.jugador_conectado.is_connected(_al_actualizar_jugador):
		NetworkManager.jugador_conectado.disconnect(_al_actualizar_jugador)
	if NetworkManager.jugador_desconectado.is_connected(_al_desconectar_jugador):
		NetworkManager.jugador_desconectado.disconnect(_al_desconectar_jugador)
	if NetworkManager.conexion_fallida.is_connected(_al_error_conexion):
		NetworkManager.conexion_fallida.disconnect(_al_error_conexion)
	if NetworkManager.rol_rechazado.is_connected(_al_rol_rechazado):
		NetworkManager.rol_rechazado.disconnect(_al_rol_rechazado)
	if NetworkManager.chat_recibido.is_connected(_al_recibir_chat):
		NetworkManager.chat_recibido.disconnect(_al_recibir_chat)

func _nombre_piloto() -> String:
	var nombre := _nombre.text.strip_edges()
	return nombre if not nombre.is_empty() else tr("LOBBY_PILOT_DEFAULT")

func _escenario_seleccionado(selector: OptionButton) -> String:
	match selector.get_selected_id():
		1:
			return "campo_pajoso"
		2:
			return "interfase_urbana"
		_:
			return "aguarague"

func _nombre_escenario(escenario: String) -> String:
	match escenario:
		"campo_pajoso":
			return "LOBBY_SCENARIO_CAMPO"
		"interfase_urbana":
			return "LOBBY_SCENARIO_URBANO"
		_:
			return "LOBBY_SCENARIO_AGUARAGUE"

func _dificultad_seleccionada(selector: OptionButton) -> String:
	match selector.get_selected_id():
		0:
			return "baja"
		2:
			return "alta"
		_:
			return "media"

func _nombre_rol(rol_id: String) -> String:
	match rol_id:
		"cisterna":
			return "LOBBY_ROLE_CISTERNA"
		"tactico":
			return "LOBBY_ROLE_TACTICO"
		_:
			return "LOBBY_ROLE_EXPLORADOR"

func _codigo_tiene_cuatro_digitos(codigo: String) -> bool:
	if codigo.length() != 4:
		return false
	for caracter in codigo:
		var digito := caracter.unicode_at(0)
		if digito < 48 or digito > 57:
			return false
	return true

func _filtrar_codigo_directorio(texto: String) -> void:
	var solo_digitos := ""
	for caracter in texto:
		var digito := caracter.unicode_at(0)
		if digito >= 48 and digito <= 57:
			solo_digitos += caracter
	if solo_digitos != texto:
		_codigo_directorio.text = solo_digitos
		_codigo_directorio.caret_column = solo_digitos.length()

func _mostrar_estado(texto: String, color: Color) -> void:
	_estado.text = texto
	_estado.add_theme_color_override("font_color", color)
