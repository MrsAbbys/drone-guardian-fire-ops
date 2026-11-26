extends CanvasLayer

signal incendio_controlado

const RETRATO_NORMAL := preload("res://imagenes_sargento/bien.jpg")
const RETRATO_CERCA := preload("res://imagenes_sargento/cerca.jpg")
const RETRATO_ENOJADO := preload("res://imagenes_sargento/enojado.png")
const RETRATO_CONTENTO := preload("res://imagenes_sargento/bien.jpg")
const TextosHartman := preload("res://scripts/ui/textos_hartman.gd")
const SCRIPT_MARCADORES_TERMICOS := preload("res://scripts/ui/thermal_grid_overlay.gd")
const SCRIPT_MINIMAPA := preload("res://scripts/ui/tactical_minimap.gd")
const SHADER_VISION_TERMICA := preload("res://drone-guardian-fire-ops-main/assets/shaders/thermal_vision.gdshader")
const BLOQUEO_GUIA_ALARMA_MS: int = 4000
const INTERVALO_MENSAJES_GUIA_MS: int = 2000
const TIPOS_PING: Array[String] = ["fuego", "agua", "peligro"]
const TEXTOS_ESCENA: Dictionary = {
	"TopBar/TitleBox/GameTitle": "HUD_GAME_TITLE",
	"TopBar/TitleBox/SectorLabel": "HUD_SECTOR_LABEL",
	"TopBar/GridData/DroneModel": "HUD_DRONE_MODEL",
	"TopBar/GridData/Signal": "HUD_TELEMETRY_STATUS",
	"TopBar/GridData/GPS": "HUD_GPS_STATUS",
	"WeatherPanel/Title": "HUD_WEATHER_TITLE",
	"FireStatePanel/Title": "HUD_FIRE_TITLE",
	"TacticalRadar/RadarTitle": "HUD_MAP_TITLE",
	"TacticalRadar/Legend": "HUD_MAP_LEGEND",
	"BottomBar/CamerasBox/CamHeader": "HUD_CAMERA_TITLE",
	"BottomBar/CamerasBox/BtnRow/BtnRGB": "HUD_CAMERA_RGB",
	"BottomBar/CamerasBox/BtnRow/BtnThermal": "HUD_CAMERA_THERMAL",
	"BottomBar/CamerasBox/BtnRow/BtnRecon": "HUD_CAMERA_RECON",
	"BottomBar/CamerasBox/CamInfo": "HUD_CAMERA_INFO",
	"BottomBar/HartmanBox/PixelArtPortrait/PortraitLabel": "HUD_HARTMAN_PORTRAIT",
	"BottomBar/HartmanBox/NameTag": "HUD_HARTMAN_NAME",
	"BottomBar/MissionObjectives/ObjTitle": "HUD_OBJECTIVES_TITLE",
	"BottomBar/AlertsBox/AlertTitle": "HUD_ALERTS_TITLE",
	"BottomBar/TimerBox/TimerTitle": "HUD_TIMER_TITLE",
	"BottomBar/TimerBox/BtnRTL": "HUD_RETURN_TO_BASE",
}

var textos_hartman = TextosHartman.new()
@onready var lbl_alt: Label = $TopBar/GridData/AltVal
@onready var lbl_speed: Label = $TopBar/GridData/SpeedVal
@onready var lbl_dist: Label = $TopBar/GridData/DistVal
@onready var lbl_time: Label = $TopBar/GridData/TimeVal
@onready var lbl_timer_bottom: Label = $BottomBar/TimerBox/TimeLeftVal
@onready var dialogue_text: Label = $BottomBar/HartmanBox/DialogueText
@onready var fire_ext_label: Label = $FireStatePanel/FireData
@onready var obj_checklist: Label = $BottomBar/MissionObjectives/ObjList
@onready var alert_label: Label = $BottomBar/AlertsBox/AlertList
@onready var water_bar: ProgressBar = $BottomBar/AlertsBox/WaterBar
@onready var hartman_portrait: TextureRect = $BottomBar/HartmanBox/PixelArtPortrait
@onready var detalles_meteorologia: Label = $WeatherPanel/Details

var flight_seconds: float = 192.0
var mission_seconds_left: float = 932.0
var fires_remaining: int = 0
var initial_fire_count: int = 0
var is_fire_defeated: bool = false
var is_mission_failed: bool = false
var post_mission_timer: float = 0.0
var drone_landed: bool = false
var fire_manager: Node
var speed_feedback_label: Label
var alcance_chorro_label: Label
var speed_feedback_tween: Tween
var capa_punteria: Control
var reticula_punteria: Label
var distancia_punteria_label: Label
var punto_impacto_punteria: ColorRect
var flecha_punteria: Label
var ultimo_mensaje_guia: String = ""
var ultima_guia_ms: int = -10000
var ultima_alarma_ms: int = -10000
var ultima_advertencia_desperdicio: String = ""
var ultima_advertencia_desperdicio_ms: int = -10000
var guia_visible_hasta_ms: int = -10000
var ultima_clave_dialogo_hartman: String = ""
var indicador_viento: PanelContainer
var flecha_viento: Label
var texto_viento: Label
var aviso_viento: Label
var _viento_direccion: Vector2 = Vector2.RIGHT
var _viento_velocidad: float = 0.0
var _aviso_viento_direccion: Vector2 = Vector2.RIGHT
var _aviso_viento_velocidad: float = 0.0
var _aviso_viento_segundos: float = 0.0
var _tiempo_parpadeo_viento: float = 0.0
var _rol_local: StringName = &""
var _vision_termica_restante: float = 0.0
var _marca_objetivo_posicion: Vector3 = Vector3.ZERO
var _marca_objetivo_hasta_ms: int = 0
var _capa_vision_termica: ColorRect
var _marcadores_termicos: Control
var _material_vision_termica: ShaderMaterial
var _etiqueta_rol: Label
var _etiqueta_marca_objetivo: Label
var _alerta_objetivo_critico: Label
var _flecha_objetivo_critico: Label
var _dron_local_objetivo: Node3D
var _objetivo_critico_actual: Dictionary = {}
var _objetivos_criticos_estado: Dictionary = {}
var _tiempo_parpadeo_objetivo: float = 0.0
var _texto_resumen_objetivos: String = ""
var _escuadron_panel: PanelContainer
var _escuadron_lista: VBoxContainer
var _filas_escuadron: Dictionary = {}
var _firma_escuadron: String = ""
var _etiquetas_aliados: Dictionary = {}
var _pings_tacticos: Array[Dictionary] = []
var _indice_tipo_ping: int = 0
var _indicador_ping: Label
var _panel_eventos: PanelContainer
var _texto_eventos: Label
var _eventos: Array[String] = []
var _panel_marcador_final: PanelContainer
var _texto_marcador_final: Label
var _menu_pausa: Control
var _menu_pausa_abierto: bool = false
var _pauso_simulacion: bool = false
var _temporizador_interfaz_cooperativa: Timer
var _viento_inicializado: bool = false
var _ultimo_evento_viento_ms: int = 0

func _ready() -> void:
	_traducir_textos_escena()
	_decir_hartman("bienvenida", "near")
	FireGridServer.viento_cambiado.connect(_al_cambiar_viento)
	FireGridServer.viento_proximo.connect(_al_anunciar_viento)
	FireGridServer.objetivo_critico_amenazado.connect(_al_objetivo_critico_amenazado)
	FireGridServer.objetivo_critico_perdido.connect(_al_objetivo_critico_perdido)
	FireGridServer.objetivos_criticos_actualizados.connect(_al_resultado_objetivos_criticos)
	NetworkManager.objetivo_critico_recibido.connect(_al_objetivo_critico_recibido_por_red)
	NetworkManager.objetivos_criticos_finales_recibidos.connect(_al_resultado_objetivos_criticos_por_red)
	NetworkManager.ping_tactico_recibido.connect(_al_recibir_ping_tactico)
	NetworkManager.evento_tactico_recibido.connect(_al_recibir_evento_tactico)
	NetworkManager.marcador_final_recibido.connect(_mostrar_marcador_final)
	fire_manager = get_tree().root.find_child("FireManager", true, false)
	if fire_manager:
		fire_manager.connect("fuegos_actualizados", _on_fuegos_actualizados)
		fire_manager.connect("incendio_controlado", _on_manager_incendio_controlado)
		fire_manager.connect("incendio_descontrolado", _on_manager_incendio_descontrolado)
	_crear_vision_termica()
	speed_feedback_label = Label.new()
	speed_feedback_label.position = Vector2(520.0, 62.0)
	speed_feedback_label.add_theme_font_size_override("font_size", 22)
	speed_feedback_label.add_theme_color_override("font_color", Color("#d5e7a5"))
	speed_feedback_label.visible = false
	add_child(speed_feedback_label)
	alcance_chorro_label = Label.new()
	alcance_chorro_label.text = tr("HUD_OUT_OF_RANGE")
	alcance_chorro_label.position = Vector2(520.0, 91.0)
	alcance_chorro_label.add_theme_font_size_override("font_size", 14)
	alcance_chorro_label.add_theme_color_override("font_color", Color("#ff684f"))
	alcance_chorro_label.visible = false
	add_child(alcance_chorro_label)
	_crear_interfaz_punteria()
	_crear_indicador_viento()
	_crear_indicadores_rol()
	_crear_indicador_objetivo_critico()
	_crear_interfaz_cooperativa()
	_crear_menu_pausa()
	var viento_actual := FireGridServer.obtener_viento()
	_al_cambiar_viento(
		FireGridServer.obtener_direccion_viento(),
		viento_actual.length()
	)

