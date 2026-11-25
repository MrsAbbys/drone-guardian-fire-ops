extends Node3D

const PALETA := preload("res://scripts/world/paleta.gd")

@export var terrain_size: Vector2 = Vector2(1400, 1400)
@export var mountain_height: float = 140.0
@export var block_step: float = 3.0

const TERRAIN_SUBDIVISIONS := 110
var ground_height_grid: Array[float] = []
var ground_grid_width: int = 0
var ground_grid_cells: int = 0
var positive_diagonal: bool = false

func _ready() -> void:
	generate_voxel_terrain()

func generate_voxel_terrain() -> void:
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = terrain_size
	plane_mesh.subdivide_width = TERRAIN_SUBDIVISIONS
	plane_mesh.subdivide_depth = TERRAIN_SUBDIVISIONS
	
	var surface_tool = SurfaceTool.new()
	surface_tool.create_from(plane_mesh, 0)
	var data = surface_tool.commit_to_arrays()
	var vertices = data[Mesh.ARRAY_VERTEX]
	var base_indices: PackedInt32Array = data[Mesh.ARRAY_INDEX]
	var colors := PackedColorArray()
	ground_grid_width = roundi(sqrt(float(vertices.size())))
	ground_grid_cells = ground_grid_width - 1
	if ground_grid_width * ground_grid_width != vertices.size() or ground_grid_cells < 1:
		push_error("No se pudo determinar la cuadrícula del terreno.")
		return
	var grid_width := ground_grid_width
	var grid_step_x := terrain_size.x / float(ground_grid_cells)
	var grid_step_z := terrain_size.y / float(ground_grid_cells)
	ground_height_grid.resize(grid_width * grid_width)
	
	for i in range(vertices.size()):
		var v: Vector3 = vertices[i]
		var dist_to_ridge = abs(v.x - 70.0)
		var ridge_profile = clamp(1.0 - (dist_to_ridge / 220.0), 0.0, 1.0)
		
		var dist_to_base = Vector2(v.x - (-120.0), v.z - 40.0).length()
		var base_flatten = clamp((dist_to_base - 28.0) / 22.0, 0.0, 1.0)
		
		var raw_elev = pow(ridge_profile, 1.8) * mountain_height
		raw_elev += sin(v.z * 0.024) * 18.0 * ridge_profile
		raw_elev += cos(v.x * 0.038 + v.z * 0.03) * 10.0 * ridge_profile
		
		var stepped_elev = floor(raw_elev / block_step) * block_step
		v.y = stepped_elev * base_flatten
		vertices[i] = v
		var grid_x := clampi(roundi((v.x + terrain_size.x * 0.5) / grid_step_x), 0, ground_grid_cells)
		var grid_z := clampi(roundi((v.z + terrain_size.y * 0.5) / grid_step_z), 0, ground_grid_cells)
		ground_height_grid[grid_z * grid_width + grid_x] = v.y
		var height_ratio := clampf(v.y / maxf(mountain_height, 1.0), 0.0, 1.0)
		colors.append(PALETA.PASTO.lerp(PALETA.PASTO_OSCURO, height_ratio * 0.35))

	positive_diagonal = _uses_positive_diagonal(vertices, base_indices)
	data[Mesh.ARRAY_VERTEX] = vertices
	data[Mesh.ARRAY_COLOR] = colors
	
	var final_mesh = ArrayMesh.new()
	final_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data)
	surface_tool.clear()
	surface_tool.create_from(final_mesh, 0)
	surface_tool.deindex()
	surface_tool.generate_normals()
	var calculated_mesh = surface_tool.commit()
	
	var mesh_inst = $TerrainMesh
	if mesh_inst:
		calculated_mesh.surface_set_material(0, _crear_material_terreno())
		mesh_inst.mesh = calculated_mesh
		
	var col_shape = $TerrainCollision
	if col_shape:
		col_shape.shape = calculated_mesh.create_trimesh_shape()

func get_ground_height_at(px: float, pz: float) -> float:
	if ground_grid_width < 2:
		push_error("La cuadrícula de alturas del terreno aún no está lista.")
		return 0.0
	var grid_step_x := terrain_size.x / float(ground_grid_cells)
	var grid_step_z := terrain_size.y / float(ground_grid_cells)
	var grid_x := clampf((px + terrain_size.x * 0.5) / grid_step_x, 0.0, float(ground_grid_cells))
	var grid_z := clampf((pz + terrain_size.y * 0.5) / grid_step_z, 0.0, float(ground_grid_cells))
	var cell_x := mini(floori(grid_x), ground_grid_cells - 1)
	var cell_z := mini(floori(grid_z), ground_grid_cells - 1)
	var u := grid_x - float(cell_x)
	var v := grid_z - float(cell_z)
	var y00 := ground_height_grid[cell_z * ground_grid_width + cell_x]
	var y10 := ground_height_grid[cell_z * ground_grid_width + cell_x + 1]
	var y01 := ground_height_grid[(cell_z + 1) * ground_grid_width + cell_x]
	var y11 := ground_height_grid[(cell_z + 1) * ground_grid_width + cell_x + 1]
	if positive_diagonal:
		if u >= v:
			return y00 * (1.0 - u) + y10 * (u - v) + y11 * v
		return y00 * (1.0 - v) + y01 * (v - u) + y11 * u
	if u + v <= 1.0:
		return y00 * (1.0 - u - v) + y10 * u + y01 * v
	return y10 * (1.0 - v) + y01 * (1.0 - u) + y11 * (u + v - 1.0)

func _uses_positive_diagonal(vertices: PackedVector3Array, indices: PackedInt32Array) -> bool:
	if indices.size() < 3:
		return false
	for first in range(3):
		for second in range(first + 1, 3):
			var a := vertices[indices[first]]
			var b := vertices[indices[second]]
			var difference := (a.x - b.x) * (a.z - b.z)
			if not is_zero_approx(difference):
				return difference > 0.0
	return false

func _crear_material_terreno() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 grass_color : source_color = vec3(0.39, 0.50, 0.30);
uniform vec3 soil_color : source_color = vec3(0.34, 0.29, 0.22);
uniform vec3 stone_color : source_color = vec3(0.37, 0.38, 0.36);
varying vec3 world_normal;

float hash_cell(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 blend = fract(p);
	blend = blend * blend * (3.0 - 2.0 * blend);
	float a = hash_cell(cell);
	float b = hash_cell(cell + vec2(1.0, 0.0));
	float c = hash_cell(cell + vec2(0.0, 1.0));
	float d = hash_cell(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, blend.x), mix(c, d, blend.x), blend.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.55;
	for (int octave = 0; octave < 4; octave++) {
		value += value_noise(p) * amplitude;
		p *= 2.03;
		amplitude *= 0.5;
	}
	return value;
}

void vertex() {
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec2 p = UV * 34.0;
	float broad = fbm(p);
	float detail = value_noise(p * 2.7);
	float soil = smoothstep(0.43, 0.60, broad * 0.72 + detail * 0.28);
	float steep = 1.0 - smoothstep(0.74, 0.94, world_normal.y);
	vec3 grass = grass_color * mix(0.90, 1.07, COLOR.g);
	vec3 ground = mix(grass, soil_color, soil * 0.62);
	ground = mix(ground, stone_color, steep * 0.82);
	ALBEDO = ground;
	ROUGHNESS = 0.98;
	SPECULAR = 0.04;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material
