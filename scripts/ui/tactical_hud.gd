extends CanvasLayer

signal incendio_controlado

const RETRATO_NORMAL := preload("res://imagenes_sargento/bien.jpg")
const RETRATO_CERCA := preload("res://imagenes_sargento/cerca.jpg")
const RETRATO_ENOJADO := preload("res://imagenes_sargento/enojado.png")
const RETRATO_CONTENTO := preload("res://imagenes_sargento/bien.jpg")

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

var flight_seconds: float = 192.0
var mission_seconds_left: float = 932.0
var fires_remaining: int = 0
var initial_fire_count: int = 0
var is_fire_defeated: bool = false
var post_mission_timer: float = 0.0
var drone_landed: bool = false
var fire_manager: Node
var speed_feedback_label: Label
var speed_feedback_tween: Tween

func _ready() -> void:
	set_hartman_dialogue("«Bienvenido a la operación, piloto. El incendio se extiende por la zona boscosa: localice cada árbol en llamas y mantenga el chorro de agua sobre ellos hasta apagarlos. Vigile su nivel de agua y vuelva a la laguna para recargar cuando sea necesario. Cuando todos los focos estén controlados, regrese y aterrice en la plataforma. Mantenga la calma y cuide la aeronave; cuento con usted.»", "near")
	fire_manager = get_tree().root.find_child("FireManager", true, false)
	if fire_manager:
		fire_manager.connect("fuegos_actualizados", _on_fuegos_actualizados)
		fire_manager.connect("incendio_controlado", _on_manager_incendio_controlado)
	speed_feedback_label = Label.new()
	speed_feedback_label.position = Vector2(520.0, 62.0)
	speed_feedback_label.add_theme_font_size_override("font_size", 22)
	speed_feedback_label.add_theme_color_override("font_color", Color("#d5e7a5"))
	speed_feedback_label.visible = false
	add_child(speed_feedback_label)

func _process(delta: float) -> void:
	flight_seconds += delta
	mission_seconds_left = max(0.0, mission_seconds_left - delta)
	
	var f_min = int(flight_seconds) / 60
	var f_sec = int(flight_seconds) % 60
	if lbl_time:
		lbl_time.text = "%02d:%02d\nTIEMPO" % [f_min, f_sec]
		
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
			set_hartman_dialogue("«¡PILOTO! ¡¿Qué parte de 'REGRESE AL HELIPUERTO' no entendió?! ¡Aterrice esa chatarra antes de que se quede sin combustible en el monte!»", "angry")

func update_telemetry(alt: float, spd: float, dist: float, water: float, max_water: float, near_water: bool, health: float) -> void:
	if lbl_alt:
		lbl_alt.text = "%d M\nALTITUD" % int(alt)
	if lbl_speed:
		lbl_speed.text = "%d M/S\nVELOCIDAD" % int(spd)
	if lbl_dist:
		lbl_dist.text = "%d M\nDIST. BASE" % int(dist)

	var water_pct = int((water / max_water) * 100.0) if max_water > 0 else 0
	update_water_level(water, max_water)
	if alert_label:
		if health <= 35.0:
			alert_label.text = "⚠ ALERTA CRÍTICA\nIntegridad: %d%%\n¡FUSELAJE DAÑADO!" % int(health)
		elif near_water and water < max_water:
			alert_label.text = "💧 SOBRE LA LAGUNA\n-> MANTENGA [E] PARA RECARGAR\nCarga: %d / %d L" % [int(water), int(max_water)]
		else:
			alert_label.text = "💧 AGUA: %d / %d L\n   [%s]\n🛡 CASCO: %d%%\n💨 Viento: 18 km/h" % [
				int(water), int(max_water),
				get_ascii_bar(water_pct),
				int(health)
			]

func update_water_level(current: float, maximum: float) -> void:
	if water_bar:
		water_bar.max_value = maximum
		water_bar.value = clampf(current, 0.0, maximum)

func notify_refilling(current: float, max_w: float) -> void:
	var pct = int((current / max_w) * 100.0)
	set_hartman_dialogue("«Recargando en la laguna: %d%% [%d/%d L]. ¡Mantenga [E]!»" % [pct, int(current), int(max_w)])

func get_ascii_bar(pct: int) -> String:
	var filled = pct / 10
	var bar = ""
	for i in range(10):
		bar += "■" if i < filled else "□"
	return bar

func set_hartman_dialogue(text: String, portrait_state: String = "normal") -> void:
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

func trigger_hartman_dialogue(text: String) -> void:
	set_hartman_dialogue(text)

