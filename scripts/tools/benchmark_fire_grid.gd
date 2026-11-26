extends SceneTree

const SCRIPT_RUNNER: Script = preload("res://scripts/tools/fire_grid_benchmark_runner.gd")
const RUTA_CSV_C: String = "res://drone-guardian-fire-ops-main/data/benchmark_results.csv"

func _initialize() -> void:
	call_deferred("_ejecutar")

func _ejecutar() -> void:
	var runner: RefCounted = SCRIPT_RUNNER.new()
	var filas := PackedStringArray([
		"n,pasos,semilla,ms_tick,celdas_que_ardieron",
	])
	var resultado_600: Dictionary = {}
	print(filas[0])
	for tamano in SCRIPT_RUNNER.TAMANOS:
		var resultado: Dictionary = runner.call(
			"medir_tamano",
			tamano,
			SCRIPT_RUNNER.PASOS,
			SCRIPT_RUNNER.SEMILLA,
			SCRIPT_RUNNER.VIENTO
		)
		if resultado.is_empty():
			quit(1)
			return
		var fila := "%d,%d,%d,%.6f,%d" % [
			tamano,
			SCRIPT_RUNNER.PASOS,
			SCRIPT_RUNNER.SEMILLA,
			float(resultado["ms_tick"]),
			int(resultado["celdas_que_ardieron"]),
		]
		filas.append(fila)
		print(fila)
		if tamano == 600:
			resultado_600 = resultado

	if not _comparar_con_csv_c(float(resultado_600["ms_tick"])):
		quit(1)
		return
	var archivo := FileAccess.open("user://benchmark_fire_grid.csv", FileAccess.WRITE)
	if archivo == null:
		push_error("No se pudo guardar el CSV del benchmark (error %d)." % FileAccess.get_open_error())
		quit(1)
		return
	archivo.store_string("\n".join(filas) + "\n")
	archivo.flush()
	print("CSV guardado en: %s" % ProjectSettings.globalize_path("user://benchmark_fire_grid.csv"))
	quit()

func _comparar_con_csv_c(ms_tick_firegrid: float) -> bool:
	var archivo := FileAccess.open(RUTA_CSV_C, FileAccess.READ)
	if archivo == null:
		push_error("No se pudo leer el CSV C %s (error %d)." % [RUTA_CSV_C, FileAccess.get_open_error()])
		return false
	var cabecera := archivo.get_csv_line()
	if cabecera != PackedStringArray(["paradigma", "unidades", "N", "steps", "tiempo_segundos"]):
		push_error("El CSV C tiene una cabecera inesperada: %s." % ",".join(cabecera))
		return false

	var filas_comparadas := 0
	var ms_total_firegrid := ms_tick_firegrid * float(SCRIPT_RUNNER.PASOS)
	print("Comparación con benchmark C histórico (N=600, 150 pasos; modelo previo):")
	print("paradigma,unidades,C_ms,FireGrid_ms,C/FireGrid")
	while not archivo.eof_reached():
		var fila := archivo.get_csv_line()
		if fila.is_empty() or (fila.size() == 1 and fila[0].is_empty()):
			continue
		if fila.size() != 5:
			push_error("Fila inválida en el CSV C: %s." % ",".join(fila))
			return false
		for indice in range(1, 4):
			if not fila[indice].is_valid_int():
				push_error("Fila inválida en el CSV C: %s." % ",".join(fila))
				return false
		if not fila[4].is_valid_float():
			push_error("Fila inválida en el CSV C: %s." % ",".join(fila))
			return false
		if int(fila[2]) != 600 or int(fila[3]) != SCRIPT_RUNNER.PASOS:
			continue
		var ms_c := float(fila[4]) * 1000.0
		print("%s,%s,%.3f,%.3f,%.3f" % [
			fila[0],
			fila[1],
			ms_c,
			ms_total_firegrid,
			ms_c / ms_total_firegrid,
		])
		filas_comparadas += 1
	if filas_comparadas == 0:
		push_error("El CSV C no contiene filas para N=600 y 150 pasos.")
		return false
	return true
