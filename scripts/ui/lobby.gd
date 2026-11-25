extends Control

const CLIENTE_DIRECTORIO: Script = preload("res://scripts/network/directorio_client.gd")
const ESCENA_MENU_PRINCIPAL: String = "res://scenes/menus/main_menu.tscn"
const URL_DIRECTORIO_PREDETERMINADA: String = "http://127.0.0.1:8080"

var _cliente_directorio: Node
var _temporizador_lista: Timer
var _nombre: LineEdit
var _selector_rol: OptionButton
var _roles_ocupados: Label
var _url_directorio: LineEdit
var _escenario: OptionButton
var _dificultad: OptionButton
var _max_jugadores: SpinBox
var _codigo_directorio: LineEdit
var _lista_salas: ItemList
var _direccion_directa: LineEdit
var _puerto_directo: SpinBox
var _codigo_directo: LineEdit
var _transporte_directo: OptionButton
var _estado: Label
var _codigo_actual: Label
var _lista_jugadores: Label
var _boton_listo: Button
var _boton_iniciar: Button
var _chat_historial: RichTextLabel
var _chat_entrada: LineEdit
var _salas_recibidas: Array[Dictionary] = []
var _mensajes_chat: PackedStringArray = PackedStringArray()

func _ready() -> void:
	_crear_interfaz()
	_cliente_directorio = CLIENTE_DIRECTORIO.new() as Node
	if _cliente_directorio == null:
		push_error("No se pudo crear el cliente HTTP del directorio.")
		return
	add_child(_cliente_directorio)
	_cliente_directorio.sala_creada.connect(_al_crear_sala_directorio)
	_cliente_directorio.salas_recibidas.connect(_al_recibir_lista_salas)
	_cliente_directorio.sala_encontrada.connect(_al_encontrar_sala)
	_cliente_directorio.error_directorio.connect(_al_error_directorio)
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
	_actualizar_sala(NetworkManager.codigo_sala, NetworkManager.jugadores)
	_solicitar_lista_salas()

func _crear_interfaz() -> void:
	var fondo := ColorRect.new()
	fondo.color = Color(0.025, 0.045, 0.07, 1.0)
	fondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(fondo)

	var margen := MarginContainer.new()
	margen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margen.add_theme_constant_override("margin_left", 32)
	margen.add_theme_constant_override("margin_top", 22)
	margen.add_theme_constant_override("margin_right", 32)
	margen.add_theme_constant_override("margin_bottom", 22)
	add_child(margen)

	var columna := VBoxContainer.new()
	columna.add_theme_constant_override("separation", 10)
	margen.add_child(columna)

	var titulo := Label.new()
	titulo.text = "CENTRO DE OPERACIONES — MULTIJUGADOR"
	titulo.add_theme_font_size_override("font_size", 24)
	columna.add_child(titulo)

	var fila_nombre := HBoxContainer.new()
	columna.add_child(fila_nombre)
	fila_nombre.add_child(_nueva_etiqueta("Nombre de piloto"))
	_nombre = _nuevo_campo(NetworkManager.nombre_local)
	_nombre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila_nombre.add_child(_nombre)

	var fila_rol := HBoxContainer.new()
	fila_rol.add_child(_nueva_etiqueta("Rol del dron"))
	_selector_rol = OptionButton.new()
	_selector_rol.add_item("Cisterna — 350 L", 0)
	_selector_rol.add_item("Explorador — 50 L", 1)
	_selector_rol.add_item("Táctico — 100 L", 2)
	_selector_rol.item_selected.connect(_al_seleccionar_rol)
	fila_rol.add_child(_selector_rol)
	_roles_ocupados = _nueva_etiqueta("Roles ocupados: ninguno")
	_roles_ocupados.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila_rol.add_child(_roles_ocupados)
	columna.add_child(fila_rol)
	var ayuda_roles := _nueva_etiqueta("Q: habilidad del rol · clic derecho: retardante (Explorador)")
	ayuda_roles.add_theme_font_size_override("font_size", 12)
	columna.add_child(ayuda_roles)

	var pestanas := TabContainer.new()
	pestanas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pestanas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columna.add_child(pestanas)
	pestanas.add_child(_crear_pestana_directorio())
	pestanas.add_child(_crear_pestana_directa())
	pestanas.set_tab_title(0, "Directorio")
	pestanas.set_tab_title(1, "Directo / LAN")

	_estado = _nueva_etiqueta("Listo para conectar.")
	_estado.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	columna.add_child(_estado)

	var panel_sala := PanelContainer.new()
	panel_sala.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columna.add_child(panel_sala)
	var contenido_sala := VBoxContainer.new()
	contenido_sala.add_theme_constant_override("separation", 6)
	panel_sala.add_child(contenido_sala)

	_codigo_actual = _nueva_etiqueta("Sin conexión")
	contenido_sala.add_child(_codigo_actual)
	_lista_jugadores = _nueva_etiqueta("PILOTOS CONECTADOS")
	_lista_jugadores.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	contenido_sala.add_child(_lista_jugadores)

	var fila_acciones := HBoxContainer.new()
	contenido_sala.add_child(fila_acciones)
	_boton_listo = _nuevo_boton("MARCAR LISTO", _alternar_listo)
	fila_acciones.add_child(_boton_listo)
	_boton_iniciar = _nuevo_boton("INICIAR PARTIDA", _iniciar_partida)
	fila_acciones.add_child(_boton_iniciar)
	fila_acciones.add_child(_nuevo_boton("SALIR DE LA SALA", _salir_de_sala))

	var fila_chat := HBoxContainer.new()
	contenido_sala.add_child(fila_chat)
	_chat_historial = RichTextLabel.new()
	_chat_historial.custom_minimum_size = Vector2(0, 76)
	_chat_historial.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_historial.scroll_following = true
	fila_chat.add_child(_chat_historial)
	var chat_columna := VBoxContainer.new()
	fila_chat.add_child(chat_columna)
	_chat_entrada = _nuevo_campo("")
	_chat_entrada.placeholder_text = "Mensaje (máx. 160 caracteres)"
	_chat_entrada.max_length = 160
	_chat_entrada.text_submitted.connect(_enviar_mensaje_chat)
	chat_columna.add_child(_chat_entrada)
	chat_columna.add_child(_nuevo_boton("ENVIAR", _enviar_chat_desde_boton))

	columna.add_child(_nuevo_boton("VOLVER AL MENÚ", _volver_al_menu))

