extends CharacterBody3D

signal agua_cambiada(cantidad: float)

@export_group("Vuelo")
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
var mouse_input: Vector2 = Vector2.ZERO
var idle_timer: float = 0.0
var collision_cooldown: float = 0.0
var wasted_water_time: float = 0.0
var flight_time: float = 0.0
var arboles_apagados: int = 0

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

func _ready() -> void:
	add_to_group("jugador")
	crear_acciones_de_entrada()
	current_health = max_health
	base_camera_fov = cam.fov
	model.scale = Vector3.ONE * maxf(escala_dron, 0.1)
	_configurar_colision()
	crear_modelo()
	crear_efectos()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	cam.current = true
	hud_node = get_tree().root.find_child("TacticalHUD", true, false) as CanvasLayer
	wildfire_node = get_tree().root.find_child("WildfireZone", true, false) as Node3D
	helipad_node = get_tree().root.find_child("BaseHelipad", true, false) as Node3D
	fire_manager = get_tree().root.find_child("FireManager", true, false)
	if fire_manager and fire_manager.has_signal("arbol_apagado"):
		fire_manager.connect("arbol_apagado", _on_tree_extinguished)
	_actualizar_nivel_tanques()

func crear_acciones_de_entrada() -> void:
	_agregar_accion_tecla("drone_forward", KEY_W)
	_agregar_accion_tecla("drone_backward", KEY_S)
	_agregar_accion_tecla("drone_left", KEY_A)
	_agregar_accion_tecla("drone_right", KEY_D)
	_agregar_accion_tecla("drone_ascend", KEY_SPACE)
	_agregar_accion_tecla("drone_descend", KEY_C)
	_agregar_accion_tecla("drone_refill", KEY_E)
	_agregar_accion_boton_mouse("drone_spray", MOUSE_BUTTON_LEFT)

func _agregar_accion_tecla(action: StringName, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = key
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)

func _agregar_accion_boton_mouse(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventMouseButton.new()
	event.button_index = button
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)

func _configurar_colision() -> void:
	var body_shape := BoxShape3D.new()
	body_shape.size = Vector3(0.8, 0.3, 0.8) * maxf(escala_dron, 0.1)
	collision_shape.shape = body_shape

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		is_mouse_captured = not is_mouse_captured
		Input.set_mouse_mode(
			Input.MOUSE_MODE_CAPTURED if is_mouse_captured else Input.MOUSE_MODE_VISIBLE
		)
	if is_mouse_captured and event is InputEventMouseMotion:
		mouse_input = event.relative

func _physics_process(delta: float) -> void:
	flight_time += delta
	if is_mouse_captured and mouse_input != Vector2.ZERO:
		rotate_y(-mouse_input.x * mouse_sensitivity)
		pivot.rotate_x(-mouse_input.y * mouse_sensitivity)
		pivot.rotation.x = clampf(pivot.rotation.x, deg_to_rad(-45.0), deg_to_rad(30.0))
		mouse_input = Vector2.ZERO

	var input_vector := Input.get_vector(
		"drone_left", "drone_right", "drone_forward", "drone_backward"
	)
	var vertical_input := Input.get_axis("drone_descend", "drone_ascend")
	var local_motion := Vector3(input_vector.x, 0.0, input_vector.y)
	var world_motion := (transform.basis * local_motion).normalized()
	var carga := agua_actual / agua_maxima if agua_maxima > 0.0 else 0.0
	var velocidad_actual := lerpf(velocidad_sin_carga, velocidad, carga)
	var target_horizontal := world_motion * velocidad_actual

	velocity.x = move_toward(velocity.x, target_horizontal.x, aceleracion * delta)
	velocity.z = move_toward(velocity.z, target_horizontal.z, aceleracion * delta)
	velocity.y = move_toward(velocity.y, vertical_input * velocidad_vertical, aceleracion * delta)
	move_and_slide()
	_actualizar_fov_velocidad()

	_actualizar_animaciones(delta, input_vector, vertical_input)
	_actualizar_recarga()
	_actualizar_disparo(delta)
	_aplicar_dano_termico(delta)
	_comprobar_aterrizaje()
	_actualizar_hud()

	if local_motion == Vector3.ZERO and vertical_input == 0.0:
		idle_timer += delta
		if idle_timer > 10.0 and idle_timer < 10.2 and hud_node:
			hud_node.trigger_hartman_warning("idle")
	else:
		idle_timer = 0.0

	collision_cooldown = maxf(0.0, collision_cooldown - delta)
	if get_slide_collision_count() > 0 and collision_cooldown <= 0.0:
		if velocity.length() > 6.0:
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
		var aim_direction := model.global_basis.inverse() * -cam.global_basis.z
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
		refill_particles.emitting = is_refilling and Input.is_action_pressed("drone_refill")

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
		var red_blink := Input.is_action_pressed("drone_spray") and agua_actual <= 0.0
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

