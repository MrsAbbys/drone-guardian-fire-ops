extends Node3D

const PALETA := preload("res://scripts/world/paleta.gd")
const COLOR_COPA_VERDE := Color("#397b45")
const COLOR_COPA_SECA := Color("#936b3e")
const COLOR_COPA_QUEMADA := Color("#332820")
const COLOR_CARBON := Color("#292421")
const DURACION_CALENTAMIENTO: float = 5.0
const DURACION_OSCURECIMIENTO: float = 2.0
const DURACION_VAPOR_ENFRIAMIENTO: float = 1.2
const DURACION_ENFRIAMIENTO_AGUA: float = 18.0
const ESTADO_MOJADO: int = 3
const INTERVALO_CHISPAS_MIN: float = 6.0
const INTERVALO_CHISPAS_MAX: float = 10.0

var forma_arbol: int = 0
var semilla_arbol: int = 0
var rng := RandomNumberGenerator.new()
var _ramas: Array[MeshInstance3D] = []
var _copa_viva: Node3D
var _material_copa: StandardMaterial3D
var _humo: GPUParticles3D
var _llamas: GPUParticles3D
var _brasas: GPUParticles3D
var _vapor_enfriamiento: GPUParticles3D
var _fase_fuego: int = 0
var intensidad_fuego: float = 0.0
var tiempo_enfriamiento_agua: float = 0.0
var _tiempo_fase: float = 0.0
var _tiempo_chispas: float = 0.0
var _tiempo_vapor_restante: float = 0.0
var _intervalo_chispas_siguiente: float = 8.0
var _progreso_quemado: float = 0.0

func configurar(_hud_ref: Node, forma: int, semilla: int) -> void:
	forma_arbol = forma
	semilla_arbol = semilla

func _ready() -> void:
	rng.seed = semilla_arbol
	add_to_group("arbol_simulado")
	_crear_forma_arbol()
	if is_instance_valid(FireGridServer) and FireGridServer.has_signal("viento_cambiado"):
		FireGridServer.viento_cambiado.connect(_al_cambiar_viento)
		_actualizar_viento(FireGridServer.obtener_viento())

func _exit_tree() -> void:
	if (
		is_instance_valid(FireGridServer)
		and FireGridServer.has_signal("viento_cambiado")
		and FireGridServer.viento_cambiado.is_connected(_al_cambiar_viento)
	):
		FireGridServer.viento_cambiado.disconnect(_al_cambiar_viento)
	for particulas in [_humo, _llamas, _brasas, _vapor_enfriamiento]:
		if is_instance_valid(particulas):
			particulas.emitting = false
	_ramas.clear()
	_copa_viva = null
	_material_copa = null
	_humo = null
	_llamas = null
	_brasas = null
	_vapor_enfriamiento = null

func _process(delta: float) -> void:
	tiempo_enfriamiento_agua = maxf(tiempo_enfriamiento_agua - delta, 0.0)
	if _tiempo_vapor_restante > 0.0:
		_tiempo_vapor_restante = maxf(_tiempo_vapor_restante - delta, 0.0)
		if is_instance_valid(_vapor_enfriamiento):
			_vapor_enfriamiento.amount_ratio = clampf(
				_tiempo_vapor_restante / DURACION_VAPOR_ENFRIAMIENTO,
				0.0,
				1.0
			)
			if _tiempo_vapor_restante <= 0.0:
				_vapor_enfriamiento.emitting = false
	if _fase_fuego == 1:
		_tiempo_fase += delta
		var avance_calentamiento := clampf(_tiempo_fase / DURACION_CALENTAMIENTO, 0.0, 1.0)
		_progreso_quemado = maxf(_progreso_quemado, avance_calentamiento)
		_actualizar_color_copa(lerp(COLOR_COPA_VERDE, COLOR_COPA_SECA, _progreso_quemado))
		if _tiempo_fase >= DURACION_CALENTAMIENTO:
			_iniciar_fase_intensa()
	elif _fase_fuego == 2:
		_tiempo_fase += delta
		_tiempo_chispas += delta
		var avance_oscurecimiento := clampf(_tiempo_fase / DURACION_OSCURECIMIENTO, 0.0, 1.0)
		_progreso_quemado = 1.0
		_actualizar_color_copa(lerp(COLOR_COPA_SECA, COLOR_COPA_QUEMADA, avance_oscurecimiento))
		if _tiempo_chispas >= _intervalo_chispas_siguiente:
			_tiempo_chispas = 0.0
			_intentar_contagio_por_chispa()
			_intervalo_chispas_siguiente = rng.randf_range(
				INTERVALO_CHISPAS_MIN,
				INTERVALO_CHISPAS_MAX
			)