func _crear_pestana_directorio() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var contenido := VBoxContainer.new()
	contenido.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contenido.add_theme_constant_override("separation", 7)
	scroll.add_child(contenido)

	contenido.add_child(_nueva_etiqueta("Servicio de salas"))
	_url_directorio = _nuevo_campo(URL_DIRECTORIO_PREDETERMINADA)
	_url_directorio.placeholder_text = "http://host:8080"
	contenido.add_child(_url_directorio)

	var fila_config := HBoxContainer.new()
	contenido.add_child(fila_config)
	_escenario = OptionButton.new()
	_escenario.add_item("Aguaragüe", 0)
	_escenario.add_item("Campo Pajoso", 1)
	_escenario.add_item("Interfase Urbana", 2)
	fila_config.add_child(_escenario)
	_dificultad = OptionButton.new()
	_dificultad.add_item("Baja", 0)
	_dificultad.add_item("Media", 1)
	_dificultad.add_item("Alta", 2)
	_dificultad.select(1)
	fila_config.add_child(_dificultad)
	_max_jugadores = _nuevo_spinbox(2, 6, 6)
	fila_config.add_child(_max_jugadores)

	contenido.add_child(_nuevo_boton("CREAR SALA", _crear_sala_directorio))
	var fila_codigo := HBoxContainer.new()
	contenido.add_child(fila_codigo)
	_codigo_directorio = _nuevo_campo("")
	_codigo_directorio.placeholder_text = "Código de 4 dígitos"
	_codigo_directorio.max_length = 4
	fila_codigo.add_child(_codigo_directorio)
	fila_codigo.add_child(_nuevo_boton("UNIRSE CON CÓDIGO", _unirse_con_codigo))

	var fila_lista := HBoxContainer.new()
	contenido.add_child(fila_lista)
	fila_lista.add_child(_nueva_etiqueta("Salas abiertas"))
	fila_lista.add_child(_nuevo_boton("ACTUALIZAR", _solicitar_lista_salas))
	_lista_salas = ItemList.new()
	_lista_salas.custom_minimum_size = Vector2(0, 110)
	_lista_salas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contenido.add_child(_lista_salas)
	contenido.add_child(_nuevo_boton("UNIRSE A SALA SELECCIONADA", _unirse_a_sala_seleccionada))
	return scroll

