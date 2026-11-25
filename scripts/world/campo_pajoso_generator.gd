extends "res://scripts/world/vegetation_spawner.gd"

const CONFIGURACION_CAMPO: Resource = preload("res://resources/sim/configuracion_campo_pajoso.tres")

@export_range(10000, 80000, 1000) var cantidad_matitas: int = 36000
@export_range(20, 80, 1) var cantidad_arboles_chaco: int = 42
@export_range(0.1, 6.0, 0.1) var amplitud_ondulacion: float = 2.4

var _ruido_terreno: FastNoiseLite = FastNoiseLite.new()
var _ruido_detalle: FastNoiseLite = FastNoiseLite.new()

func _ready() -> void:
	configuracion_grilla_incendio = CONFIGURACION_CAMPO
	GraphicsSettings.calidad_cambiada.connect(_aplicar_perfil_calidad)
	FireGridServer.viento_cambiado.connect(_al_cambiar_viento)
	_aplicar_perfil_calidad(GraphicsSettings.calidad_actual)
	FirePool.precalentar()
	rng.seed = semilla_mapa
	_ruido_terreno.seed = semilla_mapa
	_ruido_terreno.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ruido_terreno.frequency = 0.004
	_ruido_terreno.fractal_octaves = 3
	_ruido_detalle.seed = semilla_mapa ^ 76157
	_ruido_detalle.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ruido_detalle.frequency = 0.013
	hud = get_tree().root.find_child("TacticalHUD", true, false)
	terrain_generator = self
	_crear_terreno()
	_generar_arboles_chaco()
	_crear_multimeshes()
	_generar_pastizal()
	_crear_escenografia_campo()
	_iniciar_simulacion_grilla()
	_imprimir_resumen_multimeshes()

func get_exact_ground_y(px: float, pz: float) -> float:
	var altura := _ruido_terreno.get_noise_2d(px, pz) * amplitud_ondulacion
	altura += _ruido_detalle.get_noise_2d(px, pz) * amplitud_ondulacion * 0.18
	var distancia_pista := Vector2(
		maxf(absf(px + 380.0) - 92.0, 0.0),
		maxf(absf(pz + 230.0) - 16.0, 0.0)
	).length()
	var factor_aplanado := smoothstep(4.0, 38.0, distancia_pista)
	factor_aplanado *= smoothstep(28.0, 58.0, Vector2(px, pz).distance_to(Vector2(-120.0, -120.0)))
	factor_aplanado *= smoothstep(38.0, 86.0, Vector2(px, pz).distance_to(Vector2(-260.0, -30.0)))
	factor_aplanado *= smoothstep(40.0, 90.0, Vector2(px, pz).distance_to(Vector2(330.0, -120.0)))
	return altura * factor_aplanado

func _crear_terreno() -> void:
	var plano := PlaneMesh.new()
	plano.size = Vector2(1000.0, 1000.0)
	plano.subdivide_width = 120
	plano.subdivide_depth = 120
	var superficie := SurfaceTool.new()
	superficie.create_from(plano, 0)
	var datos := superficie.commit_to_arrays()
	var vertices: PackedVector3Array = datos[Mesh.ARRAY_VERTEX]
	var colores := PackedColorArray()
	for indice in range(vertices.size()):
		var vertice := vertices[indice]
		vertice.y = get_exact_ground_y(vertice.x, vertice.z)
		vertices[indice] = vertice
		var variacion := clampf((_ruido_detalle.get_noise_2d(vertice.x, vertice.z) + 1.0) * 0.5, 0.0, 1.0)
		colores.append(Color("#a9915b").lerp(Color("#b6a36a"), variacion * 0.45))
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
	var cuerpo := StaticBody3D.new()
	cuerpo.name = "MountainTerrain"
	cuerpo.collision_layer = 1
	var instancia := MeshInstance3D.new()
	instancia.name = "TerrainMesh"
	instancia.mesh = malla
	instancia.material_override = material
	cuerpo.add_child(instancia)
	var colision := CollisionShape3D.new()
	colision.name = "TerrainCollision"
	colision.shape = malla.create_trimesh_shape()
	cuerpo.add_child(colision)
	add_child(cuerpo)