func _crear_forma_arbol() -> void:
	var wood := _material(Color("#604a35"))
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
	_ramas.append(trunk)
	match forma_arbol:
		1:
			_crear_copa_seca(branch_mesh, wood)
		2:
			_crear_pino_vivo(branch_mesh, wood)
		ESTADO_MOJADO:
			_crear_arbol_torcido(branch_mesh, wood)
		_:
			_crear_ramas_torcida(branch_mesh, wood)
	if forma_arbol != 2:
		_crear_copa_frondosa()
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

func _crear_copa_frondosa() -> void:
	_copa_viva = Node3D.new()
	_copa_viva.name = "CopaViva"
	add_child(_copa_viva)
	_material_copa = _material(COLOR_COPA_VERDE)
	for indice in range(3):
		var hoja := MeshInstance3D.new()
		hoja.name = "Follaje_%02d" % indice
		var esfera := SphereMesh.new()
		esfera.radius = 1.15
		esfera.height = 2.3
		hoja.mesh = esfera
		hoja.material_override = _material_copa
		hoja.position = Vector3(
			rng.randf_range(-0.45, 0.45),
			4.4 + float(indice) * 0.48,
			rng.randf_range(-0.45, 0.45)
		)
		hoja.scale = Vector3.ONE * rng.randf_range(0.9, 1.25)
		_copa_viva.add_child(hoja)

func _crear_ramas_torcida(branch_mesh: CylinderMesh, wood: StandardMaterial3D) -> void:
	for branch in range(7):
		var angle := float(branch) * TAU / 7.0 + rng.randf_range(-0.2, 0.2)
		var start := Vector3(0.0, 1.5 + float(branch) * 0.55, 0.0)
		var end := start + Vector3(
			cos(angle) * rng.randf_range(1.1, 2.2),
			rng.randf_range(0.7, 1.5),
			sin(angle) * rng.randf_range(1.1, 2.2)
		)
		_add_branch(branch_mesh, wood, start, end, "RamaSeca_%02d" % branch)

func _crear_copa_seca(branch_mesh: CylinderMesh, wood: StandardMaterial3D) -> void:
	for index in range(7):
		var angle := TAU * float(index) / 7.0
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var start := Vector3(0.0, 2.6 + rng.randf_range(-0.25, 0.45), 0.0)
		var end := direction * rng.randf_range(1.15, 2.0) + Vector3(
			0.0, rng.randf_range(3.2, 4.8), 0.0
		)
		_add_branch(branch_mesh, wood, start, end, "RamaCopa_%02d" % index)
		for twig_index in range(3):
			var twig_angle := angle + float(twig_index - 1) * 0.7 + rng.randf_range(-0.18, 0.18)
			var twig_start := end + direction * rng.randf_range(-0.25, 0.15)
			var twig_end := twig_start + Vector3(
				cos(twig_angle) * rng.randf_range(0.45, 0.9),
				rng.randf_range(0.35, 0.85),
				sin(twig_angle) * rng.randf_range(0.45, 0.9)
			)
			_add_branch(
				branch_mesh, wood, twig_start, twig_end,
				"RamaFina_%d_%d" % [index, twig_index], 0.11
			)