func trigger_hartman_warning(reason: String) -> void:
	match reason:
		"idle":
			set_hartman_dialogue("«¡¿Se quedó dormido sobre los mandos?! ¡El fuego en Campo Pajoso sigue devorando vegetación! ¡Mueva esa aeronave!»", "angry")
		"no_source":
			set_hartman_dialogue("«¡Está fuera de la zona de recarga! Vuelva a la isla para llenar el tanque.»", "angry")
		"empty_tank":
			set_hartman_dialogue("«¡El depósito de agua está en CERO! Regrese a la isla para recargar.»", "angry")
		"wasted_water":
			set_hartman_dialogue("«¡¿Qué demonios está haciendo?! ¡Acaba de tirar litros de agua sobre el pasto limpio! ¡Esa agua es para el fuego, no para regar piedras!»", "angry")
		"collision_damage":
			set_hartman_dialogue("«¡CUIDADO INÚTIL! ¡Acaba de golpear la estructura del dron! Como destruya los rotores de la unidad se lo descontaré de su paga militar.»", "angry")
		"fire_damage":
			set_hartman_dialogue("«¡ALARMA TÉRMICA! ¡Está volando dentro de las llamas! ¡Gane altitud inmediatamente o el calor fundirá los motores del dron!»", "angry")
		"delay_rtb":
			set_hartman_dialogue("«¡Atención piloto! El incendio ya está sofocado. ¡Deje de pasear por el Chaco y regrese de inmediato a la plataforma militar!»", "angry")

func register_fire_stream_hit(_amount: float, is_extinguished: bool) -> void:
	_actualizar_contador_fuego()
	if not is_fire_defeated:
		set_hartman_dialogue(
			"«¡Foco neutralizado! Quedan %d fuegos. Mantenga el chorro sobre el siguiente árbol.»" % fires_remaining
			if is_extinguished
			else "«¡Chorro efectivo! Mantenga el clic izquierdo sobre un árbol en llamas.»"
		)

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

func _completar_mision_incendio() -> void:
	if is_fire_defeated:
		return
	is_fire_defeated = true
	post_mission_timer = 0.0
	incendio_controlado.emit()
	set_hartman_dialogue("«¡Incendio controlado! Todos los árboles objetivo están apagados. Regrese al helipuerto.»")
	if obj_checklist:
		obj_checklist.text = "✔ Reconocimiento aéreo\n✔ Recarga de agua\n✔ Sofocar todos los focos\n☐ Aterrizar en helipuerto militar"

func notify_speed_boost(speed: float) -> void:
	if not speed_feedback_label:
		return
	if speed_feedback_tween and speed_feedback_tween.is_running():
		speed_feedback_tween.kill()
	speed_feedback_label.text = "VELOCIDAD +  |  %.1f m/s" % speed
	speed_feedback_label.visible = true
	speed_feedback_label.modulate.a = 1.0
	speed_feedback_tween = create_tween()
	speed_feedback_tween.tween_property(speed_feedback_label, "modulate:a", 0.0, 1.4)

func _actualizar_contador_fuego() -> void:
	if not fire_ext_label:
		return
	var extinguished_count := maxi(0, initial_fire_count - fires_remaining)
	var percent := int(100.0 * float(extinguished_count) / float(initial_fire_count)) if initial_fire_count > 0 else 0
	var condition := "CONTROLADO" if fires_remaining == 0 and initial_fire_count > 0 else "CONTENIENDO"
	fire_ext_label.text = (
		"Area afectada:   18.7 ha\nPerimetro:       2.8 km\n"
		+ "Focos detectados: %d\nPropagacion:     %s\n" % [fires_remaining, condition]
		+ "Intensidad:      %s\n%% Extincion:     %d %%\nFuegos restantes: %d" % [
			"[□□□□] EXTINTO" if percent >= 100 else ("[■■□□] MEDIA" if percent >= 50 else "[■■■■] ALTA"),
			percent,
			fires_remaining
		]
	)
	fire_ext_label.text += " / %d" % initial_fire_count

func notify_successful_landing() -> void:
	if drone_landed:
		return
	drone_landed = true
	set_hartman_dialogue("«¡Misión Cumplida! Aeronave asegurada en plataforma. Ha salvado el sector de Campo Pajoso. Buen trabajo, piloto.»", "happy")
	if obj_checklist:
		obj_checklist.text = "✔ Reconocimiento aereo\n✔ Recarga de agua\n✔ Sofocar foco de fuego\n✔ Aterrizaje completado con exito"
