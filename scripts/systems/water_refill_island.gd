extends Node3D

signal recarga_iniciada
signal recarga_completada

@export var escala_isla: float = 7.5
@export_range(1.0, 12.0, 0.1) var radio_recarga_metros: float = 8.0
@export_range(0.2, 4.0, 0.1) var altura_maxima_sobre_agua: float = 1.0
@export_range(0.2, 4.0, 0.1) var profundidad_maxima_bajo_agua: float = 1.0

const ALTURA_AGUA_LOCAL := 0.58
@onready var refill_area: Area3D = $RefillArea

var jugador_actual: Node3D
var recargando: bool = false
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
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
	if not is_inside_tree():
		return
	for body in refill_area.get_overlapping_bodies():
		_on_body_entered(body)

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(jugador_actual):
		jugador_actual = null
		recargando = false
		set_physics_process(false)
		return
	if not _esta_en_rango_de_agua(jugador_actual):
		jugador_actual.call("set_fuente_agua_cercana", false, false)
		recargando = false
		return
	if bool(jugador_actual.call("tanque_lleno")):
		jugador_actual.call("set_fuente_agua_cercana", true, false)
		_actualizar_recarga()
		return
	var tecla_recarga: bool = Input.is_physical_key_pressed(KEY_E)
	jugador_actual.call("set_fuente_agua_cercana", true, tecla_recarga)
	if not tecla_recarga:
		recargando = false
		return
	if not recargando:
		recargando = true
		recarga_iniciada.emit()

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("jugador"):
		return
	if not body.has_method("recibir_agua") or not body.has_method("tanque_lleno"):
		return
	if not body.has_method("set_fuente_agua_cercana") or not body.has_signal("agua_cambiada"):
		return
	if jugador_actual == body:
		return

	if is_instance_valid(jugador_actual):
		jugador_actual.call("set_fuente_agua_cercana", false, false)
		if jugador_actual.is_connected("agua_cambiada", _on_agua_cambiada):
			jugador_actual.disconnect("agua_cambiada", _on_agua_cambiada)

	jugador_actual = body
	jugador_actual.connect("agua_cambiada", _on_agua_cambiada)
	jugador_actual.call("set_fuente_agua_cercana", _esta_en_rango_de_agua(body), false)
	set_physics_process(true)
	_actualizar_recarga()

func _on_body_exited(body: Node3D) -> void:
	if body != jugador_actual:
		return
	jugador_actual.call("set_fuente_agua_cercana", false, false)
	if jugador_actual.is_connected("agua_cambiada", _on_agua_cambiada):
		jugador_actual.disconnect("agua_cambiada", _on_agua_cambiada)
	jugador_actual = null
	recargando = false
	set_physics_process(false)

func _on_agua_cambiada(_cantidad: float) -> void:
	_actualizar_recarga()

func _actualizar_recarga() -> void:
	if not is_instance_valid(jugador_actual):
		recargando = false
		set_physics_process(false)
		return

	if not _esta_en_rango_de_agua(jugador_actual):
		jugador_actual.call("set_fuente_agua_cercana", false, false)
		recargando = false
		set_physics_process(true)
		return

	var tanque_esta_lleno: bool = bool(jugador_actual.call("tanque_lleno"))
	if tanque_esta_lleno:
		if recargando:
			recargando = false
			recarga_completada.emit()
		set_physics_process(false)
	else:
		set_physics_process(true)

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