func _traducir_textos_escena() -> void:
	for ruta in TEXTOS_ESCENA:
		var control := get_node_or_null(str(ruta)) as Control
		if not is_instance_valid(control):
			push_error("No se encontró el texto del HUD en la ruta %s." % ruta)
			continue
		control.set("text", tr(str(TEXTOS_ESCENA[ruta])))

func _process(delta: float) -> void:
	if _pauso_simulacion:
		return
	_actualizar_pings_tacticos()
	_actualizar_alerta_objetivo_critico(delta)
	if _rol_local == &"tactico":
		_actualizar_etiqueta_rol()
	if _vision_termica_restante > 0.0:
		_vision_termica_restante = maxf(_vision_termica_restante - delta, 0.0)
		if _vision_termica_restante <= 0.0:
			_capa_vision_termica.visible = false
			_material_vision_termica.set_shader_parameter("thermal_enabled", false)
	if Time.get_ticks_msec() >= _marca_objetivo_hasta_ms:
		_etiqueta_marca_objetivo.visible = false
	else:
		_actualizar_posicion_marca_objetivo()
	flight_seconds += delta
	mission_seconds_left = max(0.0, mission_seconds_left - delta)
	if _aviso_viento_segundos > 0.0:
		_aviso_viento_segundos = maxf(0.0, _aviso_viento_segundos - delta)
		_tiempo_parpadeo_viento += delta
		aviso_viento.text = tr("HUD_WIND_CHANGE_IN") % [
			ceili(_aviso_viento_segundos), _punto_cardinal(_aviso_viento_direccion)
		]
		aviso_viento.modulate.a = 0.35 + absf(sin(_tiempo_parpadeo_viento * 5.0)) * 0.65
		aviso_viento.visible = _aviso_viento_segundos > 0.0
	else:
		aviso_viento.visible = false
	
	var f_min = int(flight_seconds) / 60
	var f_sec = int(flight_seconds) % 60
	if lbl_time:
		lbl_time.text = "%02d:%02d\n%s" % [f_min, f_sec, tr("HUD_TIME")]
		
	var m_min = int(mission_seconds_left) / 60
	var m_sec = int(mission_seconds_left) % 60
	if lbl_timer_bottom:
		lbl_timer_bottom.text = "%02d:%02d" % [m_min, m_sec]

	# Si la misión ya acabó y el dron sigue dando vueltas en lugar de aterrizar
	if is_fire_defeated and not drone_landed:
		post_mission_timer += delta
		if post_mission_timer >= 12.0 and post_mission_timer < 12.2:
			trigger_hartman_warning("delay_rtb")
		elif post_mission_timer >= 24.0 and post_mission_timer < 24.2:
			_decir_hartman("regreso_urgente", "angry")

func _unhandled_input(event: InputEvent) -> void:
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_ESCAPE
	):
		_alternar_menu_pausa()
		get_viewport().set_input_as_handled()
		return
	if _menu_pausa_abierto:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_G:
		_indice_tipo_ping = (_indice_tipo_ping + 1) % TIPOS_PING.size()
		_colocar_ping_tactico()
	elif (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_MIDDLE
	):
		_colocar_ping_tactico()

func update_telemetry(alt: float, spd: float, dist: float, water: float, max_water: float, near_water: bool, health: float) -> void:
	if lbl_alt:
		lbl_alt.text = "%d M\n%s" % [int(alt), tr("HUD_ALTITUDE")]
	if lbl_speed:
		lbl_speed.text = "%d M/S\n%s" % [int(spd), tr("HUD_SPEED")]
	if lbl_dist:
		lbl_dist.text = "%d M\n%s" % [int(dist), tr("HUD_BASE_DISTANCE")]

	var water_pct = int((water / max_water) * 100.0) if max_water > 0 else 0
	update_water_level(water, max_water)
	if alert_label:
		if health <= 35.0:
			alert_label.text = tr("HUD_CRITICAL_DAMAGE") % int(health)
		elif near_water and water < max_water:
			alert_label.text = tr("HUD_REFILLING") % [int(water), int(max_water)]
		else:
			alert_label.text = tr("HUD_WATER_HEALTH") % [
				int(water), int(max_water), get_ascii_bar(water_pct), int(health)
			]

func update_water_level(current: float, maximum: float) -> void:
	if water_bar:
		water_bar.max_value = maximum
		water_bar.value = clampf(current, 0.0, maximum)

func notify_refilling(_current: float, _max_w: float) -> void:
	if ultima_clave_dialogo_hartman != "recargando":
		_decir_hartman("recargando")

func get_ascii_bar(pct: int) -> String:
	var filled = pct / 10
	var bar = ""
	for i in range(10):
		bar += "■" if i < filled else "□"
	return bar

func set_hartman_dialogue(text: String, portrait_state: String = "normal") -> void:
	ultima_clave_dialogo_hartman = ""
	if dialogue_text:
		dialogue_text.text = text
	if hartman_portrait:
		match portrait_state:
			"angry":
				hartman_portrait.texture = RETRATO_ENOJADO
			"near":
				hartman_portrait.texture = RETRATO_CERCA
			"happy":
				hartman_portrait.texture = RETRATO_CONTENTO
			_:
				hartman_portrait.texture = RETRATO_NORMAL

func _decir_hartman(clave: String, portrait_state: String = "normal", parametros: Dictionary = {}) -> String:
	var mensaje: String = textos_hartman.obtener(clave, parametros)
	if mensaje.is_empty():
		return ""
	set_hartman_dialogue(mensaje, portrait_state)
	ultima_clave_dialogo_hartman = clave
	return mensaje

func trigger_hartman_dialogue(text: String) -> void:
	set_hartman_dialogue(text)

func trigger_hartman_warning(reason: String, causa: String = "") -> void:
	if reason in ["empty_tank", "fire_damage", "delay_rtb"]:
		ultima_alarma_ms = Time.get_ticks_msec()
	if reason == "spray_out_of_range":
		if Time.get_ticks_msec() - ultima_alarma_ms < BLOQUEO_GUIA_ALARMA_MS:
			return
		_decir_hartman("fuera_de_alcance_antes_disparo", "near")
		return
	if reason == "wasted_water":
		if not causa.is_empty():
			var ahora_ms := Time.get_ticks_msec()
			if (
				causa == ultima_advertencia_desperdicio
				and ahora_ms - ultima_advertencia_desperdicio_ms < BLOQUEO_GUIA_ALARMA_MS
			):
				return
			ultima_advertencia_desperdicio = causa
			ultima_advertencia_desperdicio_ms = ahora_ms
	match reason:
		"idle":
			_decir_hartman("inactividad", "angry")
		"no_source":
			_decir_hartman("sin_fuente", "angry")
		"empty_tank":
			_decir_hartman("tanque_vacio", "angry")
		"wasted_water":
			match causa:
				"fuera_de_alcance":
					_decir_hartman("desperdicio_fuera_de_alcance", "angry")
				"punto_muy_bajo":
					_decir_hartman("desperdicio_punto_muy_bajo", "angry")
				"punto_muy_alto":
					_decir_hartman("desperdicio_punto_muy_alto", "angry")
				"desviado_lateral":
					_decir_hartman("desperdicio_desviado_lateral", "angry")
				_:
					_decir_hartman("desperdicio_pasto_limpio", "angry")
		"collision_damage":
			_decir_hartman("danio_colision", "angry")
		"fire_damage":
			_decir_hartman("alarma_termica", "angry")
		"delay_rtb":
			_decir_hartman("demora_regreso", "angry")

func register_fire_stream_hit(_amount: float, is_extinguished: bool) -> void:
	_actualizar_contador_fuego()
	if (
		not is_extinguished
		and AjustesAyuda.nivel_ayuda == AjustesAyuda.AYUDA_ALTA
		and Time.get_ticks_msec() < guia_visible_hasta_ms
	):
		return
	if not is_fire_defeated:
		_decir_hartman("foco_neutralizado" if is_extinguished else "chorro_efectivo")

