extends "res://scripts/world/vegetation_spawner.gd"

const CONFIGURACION_INTERFASE: Resource = preload("res://resources/sim/configuracion_interfase_urbana.tres")

@export_range(200, 1800, 50) var cantidad_arboles_ladera: int = 1050
@export_range(3000, 30000, 500) var cantidad_pasto_transicion: int = 14000
@export_range(0.0, 30.0, 0.5) var amplitud_terreno: float = 10.0

var _ruido_ladera: FastNoiseLite = FastNoiseLite.new()
var _ruido_suelo: FastNoiseLite = FastNoiseLite.new()
var _material_niebla: StandardMaterial3D

func _ready() -> void:
	configuracion_grilla_incendio = CONFIGURACION_INTERFAZ
	GraphicsSettings.calidad_cambiada.connect(_aplicar_perfil_calidad)
	FireGridServer.viento_cambiado.connect(_al_cambiar_viento)
	FireGridServer.explosion_deposito.connect(_al_explotar_deposito)
	NetworkManager.objetivo_critico_recibido.connect(_al_objetivo_critico_recibido_por_red)
	_aplicar_perfil_calidad(GraphicsSettings.calidad_actual)
	FirePool.precalentar()
	rng.seed = semilla_mapa
	_ruido_ladera.seed = semilla_mapa
	_ruido_ladera.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ruido_ladera.frequency = 0.009
	_ruido_ladera.fractal_octaves = 4
	_ruido_suelo.seed = semilla_mapa ^ 58103
	_ruido_suelo.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ruido_suelo.frequency = 0.032
	hud = get_tree().root.find_child("TacticalHUD", true, false)
	terrain_generator = self
	_crear_terreno_urbano()
	_generar_bosque_ladera()
	_generar_pasto_transicion()
	_crear_multimeshes()
	_crear_carreteras()
	_crear_objetivos_visuales()
	_crear_niebla_ladera()
	_iniciar_simulacion_grilla()
	_imprimir_resumen_multimeshes()

func _exit_tree() -> void:
	if GraphicsSettings.calidad_cambiada.is_connected(_aplicar_perfil_calidad):
		GraphicsSettings.calidad_cambiada.disconnect(_aplicar_perfil_calidad)
	if FireGridServer.viento_cambiado.is_connected(_al_cambiar_viento):
		FireGridServer.viento_cambiado.disconnect(_al_cambiar_viento)
	if FireGridServer.explosion_deposito.is_connected(_al_explotar_deposito):
		FireGridServer.explosion_deposito.disconnect(_al_explotar_deposito)
	if NetworkManager.objetivo_critico_recibido.is_connected(_al_objetivo_critico_recibido_por_red):
		NetworkManager.objetivo_critico_recibido.disconnect(_al_objetivo_critico_recibido_por_red)
	FireGridServer.detener()

func get_exact_ground_y(px: float, pz: float) -> float:
	var altura_base := clampf((260.0 - pz) * 0.55, 0.0, 360.0)
	var influencia := 1.0 - smoothstep(185.0, 275.0, pz)
	var relieve := _ruido_ladera.get_noise_2d(px, pz) * amplitud_terreno
	relieve += _ruido_suelo.get_noise_2d(px, pz) * amplitud_terreno * 0.22
	return maxf(altura_base + relieve * influencia, 0.0)

func _crear_terreno_urbano() -> void:
	var plano := PlaneMesh.new()
	plano.size = Vector2(1000.0, 1000.0)
	plano.subdivide_width = 160
	plano.subdivide_depth = 160
	var superficie := SurfaceTool.new()
	superficie.create_from(plano, 0)
	var datos := superficie.commit_to_arrays()
	var vertices: PackedVector3Array = datos[Mesh.ARRAY_VERTEX]
	var colores := PackedColorArray()
	for indice in range(vertices.size()):
		var vertice := vertices[indice]
		vertice.y = get_exact_ground_y(vertice.x, vertice.z)
		vertices[indice] = vertice
		var variacion := clampf((_ruido_suelo.get_noise_2d(vertice.x, vertice.z) + 1.0) * 0.5, 0.0, 1.0)
		var terreno := Color("#526448").lerp(Color("#796d52"), clampf((vertice.z + 240.0) / 520.0, 0.0, 1.0))
		colores.append(terreno.lerp(Color("#837c6a"), variacion * 0.14))
	datos[Mesh.ARRAY_VERTEX] = vertices
	datos[Mesh.ARRAY_COLOR] = colores
	var malla_base := ArrayMesh.new()
	malla_base.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, datos)
	var superficie_final := SurfaceTool.new()
	superficie_final.create_from(malla_base, 0)
	superficie_final.deindex()
	superficie_final.generate_normals()
	var malla := superficie_final.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.roughness = 1.0
	var terreno := StaticBody3D.new()
	terreno.name = "MountainTerrain"
	var instancia := MeshInstance3D.new()
	instancia.name = "TerrainMesh"
	instancia.mesh = malla
	instancia.material_override = material
	terreno.add_child(instancia)
	var colision := CollisionShape3D.new()
	colision.name = "TerrainCollision"
	colision.shape = malla.create_trimesh_shape()
	terreno.add_child(colision)
	add_child(terreno)

