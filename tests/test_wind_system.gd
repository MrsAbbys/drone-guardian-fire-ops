extends SceneTree

const SCRIPT_WIND_SYSTEM: Script = preload("res://scripts/sim/wind_system.gd")
const SCRIPT_CONFIGURACION_VIENTO: Script = preload("res://scripts/sim/configuracion_viento.gd")

var _avisos_a: Array[Vector2] = []
var _avisos_b: Array[Vector2] = []
var _avisos_erraticos: int = 0

func _initialize() -> void:
	call_deferred("_ejecutar_pruebas")

func _ejecutar_pruebas() -> void:
	var exitosas := 0
	var total := 3
	if _probar_determinismo_y_racha():
		exitosas += 1
	if _probar_modo_erratico():
		exitosas += 1
	if _probar_modo_constante():
		exitosas += 1
	print("WindSystem: %d/%d pruebas aprobadas." % [exitosas, total])
	call_deferred("quit", 0 if exitosas == total else 1)

func _probar_determinismo_y_racha() -> bool:
	var sistema_a := _crear_sistema()
	var sistema_b := _crear_sistema()
	sistema_a.connect("viento_proximo", _al_aviso_a)
	sistema_b.connect("viento_proximo", _al_aviso_b)
	var configuracion := _crear_configuracion(1)
	var correcto := (
		bool(sistema_a.call("configurar", configuracion, 8642))
		and bool(sistema_b.call("configurar", configuracion, 8642))
	)
	_detener_reloj(sistema_a)
	_detener_reloj(sistema_b)
	for _paso in range(370):
		sistema_a.call("avanzar", 0.1)
		sistema_b.call("avanzar", 0.1)
	correcto = correcto and _avisos_a.size() == 1 and _avisos_a == _avisos_b
	correcto = correcto and absf(float(sistema_a.get("_tiempo_total")) - 37.0) < 0.001
	for _paso in range(111):
		sistema_a.call("avanzar", 0.1)
		sistema_b.call("avanzar", 0.1)
	correcto = correcto and not bool(sistema_a.get("_transicionando"))
	correcto = correcto and is_equal_approx(float(sistema_a.get("velocidad")), float(sistema_b.get("velocidad")))
	sistema_a.queue_free()
	sistema_b.queue_free()
	_informar("racha determinista y transición", correcto)
	return correcto

func _probar_modo_erratico() -> bool:
	var sistema := _crear_sistema()
	sistema.connect("viento_proximo", _contar_aviso_erratico)
	var correcto := bool(sistema.call("configurar", _crear_configuracion(2), 155))
	_detener_reloj(sistema)
	for _paso in range(151):
		sistema.call("avanzar", 0.1)
	correcto = correcto and _avisos_erraticos == 1 and bool(sistema.get("_transicionando"))
	sistema.queue_free()
	_informar("intervalo errático", correcto)
	return correcto

func _probar_modo_constante() -> bool:
	var sistema := _crear_sistema()
	var avisos: Array[Vector2] = []
	sistema.connect("viento_proximo", func(direccion: Vector2, _velocidad: float, _segundos: float) -> void:
		avisos.append(direccion)
	)
	var correcto := bool(sistema.call("configurar", _crear_configuracion(0), 999))
	_detener_reloj(sistema)
	for _paso in range(460):
		sistema.call("avanzar", 0.1)
	correcto = correcto and avisos.is_empty()
	correcto = correcto and is_equal_approx(float(sistema.get("velocidad")), 8.3)
	sistema.queue_free()
	_informar("modo constante", correcto)
	return correcto

func _crear_sistema() -> Node:
	var sistema := SCRIPT_WIND_SYSTEM.new() as Node
	root.add_child(sistema)
	return sistema

func _crear_configuracion(modo: int) -> Resource:
	var configuracion := SCRIPT_CONFIGURACION_VIENTO.new() as Resource
	configuracion.set("modo", modo)
	configuracion.set("direccion", Vector2(3.0, 1.0))
	configuracion.set("velocidad_base", 8.3)
	configuracion.set("amplitud_direccion_grados", 30.0)
	configuracion.set("amplitud_velocidad", 3.2)
	return configuracion

func _detener_reloj(sistema: Node) -> void:
	var temporizador := sistema.get_node("TemporizadorViento") as Timer
	temporizador.stop()

func _al_aviso_a(direccion: Vector2, _velocidad: float, _segundos: float) -> void:
	_avisos_a.append(direccion)

func _al_aviso_b(direccion: Vector2, _velocidad: float, _segundos: float) -> void:
	_avisos_b.append(direccion)

func _contar_aviso_erratico(_direccion: Vector2, _velocidad: float, _segundos: float) -> void:
	_avisos_erraticos += 1

func _informar(nombre: String, correcto: bool) -> void:
	print("%s: %s" % [nombre, "OK" if correcto else "FALLO"])
