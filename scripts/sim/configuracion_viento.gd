extends Resource
class_name ConfiguracionViento

enum Modo { CONSTANTE, RACHAS, ERRATICO }

@export var modo: Modo = Modo.RACHAS
@export var direccion: Vector2 = Vector2(3.0, 1.0)
@export_range(0.0, 40.0, 0.1) var velocidad_base: float = 8.3
@export_range(0.0, 180.0, 1.0) var amplitud_direccion_grados: float = 30.0
@export_range(0.0, 20.0, 0.1) var amplitud_velocidad: float = 3.2
