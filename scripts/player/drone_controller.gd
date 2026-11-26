extends CharacterBody3D

signal agua_cambiada(cantidad: float)

const INTERVALO_CACHE_PUNTERIA_MS: int = 100
const INTERVALO_GUIA_PUNTERIA: float = 0.5
const RETRASO_INTERPOLACION_MS: int = 100
const UMBRAL_CORRECCION_METROS: float = 3.0
const INTERVALO_INTENCION_AGUA: float = 0.1
const RUTAS_ROLES: Dictionary = {
	"cisterna": "res://data/roles/cisterna.tres",
	"explorador": "res://data/roles/explorador.tres",
	"tactico": "res://data/roles/tactico.tres",
}

@export_group("Vuelo")
@export var rol_predeterminado: DroneRole = preload("res://data/roles/explorador.tres")
@export var escala_dron: float = 1.0
@export var velocidad_base: float = 16.0
@export var bonificacion_sin_carga: float = 3.0
@export var incremento_velocidad_por_arbol: float = 0.6
@export var velocidad_maxima: float = 32.0
@export var velocidad_vertical: float = 9.0
@export var aceleracion: float = 10.0
@export var mouse_sensitivity: float = 0.0022

@export_group("Agua y sistemas")
@export var agua_maxima: float = 50.0:
	set(value):
		agua_maxima = maxf(value, 0.0)
		agua_actual = clampf(agua_actual, 0.0, agua_maxima)
@export var agua_actual: float = 0.0:
	set(value):
		agua_actual = clampf(value, 0.0, agua_maxima)
@export var gasto_por_segundo: float = 5.0
@export var recarga_por_segundo: float = 25.0
@export var potencia_chorro: float = 10.0
@export var alcance_chorro: float = 25.0:
	set(value):
		alcance_chorro = maxf(value, 0.1)
		_actualizar_visual_chorro()
@export var radio_chorro_base: float = 1.6
@export var ensanche_chorro: float = 0.06
@export var max_health: float = 100.0

var current_water: float:
	get:
		return agua_actual
	set(value):
		agua_actual = value

var water_tank_capacity: float:
	get:
		return agua_maxima

var current_health: float = 100.0
var is_near_water_source: bool = false
var is_refilling: bool = false
var is_discharging: bool = false
var is_mouse_captured: bool = true
var _menu_pausa_abierto: bool = false
var mouse_input: Vector2 = Vector2.ZERO
var idle_timer: float = 0.0
var collision_cooldown: float = 0.0
var wasted_water_time: float = 0.0
var flight_time: float = 0.0
var arboles_apagados: int = 0
var rol_actual: DroneRole

var velocidad: float:
	get:
		return minf(velocidad_base + arboles_apagados * incremento_velocidad_por_arbol, velocidad_maxima)

var velocidad_sin_carga: float:
	get:
		return minf(velocidad_base + bonificacion_sin_carga + arboles_apagados * incremento_velocidad_por_arbol, velocidad_maxima)

@onready var model: Node3D = $Modelo
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var pivot: Node3D = $CameraPivot
@onready var cam: Camera3D = $CameraPivot/SpringArm3D/Camera3D

var hud_node: CanvasLayer
var wildfire_node: Node3D
var helipad_node: Node3D
var fire_manager: Node
var rotors: Array[Node3D] = []
var tank_fills: Array[MeshInstance3D] = []
var refill_particles: GPUParticles3D
var water_stream: GPUParticles3D
var water_jet_core: MeshInstance3D
var apuntando_fuego_fuera_de_alcance: bool = false
var cache_info_punteria: Dictionary = {}
var objetivo_alcanzable_cache: Node3D
var ultima_actualizacion_punteria_ms: int = -100
var tiempo_guia_punteria: float = 0.0
var nozzle: Node3D
var blue_led: OmniLight3D
var red_led: OmniLight3D
var blue_led_lens: MeshInstance3D
var red_led_lens: MeshInstance3D
var empty_water_warning_sent: bool = false
var fov_tween: Tween
var fov_is_fast: bool = false
var base_camera_fov: float = 72.0
var speed_flash_timer: float = 0.0
var recarga_solicitada: bool = false
var apuntamiento_vertical: float = 0.0
var _entrada_red: Vector2 = Vector2.ZERO
var _entrada_vertical_red: float = 0.0
var _mouse_red: Vector2 = Vector2.ZERO
var _rociado_solicitado: bool = false
var _direccion_rociado: Vector3 = Vector3.FORWARD
var _recarga_solicitada_anterior: bool = false
var _rociado_solicitado_anterior: bool = false
var _tiempo_intencion_agua: float = 0.0
var _posicion_predicha: Vector3 = Vector3.ZERO
var _rotacion_predicha: Vector3 = Vector3.ZERO
var _apuntamiento_predicho: float = 0.0
var _historial_posiciones: Array[Vector3] = []
var _historial_rotaciones: Array[Vector3] = []
var _historial_tiempos_ms: PackedInt64Array = PackedInt64Array()
var _historial_apuntamientos: PackedFloat32Array = PackedFloat32Array()
var _tiempo_aplicar_agua: float = 0.0
var _agua_pendiente_rociado: float = 0.0
var _proxima_habilidad_ms: int = 0
var _proximo_retardante_ms: int = 0
var _tiempo_desperdicio_continuo: float = 0.0

func _ready() -> void:
	add_to_group("jugador")
	var es_autoridad_local := is_multiplayer_authority()
	if es_autoridad_local:
		mouse_sensitivity = GraphicsSettings.sensibilidad_mouse
		GraphicsSettings.sensibilidad_mouse_cambiada.connect(_al_cambiar_sensibilidad_mouse)
	current_health = max_health
	crear_modelo()
	crear_efectos()
	_cargar_rol_inicial()
	model.scale = Vector3.ONE * maxf(escala_dron, 0.1)
	_configurar_colision()
	_actualizar_visual_chorro()
	if es_autoridad_local:
		base_camera_fov = cam.fov
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		cam.current = true
		_posicion_predicha = global_position
		_rotacion_predicha = global_rotation
		_apuntamiento_predicho = pivot.rotation.x
	else:
		cam.current = false
		cam.get_parent().queue_free()
		$TacticalCrosshair.queue_free()
	if es_autoridad_local:
		hud_node = get_tree().root.find_child("TacticalHUD", true, false) as CanvasLayer
		wildfire_node = get_tree().root.find_child("WildfireZone", true, false) as Node3D
		helipad_node = get_tree().root.find_child("BaseHelipad", true, false) as Node3D
		fire_manager = get_tree().root.find_child("FireManager", true, false)
		if fire_manager and fire_manager.has_signal("arbol_apagado"):
			fire_manager.connect("arbol_apagado", _on_tree_extinguished)
		if hud_node and hud_node.has_method("registrar_dron_local"):
			hud_node.call_deferred("registrar_dron_local", self)
		if hud_node and hud_node.has_method("configurar_rol_dron") and is_instance_valid(rol_actual):
			hud_node.call_deferred("configurar_rol_dron", rol_actual.identificador)
	_actualizar_nivel_tanques()