func _generar_bosque_ladera() -> void:
	var intentos := 0
	while tree_positions.size() < cantidad_arboles_ladera and intentos < cantidad_arboles_ladera * 5:
		intentos += 1
		var px := rng.randf_range(-475.0, 475.0)
		var pz := rng.randf_range(-465.0, 155.0)
		if not _posicion_ladera_apta(px, pz):
			continue
		var densidad := (_ruido_ladera.get_noise_2d(px, pz) + 1.0) * 0.5
		var umbral := 0.32 if pz < -110.0 else lerpf(0.32, 0.76, clampf((pz + 110.0) / 265.0, 0.0, 1.0))
		if densidad < umbral or not _posicion_arbol_apta(px, pz):
			continue
		_agregar_arbol_multimesh(px, pz)

func _generar_pasto_transicion() -> void:
	var transformaciones: Array[Transform3D] = []
	var intentos := 0
	while transformaciones.size() < cantidad_pasto_transicion and intentos < cantidad_pasto_transicion * 3:
		intentos += 1
		var px := rng.randf_range(-485.0, 485.0)
		var pz := rng.randf_range(105.0, 275.0)
		if _en_zona_urbana(px, pz) or absf(pz - 285.0) < 10.0:
			continue
		var escala := rng.randf_range(0.75, 1.3)
		var rotacion := rng.randf_range(0.0, TAU)
		transformaciones.append(Transform3D(
			Basis.from_euler(Vector3(0.0, rotacion, 0.0)).scaled(
				Vector3(escala, rng.randf_range(0.7, 1.25), escala)
			),
			Vector3(px, get_exact_ground_y(px, pz), pz)
		))
	grass_transforms.append_array(transformaciones)

func _posicion_ladera_apta(px: float, pz: float) -> bool:
	if pz > 170.0 or absf(pz - 285.0) < 14.0 or _en_zona_urbana(px, pz):
		return false
	return _pendiente_apta(px, pz)

func _en_zona_urbana(px: float, pz: float) -> bool:
	return pz > 310.0 and absf(px) < 455.0

func _crear_carreteras() -> void:
	var carretera := _mesh_instance(
		"VialUrbano",
		_box_mesh(Vector3(980.0, 0.24, 10.0)),
		_material(Color("#5a5850"))
	)
	carretera.position = Vector3(0.0, get_exact_ground_y(0.0, 285.0) + 0.08, 285.0)
	add_child(carretera)

func _crear_objetivos_visuales() -> void:
	var objetivos: Array = CONFIGURACION_INTERFAZ.get("objetivos_criticos")
	var torres: Array[Vector3] = []
	for elemento: Variant in objetivos:
		if not elemento is Resource:
			continue
		var objetivo: Resource = elemento
		var posicion: Vector3 = objetivo.get("posicion")
		posicion.y = get_exact_ground_y(posicion.x, posicion.z)
		match int(objetivo.get("tipo")):
			0:
				_crear_vivienda(objetivo, posicion)
			1:
				_crear_torre_electrica(objetivo, posicion)
				torres.append(posicion)
			2:
				_crear_deposito(objetivo, posicion)
			3:
				_crear_ducto(objetivo, posicion)
	if torres.size() >= 2:
		_crear_cable_torre(torres[0] + Vector3.UP * 14.0, torres[1] + Vector3.UP * 14.0)

func _crear_vivienda(objetivo: Resource, posicion: Vector3) -> void:
	var casa := StaticBody3D.new()
	casa.name = "Objetivo_%s" % str(objetivo.get("identificador"))
	casa.position = posicion
	casa.set_meta("objetivo_critico_id", str(objetivo.get("identificador")))
	add_child(casa)
	var material_muros := _material(Color("#b8aa8a"))
	var material_techo := _material(Color("#7b4235"))
	_add_solid_box(casa, "Muros", Vector3(14.0, 6.0, 12.0), Vector3(0.0, 3.0, 0.0), material_muros, true)
	_add_box_visual(casa, "Techo", Vector3(16.0, 1.2, 14.0), Vector3(0.0, 6.6, 0.0), material_techo)
	_add_box_visual(casa, "Puerta", Vector3(1.7, 3.1, 0.18), Vector3(0.0, 1.55, -6.1), _material(Color("#5e4937")))

