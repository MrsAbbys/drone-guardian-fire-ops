extends Node

enum Calidad { BAJO, MEDIO, ALTO }

signal calidad_cambiada(calidad: int)
signal sensibilidad_mouse_cambiada(valor: float)

const RUTA_AJUSTES: String = "user://ajustes.cfg"
const SENSIBILIDAD_MOUSE_DEFECTO: float = 0.0022
const VOLUMEN_MAESTRO_DEFECTO: float = 1.0
const PERFILES: Dictionary = {
	Calidad.BAJO: {
		"fog_depth_end": 70.0,
		"fog_density": 0.0028,
		"shadow_enabled": false,
		"directional_shadow_max_distance": 35.0,
		"directional_shadow_mode": DirectionalLight3D.SHADOW_ORTHOGONAL,
		"msaa_3d": Viewport.MSAA_DISABLED,
		"scaling_3d_scale": 0.67,
		"visibility_range_end": 250.0,
		"max_fire_effects": 48,
		"max_particles_per_fire": 60,
	},
	Calidad.MEDIO: {
		"fog_depth_end": 85.0,
		"fog_density": 0.0037,
		"shadow_enabled": true,
		"directional_shadow_max_distance": 60.0,
		"directional_shadow_mode": DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
		"msaa_3d": Viewport.MSAA_DISABLED,
		"scaling_3d_scale": 0.85,
		"visibility_range_end": 400.0,
		"max_fire_effects": 120,
		"max_particles_per_fire": 90,
	},
	Calidad.ALTO: {
		"fog_depth_end": 100.0,
		"fog_density": 0.0045,
		"shadow_enabled": true,
		"directional_shadow_max_distance": 100.0,
		"directional_shadow_mode": DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
		"msaa_3d": Viewport.MSAA_DISABLED,
		"scaling_3d_scale": 1.0,
		"visibility_range_end": 700.0,
		"max_fire_effects": 250,
		"max_particles_per_fire": 120,
	},
}

var calidad_actual: int = Calidad.MEDIO
var sensibilidad_mouse: float = SENSIBILIDAD_MOUSE_DEFECTO
var volumen_maestro: float = VOLUMEN_MAESTRO_DEFECTO

func _ready() -> void:
	_cargar_ajustes()
	_aplicar_perfil_viewport()
	_aplicar_volumen_maestro()

func obtener_perfil(calidad: int) -> Dictionary:
	if not PERFILES.has(calidad):
		push_error("No existe un perfil gráfico para la calidad indicada.")
		return {}
	return PERFILES[calidad]

func configurar_calidad(calidad: int) -> void:
	if not PERFILES.has(calidad):
		push_error("No se puede guardar una calidad gráfica desconocida.")
		return
	var cambio_calidad := calidad_actual != calidad
	calidad_actual = calidad
	_aplicar_perfil_viewport()
	_guardar_ajustes()
	if cambio_calidad:
		calidad_cambiada.emit(calidad_actual)

func configurar_sensibilidad_mouse(valor: float) -> void:
	sensibilidad_mouse = clampf(valor, 0.0005, 0.01)
	_guardar_ajustes()
	sensibilidad_mouse_cambiada.emit(sensibilidad_mouse)

func configurar_volumen_maestro(valor: float) -> void:
	volumen_maestro = clampf(valor, 0.0, 1.0)
	_aplicar_volumen_maestro()
	_guardar_ajustes()

func _cargar_ajustes() -> void:
	var ajustes := ConfigFile.new()
	var error_carga := ajustes.load(RUTA_AJUSTES)
	if error_carga != OK and error_carga != ERR_FILE_NOT_FOUND:
		push_error("No se pudieron cargar los ajustes gráficos: %s" % error_carga)
		calidad_actual = _detectar_calidad_automatica()
		return
	if error_carga == OK:
		if ajustes.has_section_key("graficos", "calidad"):
			var calidad_guardada: Variant = ajustes.get_value("graficos", "calidad")
			if calidad_guardada is int and PERFILES.has(calidad_guardada):
				calidad_actual = calidad_guardada
			else:
				push_warning("La calidad guardada no es válida; se detectará automáticamente.")
				calidad_actual = _detectar_calidad_automatica()
		else:
			calidad_actual = _detectar_calidad_automatica()

		if ajustes.has_section_key("controles", "sensibilidad_mouse"):
			var sensibilidad_guardada: Variant = ajustes.get_value("controles", "sensibilidad_mouse")
			if sensibilidad_guardada is int or sensibilidad_guardada is float:
				sensibilidad_mouse = clampf(float(sensibilidad_guardada), 0.0005, 0.01)
			else:
				push_warning("La sensibilidad guardada no es válida; se usará la predeterminada.")
		if ajustes.has_section_key("audio", "volumen_maestro"):
			var volumen_guardado: Variant = ajustes.get_value("audio", "volumen_maestro")
			if volumen_guardado is int or volumen_guardado is float:
				volumen_maestro = clampf(float(volumen_guardado), 0.0, 1.0)
			else:
				push_warning("El volumen maestro guardado no es válido; se usará el predeterminado.")
	else:
		calidad_actual = _detectar_calidad_automatica()

func _guardar_ajustes() -> void:
	var ajustes := ConfigFile.new()
	var error_carga := ajustes.load(RUTA_AJUSTES)
	if error_carga != OK and error_carga != ERR_FILE_NOT_FOUND:
		push_error("No se pudieron leer los ajustes existentes: %s" % error_carga)
		return
	ajustes.set_value("graficos", "calidad", calidad_actual)
	ajustes.set_value("controles", "sensibilidad_mouse", sensibilidad_mouse)
	ajustes.set_value("audio", "volumen_maestro", volumen_maestro)
	var error_guardado := ajustes.save(RUTA_AJUSTES)
	if error_guardado != OK:
		push_error("No se pudieron guardar los ajustes gráficos: %s" % error_guardado)

func _detectar_calidad_automatica() -> int:
	var adaptador := RenderingServer.get_video_adapter_name().to_lower()
	var nucleos := OS.get_processor_count()
	if (
		nucleos <= 4
		or adaptador.contains("llvmpipe")
		or adaptador.contains("microsoft basic")
	):
		return Calidad.BAJO
	if nucleos <= 8 or adaptador.contains("intel"):
		return Calidad.MEDIO
	return Calidad.ALTO

func _aplicar_perfil_viewport() -> void:
	var perfil := obtener_perfil(calidad_actual)
	if perfil.is_empty():
		return
	var viewport := get_tree().root
	viewport.msaa_3d = int(perfil["msaa_3d"])
	viewport.scaling_3d_scale = float(perfil["scaling_3d_scale"])

func _aplicar_volumen_maestro() -> void:
	if AudioServer.get_bus_count() == 0:
		push_error("No existe el bus maestro de audio.")
		return
	var volumen_db := linear_to_db(volumen_maestro) if volumen_maestro > 0.0 else -80.0
	AudioServer.set_bus_volume_db(0, volumen_db)
