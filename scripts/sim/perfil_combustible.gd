extends Resource
class_name PerfilCombustible

const BOSQUE_SECO: int = 0
const PASTIZAL: int = 1
const VIVIENDA: int = 2
const SIN_COMBUSTIBLE: int = 3

@export_range(0.0, 1.0, 0.0025) var tasa_ignicion: float = 0.0575
@export_range(0.0, 1000.0, 0.1) var tasa_consumo: float = 2.5
@export_range(0.0, 2000.0, 1.0) var calor_umbral: float = 300.0
@export_range(0.0, 3600.0, 0.1) var duracion_mojado: float = 12.0
@export_range(0.0, 1.0, 0.01) var k_viento: float = 0.25
@export_range(0.0, 1.0, 0.01) var k_pendiente: float = 0.1
