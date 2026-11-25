extends Resource
class_name ConfiguracionGrillaIncendio

const CONFIGURACION_VIENTO_DEFAULT: Resource = preload("res://resources/sim/viento_rachas.tres")

@export var origen: Vector2 = Vector2(-600.0, -600.0)
@export var tamano_celdas: Vector2i = Vector2i(600, 600)
@export var centro_foco: Vector2 = Vector2(55.0, -120.0)
@export_range(1.0, 300.0, 0.5) var radio_foco: float = 65.0
@export_range(1, 30, 1) var cantidad_celdas_foco_inicial: int = 8
@export_range(0.0, 120.0, 0.5) var retardo_propagacion: float = 5.0
@export_range(1.0, 40.0, 0.5) var radio_nucleo_arbol: float = 5.0
@export_range(1.0, 50.0, 0.5) var radio_combustible_arbol: float = 12.0
@export_enum("Bosque seco:0", "Pastizal:1", "Vivienda:2", "Sin combustible:3") var tipo_combustible_base: int = 3
@export_range(0.0, 1000.0, 1.0) var combustible_base: float = 0.0
@export_range(1.0, 1000.0, 1.0) var combustible_bosque: float = 100.0
@export_range(1.0, 1000.0, 1.0) var combustible_pastizal: float = 40.0
@export_range(1.0, 1000.0, 1.0) var combustible_vivienda: float = 120.0
@export_range(1.0, 100.0, 1.0) var porcentaje_derrota: float = 70.0
@export_range(-1, 3, 1) var tipo_objetivo_derrota: int = -1
@export_range(0, 100000, 100) var bono_cero_perdidas: int = 1000
@export_range(0.0, 100.0, 0.5) var ancho_lineas_sin_combustible: float = 0.0
@export var lineas_sin_combustible: Array[Vector4] = []
@export var zonas_sin_combustible: Array[Vector3] = []
@export var zonas_vivienda: Array[Vector3] = []
@export var objetivos_criticos: Array[Resource] = []
@export var zona_viento_erratico: Vector3 = Vector3.ZERO
@export_range(0.0, 180.0, 1.0) var amplitud_viento_erratico_grados: float = 0.0
@export var configuracion_viento: Resource = CONFIGURACION_VIENTO_DEFAULT
@export var perfil_bosque_seco: Resource
@export var perfil_pastizal: Resource
@export var perfil_vivienda: Resource
@export var perfil_sin_combustible: Resource
