extends Node3D

signal fuego_apagado(arbol: Node3D)

@export_range(1.0, 500.0, 1.0) var salud_fuego: float = 100.0
@export_range(1.0, 200.0, 1.0) var dano_por_segundo: float = 60.0
@export_range(0.1, 10.0, 0.1) var resistencia: float = 1.0
@export_range(0.0, 10.0, 0.1) var regeneracion: float = 0.0
@export var viento: Vector3 = Vector3(0.8, 0.0, 0.25)

const PALETA := preload("res://scripts/world/paleta.gd")

var salud_maxima: float = 100.0
var fuego_terminado: bool = false
var escena_visual_fuego: PackedScene
var hud: Node
var visual_fuegos: Array[Node3D] = []
var forma_arbol: int = 0
var semilla_arbol: int = 0
var rng := RandomNumberGenerator.new()

func configurar(hud_ref: Node, fire_scene: PackedScene, forma: int, seed: int) -> void:
	hud = hud_ref
	escena_visual_fuego = fire_scene
	forma_arbol = forma
	semilla_arbol = seed

func _ready() -> void:
	salud_maxima = maxf(salud_fuego, 1.0)
	salud_fuego = salud_maxima
	rng.seed = semilla_arbol
	add_to_group("fuego")
	_crear_forma_arbol()
	_crear_fuegos_visuales()
	var gestor := get_tree().root.find_child("FireManager", true, false)
	if gestor and gestor.has_method("registrar_arbol"):
		gestor.call("registrar_arbol", self)
	elif hud and hud.has_method("register_fire_tree"):
		hud.call("register_fire_tree", self)

func _process(delta: float) -> void:
	if fuego_terminado:
		return
	if salud_fuego < salud_maxima:
		salud_fuego = minf(salud_maxima, salud_fuego + regeneracion * delta)
		_actualizar_intensidad()

func _crear_forma_arbol() -> void:
	var wood := _material(PALETA.ARBOL_SECO)
	var branch_mesh := CylinderMesh.new()
	branch_mesh.top_radius = 0.035
	branch_mesh.bottom_radius = 0.18
	branch_mesh.height = 1.0
	branch_mesh.radial_segments = 6
	var trunk := MeshInstance3D.new()
	trunk.name = "TroncoSeco"
	trunk.mesh = branch_mesh
	trunk.material_override = wood
	trunk.position.y = 3.0
	trunk.scale = Vector3(1.0, 6.0, 1.0)
	add_child(trunk)
	match forma_arbol:
		1:
			_crear_copa_seca(branch_mesh, wood)
		2:
			_crear_pino_seco(branch_mesh, wood)
		3:
			_crear_arbol_torcido(branch_mesh, wood)
		_:
			_crear_ramas_torcida(branch_mesh, wood)
	var collider := StaticBody3D.new()
	collider.name = "ColisionArbol"
	add_child(collider)
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.62
	capsule.height = 6.2
	collision.shape = capsule
	collision.position.y = 3.1
	collider.add_child(collision)

func _crear_ramas_torcida(branch_mesh: CylinderMesh, wood: StandardMaterial3D) -> void:
	for branch in range(7):
		var angle := float(branch) * TAU / 7.0 + rng.randf_range(-0.2, 0.2)
		var start := Vector3(0.0, 1.5 + float(branch) * 0.55, 0.0)
		var end := start + Vector3(cos(angle) * rng.randf_range(1.1, 2.2), rng.randf_range(0.7, 1.5), sin(angle) * rng.randf_range(1.1, 2.2))
		_add_branch(branch_mesh, wood, start, end, "RamaSeca_%02d" % branch)

func _crear_copa_seca(branch_mesh: CylinderMesh, wood: StandardMaterial3D) -> void:
	for index in range(7):
		var angle := TAU * float(index) / 7.0
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var start := Vector3(0.0, 2.6 + rng.randf_range(-0.25, 0.45), 0.0)
		var end := direction * rng.randf_range(1.15, 2.0) + Vector3(0.0, rng.randf_range(3.2, 4.8), 0.0)
		_add_branch(branch_mesh, wood, start, end, "RamaCopa_%02d" % index)
		for twig_index in range(3):
			var twig_angle := angle + float(twig_index - 1) * 0.7 + rng.randf_range(-0.18, 0.18)
			var twig_start := end + direction * rng.randf_range(-0.25, 0.15)
			var twig_end := twig_start + Vector3(
				cos(twig_angle) * rng.randf_range(0.45, 0.9),
				rng.randf_range(0.35, 0.85),
				sin(twig_angle) * rng.randf_range(0.45, 0.9)
			)
			_add_branch(branch_mesh, wood, twig_start, twig_end, "RamaFina_%d_%d" % [index, twig_index], 0.11)