func _cargar_rol_inicial() -> void:
	var rol_id := str(get_meta("rol_dron", "explorador"))
	var datos_jugador: Dictionary = NetworkManager.jugadores.get(get_multiplayer_authority(), {})
	if not datos_jugador.is_empty():
		rol_id = str(datos_jugador.get("rol_dron", rol_id))
	var ruta: String = str(RUTAS_ROLES.get(rol_id, ""))
	var recurso: Resource = ResourceLoader.load(ruta) if not ruta.is_empty() else null
	var rol := recurso as DroneRole
	if not is_instance_valid(rol):
		rol = rol_predeterminado
	if not is_instance_valid(rol):
		push_error("No se pudo cargar un recurso DroneRole para el dron.")
		return
	aplicar_rol(rol)

func aplicar_rol(rol: DroneRole) -> void:
	if not is_instance_valid(rol):
		push_error("No se puede aplicar un rol de dron nulo.")
		return
	rol_actual = rol
	agua_maxima = maxf(rol.agua_maxima, 0.0)
	if agua_actual <= 0.0:
		agua_actual = agua_maxima
	gasto_por_segundo = maxf(rol.gasto_por_segundo, 0.0)
	recarga_por_segundo = maxf(rol.recarga_por_segundo, 0.0)
	velocidad_base = maxf(rol.velocidad_base, 0.0)
	velocidad_maxima = maxf(rol.velocidad_maxima, velocidad_base)
	alcance_chorro = maxf(rol.alcance_chorro, 0.1)
	radio_chorro_base = maxf(rol.ancho_chorro * 0.5, 0.1)
	potencia_chorro = maxf(rol.potencia_chorro, 0.0)
	escala_dron = maxf(rol.escala_modelo, 0.1)
	if is_instance_valid(model):
		model.scale = Vector3.ONE * escala_dron
		_aplicar_color_equipo(rol.color_equipo)
		_configurar_colision()
	_actualizar_visual_chorro()

