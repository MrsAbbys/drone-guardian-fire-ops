extends RefCounted

const PASTO := Color("#7f9f50")
const PASTO_CLARO := Color("#93b860")
const PASTO_OSCURO := Color("#6a8f44")
const COPA_VERDE := Color("#5e8f4a")
const COPA_VERDE_CLARA := Color("#6fa055")
const COPA_VERDE_OSCURA := Color("#4f7d40")
const PINO := Color("#3f6b4a")
const PINO_CLARO := Color("#4c7c59")
const PINO_OSCURO := Color("#355c45")
const OTONO := Color("#c97b4a")
const FLOR := Color("#d4ae7c")
const HONGO_ROJO := Color("#a95f54")
const HONGO_NARANJA := Color("#bd7d53")
const CRISTAL := Color("#79aeb8")
const TRONCO := Color("#6b4a32")
const TRONCO_OSCURO := Color("#5a3e2a")
const TRONCO_BASE := Color("#60432f")
const TRONCO_ALTO := Color("#79563a")
const ARBOL_SECO := Color("#4a3426")
const ROCA := Color("#8a8d8f")
const ROCA_BASE := Color("#777a7b")
const PIEDRA_CLARA := Color("#aaa69b")
const ROCA_CALIDA := Color("#9a9690")
const ROCA_OSCURA := Color("#7c7f82")
const CARBON := Color("#2b2623")
const LUZ_FUEGO := Color("#ff9a4d")
const CIELO := Color("#8fb8d8")
const HORIZONTE := Color("#cfe0e8")
const SOL := Color("#ffe8c8")

static func material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.9
	result.metallic = 0.0
	return result