func _actualizar_recarga() -> void:
	is_refilling = is_near_water_source and Input.is_action_pressed("drone_refill") and not tanque_lleno()
	if is_refilling and agua_actual < agua_maxima:
		var delta := get_physics_process_delta_time()
		agua_actual = clampf(agua_actual + recarga_por_segundo * delta, 0.0, agua_maxima)
		agua_cambiada.emit(agua_actual)
		_actualizar_nivel_tanques()
		if hud_node and hud_node.has_method("notify_refilling"):
			hud_node.notify_refilling(agua_actual, agua_maxima)

func _actualizar_disparo(delta: float) -> void:
	is_discharging = Input.is_action_pressed("drone_spray") and agua_actual > 0.0
	if Input.is_action_pressed("drone_spray") and agua_actual <= 0.0:
		is_discharging = false
		if not empty_water_warning_sent and hud_node:
			hud_node.trigger_hartman_warning("empty_tank")
			empty_water_warning_sent = true
		return
	if not is_discharging:
		empty_water_warning_sent = false
		wasted_water_time = 0.0
		return

	var used_water := minf(agua_actual, gasto_por_segundo * delta)
	agua_actual = clampf(agua_actual - used_water, 0.0, agua_maxima)
	agua_cambiada.emit(agua_actual)
	_actualizar_nivel_tanques()
	var target := _detectar_fuego()
	if target:
		wasted_water_time = 0.0
		var extinguished := false
		if target.has_method("apagar"):
			var result: Variant = target.call("apagar", delta)
			if result is bool:
				extinguished = result
		elif target.has_method("apply_water_damage"):
			extinguished = bool(target.call("apply_water_damage", used_water * potencia_chorro))
		if hud_node and hud_node.has_method("register_fire_stream_hit"):
			hud_node.register_fire_stream_hit(used_water, extinguished)
	else:
		wasted_water_time += delta
		if wasted_water_time >= 0.35:
			wasted_water_time = 0.0
			if hud_node:
				hud_node.trigger_hartman_warning("wasted_water")

func _detectar_fuego() -> Node:
	var origin := nozzle.global_position
	var direction := (nozzle.global_basis * Vector3(0.0, 0.0, -1.0)).normalized()
	var max_range := 45.0
	var best_target: Node3D
	var best_miss_distance := INF
	for fire in get_tree().get_nodes_in_group("fuego"):
		if not fire is Node3D or not fire.is_inside_tree():
			continue
		if not fire.is_visible_in_tree():
			continue
		if not fire.has_method("apply_water_damage") and not fire.has_method("apagar"):
			continue
		var fire_position: Vector3 = fire.global_position
		if fire.has_method("get_fire_target_position"):
			var target_position: Variant = fire.call("get_fire_target_position")
			if target_position is Vector3:
				fire_position = target_position
		var to_fire: Vector3 = fire_position - origin
		var along_stream := to_fire.dot(direction)
		if along_stream < 0.0 or along_stream > max_range:
			continue
		var miss_distance := (to_fire - direction * along_stream).length()
		var stream_radius := 1.6 + along_stream * 0.06
		if miss_distance <= stream_radius and miss_distance < best_miss_distance:
			best_target = fire
			best_miss_distance = miss_distance
	return best_target

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
