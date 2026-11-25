extends SceneTree

const SCRIPT_FIRE_GRID: Script = preload("res://scripts/sim/fire_grid.gd")

func _initialize() -> void:
	var grilla: RefCounted = SCRIPT_FIRE_GRID.new(Vector2(-16.0, -16.0), Vector2i(16, 16), 731)
	var celda := Vector2i(8, 8)
	var centro: Vector2 = grilla.call("celda_a_mundo", celda)
	var indice: int = celda.y * 16 + celda.x
	var mojadas: PackedByteArray

	grilla.call("aplicar_agua", centro, 0.1, 100.0)
	mojadas = grilla.get("estado")
	assert(mojadas[indice] == 3, "El agua debe mojar una celda sana para trazar una línea cortafuego.")

	var fuego: RefCounted = SCRIPT_FIRE_GRID.new(Vector2(-16.0, -16.0), Vector2i(16, 16), 731)
	fuego.call("encender", celda)
	var apagadas: int = int(fuego.call("aplicar_agua", centro, 0.1, 100.0))
	var estados_fuego: PackedByteArray = fuego.get("estado")
	assert(apagadas == 1, "El agua debe seguir apagando celdas que ya están ardiendo.")
	assert(estados_fuego[indice] == 3, "La celda extinguida debe permanecer mojada.")

	var objetivo: RefCounted = SCRIPT_FIRE_GRID.new(Vector2(-16.0, -16.0), Vector2i(16, 16), 731)
	var tipos: PackedByteArray = objetivo.get("tipo_combustible")
	var combustible_objetivo: PackedFloat32Array = objetivo.get("combustible")
	tipos.fill(3)
	tipos[indice] = 1
	combustible_objetivo.fill(0.0)
	combustible_objetivo[indice] = 4.0
	objetivo.set("tipo_combustible", tipos)
	objetivo.set("combustible", combustible_objetivo)
	objetivo.call("reconstruir_contadores")
	objetivo.call("encender", celda)
	objetivo.call("paso", 0.3, Vector2.ZERO)
	objetivo.call("reconstruir_contadores")
	var porcentaje_pastizal: float = float(objetivo.call("porcentaje_celdas_quemadas_tipo", 1))
	assert(is_equal_approx(porcentaje_pastizal, 100.0), "El porcentaje quemado debe conservarse al reconstruir contadores.")
	print("FireGrid firebreak: OK")
	quit()
