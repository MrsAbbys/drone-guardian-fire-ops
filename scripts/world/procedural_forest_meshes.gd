extends RefCounted

const PALETA := preload("res://scripts/world/paleta.gd")

static func material_vertex_color() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

static func crear_pino(semilla: int, altura: float, delgado: bool, tono_base: Color) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = semilla
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk_radius := altura * (0.045 if not delgado else 0.035)
	var trunk_height := altura * 0.96
	_agregar_tronco(surface, altura, trunk_radius, trunk_height, rng)
	var levels := rng.randi_range(5, 7)
	for level in range(levels):
		var t := float(level) / float(levels - 1)
		var y := altura * (0.27 + 0.68 * t)
		var branch_length := lerpf(altura * (0.34 if not delgado else 0.23), altura * 0.065, t)
		branch_length *= rng.randf_range(0.9, 1.12)
		var leaves := int(lerpf(9.0, 5.0, t))
		var rotation := rng.randf_range(0.0, TAU)
		for leaf_index in range(leaves):
			var angle := rotation + TAU * float(leaf_index) / float(leaves) + rng.randf_range(-0.12, 0.12)
			var direction := Vector3(cos(angle), 0.0, sin(angle))
			var side := Vector3(-direction.z, 0.0, direction.x)
			var root := direction * (trunk_radius * 0.55) + Vector3(0.0, y, 0.0)
			var tip := root + direction * branch_length + Vector3(0.0, -branch_length * rng.randf_range(0.25, 0.44), 0.0)
			var middle := root.lerp(tip, 0.48) + Vector3(0.0, branch_length * 0.12, 0.0)
			var width := branch_length * rng.randf_range(0.32, 0.44)
			var color := tono_base.lerp(PALETA.PINO_CLARO, rng.randf_range(0.0, 0.42)).darkened((1.0 - t) * 0.18)
			_triangulo(surface, root, middle + side * width, middle - side * width, color.lightened(0.035))
			_triangulo(surface, middle + side * width, tip, middle - side * width, color)
	_agregar_punta_pino(surface, altura, trunk_height, PALETA.PINO_CLARO)
	surface.generate_normals()
	return surface.commit() as ArrayMesh

static func crear_arbol_hoja_ancha(semilla: int, altura: float, tono: Color) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = semilla
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk_radius := altura * 0.055
	_agregar_tronco(surface, altura, trunk_radius, altura * 0.61, rng)
	var crown_count := rng.randi_range(3, 5)
	for cluster in range(crown_count):
		var angle := TAU * float(cluster) / float(crown_count) + rng.randf_range(-0.3, 0.3)
		var radius := altura * rng.randf_range(0.17, 0.24)
		var center := Vector3(cos(angle) * radius * 0.58, altura * rng.randf_range(0.63, 0.81), sin(angle) * radius * 0.58)
		var size := Vector3(radius * rng.randf_range(0.8, 1.25), radius * rng.randf_range(0.7, 0.95), radius * rng.randf_range(0.8, 1.2))
		_agregar_masa_facetada(surface, center, size, rng, tono)
	_agregar_masa_facetada(surface, Vector3(0.0, altura * 0.76, 0.0), Vector3.ONE * altura * 0.22, rng, tono)
	surface.generate_normals()
	return surface.commit() as ArrayMesh

static func crear_roca(semilla: int, tamano: Vector3) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = semilla
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	const segments := 9
	const rings := 5
	var points: Array[Vector3] = []
	for ring in range(1, rings):
		var phi := PI * float(ring) / float(rings)
		for segment in range(segments):
			var theta := TAU * float(segment) / float(segments)
			var direction := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
			var roughness := rng.randf_range(0.82, 1.16)
			var point := direction * roughness
			point.y = maxf(point.y, -0.58)
			points.append(point * tamano)
	var top := Vector3(0.0, tamano.y, 0.0)
	var bottom := Vector3(0.0, -tamano.y * 0.58, 0.0)
	for segment in range(segments):
		var next := (segment + 1) % segments
		_triangulo(surface, top, points[next], points[segment], _color_roca(rng, 0.7))
		for ring in range(rings - 2):
			var a := ring * segments + segment
			var b := ring * segments + next
			var c := (ring + 1) * segments + segment
			var d := (ring + 1) * segments + next
			_agregar_cara_roca(surface, points[a], points[b], points[c], rng)
			_agregar_cara_roca(surface, points[b], points[d], points[c], rng)
		var lower_start := (rings - 2) * segments
		_triangulo(surface, bottom, points[lower_start + segment], points[lower_start + next], _color_roca(rng, 0.0))
	surface.generate_normals()
	return surface.commit() as ArrayMesh