func _crear_pino_vivo(branch_mesh: CylinderMesh, wood: StandardMaterial3D) -> void:
	_copa_viva = Node3D.new()
	_copa_viva.name = "CopaViva"
	add_child(_copa_viva)
	_material_copa = _material(COLOR_COPA_VERDE)
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.02
	cone_mesh.bottom_radius = 1.0
	cone_mesh.height = 2.0
	cone_mesh.radial_segments = 7
	for layer in range(4):
		var scale_value := 1.65 - float(layer) * 0.28
		var center_y := 2.0 + float(layer) * 1.05
		var canopy := MeshInstance3D.new()
		canopy.name = "CopaPino_%02d" % layer
		canopy.mesh = cone_mesh
		canopy.material_override = _material_copa
		canopy.position.y = center_y
		canopy.scale = Vector3(scale_value, 0.9, scale_value)
		_copa_viva.add_child(canopy)
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
		_add_branch(
			branch_mesh, wood, start, finish, "TroncoTorcido_%02d" % segment,
			0.42 - float(segment) * 0.045
		)
		start = finish
	for branch in range(9):
		var angle := float(branch) * TAU / 9.0
		var height := rng.randf_range(2.2, 5.2)
		var begin := Vector3(rng.randf_range(-0.5, 0.5), height, rng.randf_range(-0.35, 0.35))
		var finish := begin + Vector3(
			cos(angle) * rng.randf_range(1.2, 2.8),
			rng.randf_range(0.6, 1.8),
			sin(angle) * rng.randf_range(1.2, 2.8)
		)
		_add_branch(branch_mesh, wood, begin, finish, "RamaRetorcida_%02d" % branch, 0.22)

func _add_branch(
	mesh: CylinderMesh,
	material: Material,
	start: Vector3,
	finish: Vector3,
	node_name: String,
	radius_scale: float = 0.3
) -> void:
	var branch := MeshInstance3D.new()
	branch.name = node_name
	branch.mesh = mesh
	branch.material_override = material
	var difference := finish - start
	branch.position = (start + finish) * 0.5
	branch.scale = Vector3(radius_scale, difference.length(), radius_scale)
	branch.quaternion = Quaternion(Vector3.UP, difference.normalized())
	add_child(branch)
	_ramas.append(branch)

func _material(color: Color) -> StandardMaterial3D:
	return PALETA.material(color)

func actualizar_estado_fuego(estado: int) -> void:
	match estado:
		1:
			if tiempo_enfriamiento_agua > 0.0:
				return
			if _fase_fuego == 3:
				return
			if _fase_fuego == 0:
				_fase_fuego = 1
				intensidad_fuego = 100.0
				_tiempo_fase = 0.0
				_crear_efectos_fuego()
				if is_instance_valid(_humo):
					_humo.emitting = true
				_actualizar_visual_intensidad_fuego()
		2:
			tiempo_enfriamiento_agua = 0.0
			_consumir_por_grilla()
		3:
			tiempo_enfriamiento_agua = maxf(
				tiempo_enfriamiento_agua,
				DURACION_ENFRIAMIENTO_AGUA
			)
			_detener_fuego()
		_:
			if estado == 0:
				tiempo_enfriamiento_agua = 0.0
			_detener_fuego()

func actualizar_intensidad_fuego(valor: float) -> void:
	var intensidad_anterior: float = intensidad_fuego
	intensidad_fuego = clampf(valor, 0.0, 100.0)
	_actualizar_visual_intensidad_fuego()
	if intensidad_fuego >= intensidad_anterior:
		return
	_tiempo_vapor_restante = DURACION_VAPOR_ENFRIAMIENTO
	if is_instance_valid(_vapor_enfriamiento):
		_vapor_enfriamiento.amount_ratio = clampf(
			0.35 + (intensidad_anterior - intensidad_fuego) / 30.0,
			0.35,
			1.0
		)
		if not _vapor_enfriamiento.emitting:
			_vapor_enfriamiento.restart()
		_vapor_enfriamiento.emitting = true