func _crear_torre_electrica(objetivo: Resource, posicion: Vector3) -> void:
	var torre := Node3D.new()
	torre.name = "Objetivo_%s" % str(objetivo.get("identificador"))
	torre.position = posicion
	torre.set_meta("objetivo_critico_id", str(objetivo.get("identificador")))
	add_child(torre)
	var metal := _material(Color("#53616a"), 0.7)
	for x in [-2.4, 2.4]:
		for z in [-2.4, 2.4]:
			_crear_cilindro(torre, "Pata", 0.28, 17.0, Vector3(x, 8.5, z), metal)
	_crear_cilindro(torre, "Mastil", 0.42, 19.0, Vector3(0.0, 9.5, 0.0), metal)
	_add_solid_box(torre, "TravesanoInferior", Vector3(8.0, 0.35, 0.35), Vector3(0.0, 11.0, 0.0), metal, false)
	_add_solid_box(torre, "TravesanoSuperior", Vector3(11.0, 0.35, 0.35), Vector3(0.0, 15.0, 0.0), metal, false)
	for x in [-4.6, 0.0, 4.6]:
		_crear_cilindro(torre, "Aislador", 0.24, 1.5, Vector3(x, 16.0, 0.0), _material(Color("#d1c9a8")))

func _crear_deposito(objetivo: Resource, posicion: Vector3) -> void:
	var deposito := StaticBody3D.new()
	deposito.name = "Objetivo_%s" % str(objetivo.get("identificador"))
	deposito.position = posicion
	deposito.set_meta("objetivo_critico_id", str(objetivo.get("identificador")))
	add_child(deposito)
	var radio := 8.0
	var altura := 13.0
	var cuerpo := _mesh_instance(
		"TanqueCombustible",
		_cylinder_mesh(radio, altura, 28),
		_material(Color("#9a5c43"), 0.35)
	)
	cuerpo.position.y = altura * 0.5
	deposito.add_child(cuerpo)
	_add_solid_box(deposito, "Bermas", Vector3(22.0, 0.5, 22.0), Vector3(0.0, 0.25, 0.0), _material(Color("#806947")), true)
	var colision := CollisionShape3D.new()
	var forma := CylinderShape3D.new()
	forma.radius = radio
	forma.height = altura
	colision.shape = forma
	colision.position.y = altura * 0.5
	deposito.add_child(colision)
	_add_box_visual(deposito, "RotuloInflamable", Vector3(4.0, 2.0, 0.25), Vector3(0.0, 5.0, -8.1), _material(Color("#d84c32")))

func _crear_ducto(objetivo: Resource, posicion: Vector3) -> void:
	var ducto := Node3D.new()
	ducto.name = "Objetivo_%s" % str(objetivo.get("identificador"))
	ducto.position = posicion
	ducto.set_meta("objetivo_critico_id", str(objetivo.get("identificador")))
	add_child(ducto)
	var direccion: Vector2 = objetivo.get("direccion_ducto")
	if direccion.length_squared() <= 0.001:
		direccion = Vector2.RIGHT
	direccion = direccion.normalized()
	var inicio := Vector3(-direccion.x, 0.0, -direccion.y) * float(objetivo.get("longitud")) * 0.5
	var fin := -inicio
	var altura := 2.2
	_crear_cilindro_entre(
		ducto,
		"TuberiaPrincipal",
		inicio + Vector3.UP * altura,
		fin + Vector3.UP * altura,
		0.65,
		_material(Color("#65727a"), 0.55)
	)
	for avance in range(0, ceili(float(objetivo.get("longitud")) / 70.0) + 1):
		var progreso := clampf(float(avance) * 70.0 / float(objetivo.get("longitud")), 0.0, 1.0)
		var punto := inicio.lerp(fin, progreso)
		_crear_cilindro(ducto, "SoporteDucto", 0.22, altura, punto + Vector3.UP * altura * 0.5, _material(Color("#4b5357"), 0.45))

