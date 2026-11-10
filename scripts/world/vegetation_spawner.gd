extends Node3D

const BURNING_TREE_SCRIPT := preload("res://scripts/world/burning_tree.gd")
const FIRE_SCENE := preload("res://scenes/actors/fire_source.tscn")
const PALETA := preload("res://scripts/world/paleta.gd")
const FOREST_MESHES := preload("res://scripts/world/procedural_forest_meshes.gd")

@export_group("Bosque")
@export_range(4, 40, 1) var separacion_arboles: int = 22
@export_range(0.0, 1.0, 0.01) var densidad_bosque: float = 0.58
@export_range(1, 60, 1) var cantidad_arboles_en_llamas: int = 30
@export var semilla_mapa: int = 12345

const FIRE_CENTER := Vector2(55.0, -120.0)
const FIRE_RADIUS := 65.0
const REFILL_CENTER := Vector2(-178.0, 40.0)
const HELIPAD_CENTER := Vector2(-120.0, 40.0)

var rng := RandomNumberGenerator.new()
var forest_noise := FastNoiseLite.new()
var foliage_shader: Shader
var hud: Node
var terrain_generator: Node
var green_tree_transforms: Array[Transform3D] = []
var pine_tree_transforms: Array[Transform3D] = []
var slender_pine_transforms: Array[Transform3D] = []
var autumn_tree_transforms: Array[Transform3D] = []
var grass_transforms: Array[Transform3D] = []
var grass_light_transforms: Array[Transform3D] = []
var grass_dark_transforms: Array[Transform3D] = []
var flower_transforms: Array[Transform3D] = []
var mushroom_stem_transforms: Array[Transform3D] = []
var mushroom_cap_transforms: Array[Transform3D] = []
var orange_mushroom_cap_transforms: Array[Transform3D] = []
var crystal_transforms: Array[Transform3D] = []
var small_rock_transforms: Array[Transform3D] = []
var tree_positions: Array[Vector2] = []

func _ready() -> void:
	rng.seed = semilla_mapa
	forest_noise.seed = semilla_mapa
	forest_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	forest_noise.frequency = 0.006
	forest_noise.fractal_octaves = 3
	hud = get_tree().root.find_child("TacticalHUD", true, false)
	terrain_generator = get_tree().root.find_child("MountainTerrain", true, false)
	_generar_bosque_y_detalles()
	_crear_multimeshes()
	_generar_arboles_en_llamas()
	_crear_escenografia()

func _generar_bosque_y_detalles() -> void:
	for x in range(-540, 521, separacion_arboles):
		for z in range(-540, 541, separacion_arboles):
			var px := float(x) + rng.randf_range(-8.0, 8.0)
			var pz := float(z) + rng.randf_range(-8.0, 8.0)
			if _zona_protegida(Vector2(px, pz)):
				continue
			var density := (forest_noise.get_noise_2d(px, pz) + 1.0) * 0.5
			if density > densidad_bosque and _pendiente_apta(px, pz) and _posicion_arbol_apta(px, pz):
				_agregar_arbol_multimesh(px, pz)
			if rng.randf() < 0.38:
				_agregar_detalle_suelo(px, pz)

func _agregar_arbol_multimesh(px: float, pz: float) -> void:
	var ground_y := get_exact_ground_y(px, pz)
	var tree_scale := rng.randf_range(1.8, 2.8)
	var yaw := rng.randf_range(0.0, TAU)
	var kind := rng.randi_range(0, 5)
	var size_factor := 1.0 if kind == 0 or kind == 2 or kind == 3 else 0.82
	var tilt_x := rng.randf_range(-0.035, 0.035)
	var tilt_z := rng.randf_range(-0.035, 0.035)
	var tree_rotation := Basis.from_euler(Vector3(tilt_x, yaw, tilt_z))
	var transform: Transform3D = Transform3D(
		tree_rotation.scaled(Vector3.ONE * tree_scale * size_factor),
		Vector3(px, ground_y, pz)
	)
	match kind:
		2:
			pine_tree_transforms.append(transform)
		3:
			autumn_tree_transforms.append(transform)
		4:
			slender_pine_transforms.append(transform)
		_:
			green_tree_transforms.append(transform)
	tree_positions.append(Vector2(px, pz))
	if tree_scale * size_factor > 2.4:
		_add_tree_collision(px, pz, ground_y, tree_scale * size_factor)