func _actualizar_visual_intensidad_fuego() -> void:
	var proporcion: float = clampf(intensidad_fuego / 100.0, 0.0, 1.0)
	if is_instance_valid(_llamas):
		_llamas.amount_ratio = proporcion
		_llamas.scale = Vector3.ONE * lerpf(0.08, 1.0, proporcion)
	if is_instance_valid(_brasas):
		_brasas.amount_ratio = proporcion
		_brasas.emitting = _fase_fuego == 2 and proporcion > 0.0
	if is_instance_valid(_humo):
		_humo.amount_ratio = proporcion

func carbonizar_por_grilla() -> void:
	_consumir_por_grilla()

func _crear_efectos_fuego() -> void:
	if not is_instance_valid(_humo):
		_humo = _crear_particulas("HumoLigero", 12, 2.4, Color(0.28, 0.29, 0.27, 0.48))
	if not is_instance_valid(_llamas):
		_llamas = _crear_particulas("Llamas", 24, 0.9, Color(1.0, 0.34, 0.06, 0.9))
	if not is_instance_valid(_brasas):
		_brasas = _crear_particulas("Brasas", 18, 1.7, Color(1.0, 0.55, 0.12, 0.95))
	if not is_instance_valid(_vapor_enfriamiento):
		_vapor_enfriamiento = _crear_vapor_enfriamiento()
	if is_instance_valid(FireGridServer):
		_actualizar_viento(FireGridServer.obtener_viento())

func _crear_particulas(
	nombre: String,
	cantidad: int,
	duracion: float,
	color: Color
) -> GPUParticles3D:
	var particulas := GPUParticles3D.new()
	particulas.name = nombre
	particulas.position = Vector3(0.0, 5.5, 0.0)
	particulas.amount = cantidad
	particulas.lifetime = duracion
	particulas.emitting = false
	particulas.visibility_aabb = AABB(Vector3(-5.0, -2.0, -5.0), Vector3(10.0, 14.0, 10.0))
	var proceso := ParticleProcessMaterial.new()
	proceso.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proceso.emission_sphere_radius = 0.5
	proceso.direction = Vector3.UP
	proceso.spread = 18.0
	proceso.initial_velocity_min = 1.0 if nombre == "HumoLigero" else 3.0
	proceso.initial_velocity_max = 2.0 if nombre == "HumoLigero" else 6.0
	proceso.gravity = Vector3(0.0, 1.8, 0.0)
	proceso.scale_min = 0.22 if nombre == "HumoLigero" else 0.08
	proceso.scale_max = 0.65 if nombre == "HumoLigero" else 0.2
	particulas.process_material = proceso
	var material_particula := StandardMaterial3D.new()
	material_particula.albedo_color = color
	material_particula.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material_particula.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if nombre != "HumoLigero":
		material_particula.emission_enabled = true
		material_particula.emission = color
		material_particula.emission_energy_multiplier = 1.5
	var esfera := SphereMesh.new()
	esfera.radius = 0.22
	esfera.height = 0.44
	esfera.material = material_particula
	particulas.draw_pass_1 = esfera
	add_child(particulas)
	return particulas

func _iniciar_fase_intensa() -> void:
	_fase_fuego = 2
	_tiempo_fase = 0.0
	_tiempo_chispas = 0.0
	_intervalo_chispas_siguiente = rng.randf_range(
		INTERVALO_CHISPAS_MIN,
		INTERVALO_CHISPAS_MAX
	)
	_crear_efectos_fuego()
	if is_instance_valid(_humo):
		_humo.emitting = true
	if is_instance_valid(_llamas):
		_llamas.emitting = intensidad_fuego > 0.0
	if is_instance_valid(_brasas):
		_brasas.emitting = intensidad_fuego > 0.0
	_actualizar_visual_intensidad_fuego()