func _crear_cilindro(
	padre: Node3D,
	nombre: String,
	radio: float,
	altura: float,
	posicion: Vector3,
	material: Material
) -> MeshInstance3D:
	var malla := CylinderMesh.new()
	malla.top_radius = radio
	malla.bottom_radius = radio
	malla.height = altura
	malla.radial_segments = 10
	var cilindro := _mesh_instance(nombre, malla, material)
	cilindro.position = posicion
	padre.add_child(cilindro)
	return cilindro

func _crear_cilindro_entre(
	padre: Node3D,
	nombre: String,
	inicio: Vector3,
	fin: Vector3,
	radio: float,
	material: Material
) -> void:
	var vector := fin - inicio
	var cilindro := _crear_cilindro(
		padre,
		nombre,
		radio,
		vector.length(),
		(inicio + fin) * 0.5,
		material
	)
	cilindro.quaternion = Quaternion(Vector3.UP, vector.normalized())

func _crear_cable_torre(inicio: Vector3, fin: Vector3) -> void:
	_crear_cilindro_entre(self, "LineaAltaTension", inicio, fin, 0.12, _material(Color("#282d30"), 0.25))

func _crear_niebla_ladera() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.68, 0.7, 0.73, 0.13)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.roughness = 1.0
	var nube := GPUParticles3D.new()
	nube.name = "BrumaAltaLadera"
	nube.amount = 36
	nube.lifetime = 22.0
	nube.preprocess = 8.0
	nube.position = Vector3(0.0, 305.0, -330.0)
	nube.visibility_aabb = AABB(Vector3(-520.0, -80.0, -520.0), Vector3(1040.0, 450.0, 1040.0))
	var proceso := ParticleProcessMaterial.new()
	proceso.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proceso.emission_box_extents = Vector3(480.0, 18.0, 72.0)
	proceso.direction = Vector3(0.0, 0.2, 0.0)
	proceso.spread = 85.0
	proceso.initial_velocity_min = 0.15
	proceso.initial_velocity_max = 0.7
	proceso.gravity = Vector3(0.0, 0.04, 0.0)
	proceso.scale_min = 7.0
	proceso.scale_max = 15.0
	proceso.color = Color(0.7, 0.72, 0.75, 0.14)
	nube.process_material = proceso
	var esfera := SphereMesh.new()
	esfera.radius = 1.0
	esfera.height = 2.0
	esfera.material = material
	nube.draw_pass_1 = esfera
	add_child(nube)

func _al_cambiar_viento(direccion: Vector2, velocidad: float) -> void:
	var direccion_normalizada := direccion.normalized() if direccion.length_squared() > 0.0 else Vector2.RIGHT
	var intensidad := clampf(velocidad / 8.3, 0.0, 2.0)
	for material in _materiales_vegetacion:
		material.set_shader_parameter("wind_direction", direccion_normalizada)
		material.set_shader_parameter("wind_strength", intensidad)

func _al_explotar_deposito(posicion: Vector3, _radio: float) -> void:
	_crear_efecto_explosion(posicion)

func _al_objetivo_critico_recibido_por_red(datos: Dictionary) -> void:
	if str(datos.get("estado", "")) != "PERDIDO" or int(datos.get("tipo", -1)) != 2:
		return
	var posicion: Variant = datos.get("posicion", Vector3.ZERO)
	if posicion is Vector3:
		_crear_efecto_explosion(posicion)

func _crear_efecto_explosion(posicion: Vector3) -> void:
	var explosion := GPUParticles3D.new()
	explosion.name = "ExplosionDeposito"
	explosion.one_shot = true
	explosion.explosiveness = 1.0
	explosion.amount = 72
	explosion.lifetime = 2.8
	explosion.position = Vector3(
		posicion.x,
		get_exact_ground_y(posicion.x, posicion.z) + 5.0,
		posicion.z
	)
	explosion.finished.connect(explosion.queue_free)
	var proceso := ParticleProcessMaterial.new()
	proceso.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proceso.emission_sphere_radius = 2.0
	proceso.direction = Vector3.UP
	proceso.spread = 180.0
	proceso.initial_velocity_min = 12.0
	proceso.initial_velocity_max = 34.0
	proceso.gravity = Vector3(0.0, -16.0, 0.0)
	proceso.scale_min = 0.45
	proceso.scale_max = 1.8
	proceso.color = Color(1.0, 0.32, 0.04, 0.95)
	explosion.process_material = proceso
	var esfera := SphereMesh.new()
	esfera.radius = 0.65
	esfera.height = 1.3
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.38, 0.04, 0.9)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	esfera.material = material
	explosion.draw_pass_1 = esfera
	add_child(explosion)