static func crear_pasto() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_agregar_hoja_pasto(surface, Vector3.ZERO, Vector3(0.0, 0.0, 1.0))
	_agregar_hoja_pasto(surface, Vector3.ZERO, Vector3(1.0, 0.0, 0.0))
	_agregar_hoja_pasto(surface, Vector3.ZERO, Vector3(0.7, 0.0, 0.7))
	surface.generate_normals()
	return surface.commit() as ArrayMesh

static func _agregar_tronco(surface: SurfaceTool, height: float, radius: float, trunk_height: float, rng: RandomNumberGenerator) -> void:
	var sides := 7
	var rings: Array[Vector2] = [
		Vector2(0.0, radius * 1.55),
		Vector2(height * 0.1, radius),
		Vector2(trunk_height * 0.62, radius * 0.68),
		Vector2(trunk_height, radius * 0.25),
	]
	var lean := Vector2(rng.randf_range(-0.035, 0.035), rng.randf_range(-0.035, 0.035)) * height
	for ring in range(rings.size() - 1):
		for side in range(sides):
			var a0 := TAU * float(side) / float(sides)
			var a1 := TAU * float(side + 1) / float(sides)
			var p00 := Vector3(cos(a0) * rings[ring].y, rings[ring].x, sin(a0) * rings[ring].y) + Vector3(lean.x * rings[ring].x / height, 0.0, lean.y * rings[ring].x / height)
			var p01 := Vector3(cos(a1) * rings[ring].y, rings[ring].x, sin(a1) * rings[ring].y) + Vector3(lean.x * rings[ring].x / height, 0.0, lean.y * rings[ring].x / height)
			var p10 := Vector3(cos(a0) * rings[ring + 1].y, rings[ring + 1].x, sin(a0) * rings[ring + 1].y) + Vector3(lean.x * rings[ring + 1].x / height, 0.0, lean.y * rings[ring + 1].x / height)
			var p11 := Vector3(cos(a1) * rings[ring + 1].y, rings[ring + 1].x, sin(a1) * rings[ring + 1].y) + Vector3(lean.x * rings[ring + 1].x / height, 0.0, lean.y * rings[ring + 1].x / height)
			var progress := rings[ring + 1].x / height
			var trunk_color := PALETA.TRONCO_BASE.lerp(PALETA.TRONCO_ALTO, progress)
			_triangulo(surface, p00, p10, p11, trunk_color)
			_triangulo(surface, p00, p11, p01, trunk_color.darkened(0.06))
	for root_index in range(4):
		var angle := TAU * float(root_index) / 4.0 + rng.randf_range(-0.25, 0.25)
		var out := Vector3(cos(angle), 0.0, sin(angle)) * radius * 2.2
		var base := Vector3(0.0, height * 0.08, 0.0)
		var end := out + Vector3(0.0, 0.02, 0.0)
		var top := out * 0.45 + Vector3(0.0, height * 0.16, 0.0)
		_triangulo(surface, base, end, top, PALETA.TRONCO_BASE)

static func _agregar_punta_pino(surface: SurfaceTool, height: float, trunk_height: float, color: Color) -> void:
	var tip := Vector3(0.0, height * 1.03, 0.0)
	for side in range(5):
		var a0 := TAU * float(side) / 5.0
		var a1 := TAU * float(side + 1) / 5.0
		var p0 := Vector3(cos(a0) * height * 0.045, trunk_height * 0.9, sin(a0) * height * 0.045)
		var p1 := Vector3(cos(a1) * height * 0.045, trunk_height * 0.9, sin(a1) * height * 0.045)
		_triangulo(surface, p0, tip, p1, color)