func register_fire_tree(tree: Node) -> void:
	if not tree.has_signal("fuego_apagado"):
		push_error("El árbol en llamas debe emitir la señal fuego_apagado.")
		return
	if not tree.is_connected("fuego_apagado", _on_tree_extinguished):
		tree.connect("fuego_apagado", _on_tree_extinguished)
	fires_remaining += 1
	initial_fire_count += 1
	_actualizar_contador_fuego()

func _on_tree_extinguished(_arbol: Node = null) -> void:
	fires_remaining = maxi(0, fires_remaining - 1)
	_actualizar_contador_fuego()
	if fires_remaining == 0 and initial_fire_count > 0:
		_completar_mision_incendio()

func _on_fuegos_actualizados(restantes: int, total: int) -> void:
	fires_remaining = restantes
	initial_fire_count = total
	_actualizar_contador_fuego()

func _on_manager_incendio_controlado() -> void:
	_completar_mision_incendio()

func _on_manager_incendio_descontrolado() -> void:
	if is_fire_defeated or is_mission_failed:
		return
	is_mission_failed = true
	_decir_hartman("incendio_descontrolado", "angry")
	if obj_checklist:
		obj_checklist.text = tr("HUD_MISSION_FAILED")
		_mostrar_resumen_objetivos_criticos(
			FireGridServer.obtener_resumen_objetivos_criticos(),
			FireGridServer.obtener_puntaje_objetivos(),
			FireGridServer.obtener_bono_objetivos()
		)

func _completar_mision_incendio() -> void:
	if is_fire_defeated or is_mission_failed:
		return
	is_fire_defeated = true
	post_mission_timer = 0.0
	incendio_controlado.emit()
	_decir_hartman("incendio_controlado")
	if obj_checklist:
		obj_checklist.text = tr("HUD_MISSION_CONTROLLED")
		_mostrar_resumen_objetivos_criticos(
			FireGridServer.obtener_resumen_objetivos_criticos(),
			FireGridServer.obtener_puntaje_objetivos(),
			FireGridServer.obtener_bono_objetivos()
		)

func notify_speed_boost(speed: float) -> void:
	if not speed_feedback_label:
		return
	if speed_feedback_tween and speed_feedback_tween.is_running():
		speed_feedback_tween.kill()
	speed_feedback_label.text = tr("HUD_SPEED_BOOST") % speed
	speed_feedback_label.visible = true
	speed_feedback_label.modulate.a = 1.0
	speed_feedback_tween = create_tween()
	speed_feedback_tween.tween_property(speed_feedback_label, "modulate:a", 0.0, 1.4)

func notificar_alcance_chorro(fuera_de_alcance: bool) -> void:
	if alcance_chorro_label:
		alcance_chorro_label.visible = (
			AjustesAyuda.nivel_ayuda == AjustesAyuda.AYUDA_ALTA
			and fuera_de_alcance
		)

func _actualizar_contador_fuego() -> void:
	if not fire_ext_label:
		return
	var extinguished_count := maxi(0, initial_fire_count - fires_remaining)
	var percent := int(100.0 * float(extinguished_count) / float(initial_fire_count)) if initial_fire_count > 0 else 0
	var condition := (
		tr("HUD_FIRE_UNCONTROLLED")
		if is_mission_failed
		else (tr("HUD_FIRE_CONTROLLED") if fires_remaining == 0 and initial_fire_count > 0 else tr("HUD_FIRE_CONTAINING"))
	)
	fire_ext_label.text = (
		tr("HUD_FIRE_SUMMARY")
		% [
			fires_remaining,
			condition,
			tr("HUD_FIRE_EXTINGUISHED")
			if percent >= 100
			else (tr("HUD_FIRE_MEDIUM") if percent >= 50 else tr("HUD_FIRE_HIGH")),
			percent,
			fires_remaining,
			initial_fire_count,
		]
	)

func notify_successful_landing() -> void:
	if drone_landed:
		return
	drone_landed = true
	AjustesAyuda.completar_primera_mision()
	_decir_hartman("aterrizaje_exitoso", "happy")
	if obj_checklist:
		obj_checklist.text = tr("HUD_MISSION_LANDED")
		if not _texto_resumen_objetivos.is_empty():
			obj_checklist.text += "\n" + _texto_resumen_objetivos

func actualizar_punteria(info: Dictionary, camara: Camera3D, nivel_ayuda: int) -> void:
	var ayuda_activa := nivel_ayuda != AjustesAyuda.AYUDA_NINGUNA
	capa_punteria.visible = ayuda_activa
	alcance_chorro_label.visible = (
		nivel_ayuda == AjustesAyuda.AYUDA_ALTA
		and info.get("estado", "SIN_OBJETIVO") == "FUERA_DE_ALCANCE"
	)
	flecha_punteria.visible = false
	if not ayuda_activa:
		return

	var estado := str(info.get("estado", "SIN_OBJETIVO"))
	var distancia := float(info.get("distancia", 0.0))
	var alcance := maxf(float(info.get("alcance_chorro", 0.1)), 0.1)
	var color_punteria := Color("#d8e6e8")
	if estado == "EN_BLANCO":
		color_punteria = Color("#58f28b")
	elif estado == "CERCA" or (estado == "FUERA_DE_ALCANCE" and distancia < alcance * 1.5):
		color_punteria = Color("#ffd34d")
	elif estado == "FUERA_DE_ALCANCE":
		color_punteria = Color("#ff584f")
	reticula_punteria.add_theme_color_override("font_color", color_punteria)
	punto_impacto_punteria.color = color_punteria

	var tamano_vista := get_viewport().get_visible_rect().size
	capa_punteria.size = tamano_vista
	var centro := tamano_vista * 0.5
	reticula_punteria.position = centro - Vector2(24.0, 28.0)
	distancia_punteria_label.position = centro + Vector2(24.0, 6.0)
	var punto_impacto: Vector3 = info.get("punto_impacto", Vector3.ZERO)
	if camara.is_position_behind(punto_impacto):
		punto_impacto_punteria.visible = false
	else:
		var posicion_punto := camara.unproject_position(punto_impacto)
		punto_impacto_punteria.position = posicion_punto - Vector2(4.0, 4.0)
		punto_impacto_punteria.visible = true

	var objetivo: Variant = info.get("objetivo")
	if not is_instance_valid(objetivo):
		distancia_punteria_label.visible = false
		return
	distancia_punteria_label.text = "%.0f m" % distancia
	distancia_punteria_label.visible = true
	var posicion_objetivo: Vector3 = info.get("posicion_objetivo", Vector3.ZERO)
	var posicion_proyectada := camara.unproject_position(posicion_objetivo)
	var fuera_de_vista := (
		camara.is_position_behind(posicion_objetivo)
		or not Rect2(Vector2.ZERO, tamano_vista).has_point(posicion_proyectada)
	)
	if nivel_ayuda < AjustesAyuda.AYUDA_BAJA and fuera_de_vista:
		_posicionar_flecha_punteria(posicion_proyectada, tamano_vista, camara.is_position_behind(posicion_objetivo))
		flecha_punteria.add_theme_color_override("font_color", color_punteria)
		flecha_punteria.visible = true

func guia_puntería(info: Dictionary) -> void:
	if AjustesAyuda.nivel_ayuda != AjustesAyuda.AYUDA_ALTA or is_fire_defeated:
		return
	if float(info.get("agua_actual", 0.0)) <= 0.0:
		return
	if info.get("estado", "SIN_OBJETIVO") == "SIN_OBJETIVO":
		return
	if info.get("estado") == "EN_BLANCO" and bool(info.get("disparando", false)):
		return

	var ahora_ms := Time.get_ticks_msec()
	if ahora_ms - ultima_alarma_ms < BLOQUEO_GUIA_ALARMA_MS:
		return
	if ahora_ms - ultima_guia_ms < INTERVALO_MENSAJES_GUIA_MS:
		return

	var estado := str(info.get("estado", "SIN_OBJETIVO"))
	var error_horizontal := float(info.get("error_horizontal", 0.0))
	var error_vertical := float(info.get("error_vertical", 0.0))
	var clave_mensaje: String
	if absf(error_horizontal) > 4.0:
		clave_mensaje = "guia_izquierda" if error_horizontal < 0.0 else "guia_derecha"
	elif absf(error_vertical) > 4.0:
		clave_mensaje = "guia_subir" if error_vertical > 0.0 else "guia_bajar"
	elif estado == "FUERA_DE_ALCANCE":
		clave_mensaje = "guia_acercarse"
	elif estado == "EN_BLANCO":
		clave_mensaje = "guia_en_blanco"
	else:
		clave_mensaje = "guia_correccion"

	var mensaje: String = textos_hartman.obtener(clave_mensaje)
	if mensaje == ultimo_mensaje_guia and ahora_ms - ultima_guia_ms < BLOQUEO_GUIA_ALARMA_MS:
		return
	set_hartman_dialogue(mensaje, "near")
	ultimo_mensaje_guia = mensaje
	ultima_guia_ms = ahora_ms
	guia_visible_hasta_ms = ahora_ms + INTERVALO_MENSAJES_GUIA_MS