func _crear_pestana_directa() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var contenido := VBoxContainer.new()
	contenido.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contenido.add_theme_constant_override("separation", 7)
	scroll.add_child(contenido)

	contenido.add_child(_nueva_etiqueta("Conexión directa por IP y puerto; no usa el directorio."))
	_direccion_directa = _nuevo_campo("127.0.0.1")
	_direccion_directa.placeholder_text = "IP o nombre de host"
	contenido.add_child(_direccion_directa)
	var fila_red := HBoxContainer.new()
	contenido.add_child(fila_red)
	_puerto_directo = _nuevo_spinbox(1, 65535, NetworkManager.PUERTO_PREDETERMINADO)
	fila_red.add_child(_puerto_directo)
	_transporte_directo = OptionButton.new()
	_transporte_directo.add_item("WebSocket", 0)
	_transporte_directo.add_item("ENet", 1)
	fila_red.add_child(_transporte_directo)
	_codigo_directo = _nuevo_campo("")
	_codigo_directo.placeholder_text = "Código (opcional al crear)"
	contenido.add_child(_codigo_directo)
	contenido.add_child(_nuevo_boton("CREAR SALA DIRECTA", _crear_sala_directa))
	contenido.add_child(_nuevo_boton("UNIRSE DIRECTAMENTE", _unirse_directamente))
	return scroll

func _nueva_etiqueta(texto: String) -> Label:
	var etiqueta := Label.new()
	etiqueta.text = texto
	return etiqueta

func _nuevo_campo(texto: String) -> LineEdit:
	var campo := LineEdit.new()
	campo.text = texto
	return campo

func _nuevo_boton(texto: String, accion: Callable) -> Button:
	var boton := Button.new()
	boton.text = texto
	boton.pressed.connect(accion)
	return boton

func _nuevo_spinbox(minimo: float, maximo: float, valor: float) -> SpinBox:
	var selector := SpinBox.new()
	selector.min_value = minimo
	selector.max_value = maximo
	selector.value = valor
	selector.step = 1.0
	return selector

func _crear_sala_directorio() -> void:
	NetworkManager.nombre_local = _nombre_piloto()
	NetworkManager.rol_dron_local = _rol_seleccionado()
	_estado.text = "Solicitando sala al directorio..."
	_cliente_directorio.crear_sala(
		_url_directorio.text,
		_escenario_seleccionado(),
		_dificultad_seleccionada(),
		int(_max_jugadores.value)
	)

func _unirse_con_codigo() -> void:
	var codigo := _codigo_directorio.text.strip_edges()
	if not _codigo_tiene_cuatro_digitos(codigo):
		_estado.text = "Ingresa un código de sala de cuatro dígitos."
		return
	NetworkManager.nombre_local = _nombre_piloto()
	_estado.text = "Buscando la sala %s..." % codigo
	_cliente_directorio.obtener_sala(_url_directorio.text, codigo)

func _solicitar_lista_salas() -> void:
	if not is_instance_valid(_cliente_directorio) or not is_instance_valid(_url_directorio):
		return
	_cliente_directorio.listar_salas(_url_directorio.text)

func _al_crear_sala_directorio(datos: Dictionary) -> void:
	NetworkManager.nombre_local = _nombre_piloto()
	_estado.text = "Sala %s creada; conectando..." % str(datos.get("codigo", ""))
	_conectar_a_sala_directorio(datos)

func _al_encontrar_sala(datos: Dictionary) -> void:
	NetworkManager.nombre_local = _nombre_piloto()
	_estado.text = "Sala encontrada; conectando..."
	_conectar_a_sala_directorio(datos)

func _conectar_a_sala_directorio(datos: Dictionary) -> void:
	var codigo := str(datos.get("codigo", ""))
	var host := str(datos.get("host", ""))
	var puerto := int(datos.get("puerto", 0))
	if not _codigo_tiene_cuatro_digitos(codigo) or host.is_empty() or puerto < 1 or puerto > 65535:
		_estado.text = "El directorio devolvió datos de conexión inválidos."
		return
	NetworkManager.transporte = "ENet" if str(datos.get("transporte", "websocket")) == "enet" else "WebSocket"
	if not NetworkManager.unirse_a_sala(host, puerto, codigo):
		_estado.text = "No se pudo iniciar la conexión con %s:%d." % [host, puerto]

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
		_lista_salas.add_item(
			"%s — %s — %d/%d — %s"
			% [
				str(sala.get("codigo", "????")),
				str(sala.get("escenario", "escenario")),
				int(sala.get("jugadores", 0)),
				int(sala.get("max_jugadores", 0)),
				str(sala.get("dificultad", "")),
			]
		)
	if salas.is_empty():
		_estado.text = "No hay salas abiertas en el directorio."

func _al_error_directorio(mensaje: String) -> void:
	_estado.text = mensaje

