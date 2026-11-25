extends Resource
class_name DroneRole

@export var identificador: StringName = &"explorador"
@export var nombre: String = "Explorador"
@export_multiline var descripcion: String = ""
@export var agua_maxima: float = 0.0
@export var gasto_por_segundo: float = 0.0
@export var velocidad_base: float = 0.0
@export var velocidad_maxima: float = 0.0
@export var recarga_por_segundo: float = 0.0
@export var ancho_chorro: float = 0.0
@export var alcance_chorro: float = 0.0
@export var potencia_chorro: float = 0.0
@export var alcance_termico: float = 0.0
@export var bonus_recarga: float = 0.0
@export var radio_bono_recarga: float = 0.0
@export var color_equipo: Color = Color.WHITE
@export var icono: Texture2D
@export var escala_modelo: float = 1.0
@export var enfriamiento_especial: float = 0.0
@export var costo_especial_agua: float = 0.0
@export var radio_especial: float = 0.0
@export var potencia_especial: float = 0.0
@export var duracion_especial: float = 0.0
@export var duracion_marca_objetivo: float = 0.0
@export var costo_retardante: float = 0.0
@export var alcance_retardante: float = 0.0
@export var radio_retardante: float = 0.0
@export var enfriamiento_retardante: float = 0.0