func _agregar_detalle_suelo(px: float, pz: float) -> void:
	var ground_y := get_exact_ground_y(px, pz)
	if rng.randf() < 0.78:
		for blade in range(rng.randi_range(5, 8)):
			var gx := px + rng.randf_range(-2.2, 2.2)
			var gz := pz + rng.randf_range(-2.2, 2.2)
			var grass_height := rng.randf_range(0.45, 0.9)
			var grass_width := rng.randf_range(0.07, 0.14)
			var lean := Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(0.0, TAU), rng.randf_range(-0.2, 0.2))
			var grass_transform := Transform3D(
				Basis.from_euler(lean).scaled(Vector3(grass_width, grass_height, grass_width)),
				Vector3(gx, get_exact_ground_y(gx, gz) + grass_height * 0.5, gz)
			)
			match rng.randi_range(0, 2):
				0:
					grass_transforms.append(grass_transform)
				1:
					grass_light_transforms.append(grass_transform)
				_:
					grass_dark_transforms.append(grass_transform)
	if rng.randf() < 0.10:
		var flower_size := rng.randf_range(0.12, 0.22)
		flower_transforms.append(_instance_transform(
			Vector3(px, ground_y + flower_size, pz), Vector3.ONE * flower_size,
			rng.randf_range(0.0, TAU)
		))
	if rng.randf() < 0.035:
		var mushroom_size := rng.randf_range(0.55, 1.0)
		mushroom_stem_transforms.append(_instance_transform(
			Vector3(px, ground_y + 0.25 * mushroom_size, pz),
			Vector3(0.12, 0.5 * mushroom_size, 0.12), rng.randf_range(0.0, TAU)
		))
		var cap_transform := _instance_transform(
			Vector3(px, ground_y + 0.42 * mushroom_size, pz),
			Vector3(0.38, 0.18, 0.38) * mushroom_size, rng.randf_range(0.0, TAU)
		)
		if rng.randf() < 0.5:
			mushroom_cap_transforms.append(cap_transform)
		else:
			orange_mushroom_cap_transforms.append(cap_transform)
	if rng.randf() < 0.018:
		var crystal_height := rng.randf_range(0.7, 1.4)
		crystal_transforms.append(_instance_transform(
			Vector3(px, ground_y + crystal_height * 0.5, pz),
			Vector3(0.34, crystal_height, 0.34), rng.randf_range(0.0, TAU)
		))
	if rng.randf() < 0.08:
		var rock_scale := Vector3(rng.randf_range(0.5, 1.0), rng.randf_range(0.4, 0.7), rng.randf_range(0.5, 1.0))
		small_rock_transforms.append(_instance_transform(
			Vector3(px, ground_y + rock_scale.y * 0.58, pz),
			rock_scale,
			rng.randf_range(0.0, TAU)
		))

func _crear_multimeshes() -> void:
	var variant_rng := RandomNumberGenerator.new()
	variant_rng.seed = semilla_mapa ^ 76157
	var green_meshes: Array[Mesh] = []
	var autumn_meshes: Array[Mesh] = []
	var pine_meshes: Array[Mesh] = []
	var slender_pine_meshes: Array[Mesh] = []
	var green_colors: Array[Color] = [
		PALETA.COPA_VERDE,
		PALETA.COPA_VERDE_CLARA,
		PALETA.COPA_VERDE_OSCURA,
		PALETA.PINO_CLARO,
	]
	var pine_colors: Array[Color] = [
		PALETA.PINO_OSCURO,
		PALETA.PINO,
		Color("#3b625e"),
		Color("#4d7157"),
	]
	var autumn_colors: Array[Color] = [
		PALETA.OTONO,
		Color("#b86145"),
		Color("#d18a4d"),
		Color("#a94e3d"),
	]
	for variant in range(4):
		green_meshes.append(FOREST_MESHES.crear_arbol_hoja_ancha(
			variant_rng.randi(), variant_rng.randf_range(3.2, 4.0), green_colors[variant]
		))
		autumn_meshes.append(FOREST_MESHES.crear_arbol_hoja_ancha(
			variant_rng.randi(), variant_rng.randf_range(3.2, 4.0), autumn_colors[variant]
		))
		pine_meshes.append(FOREST_MESHES.crear_pino(
			variant_rng.randi(), variant_rng.randf_range(3.2, 4.0), false, pine_colors[variant]
		))
		slender_pine_meshes.append(FOREST_MESHES.crear_pino(
			variant_rng.randi(), variant_rng.randf_range(3.2, 4.0), true, pine_colors[(variant + 1) % pine_colors.size()]
		))
	var vertex_color_material := FOREST_MESHES.material_vertex_color()
	_add_multimesh_variants("ArbolesFrondosos", green_meshes, vertex_color_material, green_tree_transforms)
	_add_multimesh_variants("Pinos", pine_meshes, vertex_color_material, pine_tree_transforms)
	_add_multimesh_variants("PinosEstilizados", slender_pine_meshes, vertex_color_material, slender_pine_transforms)
	_add_multimesh_variants("ArbolesOtonales", autumn_meshes, vertex_color_material, autumn_tree_transforms)
	var grass_mesh := FOREST_MESHES.crear_pasto()
	_add_multimesh("Pasto", grass_mesh, _material_vegetacion(PALETA.PASTO), grass_transforms)
	_add_multimesh("PastoClaro", grass_mesh, _material_vegetacion(PALETA.PASTO_CLARO), grass_light_transforms)
	_add_multimesh("PastoOscuro", grass_mesh, _material_vegetacion(PALETA.PASTO_OSCURO), grass_dark_transforms)
	_add_multimesh("Flores", _sphere_mesh(6, 4), _material(PALETA.FLOR), flower_transforms)
	_add_multimesh("TallosHongos", _cylinder_mesh(0.5, 1.0, 7), _material(PALETA.HORIZONTE), mushroom_stem_transforms)
	_add_multimesh("HongosRojosYNaranjas", _sphere_mesh(6, 4), _material(PALETA.HONGO_ROJO), mushroom_cap_transforms)
	_add_multimesh("HongosNaranjas", _sphere_mesh(6, 4), _material(PALETA.HONGO_NARANJA), orange_mushroom_cap_transforms)
	_add_multimesh("CristalesAzules", _cone_mesh(0.55, 1.0, 6), _material(PALETA.CRISTAL), crystal_transforms)
	_add_multimesh("RocasPequenas", FOREST_MESHES.crear_roca(semilla_mapa + 991, Vector3.ONE), FOREST_MESHES.material_vertex_color(), small_rock_transforms)

