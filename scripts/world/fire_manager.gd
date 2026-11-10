extends Node

signal fuegos_actualizados(restantes: int, total: int)
signal arbol_apagado(total_apagados: int)
signal incendio_controlado

var fuegos_restantes: int = 0
var fuegos_totales: int = 0
var _registrados: Dictionary = {}

func registrar_arbol(arbol: Node) -> void:
	if not is_instance_valid(arbol) or _registrados.has(arbol.get_instance_id()):
		return
	if not arbol.has_signal("fuego_apagado"):
		push_error("FireManager: el objetivo debe emitir fuego_apagado(arbol).")
		return
	_registrados[arbol.get_instance_id()] = true
	arbol.connect("fuego_apagado", _on_arbol_apagado)
	fuegos_totales += 1
	fuegos_restantes += 1
	fuegos_actualizados.emit(fuegos_restantes, fuegos_totales)

func _on_arbol_apagado(_arbol: Node) -> void:
	fuegos_restantes = maxi(fuegos_restantes - 1, 0)
	arbol_apagado.emit(fuegos_totales - fuegos_restantes)
	fuegos_actualizados.emit(fuegos_restantes, fuegos_totales)
	if fuegos_restantes == 0 and fuegos_totales > 0:
		incendio_controlado.emit()