func _crear_interfaz_punteria() -> void:
	capa_punteria = Control.new()
	capa_punteria.name = "CapaPunteria"
	capa_punteria.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	capa_punteria.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(capa_punteria)

	reticula_punteria = Label.new()
	reticula_punteria.text = "+"
	reticula_punteria.size = Vector2(48.0, 56.0)
	reticula_punteria.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reticula_punteria.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	reticula_punteria.add_theme_font_size_override("font_size", 40)
	reticula_punteria.mouse_filter = Control.MOUSE_FILTER_IGNORE
	capa_punteria.add_child(reticula_punteria)

	distancia_punteria_label = Label.new()
	distancia_punteria_label.size = Vector2(120.0, 24.0)
	distancia_punteria_label.add_theme_font_size_override("font_size", 14)
	distancia_punteria_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	distancia_punteria_label.visible = false
	capa_punteria.add_child(distancia_punteria_label)

	punto_impacto_punteria = ColorRect.new()
	punto_impacto_punteria.size = Vector2(8.0, 8.0)
	punto_impacto_punteria.mouse_filter = Control.MOUSE_FILTER_IGNORE
	capa_punteria.add_child(punto_impacto_punteria)

	flecha_punteria = Label.new()
	flecha_punteria.text = "▲"
	flecha_punteria.size = Vector2(30.0, 30.0)
	flecha_punteria.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flecha_punteria.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	flecha_punteria.add_theme_font_size_override("font_size", 24)
	flecha_punteria.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flecha_punteria.visible = false
	capa_punteria.add_child(flecha_punteria)
	capa_punteria.visible = false

func _posicionar_flecha_punteria(posicion: Vector2, tamano_vista: Vector2, detras: bool) -> void:
	var centro := tamano_vista * 0.5
	var direccion := posicion - centro
	if detras:
		direccion = -direccion
	if direccion.length_squared() < 0.001:
		direccion = Vector2.DOWN if detras else Vector2.UP
	direccion = direccion.normalized()
	var limites := tamano_vista * 0.5 - Vector2(36.0, 36.0)
	var escala_x := limites.x / absf(direccion.x) if absf(direccion.x) > 0.001 else INF
	var escala_y := limites.y / absf(direccion.y) if absf(direccion.y) > 0.001 else INF
	var posicion_flecha := centro + direccion * minf(escala_x, escala_y)
	flecha_punteria.position = posicion_flecha - flecha_punteria.size * 0.5
	flecha_punteria.rotation = direccion.angle() + PI * 0.5

func _exit_tree() -> void:
	if FireGridServer.viento_cambiado.is_connected(_al_cambiar_viento):
		FireGridServer.viento_cambiado.disconnect(_al_cambiar_viento)
	if FireGridServer.viento_proximo.is_connected(_al_anunciar_viento):
		FireGridServer.viento_proximo.disconnect(_al_anunciar_viento)
	if FireGridServer.objetivo_critico_amenazado.is_connected(_al_objetivo_critico_amenazado):
		FireGridServer.objetivo_critico_amenazado.disconnect(_al_objetivo_critico_amenazado)
	if FireGridServer.objetivo_critico_perdido.is_connected(_al_objetivo_critico_perdido):
		FireGridServer.objetivo_critico_perdido.disconnect(_al_objetivo_critico_perdido)
	if FireGridServer.objetivos_criticos_actualizados.is_connected(_al_resultado_objetivos_criticos):
		FireGridServer.objetivos_criticos_actualizados.disconnect(_al_resultado_objetivos_criticos)
	if NetworkManager.objetivo_critico_recibido.is_connected(_al_objetivo_critico_recibido_por_red):
		NetworkManager.objetivo_critico_recibido.disconnect(_al_objetivo_critico_recibido_por_red)
	if NetworkManager.objetivos_criticos_finales_recibidos.is_connected(_al_resultado_objetivos_criticos_por_red):
		NetworkManager.objetivos_criticos_finales_recibidos.disconnect(_al_resultado_objetivos_criticos_por_red)
	if NetworkManager.ping_tactico_recibido.is_connected(_al_recibir_ping_tactico):
		NetworkManager.ping_tactico_recibido.disconnect(_al_recibir_ping_tactico)
	if NetworkManager.evento_tactico_recibido.is_connected(_al_recibir_evento_tactico):
		NetworkManager.evento_tactico_recibido.disconnect(_al_recibir_evento_tactico)
	if NetworkManager.marcador_final_recibido.is_connected(_mostrar_marcador_final):
		NetworkManager.marcador_final_recibido.disconnect(_mostrar_marcador_final)
	for ping in _pings_tacticos:
		var etiqueta: Label = ping.get("etiqueta")
		var flecha: Label = ping.get("flecha")
		if is_instance_valid(etiqueta):
			etiqueta.queue_free()
		if is_instance_valid(flecha):
			flecha.queue_free()

func registrar_dron_local(dron: Node3D) -> void:
	_dron_local_objetivo = dron

func _al_objetivo_critico_amenazado(objetivo: Resource) -> void:
	_registrar_evento("%s en peligro" % str(objetivo.get("nombre")))
	_actualizar_objetivo_critico(
		FireGridServer.obtener_datos_objetivo_critico(objetivo, "AMENAZADO")
	)

func _al_objetivo_critico_perdido(objetivo: Resource) -> void:
	_registrar_evento("%s perdida" % str(objetivo.get("nombre")))
	_actualizar_objetivo_critico(
		FireGridServer.obtener_datos_objetivo_critico(objetivo, "PERDIDO")
	)

func _al_objetivo_critico_recibido_por_red(datos: Dictionary) -> void:
	if str(datos.get("estado", "")) == "AMENAZADO":
		_registrar_evento("%s en peligro" % str(datos.get("nombre", "Objetivo crítico")))
	elif str(datos.get("estado", "")) == "PERDIDO":
		_registrar_evento("%s perdida" % str(datos.get("nombre", "Objetivo crítico")))
	_actualizar_objetivo_critico(datos)

func _actualizar_objetivo_critico(datos: Dictionary) -> void:
	var identificador := str(datos.get("identificador", ""))
	if identificador.is_empty():
		return
	_objetivos_criticos_estado[identificador] = datos.duplicate(true)
	_objetivo_critico_actual = datos.duplicate(true)
	_tiempo_parpadeo_objetivo = 0.0
	_actualizar_alerta_objetivo_critico(0.0)

func _actualizar_alerta_objetivo_critico(delta: float) -> void:
	if not is_instance_valid(_alerta_objetivo_critico) or _objetivo_critico_actual.is_empty():
		return
	var posicion_variant: Variant = _objetivo_critico_actual.get("posicion", Vector3.ZERO)
	if not posicion_variant is Vector3:
		_alerta_objetivo_critico.visible = false
		_flecha_objetivo_critico.visible = false
		return
	var posicion_objetivo: Vector3 = posicion_variant
	var estado_objetivo := str(_objetivo_critico_actual.get("estado", "AMENAZADO"))
	var nombre_objetivo := str(_objetivo_critico_actual.get("nombre", "Objetivo crítico"))
	var penalizacion := int(_objetivo_critico_actual.get("penalizacion", 0))
	var distancia := 0.0
	var texto_distancia := "-- m"
	if is_instance_valid(_dron_local_objetivo):
		distancia = _dron_local_objetivo.global_position.distance_to(posicion_objetivo)
		texto_distancia = "%.0f m" % distancia
	_alerta_objetivo_critico.text = (
		tr("HUD_CRITICAL_TARGET_LOST") % [nombre_objetivo, penalizacion, texto_distancia]
		if estado_objetivo == "PERDIDO"
		else tr("HUD_CRITICAL_TARGET_THREATENED") % [nombre_objetivo, texto_distancia]
	)
	_tiempo_parpadeo_objetivo += delta
	_alerta_objetivo_critico.modulate.a = 0.45 + absf(sin(_tiempo_parpadeo_objetivo * 6.0)) * 0.55
	_alerta_objetivo_critico.visible = true
	var tamano_vista := get_viewport().get_visible_rect().size
	_alerta_objetivo_critico.position = Vector2(
		maxf((tamano_vista.x - _alerta_objetivo_critico.size.x) * 0.5, 0.0),
		14.0
	)
	var camara: Camera3D = get_viewport().get_camera_3d()
	if not is_instance_valid(camara):
		_flecha_objetivo_critico.visible = false
		return
	var posicion_proyectada := camara.unproject_position(posicion_objetivo)
	var detras := camara.is_position_behind(posicion_objetivo)
	var dentro_de_vista := Rect2(Vector2.ZERO, tamano_vista).has_point(posicion_proyectada)
	if detras or not dentro_de_vista:
		var direccion := posicion_proyectada - tamano_vista * 0.5
		if detras:
			direccion = -direccion
		if direccion.length_squared() <= 0.001:
			direccion = Vector2.UP
		direccion = direccion.normalized()
		var limites := tamano_vista * 0.5 - Vector2(30.0, 30.0)
		var escala_x := limites.x / absf(direccion.x) if absf(direccion.x) > 0.001 else INF
		var escala_y := limites.y / absf(direccion.y) if absf(direccion.y) > 0.001 else INF
		posicion_proyectada = tamano_vista * 0.5 + direccion * minf(escala_x, escala_y)
		_flecha_objetivo_critico.rotation = direccion.angle() + PI * 0.5
	else:
		_flecha_objetivo_critico.rotation = 0.0
	_flecha_objetivo_critico.position = posicion_proyectada - _flecha_objetivo_critico.size * 0.5
	_flecha_objetivo_critico.visible = true