func _generar_arboles_en_llamas() -> void:
	var clusters: Array[Vector2] = []
	var attempts := 0
	while clusters.size() < cantidad_arboles_en_llamas and attempts < cantidad_arboles_en_llamas * 50:
		attempts += 1
		var anchor_angle := rng.randf_range(0.0, TAU)
		var anchor_distance := rng.randf_range(16.0, FIRE_RADIUS - 16.0)
		var anchor := FIRE_CENTER + Vector2(cos(anchor_angle), sin(anchor_angle)) * anchor_distance
		var cluster_size := mini(rng.randi_range(3, 6), cantidad_arboles_en_llamas - clusters.size())
		var candidates: Array[Vector2] = []
		for _tree_index in range(cluster_size):
			var angle := rng.randf_range(0.0, TAU)
			var radius := rng.randf_range(3.5, 9.0)
			var point := anchor + Vector2(cos(angle), sin(angle)) * radius
			if point.distance_to(FIRE_CENTER) > FIRE_RADIUS - 3.0:
				continue
			var separated := true
			for existing in clusters + candidates:
				if point.distance_to(existing) < 7.0:
					separated = false
					break
			if separated:
				candidates.append(point)
		clusters.append_array(candidates)
		if candidates.is_empty() and attempts % 5 == 0:
			var fallback_angle := rng.randf_range(0.0, TAU)
			var fallback_radius := rng.randf_range(12.0, FIRE_RADIUS - 6.0)
			clusters.append(FIRE_CENTER + Vector2(cos(fallback_angle), sin(fallback_angle)) * fallback_radius)
	for index in range(clusters.size()):
		var point := clusters[index]
		var tree := Node3D.new()
		tree.name = "ArbolSecoEnLlamas_%02d" % (index + 1)
		tree.set_script(BURNING_TREE_SCRIPT)
		tree.call("configurar", hud, FIRE_SCENE, rng.randi_range(0, 3), rng.randi())
		add_child(tree)
		tree.position = Vector3(point.x, get_exact_ground_y(point.x, point.y), point.y)
		tree.rotation.y = rng.randf_range(0.0, TAU)
		tree.scale = Vector3.ONE * rng.randf_range(1.25, 1.75)

func _crear_escenografia() -> void:
	_crear_casa(Vector3(230.0, get_exact_ground_y(230.0, -235.0), -235.0))
	_crear_pozo(Vector3(244.0, get_exact_ground_y(244.0, -224.0), -224.0))
	_crear_puente(Vector3(185.0, get_exact_ground_y(185.0, 245.0), 245.0))
	_crear_ruinas(Vector3(275.0, get_exact_ground_y(275.0, 175.0), 175.0))
	_crear_farol_y_letrero(Vector3(252.0, get_exact_ground_y(252.0, -218.0), -218.0))
	_crear_troncos_y_tocones()
	_crear_grandes_rocas()
	_crear_camino(Vector2(230.0, -235.0), Vector2(320.0, -80.0))
	_crear_sendero_tierra([
		Vector2(230.0, -235.0),
		Vector2(320.0, -80.0),
		Vector2(300.0, 60.0),
		Vector2(170.0, 90.0),
		Vector2(20.0, 65.0),
		HELIPAD_CENTER,
	])