func _detener_fuego() -> void:
	if _fase_fuego == 3:
		return
	_fase_fuego = 0
	_tiempo_fase = 0.0
	_tiempo_chispas = 0.0
	intensidad_fuego = 0.0
	for particulas in [_humo, _llamas, _brasas]:
		if is_instance_valid(particulas):
			particulas.emitting = false

func _consumir_por_grilla() -> void:
	if _fase_fuego == 3:
		return
	_fase_fuego = 3
	intensidad_fuego = 0.0
	_tiempo_vapor_restante = 0.0
	for particulas in [_humo, _llamas, _brasas, _vapor_enfriamiento]:
		if is_instance_valid(particulas):
			particulas.emitting = false
	_actualizar_visual_intensidad_fuego()
	var material_carbon := _material(COLOR_CARBON)
	material_carbon.roughness = 0.96
	for rama in _ramas:
		if is_instance_valid(rama):
			rama.material_override = material_carbon
	if is_instance_valid(_copa_viva):
		var tween := create_tween()
		tween.tween_property(_copa_viva, "scale", Vector3.ONE * 0.02, 1.2)
		tween.finished.connect(_ocultar_copa_consumida)

func _ocultar_copa_consumida() -> void:
	if is_instance_valid(_copa_viva):
		_copa_viva.visible = false

func _actualizar_color_copa(color: Color) -> void:
	if is_instance_valid(_material_copa):
		_material_copa.albedo_color = color

func _crear_vapor_enfriamiento() -> GPUParticles3D:
	var vapor: GPUParticles3D = GPUParticles3D.new()
	vapor.name = "VaporEnfriamiento"
	vapor.position = Vector3(0.0, 5.5, 0.0)
	vapor.amount = 24
	vapor.lifetime = DURACION_VAPOR_ENFRIAMIENTO
	vapor.one_shot = false
	vapor.emitting = false
	vapor.amount_ratio = 0.0
	vapor.visibility_aabb = AABB(Vector3(-5.0, -2.0, -5.0), Vector3(10.0, 14.0, 10.0))
	var proceso: ParticleProcessMaterial = ParticleProcessMaterial.new()
	proceso.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proceso.emission_sphere_radius = 0.5
	proceso.direction = Vector3.UP
	proceso.spread = 22.0
	proceso.initial_velocity_min = 0.5
	proceso.initial_velocity_max = 1.4
	proceso.gravity = Vector3(0.0, 0.35, 0.0)
	proceso.scale_min = 0.28
	proceso.scale_max = 0.68
	vapor.process_material = proceso
	var material_vapor: StandardMaterial3D = StandardMaterial3D.new()
	material_vapor.albedo_color = Color(0.86, 0.93, 1.0, 0.68)
	material_vapor.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material_vapor.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var malla_vapor: SphereMesh = SphereMesh.new()
	malla_vapor.radius = 0.3
	malla_vapor.height = 0.6
	malla_vapor.material = material_vapor
	vapor.draw_pass_1 = malla_vapor
	add_child(vapor)
	return vapor

func _al_cambiar_viento(direccion: Vector2, _velocidad: float) -> void:
	_actualizar_viento(direccion)

func _actualizar_viento(direccion: Vector2) -> void:
	if not is_instance_valid(_brasas):
		return
	var proceso := _brasas.process_material as ParticleProcessMaterial
	if not is_instance_valid(proceso):
		return
	var vector_viento := Vector3(direccion.x, 0.55, direccion.y)
	proceso.direction = vector_viento.normalized() if vector_viento.length_squared() > 0.0 else Vector3.UP

func _intentar_contagio_por_chispa() -> void:
	if (
		_fase_fuego != 2
		or not is_instance_valid(self)
		or is_queued_for_deletion()
		or not is_instance_valid(FireGridServer)
		or not FireGridServer.activa
	):
		return
	FireGridServer.propagar_chispa(global_position, FireGridServer.obtener_viento().normalized())
