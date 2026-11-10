extends Node3D

@export var foliage_density: float = 0.95
@export var random_seed: int = 4821

func _ready() -> void:
	crear_arbol()

func crear_arbol() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = random_seed

	# Tronco central
	var madera = StandardMaterial3D.new()
	madera.albedo_color = Color(0.20, 0.12, 0.07, 1.0)
	madera.roughness = 0.95

	var tronco_mesh = BoxMesh.new()
	tronco_mesh.size = Vector3(0.85, 9.5, 0.85)
	tronco_mesh.material = madera

	var tronco = MeshInstance3D.new()
	tronco.name = "Tronco"
	tronco.mesh = tronco_mesh
	tronco.position.y = 4.75
	add_child(tronco)

	# Follaje en capas escalonadas en cruz (Spruce de Minecraft)
	var materiales: Array[StandardMaterial3D] = []
	var colores = [
		Color(0.08, 0.22, 0.11),
		Color(0.12, 0.28, 0.14),
		Color(0.16, 0.35, 0.18),
		Color(0.21, 0.41, 0.23),
		Color(0.26, 0.46, 0.27)
	]

	for col in colores:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = col
		mat.roughness = 0.9
		materiales.append(mat)

	var hoja_mesh = BoxMesh.new()
	hoja_mesh.size = Vector3(0.95, 0.95, 0.95)
	var grupos: Array[Array] = [[], [], [], [], []]

	var capas = [
		{"y": 3.0, "cuerpo": 1, "puntas": 3},
		{"y": 4.0, "cuerpo": 1, "puntas": 2},
		{"y": 5.0, "cuerpo": 1, "puntas": 2},
		{"y": 6.0, "cuerpo": 1, "puntas": 1},
		{"y": 7.0, "cuerpo": 0, "puntas": 1},
		{"y": 8.0, "cuerpo": 0, "puntas": 0},
		{"y": 9.0, "cuerpo": 0, "puntas": 0}
	]

	for capa in capas:
		var py: float = capa["y"]
		var c_rad: int = capa["cuerpo"]
		var p_ext: int = capa["puntas"]

		for x in range(-c_rad, c_rad + 1):
			for z in range(-c_rad, c_rad + 1):
				if x == 0 and z == 0 and py < 8.0:
					continue
				if rng.randf() > foliage_density:
					continue
				agregar_cubo(grupos, rng, Vector3(x, py, z))

		if p_ext > c_rad:
			for dist in range(c_rad + 1, p_ext + 1):
				var offsets = [
					Vector3(dist, py, 0),
					Vector3(-dist, py, 0),
					Vector3(0, py, dist),
					Vector3(0, py, -dist)
				]
				for pos in offsets:
					if rng.randf() <= foliage_density:
						agregar_cubo(grupos, rng, pos)

	for i in range(materiales.size()):
		if grupos[i].is_empty():
			continue

		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = hoja_mesh
		mm.instance_count = grupos[i].size()

		for j in range(grupos[i].size()):
			mm.set_instance_transform(j, grupos[i][j])

		var hojas_inst = MultiMeshInstance3D.new()
		hojas_inst.name = "Follaje_" + str(i)
		hojas_inst.multimesh = mm
		hojas_inst.material_override = materiales[i]
		add_child(hojas_inst)

func agregar_cubo(grupos: Array[Array], rng: RandomNumberGenerator, base_pos: Vector3) -> void:
	var color_id = rng.randi_range(0, 4)
	var jitter_x = rng.randf_range(-0.04, 0.04)
	var jitter_y = rng.randf_range(-0.04, 0.04)
	var jitter_z = rng.randf_range(-0.04, 0.04)

	var pos_final = Vector3(
		base_pos.x * 0.95 + jitter_x,
		base_pos.y + jitter_y,
		base_pos.z * 0.95 + jitter_z
	)

	var sc = rng.randf_range(0.92, 1.04)
	var t = Transform3D(Basis().scaled(Vector3.ONE * sc), pos_final)
	grupos[color_id].append(t)