func _generar_arboles_chaco() -> void:
	var intentos := 0
	while tree_positions.size() < cantidad_arboles_chaco and intentos < cantidad_arboles_chaco * 100:
		intentos += 1
		var px := rng.randf_range(-460.0, 460.0)
		var pz := rng.randf_range(-460.0, 460.0)
		var posicion := Vector2(px, pz)
		if _zona_protegida_campo(posicion) or not _posicion_arbol_apta(px, pz):
			continue
		_agregar_arbol_multimesh(px, pz)

func _generar_pastizal() -> void:
	var transformaciones: Array[Transform3D] = []
	var intentos := 0
	while transformaciones.size() < cantidad_matitas and intentos < cantidad_matitas * 3:
		intentos += 1
		var px := rng.randf_range(-490.0, 490.0)
		var pz := rng.randf_range(-490.0, 490.0)
		if _zona_protegida_campo(Vector2(px, pz)):
			continue
		var escala := rng.randf_range(0.7, 1.35)
		var rotacion := rng.randf_range(0.0, TAU)
		transformaciones.append(Transform3D(
			Basis.from_euler(Vector3(0.0, rotacion, 0.0)).scaled(
				Vector3(escala, rng.randf_range(0.75, 1.25), escala)
			),
			Vector3(px, get_exact_ground_y(px, pz), pz)
		))
	_add_multimesh(
		"PastizalSeco",
		_crear_malla_matita(),
		_material_vegetacion(Color("#b9954d")),
		transformaciones,
		true
	)

func _crear_malla_matita() -> Mesh:
	var superficie := SurfaceTool.new()
	superficie.begin(Mesh.PRIMITIVE_TRIANGLES)
	for orientacion in range(2):
		var angulo := float(orientacion) * PI * 0.5
		var izquierda := Vector3(-0.12, 0.0, 0.0).rotated(Vector3.UP, angulo)
		var derecha := Vector3(0.12, 0.0, 0.0).rotated(Vector3.UP, angulo)
		var punta := Vector3(0.0, 0.9, 0.0).rotated(Vector3.UP, angulo)
		superficie.add_vertex(izquierda)
		superficie.add_vertex(derecha)
		superficie.add_vertex(punta)
		superficie.add_vertex(derecha)
		superficie.add_vertex(izquierda)
		superficie.add_vertex(punta)
	superficie.generate_normals()
	return superficie.commit()

func _crear_escenografia_campo() -> void:
	var puntos_camino: Array[Vector2] = [
		Vector2(-480.0, -300.0),
		Vector2(0.0, -300.0),
		Vector2(480.0, -300.0),
		Vector2(350.0, -160.0),
	]
	_crear_sendero_tierra(puntos_camino)
	_crear_franga_despejada("BordeCortafuegoNorte", -180.0, 340.0, -135.0)
	_crear_franga_despejada("BordeCortafuegoSur", -180.0, 340.0, -105.0)
	_crear_represa()
	_crear_silo(Vector2(318.0, -142.0), "SiloCerealUno")
	_crear_silo(Vector2(344.0, -142.0), "SiloCerealDos")
	_crear_galpon(Vector2(320.0, -100.0))
	var corral := Node3D.new()
	corral.name = "CorralGanadero"
	corral.position = Vector3(365.0, get_exact_ground_y(365.0, -112.0), -112.0)
	add_child(corral)
	_crear_cerca(corral, Vector3.ZERO)
	var bebedero := _mesh_instance("Bebedero", _box_mesh(Vector3(5.0, 0.7, 1.4)), _material(Color("#73796b")))
	bebedero.position = Vector3(0.0, 0.45, 0.0)
	corral.add_child(bebedero)

func _crear_franga_despejada(nombre: String, inicio_x: float, fin_x: float, z: float) -> void:
	var plano := PlaneMesh.new()
	plano.size = Vector2(fin_x - inicio_x, 10.0)
	var franja := _mesh_instance(nombre, plano, _material(Color("#8d7b58")))
	franja.position = Vector3(
		(inicio_x + fin_x) * 0.5,
		get_exact_ground_y((inicio_x + fin_x) * 0.5, z) + 0.035,
		z
	)
	add_child(franja)

