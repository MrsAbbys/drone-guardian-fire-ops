extends Node3D

signal fuego_apagado(fuego: Node3D)

const PALETA := preload("res://scripts/world/paleta.gd")
static var faceted_flame_mesh: ArrayMesh

@export var objetivo_extinguible: bool = true
@export var max_health: float = 60.0
@export var viento: Vector3 = Vector3(0.8, 0.0, 0.25)
@export_range(0, 250, 1) var max_particulas_humo: int = 120

@onready var flame_particles: GPUParticles3D = get_node_or_null("FlameParticles")
@onready var legacy_smoke: GPUParticles3D = get_node_or_null("SmokeParticles")
@onready var fire_light: OmniLight3D = get_node_or_null("FireLight")

var dense_smoke: GPUParticles3D
var high_smoke: GPUParticles3D
var steam_particles: GPUParticles3D
var linked_tree: Node3D
var current_health: float = 60.0
var flicker_time: float = 0.0
var intensity: float = 1.0
var extinguishing: bool = false
var flame_material: Material

func _ready() -> void:
	current_health = max_health
	if flame_particles and flame_particles.draw_pass_1 and flame_particles.draw_pass_1.get_surface_count() > 0:
		flame_material = flame_particles.draw_pass_1.surface_get_material(0)
	var fire_area := get_node_or_null("Area3D") as Area3D
	if fire_area:
		fire_area.add_to_group("fuego_area")
	if objetivo_extinguible:
		add_to_group("fuego")
		var hud := get_tree().root.find_child("TacticalHUD", true, false)
		if hud and hud.has_method("register_fire_tree"):
			hud.call("register_fire_tree", self)
	if legacy_smoke:
		legacy_smoke.emitting = false
		legacy_smoke.amount_ratio = 0.0
	if fire_light:
		fire_light.light_color = PALETA.LUZ_FUEGO
		fire_light.light_energy = 4.0
		fire_light.omni_range = 18.0
	_create_smoke()

func _process(delta: float) -> void:
	flicker_time += delta
	if fire_light and not extinguishing:
		fire_light.light_energy = 4.0 * intensity * (0.9 + 0.1 * sin(flicker_time * 10.0))

func set_viento(value: Vector3) -> void:
	viento = value
	_apply_wind()

func set_linked_tree(tree: Node3D) -> void:
	linked_tree = tree

func apply_water_damage(amount: float) -> bool:
	if not objetivo_extinguible or extinguishing or amount <= 0.0:
		return false
	current_health = maxf(0.0, current_health - amount)
	set_intensidad(current_health / maxf(max_health, 1.0))
	if current_health <= 0.0:
		extinguish()
		return true
	return false

func apagar(delta: float) -> bool:
	return apply_water_damage(maxf(delta, 0.0) * 25.0)

func set_intensidad(value: float) -> void:
	intensity = clampf(value, 0.0, 1.0)
	if flame_particles:
		flame_particles.amount_ratio = intensity
		flame_particles.scale = Vector3.ONE * lerpf(0.4, 1.0, intensity)
	if dense_smoke:
		dense_smoke.amount_ratio = intensity
	if high_smoke:
		high_smoke.amount_ratio = intensity * 0.75
	if fire_light:
		fire_light.light_energy = 4.0 * intensity

func set_fire_variant(variant: int) -> void:
	if variant % 2 == 0 or not flame_particles:
		return
	if not faceted_flame_mesh:
		faceted_flame_mesh = _crear_malla_llama_faceteada()
		if flame_material:
			faceted_flame_mesh.surface_set_material(0, flame_material)
	flame_particles.draw_pass_1 = faceted_flame_mesh

func _crear_malla_llama_faceteada() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var heights: Array[float] = [0.0, 0.38, 0.88, 1.5]
	var radii: Array[float] = [0.42, 0.31, 0.18, 0.0]
	var centers: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(0.02, 0.0),
		Vector2(0.12, -0.02),
		Vector2(0.24, 0.04),
	]
	const SIDES := 6
	for ring in range(heights.size() - 1):
		for side in range(SIDES):
			var angle_a := TAU * float(side) / float(SIDES)
			var angle_b := TAU * float(side + 1) / float(SIDES)
			var bottom_a := Vector3(
				centers[ring].x + cos(angle_a) * radii[ring],
				heights[ring],
				centers[ring].y + sin(angle_a) * radii[ring]
			)
			var bottom_b := Vector3(
				centers[ring].x + cos(angle_b) * radii[ring],
				heights[ring],
				centers[ring].y + sin(angle_b) * radii[ring]
			)
			var upper_a := Vector3(
				centers[ring + 1].x + cos(angle_a) * radii[ring + 1],
				heights[ring + 1],
				centers[ring + 1].y + sin(angle_a) * radii[ring + 1]
			)
			var upper_b := Vector3(
				centers[ring + 1].x + cos(angle_b) * radii[ring + 1],
				heights[ring + 1],
				centers[ring + 1].y + sin(angle_b) * radii[ring + 1]
			)
			surface.add_vertex(bottom_a)
			surface.add_vertex(upper_a)
			surface.add_vertex(upper_b)
			surface.add_vertex(bottom_a)
			surface.add_vertex(upper_b)
			surface.add_vertex(bottom_b)
	surface.generate_normals()
	return surface.commit() as ArrayMesh

