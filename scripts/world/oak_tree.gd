extends Node3D

@export_enum("Aleatorio", "Pequeno", "Estandar", "Grande") var variant_size: int = 0

func _ready() -> void:
	apply_variation()

func apply_variation() -> void:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	var scale_factor: float = 1.0
	match variant_size:
		0: scale_factor = rng.randf_range(0.85, 1.45) # Variación natural
		1: scale_factor = 0.8  # Pequeño / Joven
		2: scale_factor = 1.0  # Estándar
		3: scale_factor = 1.4  # Roble centenario alto
		
	scale = Vector3(scale_factor, scale_factor, scale_factor)
	rotation.y = rng.randf_range(0, TAU)