func _crear_represa() -> void:
	var centro_agua := Vector2(-260.0, -30.0)
	var represa := StaticBody3D.new()
	represa.name = "RepresaCampo"
	add_child(represa)
	var agua := PlaneMesh.new()
	agua.size = Vector2(66.0, 54.0)
	var superficie_agua := _mesh_instance(
		"EspejoDeAgua",
		agua,
		_material(Color("#477f91"))
	)
	superficie_agua.position = Vector3(
		centro_agua.x,
		get_exact_ground_y(centro_agua.x, centro_agua.y) + 0.35,
		centro_agua.y
	)
	represa.add_child(superficie_agua)
	_add_solid_box(
		represa,
		"DiqueDeTierra",
		Vector3(76.0, 4.5, 7.0),
		Vector3(centro_agua.x, get_exact_ground_y(centro_agua.x, 0.0) + 2.0, 0.0),
		_material(Color("#927b53")),
		true
	)
	_add_box_visual(
		represa,
		"TaludNorte",
		Vector3(76.0, 2.0, 5.0),
		Vector3(centro_agua.x, get_exact_ground_y(centro_agua.x, -5.0) + 0.9, -5.0),
		_material(Color("#9e875b"))
	)

func _crear_silo(posicion: Vector2, nombre: String) -> void:
	var silo := StaticBody3D.new()
	silo.name = nombre
	silo.position = Vector3(posicion.x, get_exact_ground_y(posicion.x, posicion.y), posicion.y)
	add_child(silo)
	var radio := 4.0
	var altura := 12.0
	var chapa := _material(Color("#aeb6ad"))
	var cuerpo := _mesh_instance("Deposito", _cylinder_mesh(radio, altura, 20), chapa)
	cuerpo.position.y = altura * 0.5
	silo.add_child(cuerpo)
	var tapa := _mesh_instance("TechoConico", _cone_mesh(radio * 1.08, 2.4, 20), _material(Color("#7b8580")))
	tapa.position.y = altura + 1.2
	silo.add_child(tapa)
	var colision := CollisionShape3D.new()
	var cilindro := CylinderShape3D.new()
	cilindro.radius = radio
	cilindro.height = altura
	colision.shape = cilindro
	colision.position.y = altura * 0.5
	silo.add_child(colision)

func _crear_galpon(posicion: Vector2) -> void:
	var galpon := StaticBody3D.new()
	galpon.name = "GalponDeEstancia"
	galpon.position = Vector3(posicion.x, get_exact_ground_y(posicion.x, posicion.y), posicion.y)
	add_child(galpon)
	_add_solid_box(
		galpon,
		"Edificio",
		Vector3(22.0, 7.0, 14.0),
		Vector3(0.0, 3.5, 0.0),
		_material(Color("#8c6844")),
		true
	)
	_add_box_visual(
		galpon,
		"Techo",
		Vector3(24.0, 1.4, 16.0),
		Vector3(0.0, 7.2, 0.0),
		_material(Color("#615448"))
	)

func _zona_protegida_campo(posicion: Vector2) -> bool:
	return (
		(absf(posicion.x + 380.0) < 102.0 and absf(posicion.y + 230.0) < 18.0)
		or posicion.distance_to(Vector2(-260.0, -30.0)) < 46.0
		or posicion.distance_to(Vector2(330.0, -120.0)) < 72.0
		or absf(posicion.y + 300.0) < 9.0
		or (
			posicion.x > -190.0
			and posicion.x < 350.0
			and (absf(posicion.y + 135.0) < 6.0 or absf(posicion.y + 105.0) < 6.0)
		)
		or _distancia_a_segmento_campo(posicion, Vector2(480.0, -300.0), Vector2(350.0, -160.0)) < 9.0
	)

func _distancia_a_segmento_campo(punto: Vector2, inicio: Vector2, fin: Vector2) -> float:
	var segmento := fin - inicio
	if segmento.length_squared() <= 0.000001:
		return punto.distance_to(inicio)
	var avance := clampf((punto - inicio).dot(segmento) / segmento.length_squared(), 0.0, 1.0)
	return punto.distance_to(inicio + segmento * avance)
