extends Node3D

signal recarga_iniciada
signal recarga_completada

@export var escala_isla: float = 7.5
@export_range(1.0, 12.0, 0.1) var radio_recarga_metros: float = 8.0
@export_range(0.2, 4.0, 0.1) var altura_maxima_sobre_agua: float = 1.0
@export_range(0.2, 4.0, 0.1) var profundidad_maxima_bajo_agua: float = 1.0

const ALTURA_AGUA_LOCAL := 0.58
@onready var refill_area: Area3D = $RefillArea

var drones_en_area: Dictionary = {}
var recargando: bool = false
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	add_to_group("fuente_agua")
	var escala_real := maxf(escala_isla, 0.1)
	scale = Vector3.ONE * escala_real
	rng.randomize()
	crear_isla()
	_crear_colision_isla()
	_configurar_area_recarga(escala_real)
	refill_area.body_entered.connect(_on_body_entered)
	refill_area.body_exited.connect(_on_body_exited)
	set_physics_process(false)
	await get_tree().physics_frame
	if (
		not is_instance_valid(self)
		or not is_inside_tree()
		or not is_instance_valid(refill_area)
	):
		return
	for body in refill_area.get_overlapping_bodies():
		_on_body_entered(body)

func _exit_tree() -> void:
	if is_instance_valid(refill_area):
		if refill_area.body_entered.is_connected(_on_body_entered):
			refill_area.body_entered.disconnect(_on_body_entered)
		if refill_area.body_exited.is_connected(_on_body_exited):
			refill_area.body_exited.disconnect(_on_body_exited)
	for dron_variant in drones_en_area.values():
		if (
			is_instance_valid(dron_variant)
			and not dron_variant.is_queued_for_deletion()
			and dron_variant.has_method("set_fuente_agua_cercana")
		):
			dron_variant.call("set_fuente_agua_cercana", false, false)
	drones_en_area.clear()
	recargando = false
	refill_area = null

func _physics_process(_delta: float) -> void:
	var hay_red := multiplayer.has_multiplayer_peer()
	var es_servidor := hay_red and multiplayer.is_server()
	var hay_recarga_activa := false
	for id_variant in drones_en_area.keys().duplicate():
		var dron: Variant = drones_en_area[id_variant]
		if (
			not is_instance_valid(dron)
			or dron.is_queued_for_deletion()
			or not dron.is_inside_tree()
		):
			drones_en_area.erase(id_variant)
			continue
		var cerca := _esta_en_rango_de_agua(dron)
		var solicitada := false
		if hay_red:
			solicitada = bool(dron.get("recarga_solicitada"))
		elif dron.is_multiplayer_authority():
			solicitada = Input.is_physical_key_pressed(KEY_E)
		var puede_recargar := cerca and solicitada and not bool(dron.call("tanque_lleno"))
		dron.call("set_fuente_agua_cercana", cerca, puede_recargar)
		if not puede_recargar:
			continue
		hay_recarga_activa = true
		if es_servidor:
			var multiplicador := 1.0 + _bonus_tactico_cercano(dron)
			dron.call(
				"recibir_agua",
				float(dron.get("recarga_por_segundo")) * multiplicador * _delta
			)
	if hay_recarga_activa and not recargando:
		recargando = true
		recarga_iniciada.emit()
	elif not hay_recarga_activa and recargando:
		recargando = false
		recarga_completada.emit()

func _on_body_entered(body: Node3D) -> void:
	if not is_instance_valid(body) or body.is_queued_for_deletion():
		return
	if not body.is_in_group("jugador"):
		return
	if not body.has_method("recibir_agua") or not body.has_method("tanque_lleno"):
		return
	if not body.has_method("set_fuente_agua_cercana") or not body.has_signal("agua_cambiada"):
		return
	var id := body.get_instance_id()
	if drones_en_area.has(id):
		return
	drones_en_area[id] = body
	body.call("set_fuente_agua_cercana", _esta_en_rango_de_agua(body), false)
	set_physics_process(true)

func _on_body_exited(body: Node3D) -> void:
	if not is_instance_valid(body):
		return
	var id := body.get_instance_id()
	if not drones_en_area.has(id):
		return
	var dron: Variant = drones_en_area[id]
	drones_en_area.erase(id)
	if is_instance_valid(dron):
		dron.call("set_fuente_agua_cercana", false, false)
	if drones_en_area.is_empty():
		recargando = false
		set_physics_process(false)

func _esta_en_rango_de_agua(body: Node3D) -> bool:
	var water_position := to_global(Vector3(0.0, ALTURA_AGUA_LOCAL, 0.0))
	var horizontal_distance := Vector2(
		body.global_position.x - water_position.x,
		body.global_position.z - water_position.z
	).length()
	var height_difference := body.global_position.y - water_position.y
	return (
		horizontal_distance <= radio_recarga_metros
		and height_difference <= altura_maxima_sobre_agua
		and height_difference >= -profundidad_maxima_bajo_agua
	)

