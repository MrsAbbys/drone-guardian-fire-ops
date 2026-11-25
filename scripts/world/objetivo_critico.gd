extends Resource
class_name ObjetivoCritico

enum Tipo { VIVIENDA, TORRE, DEPOSITO, DUCTO }

@export var identificador: StringName = &""
@export var nombre: String = "Objetivo"
@export var tipo: Tipo = Tipo.VIVIENDA
@export var posicion: Vector3 = Vector3.ZERO
@export_range(1.0, 180.0, 1.0) var vida: float = 15.0
@export_range(0, 100000, 100) var penalizacion: int = 1000
@export_range(1.0, 50.0, 0.5) var area: float = 5.0
@export var direccion_ducto: Vector2 = Vector2.RIGHT
@export_range(0.0, 1000.0, 1.0) var longitud: float = 0.0
