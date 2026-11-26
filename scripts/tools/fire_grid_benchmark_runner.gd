extends RefCounted
class_name FireGridBenchmarkRunner

const SCRIPT_FIRE_GRID: Script = preload("res://scripts/sim/fire_grid.gd")
const TAMANOS: Array[int] = [100, 200, 400, 600]
const PASOS: int = 150
const SEMILLA: int = 20260117
const INTERVALO_TICK: float = 0.3
const VIENTO: Vector2 = Vector2(0.5, 0.5)

func medir_tamano(
	tamano: int,
	pasos: int = PASOS,
	semilla: int = SEMILLA,
	viento: Vector2 = VIENTO
) -> Dictionary:
	if tamano <= 0 or pasos <= 0:
		push_error("El benchmark de FireGrid requiere tamaño y pasos positivos.")
		return {}

	var grilla: RefCounted = SCRIPT_FIRE_GRID.new(Vector2.ZERO, Vector2i(tamano, tamano), semilla)
	grilla.call("encender", Vector2i(tamano / 2, tamano / 2))
	var inicio_usec := Time.get_ticks_usec()
	for _paso in range(pasos):
		grilla.call("paso", INTERVALO_TICK, viento)
	var duracion_ms := float(Time.get_ticks_usec() - inicio_usec) / 1000.0
	return {
		"tamano": tamano,
		"pasos": pasos,
		"semilla": semilla,
		"ms_tick": duracion_ms / float(pasos),
		"celdas_que_ardieron": int(grilla.call("contar_celdas_que_ardieron")),
	}
