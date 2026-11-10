extends Node3D

const PALETA := preload("res://scripts/world/paleta.gd")

@export_group("Zona del incendio")
@export var centro_incendio: Vector3 = Vector3(55.0, 60.0, -120.0)
@export_range(50.0, 300.0, 1.0) var radio_zona: float = 155.0
@export_range(0.0, 0.02, 0.0001) var densidad_niebla_incendio: float = 0.0045
@export var color_niebla_incendio: Color = Color(0.48, 0.39, 0.34, 1.0)
@export_range(0.1, 10.0, 0.1) var duracion_transicion: float = 3.2

@export_group("Cielo y nubes")
@export var crear_nubes: bool = true
@export_range(1.0, 30.0, 0.5) var velocidad_nubes: float = 2.0

var world_environment: WorldEnvironment
var environment: Environment
var sky_material: ProceduralSkyMaterial
var sun: DirectionalLight3D
var ambient_tween: Tween
var is_in_fire_zone: bool = false
var cloud_roots: Array[Node3D] = []
var cloud_directions: Array[float] = []

var clear_top_color: Color = PALETA.CIELO
var clear_horizon_color: Color = PALETA.HORIZONTE
var clear_ground_color: Color = PALETA.PASTO
var clear_fog_color: Color = PALETA.HORIZONTE
var clear_ambient_energy: float = 0.48
var clear_sun_energy: float = 0.78

func _ready() -> void:
	world_environment = get_tree().root.find_child("WorldEnvironment", true, false) as WorldEnvironment
	sun = get_tree().root.find_child("SunLight", true, false) as DirectionalLight3D
	if not world_environment or not world_environment.environment:
		push_error("MapAtmosphere requiere un WorldEnvironment con Environment asignado.")
		return
	environment = world_environment.environment
	if environment.sky and environment.sky.sky_material is ProceduralSkyMaterial:
		sky_material = environment.sky.sky_material as ProceduralSkyMaterial
		sky_material.sky_top_color = clear_top_color
		sky_material.sky_horizon_color = clear_horizon_color
		sky_material.ground_horizon_color = clear_ground_color
	if sun:
		sun.light_color = PALETA.SOL
		clear_sun_energy = 0.78
	_configure_clear_weather()
	_create_fire_zone()
	if crear_nubes:
		_create_clouds()

func _process(delta: float) -> void:
	for index in range(cloud_roots.size()):
		var cloud := cloud_roots[index]
		cloud.position.x += cloud_directions[index] * velocidad_nubes * delta
		if cloud.position.x > 620.0:
			cloud.position.x = -620.0
		elif cloud.position.x < -620.0:
			cloud.position.x = 620.0

func _configure_clear_weather() -> void:
	environment.background_mode = Environment.BG_SKY
	environment.fog_enabled = true
	environment.fog_light_color = clear_fog_color
	environment.fog_density = 0.00045
	environment.ambient_light_energy = clear_ambient_energy
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.85
	environment.glow_enabled = true
	environment.glow_intensity = 0.04
	environment.glow_strength = 0.12
	if sky_material:
		sky_material.sky_top_color = clear_top_color
		sky_material.sky_horizon_color = clear_horizon_color
		sky_material.ground_horizon_color = clear_ground_color
	if sun:
		sun.light_color = PALETA.SOL
		sun.shadow_enabled = true

func _create_fire_zone() -> void:
	var area := Area3D.new()
	area.name = "ZonaAmbienteIncendio"
	area.position = centro_incendio
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = true
	add_child(area)
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radio_zona
	shape.height = 420.0
	collision.shape = shape
	area.add_child(collision)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	area.set_meta("drone_area", true)
	call_deferred("_sync_overlapping_bodies", area)

func _sync_overlapping_bodies(area: Area3D) -> void:
	if not is_instance_valid(area):
		return
	for body in area.get_overlapping_bodies():
		_on_body_entered(body)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("jugador"):
		_set_fire_ambience(true)

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("jugador"):
		_set_fire_ambience(false)

func _set_fire_ambience(active: bool) -> void:
	if is_in_fire_zone == active or not environment:
		return
	is_in_fire_zone = active
	if ambient_tween and ambient_tween.is_running():
		ambient_tween.kill()
	ambient_tween = create_tween().set_parallel(true)
	var target_fog := densidad_niebla_incendio if active else 0.00045
	var target_fog_color := color_niebla_incendio if active else clear_fog_color
	var target_ambient := 0.46 if active else clear_ambient_energy
	ambient_tween.tween_property(environment, "fog_density", target_fog, duracion_transicion)
	ambient_tween.tween_property(environment, "fog_light_color", target_fog_color, duracion_transicion)
	ambient_tween.tween_property(environment, "ambient_light_energy", target_ambient, duracion_transicion)
	if sky_material:
		var fire_top := Color(0.43, 0.47, 0.52, 1.0) if active else clear_top_color
		var fire_horizon := Color(0.72, 0.55, 0.43, 1.0) if active else clear_horizon_color
		var fire_ground := Color(0.42, 0.36, 0.33, 1.0) if active else clear_ground_color
		ambient_tween.tween_property(sky_material, "sky_top_color", fire_top, duracion_transicion)
		ambient_tween.tween_property(sky_material, "sky_horizon_color", fire_horizon, duracion_transicion)
		ambient_tween.tween_property(sky_material, "ground_horizon_color", fire_ground, duracion_transicion)
	if sun:
		ambient_tween.tween_property(sun, "light_energy", 0.72 if active else clear_sun_energy, duracion_transicion)
		ambient_tween.tween_property(sun, "light_color", Color(0.82, 0.62, 0.48, 1.0) if active else Color(1.0, 0.91, 0.74, 1.0), duracion_transicion)

func _create_clouds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 34592
	var cloud_material := StandardMaterial3D.new()
	cloud_material.albedo_color = Color("#e5e9e4")
	cloud_material.roughness = 1.0
	var cloud_mesh := SphereMesh.new()
	cloud_mesh.radial_segments = 8
	cloud_mesh.rings = 5
	for cloud_index in range(10):
		var cloud := Node3D.new()
		cloud.name = "NubeLowPoly_%02d" % cloud_index
		cloud.position = Vector3(
			rng.randf_range(-600.0, 600.0),
			rng.randf_range(105.0, 155.0),
			rng.randf_range(-560.0, 560.0)
		)
		add_child(cloud)
		var puffs := rng.randi_range(3, 5)
		for puff_index in range(puffs):
			var puff := MeshInstance3D.new()
			puff.mesh = cloud_mesh
			puff.material_override = cloud_material
			puff.position = Vector3(
				rng.randf_range(-7.0, 7.0),
				rng.randf_range(-1.5, 1.5),
				rng.randf_range(-4.0, 4.0)
			)
			var size := rng.randf_range(4.5, 8.0)
			puff.scale = Vector3(size * 1.4, size * 0.55, size)
			cloud.add_child(puff)
		cloud_roots.append(cloud)
		cloud_directions.append(rng.randf_range(0.65, 1.0) * (1.0 if rng.randf() > 0.5 else -1.0))