func _al_resultado_objetivos_criticos(resumen: Array, puntaje: int, bono: int) -> void:
	_mostrar_resumen_objetivos_criticos(resumen, puntaje, bono)

func _al_resultado_objetivos_criticos_por_red(resumen: Array, puntaje: int, bono: int) -> void:
	_mostrar_resumen_objetivos_criticos(resumen, puntaje, bono, true)

func _mostrar_resumen_objetivos_criticos(
	resumen: Array,
	puntaje: int,
	bono: int,
	autorizado_por_red: bool = false
) -> void:
	if not obj_checklist or resumen.is_empty():
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server() and not autorizado_por_red:
		return
	var lineas := PackedStringArray([tr("HUD_CRITICAL_OBJECTIVE_RESULT")])
	lineas.append(tr("HUD_OBJECTIVE_SCORE") % puntaje)
	if bono > 0:
		lineas.append(tr("HUD_NO_LOSS_BONUS") % bono)
	for dato: Variant in resumen:
		if not dato is Dictionary:
			continue
		var objetivo: Dictionary = dato
		var salvado := str(objetivo.get("estado", "")) == "SALVADO"
		lineas.append(
			("%s %s" % ["✔" if salvado else "✖", str(objetivo.get("nombre", tr("HUD_OBJECTIVE")))])
			+ (
				tr("HUD_PENALTY") % int(objetivo.get("penalizacion", 0))
				if not salvado
				else ""
			)
		)
	_texto_resumen_objetivos = "\n".join(lineas)
	obj_checklist.text += "\n" + _texto_resumen_objetivos

func _crear_indicador_objetivo_critico() -> void:
	_alerta_objetivo_critico = Label.new()
	_alerta_objetivo_critico.name = "AlertaObjetivoCritico"
	_alerta_objetivo_critico.size = Vector2(620.0, 34.0)
	_alerta_objetivo_critico.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_alerta_objetivo_critico.add_theme_font_size_override("font_size", 19)
	_alerta_objetivo_critico.add_theme_color_override("font_color", Color("#ff3028"))
	_alerta_objetivo_critico.add_theme_color_override("font_shadow_color", Color.BLACK)
	_alerta_objetivo_critico.add_theme_constant_override("shadow_offset_x", 2)
	_alerta_objetivo_critico.add_theme_constant_override("shadow_offset_y", 2)
	_alerta_objetivo_critico.visible = false
	add_child(_alerta_objetivo_critico)

	_flecha_objetivo_critico = Label.new()
	_flecha_objetivo_critico.name = "FlechaObjetivoCritico"
	_flecha_objetivo_critico.size = Vector2(36.0, 36.0)
	_flecha_objetivo_critico.text = "▲"
	_flecha_objetivo_critico.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flecha_objetivo_critico.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_flecha_objetivo_critico.add_theme_font_size_override("font_size", 28)
	_flecha_objetivo_critico.add_theme_color_override("font_color", Color("#ff3028"))
	_flecha_objetivo_critico.visible = false
	add_child(_flecha_objetivo_critico)

func _crear_interfaz_cooperativa() -> void:
	_escuadron_panel = PanelContainer.new()
	_escuadron_panel.name = "PanelEscuadron"
	_escuadron_panel.position = Vector2(12.0, 66.0)
	_escuadron_panel.custom_minimum_size = Vector2(220.0, 145.0)
	_aplicar_estilo_panel(_escuadron_panel, Color("#55d8ff"))
	add_child(_escuadron_panel)
	_escuadron_lista = VBoxContainer.new()
	_escuadron_lista.add_theme_constant_override("separation", 3)
	_escuadron_panel.add_child(_escuadron_lista)

	var titulo_escuadron := Label.new()
	titulo_escuadron.text = tr("HUD_SQUAD")
	titulo_escuadron.add_theme_color_override("font_color", Color("#7fe8ff"))
	titulo_escuadron.add_theme_font_size_override("font_size", 11)
	_escuadron_lista.add_child(titulo_escuadron)

	var radar: ColorRect = get_node_or_null("TacticalRadar/MapSim")
	if is_instance_valid(radar):
		var minimapa := SCRIPT_MINIMAPA.new() as Control
		minimapa.name = "MinimapaFireGrid"
		minimapa.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		radar.add_child(minimapa)
		for nombre_icono in ["FirePoint", "DroneIcon", "WaterIcon"]:
			var icono: CanvasItem = radar.get_node_or_null(nombre_icono) as CanvasItem
			if is_instance_valid(icono):
				icono.visible = false
		var leyenda := get_node_or_null("TacticalRadar/Legend") as Label
		if is_instance_valid(leyenda):
			leyenda.text = tr("HUD_FIREGRID_LEGEND")

	_indicador_ping = Label.new()
	_indicador_ping.name = "TipoPingActual"
	_indicador_ping.position = Vector2(12.0, 214.0)
	_indicador_ping.add_theme_font_size_override("font_size", 10)
	_indicador_ping.add_theme_color_override("font_color", Color("#ffe67a"))
	add_child(_indicador_ping)
	_actualizar_indicador_ping()

	_panel_eventos = PanelContainer.new()
	_panel_eventos.name = "RegistroEventos"
	_panel_eventos.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_panel_eventos.offset_left = 12.0
	_panel_eventos.offset_right = 290.0
	_panel_eventos.offset_top = -300.0
	_panel_eventos.offset_bottom = -180.0
	_aplicar_estilo_panel(_panel_eventos, Color("#ffc85a"))
	add_child(_panel_eventos)
	_texto_eventos = Label.new()
	_texto_eventos.name = "Eventos"
	_texto_eventos.add_theme_font_size_override("font_size", 10)
	_texto_eventos.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_texto_eventos.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_panel_eventos.add_child(_texto_eventos)

	_panel_marcador_final = PanelContainer.new()
	_panel_marcador_final.name = "MarcadorFinal"
	_panel_marcador_final.anchor_left = 0.5
	_panel_marcador_final.anchor_top = 0.5
	_panel_marcador_final.anchor_right = 0.5
	_panel_marcador_final.anchor_bottom = 0.5
	_panel_marcador_final.offset_left = -290.0
	_panel_marcador_final.offset_top = -165.0
	_panel_marcador_final.offset_right = 290.0
	_panel_marcador_final.offset_bottom = 165.0
	_aplicar_estilo_panel(_panel_marcador_final, Color("#ffd451"))
	_panel_marcador_final.visible = false
	add_child(_panel_marcador_final)
	_texto_marcador_final = Label.new()
	_texto_marcador_final.name = "ResultadosPorJugador"
	_texto_marcador_final.add_theme_font_size_override("font_size", 14)
	_texto_marcador_final.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel_marcador_final.add_child(_texto_marcador_final)

	_temporizador_interfaz_cooperativa = Timer.new()
	_temporizador_interfaz_cooperativa.name = "TemporizadorHUDCooperativo"
	_temporizador_interfaz_cooperativa.wait_time = 0.25
	_temporizador_interfaz_cooperativa.timeout.connect(_actualizar_interfaz_cooperativa)
	add_child(_temporizador_interfaz_cooperativa)
	_temporizador_interfaz_cooperativa.start()
	_actualizar_interfaz_cooperativa()