func _crear_casa(at: Vector3) -> void:
	var house := StaticBody3D.new()
	house.name = "CasaDeCampo"
	house.position = at
	add_child(house)
	_add_solid_box(house, "Muros", Vector3(12.0, 6.0, 9.0), Vector3(0.0, 3.0, 0.0), _material(Color("#9c8060")), true)
	var roof_material := _material(Color("#925447"))
	_add_box_visual(house, "TechoRojoIzquierdo", Vector3(8.0, 0.65, 11.0), Vector3(-2.2, 7.0, 0.0), roof_material, Vector3(0.0, 0.0, deg_to_rad(18.0)))
	_add_box_visual(house, "TechoRojoDerecho", Vector3(8.0, 0.65, 11.0), Vector3(2.2, 7.0, 0.0), roof_material, Vector3(0.0, 0.0, deg_to_rad(-18.0)))
	_add_cylinder_visual(house, "Chimenea", 0.55, 3.5, Vector3(4.0, 8.0, -2.0), _material(Color("#665448")))
	_add_box_visual(house, "Puerta", Vector3(1.6, 3.2, 0.16), Vector3(0.0, 1.6, -4.58), _material(Color("#684b35")))
	for side in [-1.0, 1.0]:
		for front in [-1.0, 1.0]:
			_add_box_visual(house, "TravesanoDeMadera", Vector3(0.28, 6.2, 0.28), Vector3(side * 5.78, 3.0, front * 4.38), _material(Color("#705339")))
	_add_box_visual(house, "VigaFrontal", Vector3(11.8, 0.28, 0.28), Vector3(0.0, 5.75, -4.45), _material(Color("#705339")))
	for window_x in [-3.6, 3.6]:
		_add_box_visual(house, "Ventana", Vector3(1.8, 1.5, 0.15), Vector3(window_x, 3.6, -4.62), _material(Color("#839da0")))
		for shutter_side in [-1.0, 1.0]:
			_add_box_visual(house, "Postigo", Vector3(0.36, 1.7, 0.2), Vector3(window_x + shutter_side * 1.05, 3.6, -4.64), _material(Color("#76583b")))
	_crear_cerca(house, Vector3(0.0, 0.0, 0.0))

func _crear_pozo(at: Vector3) -> void:
	var well := Node3D.new()
	well.name = "PozoDePiedra"
	well.position = at
	add_child(well)
	var stone := _material(PALETA.ROCA_CALIDA)
	var wood := _material(Color("#715338"))
	for index in range(8):
		var angle := TAU * float(index) / 8.0
		_add_cylinder_visual(
			well,
			"PiedraDelBrocal",
			0.33,
			0.8,
			Vector3(cos(angle) * 0.86, 0.4, sin(angle) * 0.86),
			stone
		)
	_add_cylinder_visual(well, "AguaDelPozo", 0.62, 0.12, Vector3(0.0, 0.52, 0.0), _material(Color("#526e70")))
	for side in [-1.0, 1.0]:
		_add_cylinder_visual(well, "PosteDelPozo", 0.12, 3.2, Vector3(side * 1.12, 1.6, 0.0), wood)
	_add_cylinder_visual(well, "EjeDelPozo", 0.1, 2.4, Vector3(0.0, 2.8, 0.0), wood, Vector3(0.0, 0.0, PI * 0.5))
	_add_box_visual(well, "TechoDelPozoIzquierdo", Vector3(1.7, 0.18, 2.8), Vector3(-0.45, 3.45, 0.0), wood, Vector3(0.0, 0.0, deg_to_rad(20.0)))
	_add_box_visual(well, "TechoDelPozoDerecho", Vector3(1.7, 0.18, 2.8), Vector3(0.45, 3.45, 0.0), wood, Vector3(0.0, 0.0, deg_to_rad(-20.0)))
	_add_cylinder_visual(well, "CuerdaYManivela", 0.045, 1.6, Vector3(0.0, 1.7, -0.12), wood)