func _unirse_a_sala_seleccionada() -> void:
	var seleccion := _lista_salas.get_selected_items()
	if seleccion.is_empty():
		_estado.text = "Selecciona primero una sala de la lista."
		return
	var indice := seleccion[0]
	if indice < 0 or indice >= _salas_recibidas.size():
		_estado.text = "La selección de sala ya no está disponible; actualiza la lista."
		return
	var sala: Dictionary = _salas_recibidas[indice]
	var codigo := str(sala.get("codigo", ""))
	if not _codigo_tiene_cuatro_digitos(codigo):
		_estado.text = "El directorio entregó un código de sala inválido."
		return
	NetworkManager.nombre_local = _nombre_piloto()
	_estado.text = "Resolviendo la sala seleccionada..."
	_cliente_directorio.obtener_sala(_url_directorio.text, codigo)

func _crear_sala_directa() -> void:
	NetworkManager.nombre_local = _nombre_piloto()
	NetworkManager.rol_dron_local = _rol_seleccionado()
	NetworkManager.transporte = "ENet" if _transporte_directo.get_selected_id() == 1 else "WebSocket"
	var codigo := _codigo_directo.text.strip_edges()
	var configuracion := {
		"escenario": _escenario_seleccionado(),
		"dificultad": _dificultad_seleccionada(),
		"max_jugadores": int(_max_jugadores.value),
		"puerto": int(_puerto_directo.value),
		"codigo": codigo,
	}
	if NetworkManager.crear_sala(configuracion):
		_estado.text = "Sala directa creada en el puerto %d." % int(_puerto_directo.value)

func _unirse_directamente() -> void:
	var codigo := _codigo_directo.text.strip_edges()
	if codigo.is_empty():
		_estado.text = "Ingresa el código de la sala directa."
		return
	NetworkManager.nombre_local = _nombre_piloto()
	NetworkManager.transporte = "ENet" if _transporte_directo.get_selected_id() == 1 else "WebSocket"
	NetworkManager.unirse_a_sala(
		_direccion_directa.text.strip_edges(),
		int(_puerto_directo.value),
		codigo
	)

func _actualizar_sala(codigo: String, jugadores_sala: Dictionary) -> void:
	if not is_instance_valid(_codigo_actual):
		return
	_codigo_actual.text = "Sala activa: %s" % (codigo if not codigo.is_empty() else "sin conexión")
	var ids: Array = jugadores_sala.keys()
	ids.sort()
	var lineas := PackedStringArray()
	var tactico_ocupado_por := ""
	var conteos_roles: Dictionary = {"cisterna": 0, "explorador": 0, "tactico": 0}
	for id_variant in ids:
		var datos: Dictionary = jugadores_sala[id_variant]
		var rol_dron := str(datos.get("rol_dron", "explorador"))
		conteos_roles[rol_dron] = int(conteos_roles.get(rol_dron, 0)) + 1
		if rol_dron == "tactico":
			tactico_ocupado_por = str(datos.get("nombre", "Piloto"))
		lineas.append(
			"%s — %s%s — %s — %d ms"
			% [
				str(datos.get("nombre", "Piloto")),
				_nombre_rol_dron(rol_dron),
				" (ANFITRIÓN)" if str(datos.get("rol", "")) == "anfitrion" else "",
				"LISTO" if bool(datos.get("listo", false)) else "ESPERANDO",
				int(datos.get("ping", 0)),
			]
		)
	_lista_jugadores.text = "PILOTOS CONECTADOS\n%s" % "\n".join(lineas)
	_roles_ocupados.text = "Ocupados: Cisterna %d · Explorador %d · Táctico %s" % [
		int(conteos_roles["cisterna"]),
		int(conteos_roles["explorador"]),
		tactico_ocupado_por if not tactico_ocupado_por.is_empty() else "libre",
	]
	_actualizar_selector_rol(jugadores_sala, tactico_ocupado_por)
	_boton_listo.disabled = codigo.is_empty() or not jugadores_sala.has(multiplayer.get_unique_id())
	_boton_iniciar.disabled = codigo.is_empty() or not NetworkManager.es_anfitrion_local() or NetworkManager.partida_iniciada
	if not codigo.is_empty():
		_estado.text = "Conectado a la sala."
	var jugador_local: Dictionary = jugadores_sala.get(multiplayer.get_unique_id(), {})
	_boton_listo.text = "CANCELAR LISTO" if bool(jugador_local.get("listo", false)) else "MARCAR LISTO"

func _al_actualizar_sala(codigo: String, jugadores_sala: Dictionary) -> void:
	_actualizar_sala(codigo, jugadores_sala)

func _al_actualizar_jugador(_id: int, _datos: Dictionary) -> void:
	_actualizar_sala(NetworkManager.codigo_sala, NetworkManager.jugadores)