func _crear_pino_seco(branch_mesh: CylinderMesh, wood: StandardMaterial3D) -> void:
	var dry_needle := _material(Color8(119, 76, 48))
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.02
	cone_mesh.bottom_radius = 1.0
	cone_mesh.height = 2.0
	cone_mesh.radial_segments = 7
	for layer in range(4):
		var scale_value := 1.65 - float(layer) * 0.28
		var center_y := 2.0 + float(layer) * 1.05
		var canopy := MeshInstance3D.new()
		canopy.name = "CopaPinoSeca_%02d" % layer
		canopy.mesh = cone_mesh
		canopy.material_override = dry_needle
		canopy.position.y = center_y
		canopy.scale = Vector3(scale_value, 0.9, scale_value)
		add_child(canopy)
		for branch in range(4):
			var angle := float(branch) * TAU / 4.0 + float(layer) * 0.35
			var start := Vector3(0.0, center_y - 0.35, 0.0)
			var end := Vector3(cos(angle) * scale_value, center_y + 0.45, sin(angle) * scale_value)
			_add_branch(branch_mesh, wood, start, end, "RamaPino_%d_%d" % [layer, branch])

func _crear_arbol_torcido(branch_mesh: CylinderMesh, wood: StandardMaterial3D) -> void:
	var start := Vector3.ZERO
	for segment in range(6):
		var offset := Vector3(rng.randf_range(-0.55, 0.55), 1.0, rng.randf_range(-0.4, 0.4))
		var finish := start + offset
		_add_branch(branch_mesh, wood, start, finish, "TroncoTorcido_%02d" % segment, 0.42 - float(segment) * 0.045)
		start = finish
	for branch in range(9):
		var angle := float(branch) * TAU / 9.0
		var height := rng.randf_range(2.2, 5.2)
		var begin := Vector3(rng.randf_range(-0.5, 0.5), height, rng.randf_range(-0.35, 0.35))
		var finish := begin + Vector3(cos(angle) * rng.randf_range(1.2, 2.8), rng.randf_range(0.6, 1.8), sin(angle) * rng.randf_range(1.2, 2.8))
		_add_branch(branch_mesh, wood, begin, finish, "RamaRetorcida_%02d" % branch, 0.22)

func _add_branch(mesh: CylinderMesh, material: Material, start: Vector3, finish: Vector3, node_name: String, radius_scale: float = 0.3) -> void:
	var branch := MeshInstance3D.new()
	branch.name = node_name
	branch.mesh = mesh
	branch.material_override = material
	var difference := finish - start
	branch.position = (start + finish) * 0.5
	branch.scale = Vector3(radius_scale, difference.length(), radius_scale)
	branch.quaternion = Quaternion(Vector3.UP, difference.normalized())
	add_child(branch)

func _crear_fuegos_visuales() -> void:
	if escena_visual_fuego:
		var fire_positions: Array[Vector3] = [Vector3(0.0, rng.randf_range(2.3, 3.5), 0.0)]
		if forma_arbol == 1 or forma_arbol == 2:
			fire_positions.append(Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(4.0, 5.2), rng.randf_range(-0.8, 0.8)))
		for index in range(fire_positions.size()):
			var visual := escena_visual_fuego.instantiate() as Node3D
			visual.name = "AnimacionFuego_%02d" % index
			visual.position = fire_positions[index]
			visual.scale = Vector3.ONE * (0.32 if index == 0 else 0.24)
			visual.set("objetivo_extinguible", false)
			add_child(visual)
			if visual.has_method("set_fire_variant"):
				visual.call("set_fire_variant", forma_arbol % 2)
			if visual.has_method("set_viento"):
				visual.call("set_viento", viento)
			if visual.has_method("set_intensidad"):
				visual.call("set_intensidad", 1.0)
			visual_fuegos.append(visual)

func _material(color: Color) -> StandardMaterial3D:
	return PALETA.material(color)

func apply_water_damage(amount: float) -> bool:
	if fuego_terminado or amount <= 0.0:
		return false
	salud_fuego = maxf(0.0, salud_fuego - amount * resistencia)
	_actualizar_intensidad()
	if salud_fuego <= 0.0:
		_extinguir()
		return true
	return false

func apagar(delta: float) -> bool:
	return apply_water_damage(maxf(delta, 0.0) * dano_por_segundo)

func get_fire_target_position() -> Vector3:
	return global_position + Vector3(0.0, 3.0, 0.0)

func _actualizar_intensidad() -> void:
	for visual in visual_fuegos:
		if is_instance_valid(visual) and visual.has_method("set_intensidad"):
			visual.call("set_intensidad", clampf(salud_fuego / salud_maxima, 0.0, 1.0))

func _extinguir() -> void:
	if fuego_terminado:
		return
	fuego_terminado = true
	salud_fuego = 0.0
	remove_from_group("fuego")
	_carbonizar(self)
	for visual in visual_fuegos:
		if is_instance_valid(visual) and visual.has_method("extinguish"):
			visual.call("extinguish")
	fuego_apagado.emit(self)

func _carbonizar(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			var source_material := mesh_instance.material_override
			if source_material is StandardMaterial3D:
				var source_standard_material := source_material as StandardMaterial3D
				var original_color: Color = source_standard_material.albedo_color
				var burnt := source_standard_material.duplicate() as StandardMaterial3D
				burnt.albedo_color = original_color
				burnt.roughness = 0.96
				mesh_instance.material_override = burnt
				var tween := create_tween()
				tween.tween_property(burnt, "albedo_color", PALETA.CARBON, 1.0)
		_carbonizar(child)