static func _agregar_masa_facetada(surface: SurfaceTool, center: Vector3, size: Vector3, rng: RandomNumberGenerator, color: Color) -> void:
	var segments := 8
	var rings := 5
	var top := center + Vector3(0.0, size.y, 0.0)
	var bottom := center - Vector3(0.0, size.y, 0.0)
	for segment in range(segments):
		var theta0 := TAU * float(segment) / float(segments)
		var theta1 := TAU * float(segment + 1) / float(segments)
		_triangulo(surface, top, _blob_point(center, size, PI / rings, theta1), _blob_point(center, size, PI / rings, theta0), color.lightened(0.05))
		_triangulo(surface, bottom, _blob_point(center, size, PI * float(rings - 1) / float(rings), theta0), _blob_point(center, size, PI * float(rings - 1) / float(rings), theta1), color.darkened(0.05))
	for ring in range(1, rings - 1):
		var phi0 := PI * float(ring) / float(rings)
		var phi1 := PI * float(ring + 1) / float(rings)
		for segment in range(segments):
			var theta0 := TAU * float(segment) / float(segments)
			var theta1 := TAU * float(segment + 1) / float(segments)
			var a := _blob_point(center, size, phi0, theta0)
			var b := _blob_point(center, size, phi0, theta1)
			var c := _blob_point(center, size, phi1, theta0)
			var d := _blob_point(center, size, phi1, theta1)
			var shade := rng.randf_range(-0.08, 0.08)
			_triangulo(surface, a, b, c, color.lightened(maxf(shade, 0.0)).darkened(maxf(-shade, 0.0)))
			_triangulo(surface, b, d, c, color.lightened(maxf(shade * 0.6, 0.0)).darkened(maxf(-shade * 0.6, 0.0)))

static func _blob_point(center: Vector3, size: Vector3, phi: float, theta: float) -> Vector3:
	var factor := 1.0 + 0.045 * sin(theta * 4.0 + phi * 3.0) * cos(phi * 5.0 - theta * 2.0)
	return center + Vector3(sin(phi) * cos(theta) * size.x * factor, cos(phi) * size.y * factor, sin(phi) * sin(theta) * size.z * factor)

static func _agregar_cara_roca(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, rng: RandomNumberGenerator) -> void:
	var upward := clampf(((a + b + c) / 3.0).normalized().y, 0.0, 1.0)
	_triangulo(surface, a, b, c, _color_roca(rng, upward))

static func _agregar_hoja_pasto(surface: SurfaceTool, origin: Vector3, side: Vector3) -> void:
	var half_width := side.normalized() * 0.16
	var base_left := origin - half_width
	var base_right := origin + half_width
	var middle := origin + Vector3(0.0, 0.5, 0.0) + side.normalized() * 0.06
	var tip := origin + Vector3(0.0, 1.0, 0.0) + side.normalized() * 0.12
	_triangulo_sin_color(surface, base_left, middle, base_right)
	_triangulo_sin_color(surface, middle, tip, base_right)
	_triangulo_sin_color(surface, base_right, middle, base_left)
	_triangulo_sin_color(surface, base_right, tip, middle)

static func _color_roca(rng: RandomNumberGenerator, upward: float) -> Color:
	var base := PALETA.ROCA_OSCURA.lerp(PALETA.ROCA_BASE, rng.randf_range(0.25, 0.7))
	var highlight := clampf((upward - 0.5) / 0.45, 0.0, 1.0)
	highlight = highlight * highlight * (3.0 - 2.0 * highlight)
	return base.lerp(PALETA.PIEDRA_CLARA, highlight * 0.48)

static func _triangulo(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	surface.set_color(color)
	surface.add_vertex(a)
	surface.set_color(color)
	surface.add_vertex(b)
	surface.set_color(color)
	surface.add_vertex(c)

static func _triangulo_sin_color(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)