func _crear_cerca(parent: Node3D, _origin: Vector3) -> void:
	var wood := _material(Color8(138, 98, 61))
	for side in [-1.0, 1.0]:
		for index in range(9):
			var x := -10.0 + float(index) * 2.5
			_add_cylinder_visual(parent, "PosteCerca", 0.12, 1.5, Vector3(x, 0.75, side * 8.5), wood)
		_add_box_visual(parent, "BarandaCerca", Vector3(20.0, 0.18, 0.18), Vector3(0.0, 0.75, side * 8.5), wood)
		_add_box_visual(parent, "BarandaCerca", Vector3(20.0, 0.18, 0.18), Vector3(0.0, 1.25, side * 8.5), wood)
	for side in [-1.0, 1.0]:
		for index in range(7):
			var z := -7.0 + float(index) * 2.3
			_add_cylinder_visual(parent, "PosteCerca", 0.12, 1.5, Vector3(side * 10.0, 0.75, z), wood)
		_add_box_visual(parent, "BarandaCerca", Vector3(0.18, 0.18, 16.0), Vector3(side * 10.0, 0.75, 0.0), wood)

func _crear_puente(at: Vector3) -> void:
	var bridge := StaticBody3D.new()
	bridge.name = "PuenteMadera"
	bridge.position = at
	add_child(bridge)
	var wood := _material(Color8(143, 101, 63))
	for index in range(10):
		var z := -5.0 + float(index)
		_add_solid_box(bridge, "Tablon", Vector3(5.5, 0.22, 0.9), Vector3(0.0, 1.2, z), wood, true)
	for side in [-1.0, 1.0]:
		_add_cylinder_visual(bridge, "CablePuente", 0.08, 11.0, Vector3(side * 2.45, 2.4, 0.0), wood, Vector3(PI * 0.5, 0.0, 0.0))
		for z in range(-5, 6, 2):
			_add_cylinder_visual(bridge, "PostePuente", 0.1, 1.3, Vector3(side * 2.4, 1.9, float(z)), wood)

func _crear_ruinas(at: Vector3) -> void:
	var ruins := StaticBody3D.new()
	ruins.name = "ArcoDePiedraEnRuinas"
	ruins.position = at
	add_child(ruins)
	var stone := _material(Color8(157, 151, 129))
	_add_solid_box(ruins, "PilarIzquierdo", Vector3(1.8, 5.5, 1.8), Vector3(-3.2, 2.75, 0.0), stone, true)
	_add_solid_box(ruins, "PilarDerecho", Vector3(1.8, 4.4, 1.8), Vector3(3.2, 2.2, 0.0), stone, true)
	_add_solid_box(ruins, "DintelRoto", Vector3(8.0, 1.4, 2.0), Vector3(0.0, 5.4, 0.0), stone, true, Vector3(0.0, 0.0, deg_to_rad(-8.0)))

func _crear_farol_y_letrero(at: Vector3) -> void:
	var props := Node3D.new()
	props.name = "FarolYLetrero"
	props.position = at
	add_child(props)
	var wood := _material(Color8(111, 77, 48))
	var metal := _material(Color8(66, 77, 81), 0.35)
	_add_cylinder_visual(props, "PosteFarol", 0.12, 4.2, Vector3(0.0, 2.1, 0.0), metal)
	_add_box_visual(props, "LuzFarol", Vector3(0.7, 0.65, 0.7), Vector3(0.0, 4.25, 0.0), _material(Color8(255, 224, 153), 0.1))
	var lantern_light := OmniLight3D.new()
	lantern_light.name = "LuzCalidaFarol"
	lantern_light.light_color = Color(1.0, 0.72, 0.35, 1.0)
	lantern_light.light_energy = 1.2
	lantern_light.omni_range = 9.0
	lantern_light.position.y = 4.2
	props.add_child(lantern_light)
	_add_cylinder_visual(props, "PosteLetrero", 0.13, 2.4, Vector3(2.4, 1.2, 0.0), wood)
	_add_box_visual(props, "LetreroMadera", Vector3(2.2, 0.9, 0.18), Vector3(2.4, 2.0, -0.05), wood)

func _crear_troncos_y_tocones() -> void:
	var wood := _material(Color8(107, 76, 52))
	for _index in range(12):
		var px := rng.randf_range(-480.0, 480.0)
		var pz := rng.randf_range(-480.0, 480.0)
		if _zona_protegida(Vector2(px, pz)) or Vector2(px, pz).distance_to(FIRE_CENTER) < 92.0:
			continue
		var ground_y := get_exact_ground_y(px, pz)
		var log := _mesh_instance("TroncoCaido", _cylinder_mesh(0.4, 4.0, 7), wood)
		log.position = Vector3(px, ground_y + 0.42, pz)
		log.rotation.z = PI * 0.5
		log.rotation.y = rng.randf_range(0.0, TAU)
		add_child(log)
	for _index in range(16):
		var px := rng.randf_range(-500.0, 500.0)
		var pz := rng.randf_range(-500.0, 500.0)
		if _zona_protegida(Vector2(px, pz)) or Vector2(px, pz).distance_to(FIRE_CENTER) < 92.0:
			continue
		_add_cylinder_visual(self, "Tocon", rng.randf_range(0.28, 0.5), 0.7, Vector3(px, get_exact_ground_y(px, pz) + 0.35, pz), wood)