func _aplicar_color_equipo(color: Color) -> void:
	for nodo in model.find_children("*", "MeshInstance3D", true, false):
		var malla := nodo as MeshInstance3D
		if not is_instance_valid(malla) or not malla.material_override is StandardMaterial3D:
			continue
		var material := (malla.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
		material.albedo_color = material.albedo_color.lerp(color, 0.24)
		malla.material_override = material
	if is_instance_valid(blue_led):
		blue_led.light_color = color
	if is_instance_valid(blue_led_lens) and blue_led_lens.material_override is StandardMaterial3D:
		var material_lente := (blue_led_lens.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
		material_lente.albedo_color = color
		blue_led_lens.material_override = material_lente

func _al_cambiar_sensibilidad_mouse(valor: float) -> void:
	mouse_sensitivity = valor

func configurar_menu_pausa_abierto(abierto: bool) -> void:
	if not is_multiplayer_authority():
		return
	_menu_pausa_abierto = abierto
	is_mouse_captured = not abierto
	mouse_input = Vector2.ZERO
	Input.set_mouse_mode(
		Input.MOUSE_MODE_VISIBLE if abierto else Input.MOUSE_MODE_CAPTURED
	)

func _process(_delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or is_multiplayer_authority():
		return
	if multiplayer.is_server():
		return
	_interpolar_snapshot_remoto()
	_actualizar_animaciones(get_process_delta_time(), _entrada_red, _entrada_vertical_red)

func _al_sincronizar_dron() -> void:
	_actualizar_nivel_tanques()
	if not is_multiplayer_authority():
		return
	if multiplayer.is_server():
		pivot.rotation.x = apuntamiento_vertical
		return
	pivot.rotation.x = lerpf(_apuntamiento_predicho, apuntamiento_vertical, 0.1)
	_apuntamiento_predicho = pivot.rotation.x
	recibir_snapshot_autoritativo(
		global_position,
		global_rotation,
		velocity,
		Time.get_ticks_msec()
	)

func _configurar_colision() -> void:
	var body_shape := BoxShape3D.new()
	body_shape.size = Vector3(0.8, 0.3, 0.8) * maxf(escala_dron, 0.1)
	collision_shape.shape = body_shape

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if is_mouse_captured and event is InputEventMouseMotion:
		mouse_input = event.relative

func _physics_process(delta: float) -> void:
	var hay_red := multiplayer.has_multiplayer_peer()
	var es_servidor := hay_red and multiplayer.is_server()
	var autoridad_local := is_multiplayer_authority()
	if hay_red and not es_servidor and not autoridad_local:
		return

	var movimiento := Vector2.ZERO
	var vertical := 0.0
	var movimiento_mouse := Vector2.ZERO
	if autoridad_local and not _menu_pausa_abierto:
		movimiento = Input.get_vector(
			"drone_left", "drone_right", "drone_forward", "drone_backward"
		)
		vertical = Input.get_axis("drone_descend", "drone_ascend")
		if is_mouse_captured:
			movimiento_mouse = mouse_input
	if autoridad_local:
		mouse_input = Vector2.ZERO
	elif es_servidor:
		movimiento = _entrada_red
		vertical = _entrada_vertical_red
		movimiento_mouse = _mouse_red
		_mouse_red = Vector2.ZERO
	if autoridad_local and hay_red and not es_servidor:
		rpc_id(
			1,
			"_rpc_actualizar_entrada",
			movimiento,
			vertical,
			movimiento_mouse,
			mouse_sensitivity
		)

	_simular_vuelo(delta, movimiento, vertical, movimiento_mouse)
	if autoridad_local:
		_actualizar_fov_velocidad()
		_actualizar_recarga(delta, hay_red, es_servidor)
		if (
			not _menu_pausa_abierto
			and Input.is_action_just_pressed("drone_special")
		):
			_solicitar_habilidad_especial(hay_red, es_servidor)
		if (
			not _menu_pausa_abierto
			and Input.is_action_just_pressed("drone_retardant")
		):
			_solicitar_retardante(hay_red, es_servidor)
		if hay_red:
			_actualizar_disparo_multijugador(delta, es_servidor)
		else:
			_actualizar_disparo_solitario(delta)
		_actualizar_hud_local(delta)
	if es_servidor:
		_procesar_recarga_servidor(delta)
		if not autoridad_local:
			_actualizar_disparo_multijugador(delta, true)
	if es_servidor or not hay_red:
		_aplicar_dano_termico(delta)
		_comprobar_aterrizaje()
	if hay_red and autoridad_local:
		_posicion_predicha = global_position
		_rotacion_predicha = global_rotation

func _simular_vuelo(
	delta: float,
	input_vector: Vector2,
	vertical_input: float,
	entrada_mouse: Vector2
) -> void:
	flight_time += delta
	if entrada_mouse != Vector2.ZERO:
		rotate_y(-entrada_mouse.x * mouse_sensitivity)
		pivot.rotate_x(-entrada_mouse.y * mouse_sensitivity)
		pivot.rotation.x = clampf(pivot.rotation.x, deg_to_rad(-45.0), deg_to_rad(30.0))
	apuntamiento_vertical = pivot.rotation.x
	if is_multiplayer_authority():
		_apuntamiento_predicho = pivot.rotation.x
	var local_motion := Vector3(input_vector.x, 0.0, input_vector.y)
	var world_motion := (transform.basis * local_motion).normalized()
	var carga := agua_actual / agua_maxima if agua_maxima > 0.0 else 0.0
	var velocidad_actual := lerpf(velocidad_sin_carga, velocidad, carga)
	var target_horizontal := world_motion * velocidad_actual

	velocity.x = move_toward(velocity.x, target_horizontal.x, aceleracion * delta)
	velocity.z = move_toward(velocity.z, target_horizontal.z, aceleracion * delta)
	velocity.y = move_toward(velocity.y, vertical_input * velocidad_vertical, aceleracion * delta)
	move_and_slide()
	_actualizar_animaciones(delta, input_vector, vertical_input)
	if is_multiplayer_authority() or not multiplayer.has_multiplayer_peer():
		obtener_info_puntería()
		if input_vector == Vector2.ZERO and vertical_input == 0.0:
			idle_timer += delta
			if idle_timer > 10.0 and idle_timer < 10.2 and hud_node:
				hud_node.trigger_hartman_warning("idle")
		else:
			idle_timer = 0.0
	if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		collision_cooldown = maxf(0.0, collision_cooldown - delta)
		if get_slide_collision_count() > 0 and collision_cooldown <= 0.0 and velocity.length() > 6.0:
			current_health = maxf(0.0, current_health - clampf(velocity.length() * 1.5, 5.0, 30.0))
			collision_cooldown = 1.0
			if hud_node:
				hud_node.trigger_hartman_warning("collision_damage")

func _actualizar_animaciones(delta: float, movement: Vector2, vertical_input: float) -> void:
	var moving := movement.length_squared() > 0.01 or absf(vertical_input) > 0.01
	var rotor_speed := 32.0 if moving else 14.0
	for index in range(rotors.size()):
		var direction := 1.0 if index % 2 == 0 else -1.0
		rotors[index].rotate_y(rotor_speed * direction * delta)

	var bobbing := sin(flight_time * 2.4) * 0.05 if vertical_input == 0.0 else 0.0
	model.position.y = move_toward(model.position.y, bobbing, delta * 0.25)
	var target_pitch := clampf(-movement.y * deg_to_rad(20.0), -deg_to_rad(20.0), deg_to_rad(20.0))
	var target_roll := clampf(-movement.x * deg_to_rad(20.0), -deg_to_rad(20.0), deg_to_rad(20.0))
	model.rotation.x = lerp_angle(model.rotation.x, target_pitch, clampf(delta * 1.8, 0.0, 1.0))
	model.rotation.z = lerp_angle(model.rotation.z, target_roll, clampf(delta * 1.8, 0.0, 1.0))

	var recoil_target := 0.06 if is_discharging else 0.0
	model.position.z = move_toward(model.position.z, recoil_target, delta * 0.6)
	if nozzle:
		var aim_direction := model.global_basis.inverse() * -pivot.global_basis.z
		var recoil_vibration := sin(flight_time * 38.0) * 0.025 if is_discharging else 0.0
		nozzle.rotation.x = atan2(aim_direction.y, Vector2(aim_direction.x, aim_direction.z).length()) + recoil_vibration
		nozzle.rotation.y = atan2(-aim_direction.x, -aim_direction.z)
	if water_stream:
		water_stream.emitting = is_discharging
	if water_jet_core:
		water_jet_core.visible = is_discharging
		var pulse := 1.0 + sin(flight_time * 24.0) * 0.12
		water_jet_core.scale.x = pulse
		water_jet_core.scale.z = pulse
	if refill_particles:
		refill_particles.emitting = is_refilling and recarga_solicitada

	if blue_led:
		var blue_blink := is_refilling and int(flight_time * 8.0) % 2 == 0
		if speed_flash_timer > 0.0:
			speed_flash_timer = maxf(0.0, speed_flash_timer - delta)
			blue_led.light_energy = 4.0 if int(flight_time * 18.0) % 2 == 0 else 0.6
			blue_led_lens.visible = int(flight_time * 18.0) % 2 == 0
		else:
			blue_led.light_energy = 2.5 if blue_blink else 0.8
			blue_led_lens.visible = not is_refilling or blue_blink
	if red_led:
		var red_blink := is_discharging and agua_actual <= 0.0
		red_led.light_energy = (
			3.0 if red_blink and int(flight_time * 8.0) % 2 == 0 else 0.0
		)
		red_led_lens.visible = not red_blink or int(flight_time * 8.0) % 2 == 0

func _actualizar_fov_velocidad() -> void:
	var fast_now := Vector2(velocity.x, velocity.z).length() > velocidad_sin_carga * 0.65
	if fast_now == fov_is_fast:
		return
	fov_is_fast = fast_now
	if fov_tween and fov_tween.is_running():
		fov_tween.kill()
	var target_fov := base_camera_fov + 5.0 if fov_is_fast else base_camera_fov
	fov_tween = create_tween()
	fov_tween.tween_property(cam, "fov", target_fov, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _actualizar_recarga(delta: float, hay_red: bool, es_servidor: bool) -> void:
	recarga_solicitada = (
		not _menu_pausa_abierto and Input.is_action_pressed("drone_refill")
	)
	is_refilling = is_near_water_source and recarga_solicitada and not tanque_lleno()
	if hay_red:
		if not es_servidor and recarga_solicitada != _recarga_solicitada_anterior:
			rpc_id(1, "_rpc_solicitar_recarga", recarga_solicitada)
		_recarga_solicitada_anterior = recarga_solicitada
		return
	if is_refilling and agua_actual < agua_maxima:
		agua_actual = clampf(agua_actual + recarga_por_segundo * delta, 0.0, agua_maxima)
		agua_cambiada.emit(agua_actual)
		_actualizar_nivel_tanques()
		if hud_node and hud_node.has_method("notify_refilling"):
			hud_node.notify_refilling(agua_actual, agua_maxima)

func _actualizar_disparo_solitario(delta: float) -> void:
	var rociado_solicitado := (
		not _menu_pausa_abierto and Input.is_action_pressed("drone_spray")
	)
	is_discharging = rociado_solicitado and agua_actual > 0.0
	if rociado_solicitado and agua_actual <= 0.0:
		is_discharging = false
		_notificar_alcance_chorro(false)
		if not empty_water_warning_sent and hud_node:
			hud_node.trigger_hartman_warning("empty_tank")
			empty_water_warning_sent = true
		return
	if not is_discharging:
		empty_water_warning_sent = false
		_tiempo_desperdicio_continuo = 0.0
		_notificar_alcance_chorro(false)
		return
	if (
		rociado_solicitado
		and Input.is_action_just_pressed("drone_spray")
		and apuntando_fuego_fuera_de_alcance
	):
		if AjustesAyuda.nivel_ayuda == AjustesAyuda.AYUDA_ALTA and hud_node:
			hud_node.trigger_hartman_warning("spray_out_of_range")

	var used_water := minf(agua_actual, gasto_por_segundo * delta)
	agua_actual = clampf(agua_actual - used_water, 0.0, agua_maxima)
	agua_cambiada.emit(agua_actual)
	NetworkManager.registrar_agua_usada(get_multiplayer_authority(), used_water)
	_actualizar_nivel_tanques()
	var target := _detectar_fuego()
	_notificar_alcance_chorro(apuntando_fuego_fuera_de_alcance)
	if target and is_instance_valid(target):
		_tiempo_desperdicio_continuo = 0.0
		var extinguished := false
		if FireGridServer.activa:
			var informacion := obtener_info_puntería()
			var distancia_al_fuego := float(informacion.get("distancia", 0.0))
			var radio_impacto := radio_chorro_base + distancia_al_fuego * ensanche_chorro
			extinguished = FireGridServer.aplicar_agua_atribuida(
				get_multiplayer_authority(),
				target.global_position,
				radio_impacto,
				used_water * potencia_chorro
			) > 0
		elif target.has_method("apagar"):
			var result: Variant = target.call("apagar", delta)
			if result is bool:
				extinguished = result
		elif target.has_method("apply_water_damage"):
			extinguished = bool(target.call("apply_water_damage", used_water * potencia_chorro))
		if hud_node and hud_node.has_method("register_fire_stream_hit"):
			hud_node.register_fire_stream_hit(used_water, extinguished)
	elif FireGridServer.activa:
		var impacto: Variant = _obtener_punto_impacto_chorro((-nozzle.global_basis.z).normalized())
		if impacto is Vector3:
			var distancia := nozzle.global_position.distance_to(impacto)
			var radio := radio_chorro_base + distancia * ensanche_chorro
			FireGridServer.aplicar_agua_atribuida(
				get_multiplayer_authority(),
				impacto,
				radio,
				used_water * potencia_chorro
			)
			_tiempo_desperdicio_continuo = 0.0
	else:
		wasted_water_time += delta
		_tiempo_desperdicio_continuo += delta
		if _tiempo_desperdicio_continuo >= 0.35:
			_tiempo_desperdicio_continuo = 0.0
			if hud_node:
				var info := obtener_info_puntería()
				var causa := str(info.get("causa_desperdicio", "pasto_limpio"))
				if AjustesAyuda.nivel_ayuda == AjustesAyuda.AYUDA_NINGUNA:
					hud_node.trigger_hartman_warning("wasted_water")
				else:
					hud_node.call("trigger_hartman_warning", "wasted_water", causa)

func _actualizar_disparo_multijugador(delta: float, es_servidor: bool) -> void:
	var activo := (
		is_multiplayer_authority()
		and not _menu_pausa_abierto
		and Input.is_action_pressed("drone_spray")
	)
	if es_servidor:
		if is_multiplayer_authority():
			_actualizar_intencion_rociado_local(activo, (-nozzle.global_basis.z).normalized())
		_procesar_rociado_servidor(delta)
		return

	is_discharging = activo and agua_actual > 0.0
	_tiempo_intencion_agua += delta
	var direccion := (-nozzle.global_basis.z).normalized()
	if activo != _rociado_solicitado_anterior:
		_rociado_solicitado = activo
		_direccion_rociado = direccion
		rpc_id(1, "solicitar_rociar", activo, direccion)
		_tiempo_intencion_agua = 0.0
	elif activo and _tiempo_intencion_agua >= INTERVALO_INTENCION_AGUA:
		_direccion_rociado = direccion
		rpc_id(1, "solicitar_rociar", true, direccion)
		_tiempo_intencion_agua = 0.0
	_rociado_solicitado_anterior = activo
	if activo:
		obtener_info_puntería()
		_notificar_alcance_chorro(apuntando_fuego_fuera_de_alcance)
	else:
		_notificar_alcance_chorro(false)

func _actualizar_intencion_rociado_local(activo: bool, direccion: Vector3) -> void:
	_rociado_solicitado = activo
	_direccion_rociado = direccion.normalized()
	_rociado_solicitado_anterior = activo
	is_discharging = activo and agua_actual > 0.0

@rpc("any_peer", "call_remote", "reliable")
func solicitar_rociar(activo: bool, direccion: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not _validar_solicitud_remota(peer_id):
		return
	_actualizar_solicitud_rociado_servidor(activo, direccion, peer_id)

func _actualizar_solicitud_rociado_servidor(
	activo: bool,
	direccion: Vector3,
	peer_id: int
) -> void:
	if not _validar_solicitud_remota(peer_id):
		return
	if activo:
		if agua_actual <= 0.0:
			return
		var direccion_actual := (-nozzle.global_basis.z).normalized()
		if direccion.length_squared() < 0.5 or direccion.normalized().dot(direccion_actual) < 0.65:
			return
	_rociado_solicitado = activo
	is_discharging = activo and agua_actual > 0.0

func _validar_solicitud_remota(peer_id: int) -> bool:
	var datos: Dictionary = NetworkManager.jugadores.get(peer_id, {})
	return (
		peer_id == get_multiplayer_authority()
		and not datos.is_empty()
		and str(datos.get("rol_dron", "")) == str(rol_actual.identificador)
	)

func _procesar_rociado_servidor(delta: float) -> void:
	if not _rociado_solicitado or agua_actual <= 0.0 or not FireGridServer.activa:
		is_discharging = false
		_agua_pendiente_rociado = 0.0
		_tiempo_aplicar_agua = 0.0
		_tiempo_desperdicio_continuo = 0.0
		return
	is_discharging = true
	var usado := minf(agua_actual, gasto_por_segundo * delta)
	agua_actual = maxf(agua_actual - usado, 0.0)
	agua_cambiada.emit(agua_actual)
	NetworkManager.registrar_agua_usada(get_multiplayer_authority(), usado)
	_actualizar_nivel_tanques()
	if usado <= 0.0:
		is_discharging = false
		_rociado_solicitado = false
		return

	_agua_pendiente_rociado += usado
	_tiempo_aplicar_agua += delta
	if _tiempo_aplicar_agua < INTERVALO_INTENCION_AGUA:
		return
	var direccion_actual := (-nozzle.global_basis.z).normalized()
	var impacto: Variant = _buscar_celda_en_chorro(direccion_actual)
	if impacto is Vector3:
		_tiempo_desperdicio_continuo = 0.0
		var distancia := nozzle.global_position.distance_to(impacto)
		var radio := radio_chorro_base + distancia * ensanche_chorro
		FireGridServer.aplicar_agua_atribuida(
			get_multiplayer_authority(),
			impacto,
			radio,
			_agua_pendiente_rociado * potencia_chorro
		)
	else:
		wasted_water_time += _tiempo_aplicar_agua
		_tiempo_desperdicio_continuo += _tiempo_aplicar_agua
		if _tiempo_desperdicio_continuo >= 0.35:
			_tiempo_desperdicio_continuo = 0.0
			if hud_node:
				hud_node.trigger_hartman_warning("wasted_water")
	_agua_pendiente_rociado = 0.0
	_tiempo_aplicar_agua = 0.0

func _buscar_celda_en_chorro(direccion: Vector3) -> Variant:
	var celdas := FireGridServer.obtener_celdas_ardiendo()
	var alturas := FireGridServer.obtener_alturas()
	var origen := FireGridServer.obtener_origen()
	var tamano := FireGridServer.obtener_tamano_celdas()
	var mejor_distancia := INF
	var mejor_posicion: Variant = null
	for indice in celdas:
		if indice < 0 or indice >= alturas.size() or tamano.x <= 0:
			continue
		var celda_x := indice % tamano.x
		var celda_y := floori(float(indice) / float(tamano.x))
		var posicion := Vector3(
			origen.x + (float(celda_x) + 0.5) * 2.0,
			alturas[indice],
			origen.y + (float(celda_y) + 0.5) * 2.0
		)
		var hacia := posicion - nozzle.global_position
		var avance := hacia.dot(direccion)
		if avance < 0.0 or avance > alcance_chorro:
			continue
		var error_eje := (hacia - direccion * avance).length()
		var radio := radio_chorro_base + avance * ensanche_chorro
		if error_eje <= radio and avance < mejor_distancia:
			mejor_distancia = avance
			mejor_posicion = posicion
	if mejor_posicion is Vector3:
		return mejor_posicion
	return _obtener_punto_impacto_chorro(direccion)

func _obtener_punto_impacto_chorro(direccion: Vector3) -> Variant:
	var direccion_normalizada := direccion.normalized()
	if direccion_normalizada.length_squared() <= 0.000001:
		return null
	var consulta := PhysicsRayQueryParameters3D.create(
		nozzle.global_position,
		nozzle.global_position + direccion_normalizada * alcance_chorro
	)
	consulta.exclude = [get_rid()]
	var impacto := get_world_3d().direct_space_state.intersect_ray(consulta)
	if impacto.is_empty():
		return null
	return impacto.get("position")

func _solicitar_habilidad_especial(hay_red: bool, es_servidor: bool) -> void:
	if not is_instance_valid(rol_actual):
		return
	var informacion := obtener_info_puntería()
	var posicion := Vector3.ZERO
	var posicion_variant: Variant = informacion.get("posicion_objetivo", Vector3.ZERO)
	if posicion_variant is Vector3:
		posicion = posicion_variant
	if posicion == Vector3.ZERO:
		posicion = nozzle.global_position + (-nozzle.global_basis.z).normalized() * rol_actual.alcance_termico
	if not hay_red:
		_ejecutar_habilidad_especial(multiplayer.get_unique_id(), posicion)
	elif es_servidor:
		_ejecutar_habilidad_especial(multiplayer.get_unique_id(), posicion)
	else:
		rpc_id(1, "solicitar_habilidad_especial", posicion)

@rpc("any_peer", "call_remote", "reliable", 0)
func solicitar_habilidad_especial(posicion: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not _validar_solicitud_remota(peer_id):
		return
	_ejecutar_habilidad_especial(peer_id, posicion)

func _ejecutar_habilidad_especial(peer_id: int, posicion: Vector3) -> void:
	if not is_instance_valid(rol_actual):
		return
	var ahora_ms := Time.get_ticks_msec()
	if ahora_ms < _proxima_habilidad_ms:
		return
	var rol_id := str(rol_actual.identificador)
	var exito := false
	match rol_id:
		"cisterna":
			if agua_actual < rol_actual.costo_especial_agua or not FireGridServer.activa:
				return
			var impacto: Variant = _buscar_celda_en_chorro((-nozzle.global_basis.z).normalized())
			if not impacto is Vector3:
				return
			agua_actual = maxf(agua_actual - rol_actual.costo_especial_agua, 0.0)
			agua_cambiada.emit(agua_actual)
			NetworkManager.registrar_agua_usada(peer_id, rol_actual.costo_especial_agua)
			_actualizar_nivel_tanques()
			FireGridServer.aplicar_agua_atribuida(
				peer_id,
				impacto,
				rol_actual.radio_especial,
				rol_actual.costo_especial_agua * rol_actual.potencia_especial
			)
			exito = true
		"explorador":
			if peer_id == multiplayer.get_unique_id() and not multiplayer.has_multiplayer_peer():
				activar_vision_termica_local(rol_actual.alcance_termico, rol_actual.duracion_especial)
			else:
				NetworkManager.notificar_pulso_termico(
					peer_id,
					rol_actual.alcance_termico,
					rol_actual.duracion_especial
				)
			exito = true
		"tactico":
			var desde_dron := posicion - global_position
			var distancia_horizontal := Vector2(desde_dron.x, desde_dron.z).length()
			if (
				distancia_horizontal <= 0.1
				or distancia_horizontal > rol_actual.alcance_termico
				or desde_dron.normalized().dot(-global_basis.z) < 0.0
			):
				return
			var nombre_piloto := str(get_meta("nombre_jugador", NetworkManager.nombre_local))
			if multiplayer.has_multiplayer_peer():
				NetworkManager.difundir_marca_objetivo(
					posicion,
					nombre_piloto,
					rol_actual.duracion_marca_objetivo
				)
			elif hud_node and hud_node.has_method("mostrar_marca_objetivo"):
				hud_node.call(
					"mostrar_marca_objetivo",
					posicion,
					nombre_piloto,
					rol_actual.duracion_marca_objetivo
				)
			exito = true
	if exito:
		_proxima_habilidad_ms = ahora_ms + int(rol_actual.enfriamiento_especial * 1000.0)

func activar_vision_termica_local(alcance: float, duracion: float) -> void:
	if is_multiplayer_authority() and hud_node and hud_node.has_method("activar_vision_termica"):
		hud_node.call("activar_vision_termica", alcance, duracion)

func mostrar_marca_objetivo_local(posicion: Vector3, nombre_piloto: String, duracion: float) -> void:
	if is_multiplayer_authority() and hud_node and hud_node.has_method("mostrar_marca_objetivo"):
		hud_node.call("mostrar_marca_objetivo", posicion, nombre_piloto, duracion)

func _solicitar_retardante(hay_red: bool, es_servidor: bool) -> void:
	if not is_instance_valid(rol_actual) or str(rol_actual.identificador) != "explorador":
		return
	if not hay_red:
		_ejecutar_retardante_autoritativo()
	elif es_servidor:
		_ejecutar_retardante_autoritativo()
	else:
		rpc_id(1, "solicitar_retardante")

@rpc("any_peer", "call_remote", "reliable", 0)
func solicitar_retardante() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not _validar_solicitud_remota(peer_id):
		return
	_ejecutar_retardante_autoritativo()

func _ejecutar_retardante_autoritativo() -> void:
	if (
		not is_instance_valid(rol_actual)
		or str(rol_actual.identificador) != "explorador"
		or agua_actual < rol_actual.costo_retardante
		or Time.get_ticks_msec() < _proximo_retardante_ms
		or not FireGridServer.activa
	):
		return
	var direccion := (-nozzle.global_basis.z).normalized()
	var consulta := PhysicsRayQueryParameters3D.create(
		nozzle.global_position,
		nozzle.global_position + direccion * rol_actual.alcance_retardante
	)
	consulta.exclude = [get_rid()]
	var impacto := get_world_3d().direct_space_state.intersect_ray(consulta)
	if impacto.is_empty():
		return
	var posicion: Vector3 = impacto["position"]
	if not FireGridServer.aplicar_retardante(posicion, rol_actual.radio_retardante):
		return
	agua_actual = maxf(agua_actual - rol_actual.costo_retardante, 0.0)
	agua_cambiada.emit(agua_actual)
	_actualizar_nivel_tanques()
	_proximo_retardante_ms = Time.get_ticks_msec() + int(rol_actual.enfriamiento_retardante * 1000.0)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_solicitar_recarga(activo: bool) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id != get_multiplayer_authority() or not NetworkManager.jugadores.has(peer_id):
		return
	recarga_solicitada = activo
	is_refilling = activo and is_near_water_source and not tanque_lleno()

func _procesar_recarga_servidor(_delta: float) -> void:
	is_refilling = (
		recarga_solicitada
		and is_near_water_source
		and not tanque_lleno()
	)

@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _rpc_actualizar_entrada(
	movimiento: Vector2,
	vertical: float,
	movimiento_mouse: Vector2,
	sensibilidad: float
) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id != get_multiplayer_authority() or not NetworkManager.jugadores.has(peer_id):
		return
	_entrada_red = movimiento.limit_length(1.0)
	_entrada_vertical_red = clampf(vertical, -1.0, 1.0)
	mouse_sensitivity = clampf(sensibilidad, 0.0005, 0.01)
	_mouse_red += movimiento_mouse.limit_length(150.0)

func recibir_snapshot_autoritativo(
	posicion: Vector3,
	rotacion: Vector3,
	velocidad_recibida: Vector3,
	tiempo_ms: int
) -> void:
	if is_multiplayer_authority():
		var diferencia := _posicion_predicha.distance_to(posicion)
		if diferencia > UMBRAL_CORRECCION_METROS:
			_posicion_predicha = _posicion_predicha.lerp(posicion, 0.2)
		else:
			_posicion_predicha = _posicion_predicha.lerp(posicion, 0.05)
		global_position = _posicion_predicha
		_rotacion_predicha = _interpolar_rotacion(_rotacion_predicha, rotacion, 0.1)
		global_rotation = _rotacion_predicha
		pivot.rotation.x = lerpf(_apuntamiento_predicho, apuntamiento_vertical, 0.1)
		_apuntamiento_predicho = pivot.rotation.x
		velocity = velocidad_recibida
		return
	_historial_posiciones.append(posicion)
	_historial_rotaciones.append(rotacion)
	_historial_tiempos_ms.append(tiempo_ms)
	_historial_apuntamientos.append(apuntamiento_vertical)
	while _historial_tiempos_ms.size() > 8:
		_historial_posiciones.remove_at(0)
		_historial_rotaciones.remove_at(0)
		_historial_tiempos_ms.remove_at(0)
		_historial_apuntamientos.remove_at(0)

func _interpolar_rotacion(origen: Vector3, destino: Vector3, peso: float) -> Vector3:
	return Vector3(
		lerp_angle(origen.x, destino.x, peso),
		lerp_angle(origen.y, destino.y, peso),
		lerp_angle(origen.z, destino.z, peso)
	)

func _interpolar_snapshot_remoto() -> void:
	if _historial_tiempos_ms.size() < 2:
		return
	var tiempo_render := Time.get_ticks_msec() - RETRASO_INTERPOLACION_MS
	var indice_actual := _historial_tiempos_ms.size() - 1
	for indice in range(1, _historial_tiempos_ms.size()):
		if _historial_tiempos_ms[indice] >= tiempo_render:
			indice_actual = indice
			break
	var indice_anterior := maxi(indice_actual - 1, 0)
	var tiempo_anterior := _historial_tiempos_ms[indice_anterior]
	var tiempo_actual := _historial_tiempos_ms[indice_actual]
	var duracion := maxi(tiempo_actual - tiempo_anterior, 1)
	var factor := clampf(float(tiempo_render - tiempo_anterior) / float(duracion), 0.0, 1.0)
	global_position = _historial_posiciones[indice_anterior].lerp(
		_historial_posiciones[indice_actual],
		factor
	)
	global_rotation = _interpolar_rotacion(
		_historial_rotaciones[indice_anterior],
		_historial_rotaciones[indice_actual],
		factor
	)
	pivot.rotation.x = lerpf(
		_historial_apuntamientos[indice_anterior],
		_historial_apuntamientos[indice_actual],
		factor
	)

func _actualizar_hud_local(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	_actualizar_hud()
	_actualizar_guia_punteria(delta)

func _detectar_fuego() -> Node:
	obtener_info_puntería()
	return objetivo_alcanzable_cache

func obtener_info_puntería() -> Dictionary:
	var ahora_ms := Time.get_ticks_msec()
	if ahora_ms - ultima_actualizacion_punteria_ms >= INTERVALO_CACHE_PUNTERIA_MS:
		ultima_actualizacion_punteria_ms = ahora_ms
		cache_info_punteria = _calcular_info_punteria()
		var objetivo: Variant = cache_info_punteria.get("objetivo")
		objetivo_alcanzable_cache = cache_info_punteria.get("objetivo_alcanzable") as Node3D
		apuntando_fuego_fuera_de_alcance = (
			cache_info_punteria.get("estado") == "FUERA_DE_ALCANCE"
			and objetivo_alcanzable_cache == null
			and is_instance_valid(objetivo)
		)
		if hud_node and hud_node.has_method("actualizar_punteria"):
			hud_node.call("actualizar_punteria", cache_info_punteria, cam, AjustesAyuda.nivel_ayuda)
		_notificar_alcance_chorro(apuntando_fuego_fuera_de_alcance)
	return cache_info_punteria

func _calcular_info_punteria() -> Dictionary:
	var origen := nozzle.global_position
	var direccion := (-nozzle.global_basis.z).normalized()
	var info: Dictionary = {
		"estado": "SIN_OBJETIVO",
		"distancia": 0.0,
		"alcance_chorro": alcance_chorro,
		"error_horizontal": 0.0,
		"error_vertical": 0.0,
		"objetivo": null,
		"objetivo_alcanzable": null,
		"posicion_objetivo": Vector3.ZERO,
		"punto_impacto": origen + direccion * alcance_chorro,
		"dentro_del_chorro": false,
		"disparando": (
			not _menu_pausa_abierto
			and Input.is_action_pressed("drone_spray")
			and agua_actual > 0.0
		),
		"agua_actual": agua_actual,
		"causa_desperdicio": "pasto_limpio",
	}
	var mejor_error_al_eje := INF
	var mejor_error_alcanzable := INF
	var mejor_distancia := 0.0
	var mejor_avance := 0.0
	var mejor_error_horizontal := 0.0
	var mejor_error_vertical := 0.0
	var mejor_dentro_del_chorro := false
	var mejor_en_linea := false
	var mejor_posicion := Vector3.ZERO
	var mejor_causa := "pasto_limpio"

	objetivo_alcanzable_cache = null
	for fuego in get_tree().get_nodes_in_group("fuego"):
		if not fuego is Node3D or not fuego.is_inside_tree() or not fuego.is_visible_in_tree():
			continue
		if not fuego.has_method("apply_water_damage") and not fuego.has_method("apagar"):
			continue
		var nodo_fuego := fuego as Node3D
		var posicion_fuego := nodo_fuego.global_position
		if nodo_fuego.has_method("get_fire_target_position"):
			var posicion_objetivo: Variant = nodo_fuego.call("get_fire_target_position")
			if posicion_objetivo is Vector3:
				posicion_fuego = posicion_objetivo

		var hacia_fuego := posicion_fuego - origen
		var distancia := hacia_fuego.length()
		var local_fuego := nozzle.global_basis.inverse() * hacia_fuego
		var error_horizontal := rad_to_deg(atan2(local_fuego.x, -local_fuego.z))
		var error_vertical := rad_to_deg(atan2(
			local_fuego.y,
			Vector2(local_fuego.x, local_fuego.z).length()
		))
		var avance := hacia_fuego.dot(direccion)
		var punto_eje := origen + direccion * maxf(avance, 0.0)
		var error_eje := posicion_fuego.distance_to(punto_eje)
		var radio := radio_chorro_base + maxf(avance, 0.0) * ensanche_chorro
		var dentro_del_chorro := (
			avance >= 0.0
			and avance <= alcance_chorro
			and error_eje <= radio
		)
		var en_linea := avance >= 0.0 and error_eje <= radio

		if dentro_del_chorro and error_eje < mejor_error_alcanzable:
			objetivo_alcanzable_cache = nodo_fuego
			mejor_error_alcanzable = error_eje

		if error_eje >= mejor_error_al_eje:
			continue
		mejor_error_al_eje = error_eje
		mejor_distancia = distancia
		mejor_avance = avance
		mejor_error_horizontal = error_horizontal
		mejor_error_vertical = error_vertical
		mejor_dentro_del_chorro = dentro_del_chorro
		mejor_en_linea = en_linea
		mejor_posicion = posicion_fuego
		info["objetivo"] = nodo_fuego

	if not is_instance_valid(info["objetivo"]):
		return info

	info["distancia"] = mejor_distancia
	info["objetivo_alcanzable"] = objetivo_alcanzable_cache
	info["error_horizontal"] = mejor_error_horizontal
	info["error_vertical"] = mejor_error_vertical
	info["posicion_objetivo"] = mejor_posicion
	info["dentro_del_chorro"] = mejor_dentro_del_chorro
	if mejor_avance > alcance_chorro:
		info["estado"] = "FUERA_DE_ALCANCE"
	elif (
		mejor_dentro_del_chorro
		and absf(mejor_error_horizontal) <= 2.0
		and absf(mejor_error_vertical) <= 2.0
	):
		info["estado"] = "EN_BLANCO"
	else:
		info["estado"] = "CERCA"

	if mejor_avance > alcance_chorro and mejor_en_linea:
		mejor_causa = "fuera_de_alcance"
	elif absf(mejor_error_vertical) > 8.0:
		mejor_causa = "punto_muy_bajo" if mejor_error_vertical > 0.0 else "punto_muy_alto"
	elif absf(mejor_error_horizontal) > 8.0:
		mejor_causa = "desviado_lateral"
	info["causa_desperdicio"] = mejor_causa
	return info

func _actualizar_guia_punteria(delta: float) -> void:
	if AjustesAyuda.nivel_ayuda != AjustesAyuda.AYUDA_ALTA:
		tiempo_guia_punteria = 0.0
		return
	tiempo_guia_punteria += delta
	if tiempo_guia_punteria < INTERVALO_GUIA_PUNTERIA:
		return
	tiempo_guia_punteria = 0.0
	if hud_node and hud_node.has_method("guia_puntería"):
		hud_node.call("guia_puntería", obtener_info_puntería())

func _notificar_alcance_chorro(fuera_de_alcance: bool) -> void:
	if hud_node and hud_node.has_method("notificar_alcance_chorro"):
		hud_node.call("notificar_alcance_chorro", fuera_de_alcance)

func _aplicar_dano_termico(delta: float) -> void:
	if not is_instance_valid(wildfire_node):
		wildfire_node = get_tree().root.find_child("WildfireZone", true, false) as Node3D
	if wildfire_node and wildfire_node.visible:
		if global_position.distance_to(wildfire_node.global_position) < 20.0:
			current_health = maxf(0.0, current_health - 18.0 * delta)
			if hud_node:
				hud_node.trigger_hartman_warning("fire_damage")

func _comprobar_aterrizaje() -> void:
	if not is_instance_valid(helipad_node):
		helipad_node = get_tree().root.find_child("BaseHelipad", true, false) as Node3D
	if not helipad_node or not hud_node or not hud_node.is_fire_defeated:
		return
	var distance := Vector2(
		global_position.x - helipad_node.global_position.x,
		global_position.z - helipad_node.global_position.z
	).length()
	if distance < 5.0 and global_position.y <= 1.8:
		hud_node.notify_successful_landing()

func _actualizar_hud() -> void:
	if hud_node and hud_node.has_method("update_telemetry"):
		var altitude := 75.0 + global_position.y
		var speed := Vector2(velocity.x, velocity.z).length()
		var distance := global_position.distance_to(Vector3.ZERO) + 420.0
		hud_node.update_telemetry(
			altitude, speed, distance, agua_actual, agua_maxima, is_near_water_source, current_health
		)
		if hud_node.has_method("update_water_level"):
			hud_node.update_water_level(agua_actual, agua_maxima)

func _on_tree_extinguished(total_apagados: int) -> void:
	arboles_apagados = total_apagados
	speed_flash_timer = 0.9
	if hud_node and hud_node.has_method("notify_speed_boost"):
		hud_node.call("notify_speed_boost", velocidad)

func recibir_agua(cantidad: float) -> void:
	if cantidad <= 0.0:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	agua_actual = clampf(agua_actual + cantidad, 0.0, agua_maxima)
	agua_cambiada.emit(agua_actual)
	_actualizar_nivel_tanques()
	if hud_node and hud_node.has_method("notify_refilling"):
		hud_node.notify_refilling(agua_actual, agua_maxima)

func tanque_lleno() -> bool:
	return agua_actual >= agua_maxima

func set_fuente_agua_cercana(esta_cerca: bool, presionando_recarga: bool = false) -> void:
	is_near_water_source = esta_cerca
	is_refilling = esta_cerca and presionando_recarga and not tanque_lleno()

func crear_modelo() -> void:
	var body_material := _material(Color8(37, 43, 52), 0.3)
	var metal_material := _material(Color8(71, 82, 94), 0.3)
	var red_material := _material(Color8(211, 47, 47), 0.3)
	var dark_material := _material(Color8(23, 27, 33), 0.35)
	var blue_material := _material(Color8(32, 157, 235), 0.25, 0.5)
	var rotor_material := _material(Color(0.48, 0.72, 0.82, 0.62), 0.5)
	rotor_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var body_group := Node3D.new()
	body_group.name = "Cuerpo"
	model.add_child(body_group)
	_add_cylinder(body_group, "Chasis", 0.25, 0.16, body_material, Vector3.ZERO)
	_add_box(body_group, "Cubierta", Vector3(0.34, 0.08, 0.34), dark_material, Vector3(0.0, 0.08, 0.0))

	var arms_group := Node3D.new()
	arms_group.name = "Brazos"
	model.add_child(arms_group)
	var propeller_positions: Array[Vector3] = [
		Vector3(-0.53, 0.0, -0.53), Vector3(0.53, 0.0, -0.53),
		Vector3(-0.53, 0.0, 0.53), Vector3(0.53, 0.0, 0.53)
	]
	for index in range(propeller_positions.size()):
		_add_cylinder_between(
			arms_group, "Brazo%d" % index, Vector3.ZERO, propeller_positions[index],
			0.035, metal_material
		)

	var propeller_group := Node3D.new()
	propeller_group.name = "Helices"
	model.add_child(propeller_group)
	for index in range(propeller_positions.size()):
		var mount := Node3D.new()
		mount.name = "Helice%d" % index
		mount.position = propeller_positions[index]
		propeller_group.add_child(mount)
		rotors.append(mount)
		_add_cylinder(mount, "Motor", 0.09, 0.075, dark_material, Vector3.ZERO)
		_add_box(mount, "AspaA", Vector3(0.42, 0.018, 0.055), rotor_material, Vector3.ZERO)
		_add_box(
			mount, "AspaB", Vector3(0.42, 0.018, 0.055), rotor_material,
			Vector3.ZERO, deg_to_rad(90.0)
		)

	var tanks_group := Node3D.new()
	tanks_group.name = "Tanques"
	model.add_child(tanks_group)
	for index in range(2):
		var x := -0.105 if index == 0 else 0.105
		_add_cylinder(tanks_group, "TanqueRojo%d" % index, 0.105, 0.32, red_material, Vector3(x, -0.22, 0.0))
		var fill := _add_cylinder(
			tanks_group, "NivelAgua%d" % index, 0.075, 0.28, blue_material, Vector3(x, -0.34, 0.0)
		)
		tank_fills.append(fill)

	var nozzle_group := Node3D.new()
	nozzle_group.name = "Boquilla"
	nozzle_group.position = Vector3(0.0, -0.12, -0.34)
	model.add_child(nozzle_group)
	nozzle = nozzle_group
	_add_cylinder_between(
		nozzle_group, "Tubo", Vector3.ZERO, Vector3(0.0, 0.0, -0.17), 0.045, metal_material
	)
	_add_cylinder_between(
		nozzle_group, "Boca", Vector3(0.0, 0.0, -0.14), Vector3(0.0, 0.0, -0.20),
		0.07, red_material
	)

	var legs_group := Node3D.new()
	legs_group.name = "Patas"
	model.add_child(legs_group)
	for x_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			_add_cylinder_between(
				legs_group, "Soporte", Vector3(x_sign * 0.18, -0.08, z_sign * 0.16),
				Vector3(x_sign * 0.28, -0.34, z_sign * 0.28), 0.022, metal_material
			)
		_add_cylinder_between(
			legs_group, "Patin", Vector3(x_sign * 0.28, -0.34, -0.34),
			Vector3(x_sign * 0.28, -0.34, 0.34), 0.025, dark_material
		)

	blue_led = _add_light(body_group, "LED_Azul", Color8(30, 170, 255), Vector3(0.0, 0.05, -0.18))
	red_led = _add_light(body_group, "LED_Rojo", Color8(255, 40, 35), Vector3(0.0, 0.05, 0.18))
	blue_led_lens = _add_led_lens(body_group, "LenteAzul", Color8(30, 170, 255), Vector3(0.0, 0.05, -0.18))
	red_led_lens = _add_led_lens(body_group, "LenteRoja", Color8(255, 40, 35), Vector3(0.0, 0.05, 0.18))

func crear_efectos() -> void:
	water_stream = _crear_particulas(
		"ChorroAgua", nozzle, Vector3(0.0, 0.0, -0.20), 280, 1.8,
		Vector3(0.0, 0.0, -1.0), 23.0, 1.8, Color(0.55, 0.82, 1.0, 0.82)
	)
	var stream_material := water_stream.process_material as ParticleProcessMaterial
	stream_material.gravity = Vector3(0.0, -5.0, 0.0)
	stream_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	stream_material.emission_box_extents = Vector3(0.09, 0.09, 0.08)
	stream_material.scale_min = 0.8
	stream_material.scale_max = 2.2
	var core_mesh := CylinderMesh.new()
	core_mesh.top_radius = 0.11
	core_mesh.bottom_radius = 0.16
	core_mesh.height = 1.0
	water_jet_core = MeshInstance3D.new()
	water_jet_core.name = "NucleoChorro"
	water_jet_core.mesh = core_mesh
	var core_material := _material(Color(0.55, 0.82, 1.0, 0.48), 0.0, 0.2)
	core_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core_material.emission_enabled = true
	core_material.emission = Color(0.12, 0.38, 0.72, 1.0)
	core_material.emission_energy_multiplier = 0.55
	water_jet_core.material_override = core_material
	water_jet_core.rotation.x = PI * 0.5
	water_jet_core.position = Vector3(0.0, 0.0, -7.0)
	water_jet_core.scale = Vector3(1.0, 14.0, 1.0)
	water_jet_core.visible = false
	nozzle.add_child(water_jet_core)

	refill_particles = _crear_particulas(
		"ParticulasRecarga", model, Vector3(0.0, -0.45, 0.0), 28, 0.8,
		Vector3(0.0, 1.0, 0.0), 1.2, 0.5, Color(0.2, 0.65, 1.0, 0.7)
	)
	var refill_material := refill_particles.process_material as ParticleProcessMaterial
	refill_material.gravity = Vector3(0.0, 0.35, 0.0)
	refill_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	refill_material.emission_box_extents = Vector3(0.55, 0.35, 0.55)

func _actualizar_visual_chorro() -> void:
	if is_instance_valid(water_jet_core):
		water_jet_core.scale.y = alcance_chorro
		water_jet_core.position.z = -alcance_chorro * 0.5
	if is_instance_valid(water_stream):
		var velocidad_particulas := maxf(alcance_chorro * 0.92, 1.0)
		water_stream.lifetime = alcance_chorro / velocidad_particulas
		var stream_material := water_stream.process_material as ParticleProcessMaterial
		if stream_material:
			stream_material.initial_velocity_min = velocidad_particulas * 0.75
			stream_material.initial_velocity_max = velocidad_particulas

func _crear_particulas(
	nombre: String, parent: Node3D, position: Vector3, amount: int, lifetime: float,
	direction: Vector3, initial_speed: float, spread: float, color: Color
) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = nombre
	particles.position = position
	particles.amount = amount
	particles.lifetime = lifetime
	particles.local_coords = true
	particles.emitting = false
	var process_material := ParticleProcessMaterial.new()
	process_material.direction = direction
	process_material.initial_velocity_min = initial_speed * 0.75
	process_material.initial_velocity_max = initial_speed
	process_material.spread = spread
	process_material.gravity = Vector3.ZERO
	particles.process_material = process_material
	var particle_material := _material(color, 0.25)
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var particle_mesh := SphereMesh.new()
	particle_mesh.radius = 0.10 if nombre == "ChorroAgua" else 0.045
	particle_mesh.height = 0.20 if nombre == "ChorroAgua" else 0.09
	particle_mesh.material = particle_material
	particles.draw_pass_1 = particle_mesh
	parent.add_child(particles)
	return particles

func _actualizar_nivel_tanques() -> void:
	var ratio := clampf(agua_actual / agua_maxima, 0.0, 1.0) if agua_maxima > 0.0 else 0.0
	for fill in tank_fills:
		fill.scale.y = maxf(ratio, 0.001)
		fill.position.y = -0.34 + 0.14 * ratio

func _material(color: Color, metallic: float = 0.0, roughness: float = 0.5) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material

func _add_cylinder(
	parent: Node3D, node_name: String, radius: float, height: float,
	material: Material, position: Vector3
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	parent.add_child(instance)
	return instance

func _add_box(
	parent: Node3D, node_name: String, size: Vector3, material: Material,
	position: Vector3, rotation_y: float = 0.0
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	instance.rotation.y = rotation_y
	parent.add_child(instance)
	return instance

func _add_cylinder_between(
	parent: Node3D, node_name: String, start: Vector3, finish: Vector3,
	radius: float, material: Material
) -> MeshInstance3D:
	var difference := finish - start
	var instance := _add_cylinder(
		parent, node_name, radius, difference.length(), material, (start + finish) * 0.5
	)
	instance.quaternion = Quaternion(Vector3.UP, difference.normalized())
	return instance

func _add_light(parent: Node3D, node_name: String, color: Color, position: Vector3) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = node_name
	light.light_color = color
	light.light_energy = 1.2
	light.omni_range = 1.5
	light.position = position
	parent.add_child(light)
	return light

func _add_led_lens(parent: Node3D, node_name: String, color: Color, position: Vector3) -> MeshInstance3D:
	var lens := MeshInstance3D.new()
	lens.name = node_name
	var mesh := SphereMesh.new()
	mesh.radius = 0.035
	mesh.height = 0.07
	lens.mesh = mesh
	var material := _material(color, 0.1, 0.3)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.5
	lens.material_override = material
	lens.position = position
	parent.add_child(lens)
	return lens
