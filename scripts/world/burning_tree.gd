extends Node3D

const PALETA := preload("res://scripts/world/paleta.gd")

var forma_arbol: int = 0
var semilla_arbol: int = 0
var rng := RandomNumberGenerator.new()

func configurar(_hud_ref: Node, forma: int, semilla: int) -> void:
	forma_arbol = forma
	semilla_arbol = semilla

func _ready() -> void:
	rng.seed = semilla_arbol
	add_to_group("arbol_simulado")
	_crear_forma_arbol()

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

func _material(color: Color) -> StandardMaterial3D:
	return PALETA.material(color)

func carbonizar_por_grilla() -> void:
	_carbonizar(self)

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