func _aplicar_estilo_panel(panel: PanelContainer, color_borde: Color) -> void:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.02, 0.06, 0.12, 0.94)
	estilo.border_color = color_borde
	estilo.set_border_width_all(1)
	estilo.set_content_margin_all(6.0)
	panel.add_theme_stylebox_override("panel", estilo)

func _crear_menu_pausa() -> void:
	_menu_pausa = Control.new()
	_menu_pausa.name = "MenuPausa"
	_menu_pausa.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_pausa.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu_pausa.process_mode = Node.PROCESS_MODE_ALWAYS
	_menu_pausa.visible = false
	add_child(_menu_pausa)

	var fondo := ColorRect.new()
	fondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fondo.color = Color(0.0, 0.02, 0.06, 0.82)
	fondo.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu_pausa.add_child(fondo)

	var centrador := CenterContainer.new()
	centrador.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centrador.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_pausa.add_child(centrador)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320.0, 0.0)
	_aplicar_estilo_panel(panel, Color("#55d8ff"))
	centrador.add_child(panel)

	var contenido := VBoxContainer.new()
	contenido.add_theme_constant_override("separation", 12)
	panel.add_child(contenido)

	var titulo := Label.new()
	titulo.text = tr("PAUSE_TITLE")
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_font_size_override("font_size", 22)
	titulo.add_theme_color_override("font_color", Color("#7fe8ff"))
	contenido.add_child(titulo)

	var continuar := Button.new()
	continuar.text = tr("PAUSE_RESUME")
	continuar.custom_minimum_size = Vector2(0.0, 40.0)
	continuar.pressed.connect(_cerrar_menu_pausa)
	contenido.add_child(continuar)

	var menu_principal := Button.new()
	menu_principal.text = tr("PAUSE_MAIN_MENU")
	menu_principal.custom_minimum_size = Vector2(0.0, 40.0)
	menu_principal.pressed.connect(_volver_al_menu_desde_pausa)
	contenido.add_child(menu_principal)

func _alternar_menu_pausa() -> void:
	if _menu_pausa_abierto:
		_cerrar_menu_pausa()
	else:
		_abrir_menu_pausa()

func _abrir_menu_pausa() -> void:
	if not is_instance_valid(_menu_pausa):
		return
	_menu_pausa_abierto = true
	_menu_pausa.visible = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pauso_simulacion = (
		not multiplayer.has_multiplayer_peer() and not get_tree().paused
	)
	if _pauso_simulacion:
		if is_instance_valid(_temporizador_interfaz_cooperativa):
			_temporizador_interfaz_cooperativa.stop()
		get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if is_instance_valid(_dron_local_objetivo):
		if _dron_local_objetivo.has_method("configurar_menu_pausa_abierto"):
			_dron_local_objetivo.call("configurar_menu_pausa_abierto", true)

func _cerrar_menu_pausa() -> void:
	if not _menu_pausa_abierto:
		return
	if _pauso_simulacion:
		get_tree().paused = false
		if is_instance_valid(_temporizador_interfaz_cooperativa):
			_temporizador_interfaz_cooperativa.start()
	_menu_pausa_abierto = false
	_pauso_simulacion = false
	_menu_pausa.visible = false
	if (
		is_instance_valid(_dron_local_objetivo)
		and _dron_local_objetivo.has_method("configurar_menu_pausa_abierto")
	):
		_dron_local_objetivo.call("configurar_menu_pausa_abierto", false)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	process_mode = Node.PROCESS_MODE_INHERIT

func _volver_al_menu_desde_pausa() -> void:
	_cerrar_menu_pausa()
	MissionResults.volver_al_menu()

func _actualizar_interfaz_cooperativa() -> void:
	_actualizar_lista_escuadron()
	_actualizar_etiquetas_aliados()

func _actualizar_lista_escuadron() -> void:
	var ids: Array = NetworkManager.jugadores.keys()
	if ids.is_empty() and is_instance_valid(_dron_local_objetivo):
		ids.append(_dron_local_objetivo.get_multiplayer_authority())
	ids.sort()
	var firma := ""
	for id_variant in ids:
		var id := int(id_variant)
		var datos: Dictionary = NetworkManager.jugadores.get(id, {})
		firma += "%d:%s:%s:%s;" % [
			id,
			str(datos.get("nombre", "")),
			str(datos.get("rol_dron", "")),
			str(datos.get("equipo", "")),
		]
	if firma != _firma_escuadron:
		for hijo in _escuadron_lista.get_children():
			if hijo != _escuadron_lista.get_child(0):
				_escuadron_lista.remove_child(hijo)
				hijo.queue_free()
		_filas_escuadron.clear()
		for id_variant in ids:
			var id := int(id_variant)
			var fila := HBoxContainer.new()
			fila.name = "Jugador_%d" % id
			fila.add_theme_constant_override("separation", 4)
			var icono := Label.new()
			icono.custom_minimum_size = Vector2(18.0, 18.0)
			icono.add_theme_font_size_override("font_size", 12)
			fila.add_child(icono)
			var texto := Label.new()
			texto.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			texto.add_theme_font_size_override("font_size", 9)
			fila.add_child(texto)
			_escuadron_lista.add_child(fila)
			_filas_escuadron[id] = {"icono": icono, "texto": texto}
		_firma_escuadron = firma

	for id_variant in ids:
		var id := int(id_variant)
		var datos: Dictionary = NetworkManager.jugadores.get(id, {})
		var dron := NetworkManager.obtener_dron(id)
		if not is_instance_valid(dron) and is_instance_valid(_dron_local_objetivo):
			if id == _dron_local_objetivo.get_multiplayer_authority():
				dron = _dron_local_objetivo
		var agua := -1.0
		var agua_maxima := 0.0
		var vida := -1.0
		var vida_maxima := 100.0
		if is_instance_valid(dron):
			agua = float(dron.get("agua_actual"))
			agua_maxima = maxf(float(dron.get("agua_maxima")), 0.0)
			vida = float(dron.get("current_health"))
			vida_maxima = maxf(float(dron.get("max_health")), 1.0)
		var porcentaje_agua := roundi(agua / agua_maxima * 100.0) if agua_maxima > 0.0 else -1
		var porcentaje_vida := roundi(vida / vida_maxima * 100.0) if vida >= 0.0 else -1
		var ping := int(datos.get("ping", 0))
		var nombre := str(datos.get("nombre", NetworkManager.nombre_local))
		var rol := str(datos.get("rol_dron", NetworkManager.rol_dron_local))
		var fila: Dictionary = _filas_escuadron.get(id, {})
		if fila.is_empty():
			continue
		var icono: Label = fila["icono"]
		var texto: Label = fila["texto"]
		icono.text = _icono_rol(rol)
		icono.add_theme_color_override("font_color", _color_equipo(str(datos.get("equipo", "Equipo %d" % id))))
		texto.text = "%s  A:%s%% V:%s%% %dms" % [
			nombre,
			str(porcentaje_agua) if porcentaje_agua >= 0 else "--",
			str(porcentaje_vida) if porcentaje_vida >= 0 else "--",
			ping,
		]

func _actualizar_etiquetas_aliados() -> void:
	var camara: Camera3D = get_viewport().get_camera_3d()
	var dron_local := _dron_local_objetivo
	if not is_instance_valid(camara) or not is_instance_valid(dron_local):
		for etiqueta_variant in _etiquetas_aliados.values():
			var etiqueta_oculta: Label = etiqueta_variant
			etiqueta_oculta.visible = false
		return
	var drones := NetworkManager.obtener_drones_por_id()
	var vigentes: Dictionary = {}
	var rectangulo := get_viewport().get_visible_rect()
	for id_variant in drones.keys():
		var id := int(id_variant)
		var dron: Variant = drones[id]
		if not is_instance_valid(dron) or not dron is Node3D or id == dron_local.get_multiplayer_authority():
			continue
		vigentes[id] = true
		var etiqueta: Label = _etiquetas_aliados.get(id)
		if not is_instance_valid(etiqueta):
			etiqueta = Label.new()
			etiqueta.name = "Aliado_%d" % id
			etiqueta.size = Vector2(180.0, 24.0)
			etiqueta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			etiqueta.add_theme_font_size_override("font_size", 12)
			etiqueta.add_theme_color_override("font_shadow_color", Color.BLACK)
			etiqueta.add_theme_constant_override("shadow_offset_x", 2)
			etiqueta.add_theme_constant_override("shadow_offset_y", 2)
			add_child(etiqueta)
			_etiquetas_aliados[id] = etiqueta
		var aliado := dron as Node3D
		var distancia := dron_local.global_position.distance_to(aliado.global_position)
		var posicion := aliado.global_position + Vector3.UP * 2.0
		var proyectada := camara.unproject_position(posicion)
		var visible := (
			distancia >= 15.0
			and not camara.is_position_behind(posicion)
			and rectangulo.has_point(proyectada)
		)
		etiqueta.visible = visible
		if visible:
			var datos: Dictionary = NetworkManager.jugadores.get(id, {})
			etiqueta.text = "%s · %.0f m" % [
				str(datos.get("nombre", aliado.get_meta("nombre_jugador", tr("HUD_ALLY")))),
				distancia,
			]
			etiqueta.add_theme_color_override(
				"font_color",
				_color_equipo(str(datos.get("equipo", "Equipo %d" % id)))
			)
			etiqueta.position = proyectada - etiqueta.size * 0.5
	for id_variant in _etiquetas_aliados.keys():
		var id := int(id_variant)
		if not vigentes.has(id):
			var etiqueta_eliminar: Label = _etiquetas_aliados[id]
			if is_instance_valid(etiqueta_eliminar):
				etiqueta_eliminar.queue_free()
			_etiquetas_aliados.erase(id)