func _add_tree_collision(px: float, pz: float, ground_y: float, tree_scale: float) -> void:
	var body := StaticBody3D.new()
	body.name = "ColisionArbolGrande"
	body.position = Vector3(px, ground_y, pz)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4 * tree_scale
	capsule.height = 4.0 * tree_scale
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = 2.0 * tree_scale
	body.add_child(shape)
	add_child(body)

func _crear_grandes_rocas() -> void:
	var rock_material := FOREST_MESHES.material_vertex_color()
	var rock_meshes: Array[Mesh] = []
	var rock_rng := RandomNumberGenerator.new()
	rock_rng.seed = semilla_mapa ^ 38471
	for variant in range(5):
		rock_meshes.append(FOREST_MESHES.crear_roca(rock_rng.randi(), Vector3.ONE))
	for index in range(30):
		var point: Vector2
		if index < 12:
			var angle := rng.randf_range(0.0, TAU)
			var radius := rng.randf_range(88.0, 118.0)
			point = FIRE_CENTER + Vector2(cos(angle), sin(angle)) * radius
		else:
			point = Vector2(rng.randf_range(-500.0, 500.0), rng.randf_range(-500.0, 500.0))
		var px := point.x
		var pz := point.y
		if _zona_protegida(Vector2(px, pz)):
			continue
		if index >= 12 and Vector2(px, pz).distance_to(FIRE_CENTER) < 90.0:
			continue
		var ground_y := get_exact_ground_y(px, pz)
		var scale_x := rng.randf_range(1.3, 3.2)
		var rock_height := scale_x * rng.randf_range(0.55, 0.95)
		var rock_depth := scale_x * 0.85
		var rock := StaticBody3D.new()
		rock.name = "RocaGrande"
		rock.position = Vector3(px, ground_y + rock_height * 0.58, pz)
		rock.rotation.y = rng.randf_range(0.0, TAU)
		add_child(rock)
		var mesh_instance := _mesh_instance("Malla", rock_meshes[index % rock_meshes.size()], rock_material)
		mesh_instance.scale = Vector3(scale_x, rock_height, rock_depth)
		rock.add_child(mesh_instance)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(scale_x * 1.5, rock_height * 1.5, rock_depth * 1.5)
		collision.shape = shape
		rock.add_child(collision)

func _crear_camino(start: Vector2, finish: Vector2) -> void:
	var transforms: Array[Transform3D] = []
	var stone_material := FOREST_MESHES.material_vertex_color()
	var stone_mesh := FOREST_MESHES.crear_roca(semilla_mapa ^ 8821, Vector3.ONE)
	for index in range(50):
		var t := float(index) / 49.0
		var point := start.lerp(finish, t)
		point.x += sin(t * PI * 3.2) * 7.0 + rng.randf_range(-1.3, 1.3)
		point.y += cos(t * PI * 2.5) * 3.5 + rng.randf_range(-1.2, 1.2)
		var stone_count := rng.randi_range(2, 4)
		for _stone_index in range(stone_count):
			var stone_x := point.x + rng.randf_range(-1.8, 1.8)
			var stone_z := point.y + rng.randf_range(-1.6, 1.6)
			if _zona_protegida(Vector2(stone_x, stone_z)):
				continue
			var stone_size := Vector3(
				rng.randf_range(0.38, 0.72),
				rng.randf_range(0.11, 0.19),
				rng.randf_range(0.32, 0.62)
			)
			var y := get_exact_ground_y(stone_x, stone_z)
			transforms.append(_instance_transform(
				Vector3(stone_x, y + stone_size.y * 0.58, stone_z),
				stone_size, rng.randf_range(0.0, TAU)
			))
	_add_multimesh("SenderoPiedrasIrregulares", stone_mesh, stone_material, transforms)