func _al_desconectar_jugador(_id: int) -> void:
	_actualizar_sala(NetworkManager.codigo_sala, NetworkManager.jugadores)

func _alternar_listo() -> void:
	if not NetworkManager.establecer_listo(not _jugador_local_listo()):
		_estado.text = "No fue posible cambiar el estado de listo."

func _jugador_local_listo() -> bool:
	var jugador: Dictionary = NetworkManager.jugadores.get(multiplayer.get_unique_id(), {})
	return bool(jugador.get("listo", false))

func _iniciar_partida() -> void:
	if not NetworkManager.iniciar_partida():
		_estado.text = "No se pudo iniciar la partida."

func _salir_de_sala() -> void:
	NetworkManager.salir()
	_estado.text = "Saliste de la sala."

func _enviar_chat_desde_boton() -> void:
	_enviar_mensaje_chat(_chat_entrada.text)

func _enviar_mensaje_chat(texto: String) -> void:
	if not NetworkManager.enviar_chat(texto):
		_estado.text = "El mensaje está vacío, supera 160 caracteres o no estás en una sala."
		return
	_chat_entrada.clear()

func _al_recibir_chat(nombre: String, texto: String) -> void:
	_mensajes_chat.append("%s: %s" % [nombre, texto])
	if _mensajes_chat.size() > 30:
		_mensajes_chat.remove_at(0)
	_chat_historial.text = "\n".join(_mensajes_chat)
	_chat_historial.scroll_to_line(_chat_historial.get_line_count())

func _al_error_conexion(mensaje: String) -> void:
	_estado.text = mensaje

func _al_seleccionar_rol(indice: int) -> void:
	var rol_id := _rol_id_por_indice(indice)
	if not NetworkManager.seleccionar_rol_dron(rol_id):
		_estado.text = "No se pudo seleccionar el rol."

func _al_rol_rechazado(motivo: String) -> void:
	_estado.text = motivo
	var jugador_local: Dictionary = NetworkManager.jugadores.get(multiplayer.get_unique_id(), {})
	if not jugador_local.is_empty():
		_seleccionar_rol_visual(str(jugador_local.get("rol_dron", "explorador")))

func _actualizar_selector_rol(jugadores_sala: Dictionary, tactico_ocupado_por: String) -> void:
	var jugador_local: Dictionary = jugadores_sala.get(multiplayer.get_unique_id(), {})
	var rol_local := str(jugador_local.get("rol_dron", NetworkManager.rol_dron_local))
	_seleccionar_rol_visual(rol_local)
	var tactico_es_mio := rol_local == "tactico"
	_selector_rol.set_item_disabled(2, not tactico_ocupado_por.is_empty() and not tactico_es_mio)
	_selector_rol.disabled = not jugador_local.is_empty() and NetworkManager.partida_iniciada

func _seleccionar_rol_visual(rol_id: String) -> void:
	for indice in range(_selector_rol.get_item_count()):
		if _rol_id_por_indice(indice) == rol_id:
			_selector_rol.select(indice)
			return

func _rol_seleccionado() -> String:
	return _rol_id_por_indice(_selector_rol.get_selected_id())

func _rol_id_por_indice(indice: int) -> String:
	match indice:
		0:
			return "cisterna"
		2:
			return "tactico"
		_:
			return "explorador"

func _nombre_rol_dron(rol_id: String) -> String:
	match rol_id:
		"cisterna":
			return "Cisterna"
		"tactico":
			return "Táctico"
		_:
			return "Explorador"

func _volver_al_menu() -> void:
	_temporizador_lista.stop()
	NetworkManager.salir()
	var error_cambio := get_tree().change_scene_to_file(ESCENA_MENU_PRINCIPAL)
	if error_cambio != OK:
		push_error("No se pudo volver al menú principal (error %d)." % error_cambio)

func _nombre_piloto() -> String:
	var nombre := _nombre.text.strip_edges()
	return nombre if not nombre.is_empty() else "Piloto"

func _dificultad_seleccionada() -> String:
	match _dificultad.get_selected_id():
		0:
			return "baja"
		2:
			return "alta"
		_:
			return "media"

func _escenario_seleccionado() -> String:
	match _escenario.get_selected_id():
		1:
			return "campo_pajoso"
		2:
			return "interfase_urbana"
		_:
			return "aguarague"

func _codigo_tiene_cuatro_digitos(codigo: String) -> bool:
	if codigo.length() != 4:
		return false
	for caracter in codigo:
		var digito := caracter.unicode_at(0)
		if digito < 48 or digito > 57:
			return false
	return true