func _colocar_ping_tactico() -> void:
	var camara: Camera3D = get_viewport().get_camera_3d()
	if not is_instance_valid(camara):
		return
	var origen_rayo := camara.project_ray_origin(get_viewport().get_visible_rect().size * 0.5)
	var direccion_rayo := camara.project_ray_normal(get_viewport().get_visible_rect().size * 0.5)
	var consulta := PhysicsRayQueryParameters3D.create(
		origen_rayo,
		origen_rayo + direccion_rayo * 800.0
	)
	if is_instance_valid(_dron_local_objetivo):
		consulta.exclude = [_dron_local_objetivo.get_rid()]
	var impacto := camara.get_world_3d().direct_space_state.intersect_ray(consulta)
	var posicion := origen_rayo + direccion_rayo * 100.0
	if impacto.has("position") and impacto["position"] is Vector3:
		posicion = impacto["position"]
	NetworkManager.enviar_ping_tactico(TIPOS_PING[_indice_tipo_ping], posicion)

func _actualizar_indicador_ping() -> void:
	if not is_instance_valid(_indicador_ping):
		return
	var etiquetas: Dictionary = {
		"fuego": tr("PING_FIRE"),
		"agua": tr("PING_WATER"),
		"peligro": tr("PING_DANGER"),
	}
	_indicador_ping.text = tr("HUD_PING_GUIDE") % str(etiquetas[TIPOS_PING[_indice_tipo_ping]])

func _al_recibir_ping_tactico(tipo: String, posicion: Vector3, emisor_id: int) -> void:
	var datos: Dictionary = NetworkManager.jugadores.get(emisor_id, {})
	var nombre := str(datos.get("nombre", tr("HUD_PILOT")))
	var etiquetas: Dictionary = {
		"fuego": tr("PING_FIRE"),
		"agua": tr("PING_WATER"),
		"peligro": tr("PING_DANGER"),
	}
	var etiqueta := Label.new()
	etiqueta.name = "Ping_%d" % Time.get_ticks_msec()
	etiqueta.size = Vector2(200.0, 26.0)
	etiqueta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	etiqueta.add_theme_font_size_override("font_size", 13)
	etiqueta.add_theme_color_override(
		"font_color",
		Color("#ff594b") if tipo == "peligro" else (Color("#55dcff") if tipo == "agua" else Color("#ffcf4f"))
	)
	add_child(etiqueta)
	var flecha := Label.new()
	flecha.size = Vector2(32.0, 32.0)
	flecha.text = "▲"
	flecha.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flecha.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	flecha.add_theme_font_size_override("font_size", 24)
	flecha.add_theme_color_override("font_color", etiqueta.get_theme_color("font_color"))
	flecha.visible = false
	add_child(flecha)
	_pings_tacticos.append({
		"tipo": tipo,
		"posicion": posicion,
		"emisor": nombre,
		"expira": Time.get_ticks_msec() + 8000,
		"etiqueta": etiqueta,
		"flecha": flecha,
	})
	_actualizar_pings_tacticos()

func _actualizar_pings_tacticos() -> void:
	var camara: Camera3D = get_viewport().get_camera_3d()
	var rectangulo := get_viewport().get_visible_rect()
	var ahora := Time.get_ticks_msec()
	var indice := _pings_tacticos.size() - 1
	while indice >= 0:
		var ping: Dictionary = _pings_tacticos[indice]
		var etiqueta: Label = ping["etiqueta"]
		var flecha: Label = ping["flecha"]
		if ahora >= int(ping["expira"]):
			if is_instance_valid(etiqueta):
				etiqueta.queue_free()
			if is_instance_valid(flecha):
				flecha.queue_free()
			_pings_tacticos.remove_at(indice)
			indice -= 1
			continue
		if not is_instance_valid(camara):
			etiqueta.visible = false
			flecha.visible = false
			indice -= 1
			continue
		var posicion: Vector3 = ping["posicion"]
		var proyectada := camara.unproject_position(posicion)
		var detras := camara.is_position_behind(posicion)
		var dentro := not detras and rectangulo.has_point(proyectada)
		var tipo := str(ping["tipo"])
		var nombre_tipo: String = {
			"fuego": tr("PING_FIRE_SHORT"),
			"agua": tr("PING_WATER_SHORT"),
			"peligro": tr("PING_DANGER"),
		}.get(tipo, tr("PING_UNKNOWN"))
		etiqueta.text = "%s · %s" % [nombre_tipo, str(ping["emisor"])]
		etiqueta.visible = dentro
		flecha.visible = not dentro
		if dentro:
			etiqueta.position = proyectada - etiqueta.size * 0.5
		else:
			var direccion := proyectada - rectangulo.size * 0.5
			if detras:
				direccion = -direccion
			if direccion.length_squared() < 0.001:
				direccion = Vector2.UP
			direccion = direccion.normalized()
			var limites := rectangulo.size * 0.5 - Vector2(28.0, 28.0)
			var escala_x := limites.x / absf(direccion.x) if absf(direccion.x) > 0.001 else INF
			var escala_y := limites.y / absf(direccion.y) if absf(direccion.y) > 0.001 else INF
			flecha.position = (
				rectangulo.size * 0.5 + direccion * minf(escala_x, escala_y)
				- flecha.size * 0.5
			)
			flecha.rotation = direccion.angle() + PI * 0.5
		indice -= 1

func _registrar_evento(texto: String) -> void:
	if not is_instance_valid(_texto_eventos):
		return
	_eventos.push_front(
		"%s  %s" % [Time.get_time_string_from_system(), _traducir_evento(texto)]
	)
	while _eventos.size() > 5:
		_eventos.pop_back()
	_texto_eventos.text = "\n".join(_eventos)

func _traducir_evento(texto: String) -> String:
	var indice_apagado := texto.find(" apagó ")
	if indice_apagado > 0:
		var nombre := texto.substr(0, indice_apagado)
		var celdas := texto.substr(indice_apagado + 7).to_int()
		return tr("HUD_EVENT_EXTINGUISHED") % [nombre, celdas]
	var partes_ping := texto.split(": ", false, 1)
	if partes_ping.size() == 2:
		var tipo_ping: String = {
			"Fuego aquí": tr("PING_FIRE"),
			"Necesito agua": tr("PING_WATER"),
			"Peligro": tr("PING_DANGER"),
		}.get(partes_ping[1], "")
		if not tipo_ping.is_empty():
			return tr("HUD_EVENT_PING") % [partes_ping[0], tipo_ping]
	return tr(texto)

func _al_recibir_evento_tactico(texto: String) -> void:
	_registrar_evento(texto)

func _mostrar_marcador_final(resultados: Array) -> void:
	var lineas := PackedStringArray([tr("HUD_FINAL_SCORE")])
	for dato: Variant in resultados:
		if not dato is Dictionary:
			continue
		var jugador: Dictionary = dato
		lineas.append(
			tr("HUD_PLAYER_SCORE_LINE")
			% [
				str(jugador.get("nombre", tr("HUD_PILOT"))),
				_traducir_rol(str(jugador.get("rol_dron", "explorador"))),
				int(jugador.get("celdas_apagadas", 0)),
				int(jugador.get("agua_usada", 0)),
				int(jugador.get("asistencias", 0)),
			]
		)
	_texto_marcador_final.text = "\n".join(lineas)
	_panel_marcador_final.visible = true

func _actualizar_indicador_ping_actual() -> void:
	_actualizar_indicador_ping()

func _icono_rol(rol: String) -> String:
	match rol:
		"cisterna":
			return "[C]"
		"tactico":
			return "[T]"
		_:
			return "[E]"

func _traducir_rol(rol: String) -> String:
	match rol:
		"cisterna":
			return tr("ROLE_TANKER")
		"tactico":
			return tr("ROLE_TACTICIAN")
		_:
			return tr("ROLE_SCOUT")