func _crear_sendero_tierra(waypoints: Array[Vector2]) -> void:
	if waypoints.size() < 2:
		return
	var samples: Array[Vector2] = []
	var distance_along := 0.0
	for segment in range(waypoints.size() - 1):
		var start := waypoints[segment]
		var finish := waypoints[segment + 1]
		var steps := maxi(4, ceili(start.distance_to(finish) / 4.0))
		for step in range(steps):
			var t := float(step) / float(steps)
			samples.append(start.lerp(finish, t))
	samples.append(waypoints[waypoints.size() - 1])
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(samples.size() - 1):
		var previous := samples[maxi(index - 1, 0)]
		var next := samples[mini(index + 1, samples.size() - 1)]
		var tangent := (next - previous).normalized()
		var side := Vector2(-tangent.y, tangent.x)
		var center := samples[index] + side * sin(distance_along * 0.018) * 3.2
		var width := 5.2 + sin(distance_along * 0.037) * 0.75
		var left := center + side * width * 0.5
		var right := center - side * width * 0.5
		var following := samples[index + 1] + side * sin((distance_along + 4.0) * 0.018) * 3.2
		var left_next := following + side * width * 0.5
		var right_next := following - side * width * 0.5
		var left_vertex := Vector3(left.x, get_exact_ground_y(left.x, left.y) + 0.07, left.y)
		var right_vertex := Vector3(right.x, get_exact_ground_y(right.x, right.y) + 0.07, right.y)
		var left_next_vertex := Vector3(left_next.x, get_exact_ground_y(left_next.x, left_next.y) + 0.07, left_next.y)
		var right_next_vertex := Vector3(right_next.x, get_exact_ground_y(right_next.x, right_next.y) + 0.07, right_next.y)
		surface.add_vertex(left_vertex)
		surface.add_vertex(left_next_vertex)
		surface.add_vertex(right_vertex)
		surface.add_vertex(right_vertex)
		surface.add_vertex(left_next_vertex)
		surface.add_vertex(right_next_vertex)
		distance_along += samples[index].distance_to(samples[index + 1])
	surface.generate_normals()
	var path := MeshInstance3D.new()
	path.name = "SenderoTierra"
	path.mesh = surface.commit()
	path.material_override = _material(Color("#75684e"))
	add_child(path)

func _zona_protegida(point: Vector2) -> bool:
	return (
		point.distance_to(REFILL_CENTER) < 72.0
		or point.distance_to(HELIPAD_CENTER) < 52.0
		or point.distance_to(FIRE_CENTER) < 88.0
		or _en_ruta_dron(point)
		or point.distance_to(Vector2(230.0, -235.0)) < 46.0
		or point.distance_to(Vector2(244.0, -224.0)) < 10.0
		or point.distance_to(Vector2(185.0, 245.0)) < 16.0
		or point.distance_to(Vector2(275.0, 175.0)) < 17.0
		or _en_sendero_visual(point)
	)