func extinguish() -> void:
	if extinguishing:
		return
	extinguishing = true
	intensity = 0.0
	current_health = 0.0
	remove_from_group("fuego")
	if is_instance_valid(linked_tree):
		_burn_tree(linked_tree)
	fuego_apagado.emit(self)
	if flame_particles:
		flame_particles.emitting = false
	if dense_smoke:
		dense_smoke.emitting = false
	if high_smoke:
		high_smoke.emitting = false
	if fire_light:
		fire_light.visible = false
	var area := get_node_or_null("Area3D") as Area3D
	if area:
		area.monitoring = false
		area.monitorable = false
	if steam_particles:
		steam_particles.emitting = true
	await get_tree().create_timer(1.6).timeout
	queue_free()

func _burn_tree(tree: Node) -> void:
	for child in tree.get_children():
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			var source_material := mesh_instance.material_override
			if source_material == null and mesh_instance.mesh and mesh_instance.mesh.get_surface_count() > 0:
				source_material = mesh_instance.mesh.surface_get_material(0)
			if source_material is StandardMaterial3D:
				var burnt := (source_material as StandardMaterial3D).duplicate() as StandardMaterial3D
				burnt.albedo_color = PALETA.CARBON
				mesh_instance.material_override = burnt
		_burn_tree(child)

func _create_smoke() -> void:
	var total_particles := mini(max_particulas_humo, 250)
	var dense_amount := maxi(1, int(total_particles * 2 / 3))
	var fine_amount := maxi(1, total_particles - dense_amount)
	dense_smoke = _make_smoke_layer("HumoDenso", dense_amount, 1.8, 0.38, 0.9, Color(0.18, 0.17, 0.16, 0.72), Color(0.42, 0.41, 0.4, 0.0))
	high_smoke = _make_smoke_layer("HumoFino", fine_amount, 3.8, 0.72, 1.8, Color(0.38, 0.37, 0.36, 0.5), Color(0.72, 0.7, 0.67, 0.0))
	dense_smoke.position = Vector3(0.0, 1.8, 0.0)
	high_smoke.position = Vector3(0.0, 4.0, 0.0)
	add_child(dense_smoke)
	add_child(high_smoke)
	steam_particles = _make_smoke_layer("VaporFinal", 48, 1.25, 0.28, 1.6, Color(0.82, 0.9, 0.95, 0.72), Color(0.9, 0.96, 1.0, 0.0))
	steam_particles.one_shot = true
	steam_particles.emitting = false
	steam_particles.position = Vector3(0.0, 2.2, 0.0)
	add_child(steam_particles)
	_apply_wind()

func _make_smoke_layer(node_name: String, amount: int, lifetime: float, velocity: float, size: float, start_color: Color, end_color: Color) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = node_name
	particles.amount = amount
	particles.lifetime = lifetime
	particles.emitting = true
	particles.local_coords = true
	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(0.55, 0.25, 0.55)
	process_material.direction = Vector3(0.0, 1.0, 0.0)
	process_material.spread = 18.0
	process_material.initial_velocity_min = velocity * 0.5
	process_material.initial_velocity_max = velocity
	process_material.gravity = Vector3(0.0, -0.18, 0.0)
	process_material.scale_min = size * 0.55
	process_material.scale_max = size
	var expansion_curve := Curve.new()
	expansion_curve.add_point(Vector2(0.0, 0.3))
	expansion_curve.add_point(Vector2(1.0, 1.6))
	var expansion_texture := CurveTexture.new()
	expansion_texture.curve = expansion_curve
	process_material.scale_curve = expansion_texture
	process_material.color_ramp = _smoke_gradient(start_color, end_color)
	particles.process_material = process_material
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.vertex_color_use_as_albedo = true
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.0, 2.0)
	mesh.material = material
	material.albedo_texture = _radial_smoke_texture()
	particles.draw_pass_1 = mesh
	return particles

func _radial_smoke_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.7))
	gradient.add_point(0.62, Color(1.0, 1.0, 1.0, 0.22))
	gradient.set_color(gradient.get_point_count() - 1, Color(1.0, 1.0, 1.0, 0.0))
	var texture := GradientTexture2D.new()
	texture.width = 64
	texture.height = 64
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.gradient = gradient
	return texture

func _smoke_gradient(start_color: Color, end_color: Color) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, start_color)
	gradient.add_point(0.45, Color(
		lerpf(start_color.r, end_color.r, 0.55),
		lerpf(start_color.g, end_color.g, 0.55),
		lerpf(start_color.b, end_color.b, 0.55),
		lerpf(start_color.a, end_color.a, 0.55)
	))
	gradient.set_color(gradient.get_point_count() - 1, end_color)
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture

func _apply_wind() -> void:
	for particles in [dense_smoke, high_smoke, steam_particles]:
		if not is_instance_valid(particles):
			continue
		var process_material := particles.process_material as ParticleProcessMaterial
		process_material.direction = Vector3(viento.x, 1.0, viento.z).normalized()