func _color_equipo(equipo: String) -> Color:
	var colores: Array[Color] = [
		Color("#54e6ff"),
		Color("#ffa943"),
		Color("#d47bff"),
		Color("#83e36a"),
		Color("#ff7190"),
		Color("#f2e85b"),
	]
	return colores[absi(equipo.hash()) % colores.size()]

func _crear_indicador_viento() -> void:
	indicador_viento = PanelContainer.new()
	indicador_viento.name = "IndicadorViento"
	indicador_viento.anchor_left = 0.5
	indicador_viento.anchor_right = 0.5
	indicador_viento.offset_left = -112.0
	indicador_viento.offset_top = 62.0
	indicador_viento.offset_right = 112.0
	indicador_viento.offset_bottom = 100.0
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.02, 0.06, 0.12, 0.92)
	estilo.border_color = Color(0.1, 0.8, 1.0, 0.8)
	estilo.set_border_width_all(1)
	estilo.set_content_margin_all(4.0)
	indicador_viento.add_theme_stylebox_override("panel", estilo)
	add_child(indicador_viento)

	var fila := HBoxContainer.new()
	fila.alignment = BoxContainer.ALIGNMENT_END
	fila.add_theme_constant_override("separation", 6)
	indicador_viento.add_child(fila)
	flecha_viento = Label.new()
	flecha_viento.text = "↑"
	flecha_viento.custom_minimum_size = Vector2(28.0, 26.0)
	flecha_viento.pivot_offset = Vector2(14.0, 13.0)
	flecha_viento.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flecha_viento.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	flecha_viento.add_theme_font_size_override("font_size", 22)
	fila.add_child(flecha_viento)
	texto_viento = Label.new()
	texto_viento.add_theme_font_size_override("font_size", 13)
	texto_viento.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fila.add_child(texto_viento)

	aviso_viento = Label.new()
	aviso_viento.name = "AvisoViento"
	aviso_viento.anchor_left = 0.5
	aviso_viento.anchor_right = 0.5
	aviso_viento.offset_left = -185.0
	aviso_viento.offset_top = 103.0
	aviso_viento.offset_right = 185.0
	aviso_viento.offset_bottom = 128.0
	aviso_viento.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	aviso_viento.add_theme_font_size_override("font_size", 14)
	aviso_viento.add_theme_color_override("font_color", Color("#ffd34d"))
	aviso_viento.visible = false
	add_child(aviso_viento)

func _crear_vision_termica() -> void:
	_capa_vision_termica = ColorRect.new()
	_capa_vision_termica.name = "VisionTermica"
	_capa_vision_termica.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_capa_vision_termica.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_capa_vision_termica.visible = false
	_capa_vision_termica.z_index = -1
	_material_vision_termica = ShaderMaterial.new()
	_material_vision_termica.shader = SHADER_VISION_TERMICA
	_capa_vision_termica.material = _material_vision_termica
	add_child(_capa_vision_termica)
	move_child(_capa_vision_termica, 0)

	_marcadores_termicos = SCRIPT_MARCADORES_TERMICOS.new() as Control
	_marcadores_termicos.name = "MarcadoresTermicos"
	_marcadores_termicos.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_marcadores_termicos.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marcadores_termicos.z_index = 1
	add_child(_marcadores_termicos)

func _crear_indicadores_rol() -> void:
	_etiqueta_rol = Label.new()
	_etiqueta_rol.name = "EstadoRol"
	_etiqueta_rol.position = Vector2(520.0, 132.0)
	_etiqueta_rol.add_theme_font_size_override("font_size", 13)
	_etiqueta_rol.add_theme_color_override("font_color", Color("#ffd34d"))
	_etiqueta_rol.visible = false
	add_child(_etiqueta_rol)

	_etiqueta_marca_objetivo = Label.new()
	_etiqueta_marca_objetivo.name = "MarcaObjetivo"
	_etiqueta_marca_objetivo.size = Vector2(220.0, 34.0)
	_etiqueta_marca_objetivo.add_theme_font_size_override("font_size", 16)
	_etiqueta_marca_objetivo.add_theme_color_override("font_color", Color("#ffdf56"))
	_etiqueta_marca_objetivo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_etiqueta_marca_objetivo.visible = false
	add_child(_etiqueta_marca_objetivo)

func configurar_rol_dron(rol: StringName) -> void:
	_rol_local = rol
	_etiqueta_rol.visible = rol == &"tactico"
	_actualizar_etiqueta_rol()

func activar_vision_termica(alcance: float, duracion: float) -> void:
	_vision_termica_restante = maxf(duracion, 0.0)
	_material_vision_termica.set_shader_parameter("alcance", maxf(alcance, 0.0))
	_material_vision_termica.set_shader_parameter("thermal_enabled", _vision_termica_restante > 0.0)
	_capa_vision_termica.visible = _vision_termica_restante > 0.0
	_marcadores_termicos.call("activar", alcance, duracion)

func mostrar_marca_objetivo(posicion: Vector3, nombre_piloto: String, duracion: float) -> void:
	_marca_objetivo_posicion = posicion
	_marca_objetivo_hasta_ms = Time.get_ticks_msec() + int(maxf(duracion, 0.0) * 1000.0)
	_etiqueta_marca_objetivo.text = tr("HUD_TARGET_MARKER") % nombre_piloto
	_etiqueta_marca_objetivo.visible = true
	_actualizar_posicion_marca_objetivo()

func _actualizar_posicion_marca_objetivo() -> void:
	var camara := get_viewport().get_camera_3d()
	if not is_instance_valid(camara):
		_etiqueta_marca_objetivo.visible = false
		return
	if camara.is_position_behind(_marca_objetivo_posicion):
		_etiqueta_marca_objetivo.visible = false
		return
	_etiqueta_marca_objetivo.position = (
		camara.unproject_position(_marca_objetivo_posicion)
		- _etiqueta_marca_objetivo.size * 0.5
	)

func _actualizar_etiqueta_rol() -> void:
	if _rol_local == &"tactico":
		if _aviso_viento_segundos > 0.0:
			_etiqueta_rol.text = tr("HUD_TACTIC_WIND_CHANGE") % [
				ceili(_aviso_viento_segundos), _punto_cardinal(_aviso_viento_direccion)
			]
		else:
			_etiqueta_rol.text = tr("HUD_TACTIC_CURRENT_WIND") % _punto_cardinal(_viento_direccion)

func _al_cambiar_viento(direccion: Vector2, velocidad: float) -> void:
	if direccion.length_squared() > 0.0:
		_viento_direccion = direccion.normalized()
	if is_instance_valid(flecha_viento):
		var direccion_pantalla := _viento_direccion
		flecha_viento.rotation = direccion_pantalla.angle() + PI * 0.5
		texto_viento.text = tr("HUD_WIND_SPEED") % [
			roundi(maxf(velocidad, 0.0) * 3.6),
			_punto_cardinal(_viento_direccion)
		]
	_viento_velocidad = maxf(velocidad, 0.0)
	_actualizar_meteorologia()
	_aviso_viento_segundos = 0.0
	if is_instance_valid(aviso_viento):
		aviso_viento.visible = false
	_actualizar_etiqueta_rol()

func _al_anunciar_viento(direccion: Vector2, velocidad: float, segundos: float) -> void:
	_aviso_viento_direccion = direccion.normalized()
	_aviso_viento_velocidad = maxf(velocidad, 0.0)
	_aviso_viento_segundos = maxf(segundos, 0.0)
	_tiempo_parpadeo_viento = 0.0
	_actualizar_meteorologia()
	_actualizar_etiqueta_rol()

func _punto_cardinal(direccion: Vector2) -> String:
	var angulo := atan2(-direccion.y, direccion.x)
	var indice := posmod(roundi(angulo / (PI / 4.0)), 8)
	var puntos: Array[String] = ["E", "NE", "N", "NO", "O", "SO", "S", "SE"]
	return puntos[indice]

func _actualizar_meteorologia() -> void:
	if not is_instance_valid(detalles_meteorologia):
		return
	var velocidad_mostrada := _aviso_viento_velocidad if _aviso_viento_segundos > 0.0 else _viento_velocidad
	var direccion_mostrada := _aviso_viento_direccion if _aviso_viento_segundos > 0.0 else _viento_direccion
	var velocidad_rafaga := _aviso_viento_velocidad if _aviso_viento_segundos > 0.0 else _viento_velocidad
	detalles_meteorologia.text = (
		tr("HUD_WEATHER_DETAILS")
		% [
			roundi(velocidad_mostrada * 3.6),
			_punto_cardinal(direccion_mostrada),
			roundi(velocidad_rafaga * 3.6),
		]
	)