func _en_sendero_visual(point: Vector2) -> bool:
	var route: Array[Vector2] = [
		Vector2(230.0, -235.0),
		Vector2(320.0, -80.0),
		Vector2(300.0, 60.0),
		Vector2(170.0, 90.0),
		Vector2(20.0, 65.0),
		HELIPAD_CENTER,
	]
	for index in range(route.size() - 1):
		var start := route[index]
		var segment := route[index + 1] - start
		var progress := clampf((point - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
		if point.distance_to(start + segment * progress) < 10.0:
			return true
	return false

func _en_ruta_dron(point: Vector2) -> bool:
	for sample in range(11):
		var route_point := HELIPAD_CENTER.lerp(FIRE_CENTER, float(sample) / 10.0)
		if point.distance_to(route_point) < 24.0:
			return true
	return false

func _posicion_arbol_apta(px: float, pz: float) -> bool:
	var point := Vector2(px, pz)
	for placed in tree_positions:
		if point.distance_to(placed) < 12.0:
			return false
	return true

func _pendiente_apta(px: float, pz: float) -> bool:
	var rise_x := get_exact_ground_y(px + 1.0, pz) - get_exact_ground_y(px - 1.0, pz)
	var rise_z := get_exact_ground_y(px, pz + 1.0) - get_exact_ground_y(px, pz - 1.0)
	var slope_angle := rad_to_deg(atan(sqrt(rise_x * rise_x + rise_z * rise_z) * 0.5))
	return slope_angle <= 35.0

func get_exact_ground_y(px: float, pz: float) -> float:
	if is_instance_valid(terrain_generator) and terrain_generator.has_method("get_ground_height_at"):
		return float(terrain_generator.call("get_ground_height_at", px, pz))
	var ridge_profile := clampf(1.0 - absf(px - 70.0) / 220.0, 0.0, 1.0)
	var base_distance := Vector2(px + 120.0, pz - 40.0).length()
	var base_flatten := clampf((base_distance - 28.0) / 22.0, 0.0, 1.0)
	var raw_elevation := pow(ridge_profile, 1.8) * 140.0
	raw_elevation += sin(pz * 0.024) * 18.0 * ridge_profile
	raw_elevation += cos(px * 0.038 + pz * 0.03) * 10.0 * ridge_profile
	return floor(raw_elevation / 3.0) * 3.0 * base_flatten

func _instance_transform(origin: Vector3, scale_value: Vector3, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(scale_value), origin)

func _add_multimesh(node_name: String, mesh: Mesh, material: Material, transforms: Array[Transform3D]) -> void:
	if transforms.is_empty():
		return
	var cells: Dictionary = {}
	var cell_origins: Dictionary = {}
	for transform in transforms:
		var cell_x := floori(transform.origin.x / 240.0)
		var cell_z := floori(transform.origin.z / 240.0)
		var cell_key := "%d_%d" % [
			cell_x,
			cell_z
		]
		if not cells.has(cell_key):
			var new_cell_transforms: Array[Transform3D] = []
			cells[cell_key] = new_cell_transforms
			cell_origins[cell_key] = Vector3(float(cell_x) * 240.0, 0.0, float(cell_z) * 240.0)
		var cell_origin: Vector3 = cell_origins[cell_key]
		var bucket_transforms: Array[Transform3D] = cells[cell_key]
		var local_transform := transform
		local_transform.origin -= cell_origin
		bucket_transforms.append(local_transform)
	for cell_key in cells:
		var key := str(cell_key)
		var cell_instances: Array[Transform3D] = cells[cell_key]
		var cell_origin: Vector3 = cell_origins[cell_key]
		_add_multimesh_cell(node_name, key, mesh, material, cell_instances, cell_origin)

func _add_multimesh_cell(node_name: String, cell_key: String, mesh: Mesh, material: Material, transforms: Array[Transform3D], cell_origin: Vector3) -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for index in range(transforms.size()):
		multi.set_instance_transform(index, transforms[index])
	var instance := MultiMeshInstance3D.new()
	instance.name = "%s_%s" % [node_name, cell_key]
	instance.position = cell_origin
	instance.multimesh = multi
	instance.material_override = material
	instance.visibility_range_end = 820.0
	instance.visibility_range_end_margin = 60.0
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(instance)

func _sphere_mesh(segments: int, rings: int) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radial_segments = segments
	mesh.rings = rings
	return mesh

func _cylinder_mesh(radius: float, height: float, segments: int) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	return mesh

func _cone_mesh(bottom_radius: float, height: float, segments: int) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.05
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = segments
	return mesh

func _box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh

func _material(color: Color, _metallic: float = 0.0) -> StandardMaterial3D:
	return PALETA.material(color)

func _material_vegetacion(color: Color) -> ShaderMaterial:
	if not foliage_shader:
		foliage_shader = Shader.new()
		foliage_shader.code = """shader_type spatial;
uniform vec4 tint : source_color = vec4(0.4, 0.55, 0.3, 1.0);
void vertex() {
	float weight = clamp(VERTEX.y + 0.35, 0.0, 1.0);
	VERTEX.x += sin(TIME * 1.3 + VERTEX.y * 2.0) * 0.025 * weight;
	VERTEX.z += cos(TIME * 1.1 + VERTEX.y * 1.5) * 0.012 * weight;
}
void fragment() {
	ALBEDO = COLOR.rgb * tint.rgb;
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
}
"""
	var material := ShaderMaterial.new()
	material.shader = foliage_shader
	material.set_shader_parameter("tint", color)
	return material

func _add_multimesh_variants(node_name: String, meshes: Array[Mesh], material: Material, transforms: Array[Transform3D]) -> void:
	if meshes.is_empty() or transforms.is_empty():
		return
	for variant in range(meshes.size()):
		var subset: Array[Transform3D] = []
		for index in range(variant, transforms.size(), meshes.size()):
			subset.append(transforms[index])
		_add_multimesh("%s_Variante_%02d" % [node_name, variant + 1], meshes[variant], material, subset)

func _mesh_instance(node_name: String, mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	return instance

func _add_box_visual(parent: Node3D, node_name: String, size: Vector3, at: Vector3, material: Material, rotation: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var instance := _mesh_instance(node_name, _box_mesh(size), material)
	instance.position = at
	instance.rotation = rotation
	parent.add_child(instance)
	return instance

func _add_solid_box(parent: StaticBody3D, node_name: String, size: Vector3, at: Vector3, material: Material, collision: bool, rotation: Vector3 = Vector3.ZERO) -> void:
	_add_box_visual(parent, node_name, size, at, material, rotation)
	if not collision:
		return
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	shape.rotation = rotation
	parent.add_child(shape)

func _add_cylinder_visual(parent: Node3D, node_name: String, radius: float, height: float, at: Vector3, material: Material, rotation: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var instance := _mesh_instance(node_name, _cylinder_mesh(radius, height, 8), material)
	instance.position = at
	instance.rotation = rotation
	parent.add_child(instance)
	return instance