func _bonus_tactico_cercano(dron: Node3D) -> float:
	var bonus_maximo: float = 0.0
	for candidato in get_tree().get_nodes_in_group("jugador"):
		if (
			not is_instance_valid(candidato)
			or candidato.is_queued_for_deletion()
			or candidato == dron
			or not candidato is Node3D
		):
			continue
		var aliado := candidato as Node3D
		var rol: Variant = aliado.get("rol_actual")
		if not rol is DroneRole or str(rol.identificador) != "tactico":
			continue
		var distancia := Vector2(
			aliado.global_position.x - dron.global_position.x,
			aliado.global_position.z - dron.global_position.z
		).length()
		if distancia <= float(rol.radio_bono_recarga):
			bonus_maximo = maxf(bonus_maximo, float(rol.bonus_recarga))
	return bonus_maximo

func _configurar_area_recarga(escala_real: float) -> void:
	refill_area.position = Vector3(0.0, ALTURA_AGUA_LOCAL, 0.0)
	refill_area.scale = Vector3.ONE / escala_real
	var collision := refill_area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision and collision.shape is CylinderShape3D:
		var cylinder := collision.shape as CylinderShape3D
		cylinder.radius = radio_recarga_metros
		cylinder.height = altura_maxima_sobre_agua + profundidad_maxima_bajo_agua + 0.3

func _crear_colision_isla() -> void:
	var body := StaticBody3D.new()
	body.name = "ColisionIsla"
	body.collision_layer = 1
	body.collision_mask = 0
	body.position.y = 0.275
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 3.0
	shape.height = 0.55
	collision.shape = shape
	body.add_child(collision)
	add_child(body)

func crear_isla() -> void:
	# La base empieza en Y=0; las demás capas descansan encima.
	crear_cilindro("BaseTierra", 3.0, 0.3, Color8(217, 160, 91), 0.15)
	crear_cilindro("Cesped", 2.6, 0.25, Color8(126, 217, 87), 0.425)
	crear_cilindro("Laguna", 1.2, 0.06, Color8(79, 195, 247), 0.58)
	crear_pinos()
	crear_piedras()

func crear_cilindro(nombre: String, radio: float, alto: float, color: Color, y: float) -> void:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = nombre
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radio
	mesh.bottom_radius = radio
	mesh.height = alto
	mesh_instance.mesh = mesh
	mesh_instance.material_override = crear_material(color)
	mesh_instance.position.y = y
	add_child(mesh_instance)

func crear_pinos() -> void:
	var verde: StandardMaterial3D = crear_material(Color8(95, 181, 74))
	for i in range(5):
		var angulo: float = TAU * float(i) / 5.0 - PI * 0.5
		var pino: Node3D = Node3D.new()
		pino.name = "Pino%02d" % (i + 1)
		pino.position = Vector3(cos(angulo) * 2.0, 0.55, sin(angulo) * 2.0)
		var escala: float = rng.randf_range(0.8, 1.2)
		pino.scale = Vector3.ONE * escala
		add_child(pino)

		var y: float = 0.0
		var alturas: Array[float] = [0.48, 0.44, 0.40, 0.36]
		var radios: Array[float] = [0.43, 0.35, 0.27, 0.19]
		for nivel in range(4):
			var cono: MeshInstance3D = MeshInstance3D.new()
			var cono_mesh: CylinderMesh = CylinderMesh.new()
			cono_mesh.top_radius = 0.015
			cono_mesh.bottom_radius = radios[nivel]
			cono_mesh.height = alturas[nivel]
			cono.mesh = cono_mesh
			cono.material_override = verde
			y += alturas[nivel] * 0.5
			cono.position.y = y
			pino.add_child(cono)
			y += alturas[nivel] * 0.5 - 0.08

func crear_piedras() -> void:
	var material_piedra: StandardMaterial3D = crear_material(Color8(130, 137, 139))
	for i in range(2):
		var piedra: MeshInstance3D = MeshInstance3D.new()
		piedra.name = "Piedra%02d" % (i + 1)
		var mesh: SphereMesh = SphereMesh.new()
		mesh.radial_segments = 12
		mesh.rings = 6
		piedra.mesh = mesh
		piedra.material_override = material_piedra
		var angulo: float = 0.8 + float(i) * 2.4
		piedra.position = Vector3(cos(angulo) * 2.35, 0.64, sin(angulo) * 2.35)
		piedra.scale = Vector3(0.25, 0.16, 0.20)
		add_child(piedra)

func crear_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.6
	return material
